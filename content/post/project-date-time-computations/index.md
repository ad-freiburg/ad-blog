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
- [Evaluation](#evaluation)
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
Without support for the subtraction between `xsd:dateTime` objects this query would not be working. This project aimed to enable queries like this (and more) in QLever, that are **fast** and **correct**.

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

### Addition/Subtraction

The following operations were implemented in this project: 
| Operation | Description | Result |
|--|--|--|
|`xsd:date - xsd:date`| This will compute the duration between the given dates.  | `xsd:dayTimeDuration` |
|`xsd:date - xsd:dayTimeDuration`|The result will be the date and time that is the time of the duration earlier than the date. | `xsd:dateTime` |
|`xsd:dateTime - xsd:dateTime`| As above this will compute the duration between the two dates. Here also taking into account the time. | `xsd:dayTimeDuration`|
|`xsd:dateTime - xsd:dayTimeDuration`| As above this results in a date and time that is the time of the duration earlier than the date. | `xsd:dateTime`|
|`xsd:gYear - xsd:gYear`| As with dates this will yield the duration between the two years. |`xsd:dayTimeDuration`|
|`xsd:date + xsd:dayTimeDuration`| Similar to above the result will be a date that is the time of the duration later than the original date. |`xsd:dateTime`|
|`xsd:dateTime + xsd:dayTimeDuration`|Here again the result will be the time of the duration later than the original date and time. |`xsd:dateTime`|  


In QLever the subtractions of `xsd:date`and `xsd:dateTime` and `xsd:gYear` (that are in [-9999, 9999]) are all handled the same. Internally they are all interpreted as a date and can thus be turned into an [epoch time](#epoch-time). The subtraction is done between both millisecond epoch times. From the result an according duration is constructed as a result.  
Since they are all internally seen as the same class, it is also possible to subtract between them.

For the subtraction of two so called `LargeYears`, a `xsd:gYear` outside of [-9999, 9999], both years will be used to create two corresponding `std::chrono::year_month_day` (using Jan 1.). The difference between those years will then be computed by subtracting the `std::chrono::sys_days`. The total amount of days between the two years is then fetched by using the `count`-method of the difference. This days amount is used to construct the resulting duration.  

The subtraction and addition between two `xsd:dayTimeDuration` objects is more simple. Internally the durations are stored by a total amount of milliseconds. Therefore the computation is just done between the amounts of milliseconds. Then the duration type needs to be set according to whether the duration is positive or negative and the new result duration is constructed using the result of the computation.  

Lastly for the subtraction and addition between a date type (`xsd:date` or `xsd:dateTime`) and a `xsd:dayTimeDuration` a combination of the previous procedures is used. The computation is done between the epoch representation of the date and the total amount of milliseconds of the duration. The result of this computation will again be a epoch time, that will be converted into a date again [as seen above](#epoch-time).

## Evaluation
There are two things to be shown for this project. First since the internal subtraction/addition logic was changed, we need to be sure that the subtraction/addition of `xsd:int` and `xsd:decimal` can still be done in the same time. Secondly the subtraction/addition of date or time objects should be fast.  

### Operations on `xsd:int`/`xsd:decimal`
To test this, two versions of a `qlever-server` are compared on the same datasets and queries. For the build without the changes from this project, the last commit before was taken. The datasets consists of 30,000 random `xsd:int`/`xsd:decimals`. As the result of the operations does not matter here this is enough to get 900,000,000 computations via the cartesian product. Simple queries were used that computed the sum of the 9,000,000 subtractions/additions. Using this it could also be ensured that the computation results did not change between the two versions. Example query for subtraction of `xsd:int`:
```sparql
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
SELECT (SUM(?diff) AS ?sumDiff) WHERE {
  ?x <http://example.org/value> ?value .
  ?y <http://example.org/value> ?value2 .
  BIND((?value - ?value2) AS ?diff)
}
```
  
| **`xsd:int`**       | **subtraction** | subtraction (only BIND) | subtraction (only CARTESIAN) | **addition** | addition (only BIND) | addition (only CARTESIAN) |
|----------------|-------------|-------------------------|------------------------------|----------|----------------------|--------------------------|
| **before changes** |     28.488ms        |  18,576ms      |        4,671ms               |    27.968ms      |     18,086ms       |     4,703ms       |
| **after changes**  |     29.136ms    |    19,732ms      |        4,508ms        |     28.995     |     19,621       |    4,506      |  

For both the subtraction and the addition of `xsd:int` the computations are only about a millisecond slower than before. This change should not be noticeable and it could also be caused by other changes that happened after the first commits of this project.  
  

| **`xsd:decimal`**       | **subtraction** | subtraction (only BIND) | subtraction (only CARTESIAN) | **addition** | addition (only BIND) | addition (only CARTESIAN) |
|----------------|-------------|-------------------------|------------------------------|----------|----------------------|--------------------------|
| **before changes** |     34.866ms         |   22,951ms     |       5,892ms               |    34.127ms      |    22,478ms        |     5,599ms       |
| **after changes**  |     32.133ms    |      21,298ms    |       5,872ms         |    34.204ms      |   22,293ms        |    6,725ms    |  

Here the subtraction of `xsd:decimal` is even faster than before the changes and the addition is just as fast as before. This change cannot come from the implementations of this project. Therefore the changes of computation times probably comes from other changes done to the codebase or is just due to fluctuation.

### Date and time operations
For the evaluation of the operations implemented in this project, different queries and datasets were used.  
The subtraction of two dates was tested on two different datasets. First a dataset of all start dates (`P580`) and end dates (`P582`) in Wikidata was constructed. On it the following query computed 813,608 subtractions between a end and its corresponding start date resulting in a total duration of this object `?x`:  
```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
SELECT * WHERE {
  ?x wdt:P580 ?start .
  ?x wdt:P582 ?end .
  BIND(?end - ?start AS ?duration)
}
```

To get even more computations a second dataset was constructed of the birth dates (`P569`) and death dates (`P570`) of humans in Wikidata. Here a similar query computed the lifespans (as a duration) of 3,655,482 humans: 
```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
SELECT ?duration
WHERE {
  ?y wdt:P569 ?birth_date .
  ?y wdt:P570 ?death_date .
  BIND(?death_date - ?birth_date AS ?duration)
}
```   

| dataset   | #subtractions | total time | time for BIND | time for JOIN |
|-----------|-------------------|-----------|-----------|-----------|
| **start-end** | 813,608 |  153ms      |   58ms       |     53ms     |
| **lifespan**  |  3,655,482  |    378ms           |    215ms       |    159ms       |  

This evaluation clearly shows that the subtraction of two dates (`xsd:date`/`xsd:dateTime`) can be computed fast and again that this subtraction can be really helpful for new insights on real life data.  
To also evaluate subtractions containing `xsd:dayTimeDuration` a third dataset was constructed using the lifespan query shown above. The new dataset contained every birth and death date and a corresponding lifespan duration (`?duration` in the query above) for each human in Wikidata. Using this the time for the computation of subtraction/addition between `xsd:date`/`xsd:dateTime` and `xsd:dayTimeDuration` could be measured:

```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
SELECT ?result ?correct
WHERE {
  ?y wdt:P569 ?birth_date .
  ?y wdt:P570 ?death_date .
  ?y <http://example.org/lifespan> ?lifespan .
  BIND((?death_date - ?lifespan) AS ?result) .
  BIND((?result = ?birth_date) AS ?correct) .
}
```  

The query above also checked if the computed result was correct, as the dataset contained both birth and death date and the lifespan should be exacty the time between them. Strangely enough for some computations `?correct` was false, which indicated that the computation was faulty. After a closer look it was clear that these "errors" were caused by humans with multiple birth or death dates in Wikidata and therefore they don't matter in this project.    

The dataset also allowed for tests of the subtraction/addition of `xsd:dayTimeDuration` objects using this query (or it's counterpart):  

```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>

SELECT (COUNT(*) AS ?count) (MIN(?result) AS ?min) (MAX(?result) AS ?max) WHERE {
  { SELECT ?lifespan1 WHERE { ?y <http://example.org/lifespan> ?lifespan1 } LIMIT 4000 }
  { SELECT ?lifespan2 WHERE { ?x <http://example.org/lifespan> ?lifespan2 } LIMIT 4000 }
  BIND(?lifespan1 + ?lifespan2 AS ?result)
}
```

Here as with the evaluation of `xsd:int`/`xsd:decimal` the result of the computations did not matter. Therefore the cartesian product was used again to increase the number of operations.  

| operation           | #operations | total computation | only BIND |
|---------------------|-------------|-------------------|-----------|
| **date - duration**     |  3,951,938   |     740ms        |   267ms        |
| **date + duration**     |  3,951,938   |     910ms        |    299ms       |
| **duration - duration** |  16,000,000  |    1262ms        |    742ms       |
| **duration + duration**  |  16,000,000  |    1208ms        |    727ms       |

This again shows that the implementation of this project enables reasonably fast computation between dates and/or durations even on larger datasets.  

## Discussion

### Correctness
The correctness of the project is verified throught various unit tests, that cover all operations presented earlier and the most important edge cases. Also in the [evaluation](#evaluation) the operations on the Wikidata human lifespans were tested for correctness. As the most important internal computation use implementations from `std::chrono`, this also implies correctness of these computations.  
The handling of timezones was tricky but in the end by using [epoch times](#epoch-time) timezones are accounted for in a correct and unified way. 

### Completeness
The operations proposed in [SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md) that involve `xsd:date`, `xsd:dateTime` and `xsd:dayTimeDuration` were fully implemented and are now supported in QLever. The built-in function `ql:toEpoch()` now also allows correct comparison between `xsd:date`/`xsd:dateTime`. In addition to the proposal the subtraction and addition was also implemented for `xsd:gYear`.  

The datatype `xsd:yearMonthDuration` is not supported in QLever yet. The datatype `xsd:time` is supported but the proposed operations are not fully implemented, as it only supports comparisons with some problems with different time zones.   

## Conclusion

TODO: 


In the future QLever could be improved by also supporting `xsd:time` and `xsd:yearMonthDuration` and their subtractions/additions formulated in [SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md).

TODO: Use of AI


