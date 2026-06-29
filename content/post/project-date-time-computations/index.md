---
title: "Date and Time Computations"
date: 2026-06-29T15:33:48+02:00
author: "Yannik Schnell"
authorAvatar: "img/ada.jpg"
tags: ["QLever", "SPARQL"]
categories: ["project"]
image: "img/cover.png"
---

This project enables more usage of dates and times in [QLever](https://github.com/ad-freiburg/qlever), an open-source RDF engine. The project was structured according to the SPARQL Extension Proposal [SEP-0002][sep02] and focuses on the subtraction and addition of `xsd:date`, `xsd:dayTimeDuration`, `xsd:dateTime` and `xsd:gYear` objects.

<!--more-->

---

## Disclaimer

I used Claude and ChatGPT as discussion partners and to identify grammatical or structural errors. I did not use LLMs to prewrite entire text passages. I used DeepL to translate some phrases.

---

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
  - [Existing Operations](#existing-operations)
  - [Date and Time Operations](#date-and-time-operations)
- [Discussion](#discussion)
  - [Correctness](#correctness)
  - [Completeness](#completeness)
- [Conclusion](#conclusion)

## Introduction

### RDF

The Resource Description Framework (RDF) is a widely used system to describe and represent information. It follows the principle that all data is stored in so-called triples. Every triple consists of a subject, a predicate and  an object and can be interpreted as a simple sentence. For example, people and their jobs could be stored in triples like: `<person> <has_job> <job>`.   
This system allows to represent the data as a knowledge graph. In this graph every node is an entity (like a person or a job). The edges are the triples that connect the subject nodes to the object nodes.  
However, multiple people can share the same name. Therefore, IRIs were given to each entity, such that it is easy to differentiate between two entities. They are often more like IDs and not really readable for a human. Additional triples often link the IRI to a label or a name that corresponds to the entity. For example, in the large knowledge graph of [Wikidata](https://www.wikidata.org/wiki/Wikidata:Main_Page) the former German chancellor [Angela Merkel](https://www.wikidata.org/wiki/Q567) has the unique identifier (IRI) `wd:Q567`.

### SPARQL and [SEP-0002][sep02] 

SPARQL is a query language used to extract information from [RDF](#rdf) knowledge graphs. Each SPARQL query can be viewed as a graph pattern that is then applied to the knowledge graph. For example, this query searches for the country of citizenship (`wdt:P27`) of Angela Merkel (`wd:Q567`) and returns the corresponding labels for the country.  
```sparql
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
SELECT ?c WHERE {
  wd:Q567 wdt:P27 ?x. # <Angela Merkel> <country of citizenship> <x>
  ?x wdt:P1705 ?c. # <x> <native label> <c>
}
```
Here the corresponding graph pattern would be:  
{{< figure src="img/sparql_graph1.png" caption="" width="800px">}} 

SPARQL 1.1 standard specifies what should be supported in SPARQL.  
In addition, SPARQL Extension Proposals can highlight what should still be added to the language.    
[SEP-0002][sep02] proposes to update SPARQL to improve handling of durations, dates and times. It would include newly supported datatypes `xsd:time`, `xsd:date`, `xsd:duration` and `xsd:dayTimeDuration` and `xsd:yearMonthDuration`. This project focuses largely on implementing the additions and subtractions that were proposed containing the following datatypes:  

| Type | Description | Example |
|--|--|--|
|`xsd:date`|Simple date containing year, month and day. |`"2025-12-24"^^xsd:date`|
|`xsd:dateTime`|Date combined with time (hour, minute,<br> second, and optional timezone).|`"2025-12-24T18:11:00Z"^^xsd:dateTime`|
|`xsd:dayTimeDuration`|A time interval consisting of days and time<br> components (hours, minutes, seconds).|`"P2DT4H5M6S"^^xsd:dayTimeDuration`|
|`xsd:gYear`|A (potentially large) calendar year.<br> Negative years are also allowed.|`"12000"^^xsd:gYear`|

### QLever
[QLever](https://github.com/ad-freiburg/qlever) is an open-source [RDF](#rdf) engine that is actively developed by the [Chair of Algorithms and Data Structures](https://ad.informatik.uni-freiburg.de) at the University of Freiburg. It implements the [RDF](#rdf) and [SPARQL](#sparql-and-sep-0002) standards. QLever is able to handle extremely large knowledge graphs efficiently. For example, it is able to quickly query the full [Wikidata](https://www.wikidata.org/wiki/Wikidata:Main_Page) graph that contains billions of triples. To achieve this QLever uses a custom precomputed index data structure for each dataset.

QLever already supported storing `xsd:date`, `xsd:dateTime`, `xsd:dayTimeDuration`, `xsd:gYear` as literals, but comparisons were not always correct - for example for dates with different timezones, and arithmetics such as additions or subtractions were not yet supported. This project closes that gap.

## Motivation
Date and time values occur frequently in knowledge graphs. Especially in [Wikidata](https://www.wikidata.org/wiki/Wikidata:Main_Page), every person alone has a date of birth (`P569`) linked to them. Additionally historical events, dates of death (`P570`), the reign start of kings or the start of occupations contain a variety of different dates and times. The ability to compute with all these values opens many new possibilities. For example, in Wikidata there is no triple for a person's lifetime, but a single subtraction could yield that value. Here is the query for the total lifespan (as `xsd:dayTimeDuration`) of Johann Wolfgang von Goethe (`Q5879`):
```sparql
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
SELECT * WHERE {
  wd:Q5879 wdt:P569 ?date_of_birth.
  wd:Q5879 wdt:P570 ?date_of_death.
  BIND((?date_of_death - ?date_of_birth) AS ?lifespan)
}
```  

{{< figure src="img/cover.png" caption="Date of birth, death and licentiate for Johann Wolfgang von Goethe - illustrating what the query computes." width="800px">}}  

Without support for the subtraction between `xsd:dateTime` objects, this query would not work. This project aimed to enable **fast** and **correct** queries like this (and more) in QLever.

## Implementation

The implementation relies heavily on [`std::chrono`](https://cppreference.com/cpp/chrono). Therefore the features of this project are not available for the CPP17 version of QLever.

### Epoch Time
For this project, a common internal representation of time was needed, especially for subtractions/additions between different types. Therefore Unix epoch time was used. It describes points in time (e.g. `xsd:date`) as the total number of seconds elapsed since January 1, 1970 at 00:00:00 UTC. Before computing, each `xsd:date` or `xsd:dateTime` is converted into an epoch time. The computations themselves then only happen between the resulting numbers.  

To get the epoch time for dates a `std::chrono::year_month_day` is constructed using the getter methods for year, month and day. For `xsd:gYear`, Jan. 1 of the year is assumed. Invalid dates can easily be filtered out with the `year_month_day`-object. For valid dates a `std::chrono::milliseconds` duration is constructed using the `std::chrono::sys_days` of the date combined with the time specifications if given. This duration is the internally used epoch time. It is also possible to convert this duration to a `int64_t`.  

This also enables correct comparisons between dates. The project added a built-in function `ql:toEpoch()` to QLever. Using this function a `xsd:date` or `xsd:dateTime` can be turned into an epoch time (`int64_t`). Comparisons can then be made on these numbers. For example:  
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

Of course a conversion from the internally used epoch time to a date object was necessary. First, the total number of days contained in the epoch time duration is extracted using `std::chrono::floor<std::chrono::days>`. Using these days a `std::chrono::year_month_day` is constructed. Then, from the remaining duration, the total amount of seconds is extracted using `std::chrono::floor<std::chrono::seconds>`. From the seconds a `std::chrono::hh_mm_ss` is constructed. This object automatically turns the seconds into a time. Then again from the remaining duration the milliseconds are extracted. If the year of the `std::chrono::year_month_day` is in [-9999, 9999], a date is constructed using the methods of `std::chrono::year_month_day` and `std::chrono::hh_mm_ss` to immediately extract the year, month, day, hours, minutes and seconds. The milliseconds are added to the seconds, which will result in a `double` value. If the year is outside the range, a large year object that only contains the year is constructed.

### Addition/Subtraction

The following operations were implemented in this project:
| Operation | Description | Result |
|--|--|--|
|`xsd:date - xsd:date`| This will compute the duration between the given<br> dates.  | `xsd:dayTimeDuration` |
|`xsd:date - xsd:dayTimeDuration`|The result will be the date and time<br> that is the time of the duration earlier than<br> the date. | `xsd:dateTime` |
|`xsd:dateTime - xsd:dateTime`| As above this will compute the duration between<br> the two dates. Here also taking into account<br> the time. | `xsd:dayTimeDuration`|
|`xsd:dateTime - xsd:dayTimeDuration`| As above this results in a date and time that is<br> the time of the duration earlier than the date. | `xsd:dateTime`|
|`xsd:gYear - xsd:gYear`| As with dates this will yield the duration between<br> the two years. |`xsd:dayTimeDuration`|
|`xsd:date + xsd:dayTimeDuration`| Similar to above the result will be a date that is<br> the time of the duration later than the original date. |`xsd:dateTime`|
|`xsd:dateTime + xsd:dayTimeDuration`|Here again the result will be the time of the duration<br> later than the original date and time. |`xsd:dateTime`|  


In QLever the subtractions involving `xsd:date`, `xsd:dateTime` or `xsd:gYear` (with year in [-9999, 9999]) are all handled the same. Internally, they are all interpreted as a date and can thus be turned into an [epoch time](#epoch-time). The subtraction is performed between both millisecond epoch times. From the result, a corresponding duration is constructed.  
Since they are all internally seen as the same class, it is also possible to subtract them from one another.

For the subtraction of two so called `LargeYears`, a `xsd:gYear` outside of [-9999, 9999], both years will be used to create two corresponding `std::chrono::year_month_day` (using Jan. 1). The difference between those years will then be computed by subtracting the corresponding `std::chrono::sys_days` values. The total amount of days between the two years is then fetched by using the `count()` method of the difference. This amount of days is used to construct the resulting duration.  

The subtraction and addition between two `xsd:dayTimeDuration` objects is simpler. Internally the durations are stored by a total amount of milliseconds. Therefore, the computation is just done between the amounts of milliseconds. Then the duration type needs to be set according to whether the duration is positive or negative and the new resulting duration is constructed using the result of the computation.  

Lastly for the subtraction and addition between a date type (`xsd:date` or `xsd:dateTime`) and a `xsd:dayTimeDuration` a combination of the previous procedures is used. The computation is done between the epoch representation of the date and the total amount of milliseconds of the duration. The result of this computation will again be an epoch time, which will be converted back into a date again [as seen above](#epoch-time).

## Evaluation
There are two things that need to be shown for this project. First, since the internal subtraction/addition logic was changed, we need to be sure that the subtraction/addition of `xsd:int` and `xsd:decimal` can still be performed in the same time. Secondly, the subtraction/addition of date or time objects should be fast.  

### Existing Operations
To test this, two versions of a `qlever-server` are compared on the same datasets and queries. For the build without the changes from this project, the last commit before these changes was used. The dataset consists of 30,000 random `xsd:int`/`xsd:decimal`s. As the result of the operations does not matter here, this is enough to get 900,000,000 computations via the cartesian product. Simple queries were used that computed the sum of the results of the 9,000,000 subtractions/additions. Using this it could also be ensured that the computation results did not change between the two versions. Example query for the subtraction of `xsd:int`:
```sparql
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
SELECT (SUM(?diff) AS ?sumDiff) WHERE {
  ?x <http://example.org/value> ?value .
  ?y <http://example.org/value> ?value2 .
  BIND((?value - ?value2) AS ?diff)
}
```
  
| **`xsd:int`**       | **subtraction** | subtraction<br> (only BIND) | subtraction<br> (only CARTESIAN) | **addition** | addition<br> (only BIND) | addition<br> (only CARTESIAN) |
|----------------|-------------|-------------------------|------------------------------|----------|----------------------|--------------------------|
| **before changes** |     28.488ms        |  18.576ms      |        4.671ms               |    27.968ms      |     18.086ms       |     4.703ms       |
| **after changes**  |     29.136ms    |    19.732ms      |        4.508ms        |     28.995ms     |     19.621ms       |    4.506ms      |  

For both the subtraction and the addition of `xsd:int` the computations are only slightly slower than before. This change should not be noticeable and it could also be caused by other changes that happened after the first commits of this project.  
  

| **`xsd:decimal`**       | **subtraction** | subtraction<br> (only BIND) | subtraction<br> (only CARTESIAN) | **addition** | addition<br> (only BIND) | addition<br> (only CARTESIAN) |
|----------------|-------------|-------------------------|------------------------------|----------|----------------------|--------------------------|
| **before changes** |     34.866ms         |   22.951ms     |       5.892ms               |    34.127ms      |    22.478ms        |     5.599ms       |
| **after changes**  |     32.133ms    |      21.298ms    |       5.872ms         |    34.204ms      |   22.293ms        |    6.725ms    |  

Here the subtraction of `xsd:decimal` is even faster than before the changes and the addition is just as fast as before. This change cannot be due to the implementations of this project. Therefore, the changes in computation times probably come from other changes done to the codebase or are just due to fluctuation.

### Date and time operations
For the evaluation of the operations implemented in this project, different queries and datasets were used.  
The subtraction of two dates was tested on two different datasets. First, a dataset of all start dates (`P580`) and end dates (`P582`) in Wikidata was constructed. On it, the following query computed 813,608 subtractions between an end and its corresponding start date resulting in a total duration for this object `?x`:  
```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
SELECT * WHERE {
  ?x wdt:P580 ?start .
  ?x wdt:P582 ?end .
  BIND(?end - ?start AS ?duration)
}
```

To get even more computations a second dataset was constructed from the birth dates (`P569`) and death dates (`P570`) of humans in Wikidata. Here, a similar query computed the lifespans (as a duration) of 3,655,482 humans: 
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

This evaluation clearly shows that the subtraction of two dates (`xsd:date`/`xsd:dateTime`) can be computed quickly and that this subtraction can be really helpful for new insights from real life data.  
To also evaluate operations involving `xsd:dayTimeDuration` a third dataset was constructed using the lifespan query shown above. The new dataset contained every birth and death date and a corresponding lifespan duration (`?duration` in the query above) for each human in Wikidata. Using this, the computation time of subtractions/additions between `xsd:date`/`xsd:dateTime` and `xsd:dayTimeDuration` could be measured:

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

The query above also checked if the computed result was correct, as the dataset contained both birth and death dates and the lifespan should be exactly the time between them. Strangely enough, for some computations `?correct` was false, which could have indicated that the computation was faulty. After a closer look it was clear that these "errors" were caused by humans with multiple birth or death dates in Wikidata and therefore they do not matter in this project.    

The dataset also allowed testing the subtraction/addition of `xsd:dayTimeDuration` objects using this query (or its counterpart):  

```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>

SELECT (COUNT(*) AS ?count) (MIN(?result) AS ?min) (MAX(?result) AS ?max) WHERE {
  { SELECT ?lifespan1 WHERE { ?y <http://example.org/lifespan> ?lifespan1 } LIMIT 4000 }
  { SELECT ?lifespan2 WHERE { ?x <http://example.org/lifespan> ?lifespan2 } LIMIT 4000 }
  BIND(?lifespan1 + ?lifespan2 AS ?result)
}
```

Here, as with the evaluation of `xsd:int`/`xsd:decimal`, the result of the computations did not matter. Therefore, the cartesian product was used again to increase the number of operations.  

| operation           | #operations | total computation | only BIND |
|---------------------|-------------|-------------------|-----------|
| **date - duration**     |  3,951,938   |     740ms        |   267ms        |
| **date + duration**     |  3,951,938   |     910ms        |    299ms       |
| **duration - duration** |  16,000,000  |    1262ms        |    742ms       |
| **duration + duration**  |  16,000,000  |    1208ms        |    727ms       |

This again shows that the implementation of this project enables reasonably fast computations between dates and/or durations even on larger datasets.  

## Discussion

### Correctness
The correctness of the project is verified through various unit tests that cover all operations presented earlier and the most important edge cases. Also, in the [evaluation](#evaluation), the operations on Wikidata human lifespans were tested for correctness. Since the most important internal computations use implementations from `std::chrono`, this also implies the correctness of these computations.  
The handling of time zones was tricky, but in the end, by using [epoch times](#epoch-time), timezones are accounted for in a correct and consistent way. 

### Completeness
The operations proposed in [SEP-0002][sep02] that involve `xsd:date`, `xsd:dateTime` and `xsd:dayTimeDuration` were fully implemented and are now supported in QLever. The built-in function `ql:toEpoch()` now also allows correct comparisons between `xsd:date`/`xsd:dateTime` values. In addition to the proposal, subtraction and addition were also implemented for `xsd:gYear`.  

The datatype `xsd:yearMonthDuration` is not yet supported in QLever. The datatype `xsd:time` is supported, but the proposed operations are not fully implemented, as it currently only supports comparisons and still has some issues with different time zones.   

## Conclusion
With this project, QLever now supports most of the proposed operations from [SEP-0002][sep02]. It was also extended by operations for `xsd:gYear` and the built-in function `ql:toEpoch()`. The evaluation showed that the operations can be computed quickly without affecting subtraction/addition operations for other datatypes (`xsd:int`, `xsd:decimal`).  

Now queries like the one shown in [Motivation](#motivation) can easily be evaluated in QLever and can yield more useful information. Especially when using it on Wikidata, there are many possibilities. This can also be seen in the [Evaluation](#evaluation), where the lifespans of humans in Wikidata were computed. The new features could also be used to determine the length of historical events, reigns or occupations.  

In the future, QLever could be improved by also supporting the subtractions and additions of `xsd:time` and `xsd:yearMonthDuration` formulated in [SEP-0002][sep02]. This would need to include general support for the datatype `xsd:yearMonthDuration`, as it is not yet supported in QLever. In addition, correct comparisons for `xsd:time` objects could be achieved by accounting for differences in time zones. 

[sep02]: https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md


