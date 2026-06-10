---
title: "Date and Time Computations"
date: 2026-04-27T15:13:48+02:00
author: "Yannik Schnell"
authorAvatar: "img/ada.jpg"
tags: ["QLever", "SPARQL"]
categories: ["project"]
image: "img/writing.jpg"
---

This project enables more usage of dates and times in [QLever](https://github.com/ad-freiburg/qlever), an open-source RDF engine. The project was structured after the SPARQL Extension Proposal [SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md) and focuses on the subtraction and addition of `xsd:date`, `xsd:dayTimeDuration`, `xsd:dateTime` and `xsd:gYear` objects.

<!--more-->

## Content
- [Introduction](#introduction)
    - [RDF](#rdf)
    - [SPARQL and SEP-0002](#sparql-and-sep-0002)
    - [QLever](#qlever)
- [Motivation](#motivation)
- [Implementation](#implementation)
  - [Epoch Time](#epoch-time)
  - [Addition/Subtraction](#additionsubtraction)
- [Discussion](#discussion)
- [Conclusion](#conclusion)

## Introduction

### RDF

The Resource Description Framework (RDF) is a widely used system to describe and formulate informations. It follows the principle that all data is stored in so called triples. Every triple consist of a subject, predicate and object and can be interpreted as a simple sentence. For Example people and their jobs could be stored in triples like: `<person> <has_job> <job>`. 
This system allows to represent the data as a knowledge graph. In this graph every node is an entity (like a person or a job). The edges are the triples that connect the subject nodes to the object nodes.
But multiple people share the same name. Therefore IRIs were given to each entity, such that it is easy to differentiate between two entities. They are often more like an ID and not really readable for a human. Additional triples often link the IRI to a label or a name that corresponds to the entity. For example in the large knowledge graph of [Wikidata](https://www.wikidata.org/wiki/Wikidata:Main_Page) the former german chancellor [Angela Merkel](https://www.wikidata.org/wiki/Q567) has the unique identifier (IRI) `wd:Q567`.

### SPARQL and [SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md) 

SPARQL is a query language used to extract information from [RDF](#rdf) knowledge graphs. Each SPARQL query can be viewed as a graph pattern that is then applied to the knowledge graph. For example this query searches for the country of citizenship (`wdt:P27`) of Angela Merkel (`wd:Q567`) and returns the corresponding labels for the country.  
```sparql
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
SELECT ?c WHERE {
  wd:Q567 wdt:P27 ?x. # <Angela Merkel> <country of citizenship> <x>
  ?x wdt:P1705 ?c. # <x> <native label> <c>
}
```
Here the corresponding graph pattern would be:  
{{< figure src="img/sparql_graph1.png" caption="" >}}  
SPARQL 1.1 standard yiels specifications for what should be supported in SPARQL.  
In addition SPARQL Extension Proposals can highlight what should still be added to the language.  
[SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md) proposes to update SPARQL to improve handling of durations, dates and times. It comes with newly supported datatypes `xsd:time`, `xsd:date`, `xsd:duration` and `xsd:dayTimeDuration` and `xsd:yearMonthDuration`. This project focusses largely on implementing the additions/subtractions that were proposed containing the following datatypes:  
| Type | Description | Example |
|--|--|--|
|`xsd:date`|Simple date containing year, month and day. |`"2025-12-24"^^xsd:date`|
|`xsd:dateTime`|Date combined with time (hour, minute, second, and optional timezone).|`"2025-12-24T18:11:00Z"^^xsd:dateTime`|
|`xsd:dayTimeDuration`|A time interval consisting of days and time components (hours, minutes, seconds).|`"P2DT4H5M6S"^^xsd:dayTimeDuration`|
|`xsd:gYear`|A (potentially large) calendar year. Negative years are also allowed.|`"12000"^^xsd:gYear`|

### QLever
[QLever](https://github.com/ad-freiburg/qlever) is an open-source [RDF](#rdf) engine that is actively developed by the [Chair of Algorithms and Data Structures](https://ad.informatik.uni-freiburg.de) at the University of Freiburg. It implements the [RDF](#rdf) and [SPARQL](#sparql-and-sep-0002) standards. QLever is able to handle extremely large knowledge graphs efficiently. For example it is able to quickly query the full [Wikidata](https://www.wikidata.org/wiki/Wikidata:Main_Page) graph that contains billions of triples. To achieve this QLever uses a custom Index datastructure.

TODO: evtl. details wie funktioniert

QLever already supported storing `xsd:date`, `xsd:dateTime`, `xsd:dayTimeDuration`, `xsd:gYear` as literals, but comparisons were not always correct - for example for dates with different timezones, and arithmetics such as additions or subtractions were not yet supported. This project closes that gap.

## Motivation
Date and time values occur frequently in knowledge graphs. Especially in [Wikidata](https://www.wikidata.org/wiki/Wikidata:Main_Page) every person alone has a date of birth (`P569`) linked to them. Additonally historical events, dates of death (`P570`), the reign start of kings or the start of occupations contain a variety of different dates and times. The ability to compute with all these values opens many new possibilities. For example in Wikidate there is no triple for lifetime, but using a single subtraction could yield that value. Here is the query for the total lifespan (as `xsd:dayTimeDuration`) of Johann Wolfgang von Goethe (`Q5879`):
```sparql
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
SELECT * WHERE {
  wd:Q5879 wdt:P569 ?date_of_birth.
  wd:Q5879 wdt:P570 ?date_of_death.
  BIND((?date_of_death - ?date_of_birth) AS ?lifespan)
}
```
Without support for the subtraction between `xsd:dateTime` objects this query would not be working. This project enables queries like this (and more) in QLever.

## Implementation

The implementation relies heavily on [`std::chrono`](https://cppreference.com/cpp/chrono). Therefore the features of this project are not available for the CPP17 version of QLever.

### Epoch Time
For this project a common internal representation of time was needed, espescially for additions/subtractions of different types. Therefore Unix epoch time was used. It describes points in time (e.g. `xsd:date`) as the total number of seconds elapsed since January 1, 1970 at 00:00:00 UTC. Before computing each `xsd:date` or `xsd:dateTime` will now be turned into a Epoch time. The computations themselves then only happen between numbers.  

To get the epoch time for dates a `std::chrono::year_month_day` is constructed using the getter methods for year, month and day. For `xsd:gYear`s Jan 1. of the year is assumed. Invalid dates can easily be filtered with the `year_month_day`-object. For valid dates a `std::chrono::milliseconds` duration is constructed using the `std::chrono::sys_days` of the date combined with the time specifications if given. This duration is the is the internally used epoch time. It is also possible to convert this duration to a `int64_t`.  

This also enables correct comparisons between dates. The project added a built-in function `ql:toEpoch()` to QLever. Using this function a `xsd:date` or `xsd:dateTime` can be turned into an Epoch time (`int`). Comparisons can then be made on these numbers. For example:  
```sparql
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
SELECT ?date1 ?date2 ?lt1 ?lt2
WHERE {
  BIND("2025-12-24T14:15:00Z"^^xsd:dateTime AS ?date1)
  BIND("2025-12-24T13:15:00-02:00"^^xsd:dateTime AS ?date2)
  BIND(ql:toEpoch(?date1) < ql:toEpoch(?date2) AS ?lt1)
  BIND(ql:toEpoch(?date2) < ql:toEpoch(?date1) AS ?lt2)
}
```

Of course a conversion from the internally used epoch time to a date object was necessary. Firstly the total days contained in the epoch time duration werde extracted using `std::chrono::floor<std::chrono::days>`. Using these days a `std::chrono::year_month_day` is constructed. Then from the remaining duration the total amount of seconds are extracted using `std::chrono::floor<std::chrono::seconds>`. With the seconds a `std::chrono::hh_mm_ss` is constructed. This object will automatically make a time from the seconds. Then again from the remaining duration the milliseconds are extracted. If the year of the `std::chrono::year_month_day` is in [-9999, 9999] a date is constructed using the methods of `std::chrono::year_month_day` and `std::chrono::hh_mm_ss` to immediately get the year, month, day, hours, minutes and seconds. The milliseconds are added to the seconds which will result in a `double` value. If the year is not in the range a large year object, that only contains the year, is constructed.

TODO: makeFrom Epoch

### Addition/Subtraction

The following operations were implemented in this project: 
| Operation | Description | Result |
|--|--|--|
|`xsd:date - xsd:date`| This will compute the duration between the given dates.  | `xsd:dayTimeDuration` |
|`xsd:date - xsd:dayTimeDuration`|The result will be the date and time that is the time of the duration earlier than the date. | `xsd:dateTime` |
|`xsd:dateTime - xsd:dateTime`| As above this will compute the duration between the two dates. Here also taking into account the time. | `xsd:dayTimeDuration`|
|`xsd:dateTime - xsd:dayTimeDuration`| As above this results in a date and time that is the time of the duration earlier than the date. | `xsd:dateTime`|
||||


TODO: focus on subtraction (addition is equivalent)

## Discussion

TODO: 

## Conclusion

TODO: 

In the future QLever could be improved by also supporting `xsd:time` and `xsd:yearMonthDuration` and their subtractions/additions formulated in [SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md).


