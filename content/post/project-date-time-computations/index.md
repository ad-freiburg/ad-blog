---
title: "Date and Time Computations"
date: 2026-04-27T15:13:48+02:00
author: "Yannik Schnell"
authorAvatar: "img/ada.jpg"
tags: ["QLever", "SPARQL"]
categories: ["project"]
image: "img/writing.jpg"
---

This project enables more usage of dates and times in [QLever](https://github.com/ad-freiburg/qlever), an open-source RDF engine. The project was structured after the SPARQL Extension Proposal [SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md) and focuses on the subtraction and addition of `xsd:date`, `xsd:dayTimeDuration`, `xsd:dateTime` objects.

<!--more-->

## Content
- [Introduction](#introduction)
- [Motivation](#motivation)
- [Implementation](#implementation)
- [Discussion](#discussion)
- [Conclusion](#conclusion)

## Introduction

### RDF

The Resource Description Framework (RDF) is a widely used system to describe and formulate informations. It follows the principle that all data is stored in so called triples. Every triple consist of a subject, predicate and object and can be interpreted as a simple sentence. For Example people and their jobs could be stored in triples like: `<person> <has_job> <job>`. 
This system allows to represent the data as a knowledge graph. In this graph every node is an entity (like a person or a job). The edges are the triples that connect the subject nodes to the object nodes.
But multiple people share the same name. Therefore IRIs were given to each entity, such that it is easy to differentiate between to entities. They are often more like an ID and not really readable for a human. Additional triples often link the IRI to a label or a name that corresponds to the entity. For example in the large knowledge graph of [Wikidata](https://www.wikidata.org/wiki/Wikidata:Main_Page) the former german chancellor [Angela Merkel](https://www.wikidata.org/wiki/Q567) has the unique identifier (IRI) `wd:q567`.

### SPARQL and [SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md) 

SPARQL is a query language used to extract information from [RDF](#rdf) knowledge graphs. Each SPARQL query can be viewed as a graph pattern that is then applied to the knowledge graph (TODO: example?). SPARQL 1.1 standard yiels specifications for what should be supported in SPARQL.  
In addition SPARQL Extension Proposals can highlight what should still be added to the language. [SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md) proposes to update SPARQL to support handling of durations, dates and times. It comes with newly supported datatypes `xsd:time`, `xsd:date`, `xsd:duration` and `xsd:dayTimeDuration` and `xsd:yearMonthDuration`.

### Relevant XSD types

### QLever

## Motivation

## Implementation

## Discussion

## Conclusion

In the future QLever could be improved by also supporting `xsd:time` and `xsd:yearMonthDuration` and their subtractions/additions formulated in [SEP-0002](https://github.com/w3c/sparql-dev/blob/main/SEP/SEP-0002/sep-0002.md).


