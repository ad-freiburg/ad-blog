---
title: "QLever Update"
date: 2025-10-16T18:41:00+02:00
author: "Julian Mundhahs"
authorAvatar: "img/profile.jpg"
tags: ["QLever", "SPARQL", "Update"]
categories: ["project"]
image: "img/cover.png"
---

foodas jdkas daksjd

<!--more-->

## Content

- [Introduction](#introduction)
  - [RDF](#rdf)
  - [SPARQL](#sparql)
  - [SPARQL Update](#sparql-update)
  - [SPARQL Graph Store HTTP Protocol](#sparql-graph-store-http-protocol)
  - [QLever](#qlever)
- [Problem Statement](#problem-statement)
- [Implementation](#implementation)
- [Discussion](#discussion)
  - [Correctness](#correctness)
  - [Completeness](#completeness)
  - [Performance (Impact)](#performance-impact)
- [Conclusion and Future Work](#conclusion-and-future-work)

## Introduction

### RDF

The [Resource Description Framework](https://www.w3.org/TR/rdf11-concepts) (RDF) is a model for representing information. Every piece of information is represented as a triple with a subject, predicate and object. RDF data is commonly visualized as a directed graph with labeled edges with the triple's components being nodes or the label on the edge as shown below.

{{< figure src="img/triple.svg" caption="RDF triple with a <span style='color:red'>subject</span>, <span style='color:blue'>predicate</span> and <span style='color:green'>object</span> stating that Foo bar baz" width="500px" >}}

*IRIs* and *literals* are called **resources** and used to denote anything we describe. *Blank Nodes* are used in triples when only stating that something exists without naming it. The subject may be an IRI or a blank node, the predicate is always an IRI and the object may be an IRI, a literal or a blank node. An RDF graph is a set of RDF triples.

{{< figure src="img/graph.svg" caption="An RDF graph stating that *Freiburg* and *Hamburg* are cities and giving their respective population sizes and names" width="750px" >}}

An RDF dataset is a collection of RDF graphs. It consists of one designated RDF graph - the default graph and arbitrarily many IRI and RDF graph pairs - the named graphs.

### SPARQL

*SPARQL 1.1* is a collection of standards for interacting with RDF data. Relevant for this project are

<!--- [*SPARQL 1.1 Query Language*](https://www.w3.org/TR/sparql11-query/) which defines a query language for querying RDF data [*SPARQL 1.1 Protocol for RDF*](https://www.w3.org/TR/sparql11-protocol/)-->
- [*SPARQL 1.1 Protocol for RDF*](https://www.w3.org/TR/sparql11-protocol/) is a protocol for transmitting SPARQL queries and updates over HTTP
- [*SPARQL 1.1 Update Language*](https://www.w3.org/TR/sparql11-update/) which defines a language for updating RDF data on top of *SPARQL 1.1 Protocol for RDF*
- [*SPARQL 1.1 Graph Store HTTP Protocol*](https://www.w3.org/TR/sparql11-http-rdf-update/) which defines a protocol for updating RDF data using common HTTP methods

#### SPARQL Update

*SPARQL 1.1 Update Language* (Update) defines operations for updating RDF datasets. The operations are atomic and can be chained into larger atomic operations. It defines 5 Graph Update operations for updating data in RDF graphs

- *DELETE/INSERT DATA* - removing or adding triples
- *DELETE INSERT WHERE* - removing or adding triples based on the results of a query
- *LOAD* adding triples from a serialized RDF document
- *DELETE WHERE* - removing all existing triples that match a pattern
- *CLEAR* - removing all triples from graphs

and 5 Graph Management operations for managing RDF graphs

- *CREATE* - creating a new empty named graph
- *DROP* - removing a graph
- *COPY* - copying a graph to another graph, overwriting the target
- *MOVE* - renaming a graph
- *ADD* - adding all triples from a graph to another graph

#### SPARQL Graph Store HTTP Protocol

*SPARQL 1.1 Graph Store HTTP Protocol* (Graph Store Protocol or GSP) defines a protocol for updating RDF datasets. HTTP methods are used to specific the operation and serialized RDF is accepted as input. It provides an alternative interface for some [*SPARQL Update*](#sparql-update) operations which may be easier to work with in some cases. Subtle differences in the escaping between RDF Turtle and SPARQL can also make the Graph Store Protocol more convenient when dealing with large serialized RDF because it eliminates the need for re-escaping the data.

- *GET* - retrieve all triples in an graph
- *PUT* - replace the graph's triples with the triples contained in the request body
- *DELETE* - delete a graph
- *POST* - add the serialized triples in the request body to a graph
- *HEAD* - equivalent to *GET* except that no response body is returned
- *PATCH* - apply a [*SPARQL Update*](#sparql-update) to a graph

### QLever

QLever is a extremly fast graph database for storing an RDF dataset which can be queried and updated using SPARQL. QLever is written in C++ and actively being developed by the [Chair of Algorithms and Data Structures](https://ad.informatik.uni-freiburg.de/front-page-en) at the University Freiburg and [QLeverize AG](https://www.qleverize.com/).

To enable it's fast performance QLever stores the data in a custom index format. Before the addition of update this index was built once for a RDF dataset. QLever then uses this index to compute query results. Building the index is quick but can take a couple of hours for the largest datasets, which can contain hundreds of billions of triples.

Remember that all RDF data is made up of RDF triples with a subject, predicate and object. A *permutation* is a structure that contains the triples with the triples components in a specific order (*permuted triple*), e.g. Predicate-Subject-Object. The triples in a permutation are ordered with respect to the permuted triples. Both the order of the triples and the order of the triples components are thus given by the permutation. QLever stores the triples each in all 6 possible permutations. This allows easy acces to the triples in all the constellations that may be required.  

Permutations are divided up into *blocks*. Blocks have metadata which contain the first and last triple and the consecutive region on disk that the block is stored on. The borders of the blocks are determined heuristically when building the index. Storing this metadata of the blocks allows quick access to exactly the required blocks for an operation eliminting the need to scan the whole permutation.

Conceptually for a RDF dataset

```turtle
<Hamburg> <is-a> <City> .
<Freiburg> <is-a> <City> .
<Hamburg> <population> "2000000" .
<Freiburg> <population> "250000" .
```

for the SPO (Subject-Predicate-Object) permutation we would store

```text
<Hamburg> <is-a> <City> <Hamburg> <population> "2000000"
<Freiburg> <is-a> <City> <Freiburg> <population> "250000"
```

while for PSO (Predicate-Subject-Object) it would be

```text
<is-a> <Hamburg> <City> <is-a> <Freiburg> <City>
<population> <Hamburg> "2000000" <population> <Freiburg> "250000"
```

where the different lines are stored in different blocks.

## Problem Statement

Updating the data at runtime without requiring a full index re-build is usefull for many use cases and required for use cases like keeping an up-to-date Wikidata index.
We thus want to enable the modification of the data at runtime using [SPARQL Update](#sparql-update) and the [Graph Store Protocol](#sparql-graph-store-http-protocol).
Updating the data should be **correct** with respect to to the standards being implemented, **easy to use**, **fast** and applied updates should have **little performance impact**.

## Implementation

On a high level the updates in QLever are easy to understand. Due to QLevers implicit graph existence *all* operations only need to add or remove some triples in the end. In many cases like `LOAD` or `DELETE INSERT WHERE` the set of triples to add or remove is not trivial, but once the triples have been computed the operations reduce to adding or removing triples.

For each permutation and block we will keep one ordered list of the triples that have been changed. When an operations changes a triple for then for each permutation we determine in which block the triple would fall and add it to the coresponding change list. After an operation we also update the metadata of a block because the first and last triple may have changed.

All operations that use the dataset start with an `IndexScan`. An `IndexScan` reads a permutation in a blockwise manner. It may read the whole permutation or only some blocks. When reading a block for an `IndexScan` we merge the block being read with the modified triples in that block using a zip join. We generally return the triples obtained from the original block. A triple in the original block is not returned if it is deleted by the modified triples. An added triple from the modified triples is returned if it is not already in the original block. The other combinations can be skipped because they have no effect (deleting non-existent triples and adding already existing triples).

Parsing SPARQL Update is fortunately very easy because we use [ANTLR](https://www.antlr.org/), a parser generator. The grammar given in the standard can easily be adapted for use with ANTLR and building an internal representation of the parsed Update is also not very hard. Though this was only this quick and easy because we transitioned to ANTLR from a hand-written parser. A large part of this transition was done as my Bachelor Thesis.  
*DELETE WHERE* and *CLEAR* only are syntactic sugar for other Graph Update operations. All Graph Management operations can be broken down into basic Graph Update operations.

{{< notice type="info" >}}
The Graph Management Operations can be broken down this way because QLever has implicit graph existence. This means that QLever does not explicitly track the existence of graphs. This means that a graph exists iff there are triples in it. Explicit graph existence allows for empty graphs. If graph existence were explicit, then at a minimum additional operations for adding and removing a graph would be required.
{{< /notice >}}

Graph Store Protocol requests can approximately be translated into equivalent SPARQL Update requests. This makes the majority of the functionality easy to implement, while some [niche cases](#completeness) require extra work. For this work we translate the Graph Store Protocol requests into their equivalent SPARQL Update requests and ignore the niche cases.

## Discussion

### Correctness

- bla bla extensive unit tests
- test in production at ...
- insert olympics from scratch -> diff = 0 etc.

### Completeness

[Update](#sparql-update) is implemented fully with all operations. Note that QLever has implicit graph existence.

The major parts of [Graph Store Protocol](#sparql-graph-store-http-protocol) are implemented. The `GET`, `PUT`, `DELETE` and `POST` operations are supported. We also added a non-standard but natural `TSOP` operation which does a `DELETE DATA` of the payload - the opposite of `POST`s `INSERT DATA`.  
`HEAD` and the optional `PATCH` operations are not supported. There are also some niche cases that are not yet handled correctly

- `PUT` does not return `201 Created` when a new graph is created, it always returns `200 OK`
- `POST` without a graph IRI is not supported (a graph IRI is chosen and returned afterwards in the `Location` header)
- the `multipart/form-data` content type is not supported

`multipart/form-data` is easy to implement, but out of scope for this project. All the other deviations (except `PATCH`) can be implented using similar mechanism. Once one is implemented the others can be implemented easily as well.

### Performance (Impact)

ToDo:

- Benchmark with graphs
- Wikidata updating

## Conclusion and Future Work

The implementation supports the majority of SPARQL Update and Graph Store Protocol. We extended it with a method that we felt was missing. The implementation has been available in QLever for some time while developing and has been used in ... Updating is fast enough to keep up with the Wikidata knowledge graph with almost no delay.

While QLever's updating should be fast enough for most needs, there are some areas that we want to improve. Both Update and GSP use the same base for updating, so both will see performance improvements from improvements in this area. We see this as the most important area to improve on.

- Smaller updates are comparatively slower per triple, because there is a constant overhead. Reducing the overhead in general and eliminating it completely in special cases will be a target.
- When a signifcant proportion of the triples has been updated, there is a noticeable performance impact. The goal is to reduce the performance impact to a level that instances running QLever with updates, like Wikidata, can be run indefinitely.

The size of updates is currently limited because the whole update is processed as one piece. We want to process the update in chunks similar to how queries are computed. This will enable larger updates and we also expect a small performance improvement from this. Both Update and GSP will benefit from improvments in this area. For GSP it is also natural to parallelize the deserialization of the RDF data.

Implementing the remaining parts of the standard (see [Completeness](#completeness)) will also be an area for future improvement. The missing parts are all niche and we expect that they are used sparsely. This assesment might change with user feedback, increasing the priority of features.
A related area are the supported media types for the Graph Store Protocol for input and output of serialized RDF data. For output a wide range of media types (ToDo: list) is already supported. For input only *Turtle* and *N-Triples* are supported. Adding support for more media types here would make QLever more versatile.

There may also arise the need for extensions to the standardized functionality like the already implemented `TSOP`. This will depend on the needs of the users.

<!--
## Update Bottlenecks

- Snapshots cause linear cost in # of updates applied so-far per Update
  - Blocking Updates, execute queries against DeltaTriples directly -> no Snapshots required for chained Updates
  - temporarily deactivate Snapshots -> Updates that don't depend on the state (and some few more) can still be executed
  - multiple layered DeltaTriples, regularly (TM) compact them -> reduce size of top-most DeltaTriples that need to be snapshoted
    - `write back` Updates to another Index (that's layered on-top) -> reduce size of DeltaTriples + increase query execution time
  - mechanism for Chaining Updates in GSP, something with ndjson, operation type and the payload
- Update processing is slow
  - optimize transformations
    - Batch ID lookup
    - optimize data structures
- Updates können persistiert werden. Ist das persistieren effizient? Wo sind beim lesen und schreiben Bottlenecks?
- Große Updates (z.B. `LOAD` aber auch andere) gehen OOM. Updates werden in einem Stück verarbeitet.
  - Updates, wie Query, blockweise verabeiten.
    - Triples blockweise parsen
    - Triples blockweise verarbeiten
- viele LocatedTriples brauchen sehr viel RAM

**
1. Update dauert lange wenn es schon viele Updates gab
  - std::set?
2. Warum dauert Preparation so lange
**

-->

[^1]: This is only the case because QLever has implicit graph existence. This means that QLever does not explicitly track the existence of graphs. This means that a graph exists iff there are triples in it. Explicit graph existence allows for empty graphs. If graph existence were explicit, then at a minimum additional operations for adding and removing a graph would be required.
