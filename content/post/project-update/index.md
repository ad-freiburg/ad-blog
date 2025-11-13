---
title: "QLever Update"
date: 2025-10-16T18:41:00+02:00
author: "Julian Mundhahs"
authorAvatar: "img/profile.jpg"
tags: ["QLever", "SPARQL", "Update"]
categories: ["project"]
image: "img/cover.svg"
---

[QLever](https://github.com/ad-freiburg/qlever) is a graph database for RDF data which can be queried using SPARQL. As part of this project we implemented the SPARQL Update and Graph Store Protocol standards for modifying the data of the database at runtime after its initial load.

<!--more-->

## Content

<style>
:root {
  --blue: #0074d9;
  --teal: #39cccc;
  --purple: #b10dc9;
  --fuchsia: #f012be;
  --red: #ff4136;
  --olive: #3d9970;
  --green: #2ecc40;
}
</style>

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

The [Resource Description Framework](https://www.w3.org/TR/rdf11-concepts) (RDF) is a model for representing information. Every piece of information is represented as a triple with a <span style='color:var(--red)'>subject</span>, <span style='color:var(--blue)'>predicate</span> and <span style='color:var(--green)'>object</span>. RDF data is commonly visualized as a directed graph with labeled edges. The subject and predicate are represented as nodes and the predicate as the edge's label. Stating that the <span style='color:var(--red)'>City Hamburg</span> <span style='color:var(--blue)'>has the name</span> <span style='color:var(--green)'>"Hansestadt Hamburg"</span> could be done as

{{< figure src="img/rdf/triple.svg" caption="RDF triple with a <span style='color:var(--red)'>subject</span>, <span style='color:var(--blue)'>predicate</span> and <span style='color:var(--green)'>object</span>" width="500px" >}}

An RDF graph is simply a set of RDF triples. The following graph states that *Freiburg* and *Hamburg* are cities and gives their respective population sizes and names.

{{< notice type="note" >}}
Values enclosed by `<...>` are IRIs (a generalization of URLs and URIs) which denote the objects that we describe. Values enclosed by `"..."` are literals which can have an optional datatype like string, float, integer or many more.
{{< /notice >}}

{{< figure src="img/rdf/graph.svg" width="750px" >}}

An RDF dataset is a collection of RDF graphs. It consists of one designated RDF graph - the default graph and arbitrarily many IRI and RDF graph pairs - the named graphs.

To recap: an <span style='color:var(--purple)'>RDF dataset</span> is made up of one <span style='color:var(--fuchsia)'>default graph</span> and arbitrily many <span style='color:var(--olive)'>named graphs</span>. Each RDF graph consists of <span style='color:var(--teal)'>RDF triples</span>.

{{< figure src="img/rdf/dataset.svg" width="750px" >}}

### SPARQL

*SPARQL 1.1* is a collection of standards for interacting with RDF data. Relevant for this project are

- [*SPARQL 1.1 Protocol for RDF*](https://www.w3.org/TR/sparql11-protocol/) is a protocol for transmitting SPARQL queries and updates over HTTP
- [*SPARQL 1.1 Update Language*](https://www.w3.org/TR/sparql11-update/) which defines a language for updating RDF data on top of *SPARQL 1.1 Protocol for RDF*
- [*SPARQL 1.1 Graph Store HTTP Protocol*](https://www.w3.org/TR/sparql11-http-rdf-update/) which defines a protocol for updating RDF data using common HTTP methods

#### SPARQL Update

*SPARQL 1.1 Update Language* (Update) defines operations for updating RDF datasets. The operations are atomic and can be chained into larger atomic operations. It defines five Graph Update operations for updating data in RDF graphs

- *DELETE/INSERT DATA* - removing or adding triples
- *DELETE INSERT WHERE* - removing or adding triples based on the results of a query
- *LOAD* adding triples from a serialized RDF document
- *DELETE WHERE* - removing all existing triples that match a pattern
- *CLEAR* - removing all triples from graphs

and five Graph Management operations for managing RDF graphs

- *CREATE* - creating a new empty named graph
- *DROP* - removing a graph
- *COPY* - copying a graph to another graph, overwriting the target
- *MOVE* - renaming a graph
- *ADD* - adding all triples from a graph to another graph

#### SPARQL Graph Store HTTP Protocol

*SPARQL 1.1 Graph Store HTTP Protocol* (Graph Store Protocol or GSP) defines a protocol for updating RDF datasets. HTTP methods are used to specify the operation and serialized RDF is accepted as input. It provides an alternative interface for some [*SPARQL Update*](#sparql-update) operations which may be easier to work with in some cases. Subtle differences in the escaping between RDF Turtle and SPARQL can also make the Graph Store Protocol more convenient when dealing with large serialized RDF because it eliminates the need for re-escaping the data.

- *GET* - retrieve all triples in a graph
- *PUT* - replace the graph's triples with the triples contained in the request body
- *DELETE* - delete a graph
- *POST* - add the serialized triples in the request body to a graph
- *HEAD* - equivalent to *GET* except that no response body is returned
- *PATCH* - apply a [*SPARQL Update*](#sparql-update) to a graph

### QLever

QLever is an extremly fast graph database for storing an RDF dataset which can be queried and updated using SPARQL. QLever is an open source project written in C++. It is under active developement in particular by the [Chair of Algorithms and Data Structures](https://ad.informatik.uni-freiburg.de/front-page-en) at the University Freiburg.

To enable its fast performance QLever stores the data in a custom index format. Before the addition of update this index was built once for an RDF dataset. QLever then uses this index to compute query results. Building the index is quick but can take a couple of hours for the largest datasets, which can contain hundreds of billions of triples.

Remember that all RDF data is made up of RDF triples with a subject, predicate and object. A *permutation* is a structure that contains the triples with the triples' components in a specific order (*permuted triple*), e.g. Predicate-Subject-Object. The triples in a permutation are ordered with respect to the permuted triples. Both the order of the triples and the order of the triples components are thus given by the permutation. QLever stores the triples each in all 6 possible permutations. This allows easy acces to the triples in all the constellations that may be required.  

Permutations are divided up into *blocks*. Blocks have metadata which contain the first and last triple and the consecutive region on disk that the block is stored on. The borders of the blocks are determined heuristically when building the index. Storing this metadata of the blocks allows quick access to exactly the required blocks for an operation eliminating the need to scan the whole permutation.

{{< notice type="example">}}

Assume an RDF dataset with 4 triples:

```turtle
<Hamburg> <is-a> <City> .
<Freiburg> <is-a> <City> .
<Hamburg> <population> "1.862.565" .
<Freiburg> <population> "237.460" .
```

Looking at how the data is stored in the two permutations below one notices three differences:

- the <span style='color:var(--red)'>subject</span>, <span style='color:var(--blue)'>predicate</span> and <span style='color:var(--green)'>object</span> are stored in different orders inside the <span style='color:var(--teal)'>permuted triples</span>,
- the <span style='color:var(--teal)'>permuted triples</span> are in a different order and
- the <span style='color:var(--fuchsia)'>blocks</span> contain different <span style='color:var(--teal)'>permuted triples</span>

{{< figure src="img/index/spo.svg" caption="SPO (Subject-Predicate-Object) permutation" width="750px" >}}

{{< figure src="img/index/pso.svg" caption="PSO (Predicate-Subject-Object) permutation" width="750px" >}}

{{< /notice >}}

## Problem Statement

Updating the data at runtime without requiring a full index re-build is useful for many use cases and required for use cases like keeping an up-to-date Wikidata index.
We thus want to enable the modification of the data at runtime using [SPARQL Update](#sparql-update) and the [Graph Store Protocol](#sparql-graph-store-http-protocol).
Updating the data should be **correct** with respect to to the standards being implemented, **easy to use**, **fast** and applied updates should have **little performance impact**.

## Implementation

On a high level the updates in QLever are easy to understand. Due to QLevers implicit graph existence *all* operations only need to add or remove some triples in the end. In many cases like `LOAD` or `DELETE INSERT WHERE` the set of triples to add or remove is not trivial, but once the triples have been computed the operations reduce to adding or removing triples.

For each permutation and block we will keep one ordered list of the triples that have been changed. When an operation changes a triple then we determine in which block the triple would fall and add it to the coresponding change list for each permutation. After an operation we also update the metadata of a block because the first and last triple may have changed.

All operations that use the dataset start with an `IndexScan`. An `IndexScan` reads a permutation in a blockwise manner. It may read the whole permutation or only some blocks. When reading a block for an `IndexScan` we merge the block being read with the modified triples in that block using a zip join. We generally return the triples obtained from the original block. A triple in the original block is not returned if it is deleted by the modified triples. An added triple from the modified triples is returned if it is not already in the original block. The other combinations can be skipped because they have no effect (deleting non-existent triples and adding already existing triples).

Parsing SPARQL Update is fortunately very easy because we use [ANTLR](https://www.antlr.org/), a parser generator. The grammar given in the standard can easily be adapted for use with ANTLR and building an internal representation of the parsed Update is also not very hard. Though this was only this quick and easy because we transitioned to ANTLR from a hand-written parser. A large part of this transition was done as my Bachelor Thesis.  
*DELETE WHERE* and *CLEAR* only are syntactic sugar for other Graph Update operations. All Graph Management operations can be broken down into basic Graph Update operations.

{{< notice type="info" >}}
The Graph Management Operations can be broken down this way because QLever has implicit graph existence. This means that QLever does not explicitly track the existence of graphs. A graph exists iff there are triples in it. Explicit graph existence enables empty graphs to exist. If graph existence were explicit, then at a minimum additional operations for adding and removing a graph would be required.
{{< /notice >}}

Graph Store Protocol requests can approximately be translated into equivalent SPARQL Update requests. This makes the majority of the functionality easy to implement, while some [niche cases](#completeness) require extra work. For this work we translate the Graph Store Protocol requests into their equivalent SPARQL Update requests and ignore the niche cases.

## Discussion

### Correctness

All major parts of the update implementation are thoroughly tested with unit tests. QLever and its update implementation are already being used in production at [UniProt](https://sparql.uniprot.org/) and for a [live copy of Wikidata by the chair](https://qlever.dev/wikidata).

To further test that update works correctly we can

1. Create an index with the [Olympics](https://github.com/wallscope/olympics-rdf) data in the default graph. The default graph now contains the Olympics dataset and the graph `<INSERTED>` contains no triples.
2. Insert the data a second time into another graph `<INSERTED>` with `LOAD`. We can verify that both graphs now contain the same triples with a query from the [OSM Live Updates for SPARQL Endpoints](https://ad-blog.cs.uni-freiburg.de/post/osm-live-updates-for-sparql-endpoints/#a-idcorrectnessa31-correctness) which gives us the difference between the graph's triples
   ```sparql
   SELECT ?s ?p ?o WHERE {
     {
       {
         GRAPH ql:default-graph {
           ?s ?p ?o .
         }
       } MINUS {
         GRAPH <INSERTED> {
           ?s ?p ?o .
         }
       }
     } UNION {
       {
         GRAPH <INSERTED> {
           ?s ?p ?o .
         }
       } MINUS {
         GRAPH ql:default-graph {
           ?s ?p ?o .
         }
       }
     }
   }
   ```
3. Delete all triples in the default graph that are in `<INSERTED>` with `DELETE { ?s ?p ?o } WHERE { GRAPH <INSERTED> { ?s ?p ?o } }`. The default graph is now empty and `<INSERTED>` now contains the Olympics dataset.

### Completeness

[Update](#sparql-update) is implemented fully with all operations. Note that QLever has implicit graph existence.

The major parts of [Graph Store Protocol](#sparql-graph-store-http-protocol) are implemented. The `GET`, `PUT`, `DELETE` and `POST` operations are supported. We also added a non-standard but natural `TSOP` operation which does a `DELETE DATA` of the payload - the opposite of `POST`s `INSERT DATA`.  
`HEAD` and the optional `PATCH` operations are not supported. There are also some niche cases that are not yet handled correctly

- `PUT` does not return `201 Created` when a new graph is created, it always returns `200 OK`
- `POST` without a graph IRI is not supported (a graph IRI is chosen and returned afterwards in the `Location` header)
- the `multipart/form-data` content type is not supported

`multipart/form-data` is easy to implement, but out of scope for this project. All the other deviations (except `PATCH`) can be implented using similar mechanisms. Once one is implemented the others can be implemented easily as well.

### Performance (Impact)

{{< notice type="warning">}}

QLever is under active development. The performance numbers presented below are a snpashot from September 2025 and have already been improved significantly since then.

{{< /notice >}}

Performance is impressive for a first iteration of the Update feature considering that the main focus was to achieve a high coverage of the [SPARQL Update](#sparql-update) and [Graph Store Protocol](#sparql-graph-store-http-protocol) standards. The current version is already able to catch up and keep up with the [Wikidata knowledge graph](https://qlever.dev/wikidata) for some time. The throughput of updates is better for larger updates. The throughput of updates deteriorates linearly with the number of already updates triples. The impact of applied updates on queries can be high but depends heavily on the type of the query.

We repeatedly delete 10000 random triples on a QLever instance to test how the update performance evolves with the number of already updated triples.
We observere a linear increase for the deletion of the 10000 triples with the number of already inserted triples.

{{< figure src="img/eval/update_over_time.png" width="750px" >}}

To test the throughput for different update sizes we test updates that delete a different number of triples. The updates of the QLever instance are reset between runs. Each update size is tested 10 times and we take the mean. The plot shows the throughput (update size divided by the time for the update) against the update size.
Under good conditions the throughput is around 350.000 triple per second.
The throughput decreases significantly for update sizes below 1 million triples.

{{< figure src="img/eval/triples_per_s_batch_size.png" width="750px" >}}

Finally we evaluate the performance impact of applied updates to queries. To do this we run a curated set of queries when no updates are applied and when certain fractions of the dataset have been updated. We observe that updates can result in a big impact to the query performance, but the impact depends heavily on the nature of the query being run.

[Predicate frequencies](https://qlever.dev/wikidata/kKNJ0F) counts the occurences of all predicates across the whole dataset. It sees a heavy performance impact with an 80% increase in the runtime of the query. This query requires the whole dataset to compute and as such will also come in contact with all the updates that have been applied. Heavy optimizations have also been done to make queries like this fast in QLever.

[Scientific articles](https://qlever.dev/wikidata/oCjDui) retrieves all scientific articles and their author if available. This query has a large result with around 42 mio. rows. Most of the query's time is spent on aggregations and only very little time is spent on `IndexScan`s. We see no increase in the execution time for this query.

[People](https://qlever.dev/wikidata/cg6A8w) calculates people who were born and died on the same day of the year. For this query we see about a 4% increase in the runtime for the query with 0.1% of the dataset being updated.

{{< figure src="img/eval/query_performance.png" width="750px" >}}

## Conclusion and Future Work

The implementation supports the majority of SPARQL Update and Graph Store Protocol. We extended it with a method that we felt was missing. The implementation has been available in QLever for some time while developing and has already been used in [the official UniProt SPARQL endpoint](https://sparql.uniprot.org/) and as a backend for [a Scholia instance run by the chair](https://qlever.scholia.wiki/). Updating is fast enough to keep up with the [Wikidata knowledge graph](https://qlever.dev/wikidata) with almost no delay.

While QLever's updating should be fast enough for most needs, there are some areas that we want to improve. Both Update and GSP use the same base for updating, so both will see performance improvements if the speed of updates is improved there. We see this as the most important area to improve on.

- Smaller updates are comparatively slower per triple, because there is a constant overhead. Reducing the overhead in general and eliminating it completely in special cases will be a target.
- When a signifcant proportion of the triples has been updated, there is a noticeable performance impact. The goal is to reduce the performance impact to a level that instances running QLever with updates, like Wikidata, can be run indefinitely.

The size of updates is currently limited because the whole update is processed as one piece. We want to process the update in chunks similar to how queries are computed. This will enable larger updates and we also expect a small performance improvement from this. Both Update and GSP will benefit from improvments in this area. For GSP it is also natural to parallelize the deserialization of the RDF data.

Implementing the remaining parts of the standard (see [Completeness](#completeness)) will also be an area for future improvement. The missing parts are all niche and we expect that they are used sparsely. This assesment might change with user feedback, increasing the priority of features.
A related area are the supported media types for the Graph Store Protocol for input and output of serialized RDF data. For output a wide range of media types (CSV, TSV, Turtle, N-Triples, JSON, XML, Binary, QLever JSON) is already supported. For input only *Turtle* and *N-Triples* are supported. Adding support for more media types here would make QLever more versatile.

There may also arise the need for extensions to the standardized functionality like the already implemented `TSOP`. This will depend on the needs of the users.
