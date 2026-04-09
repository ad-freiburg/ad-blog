---
title: "Project Efficient Export of Construct Query Results"
date: 2026-04-07
author: "Marvin Stoetzel"
authorAvatar: "img/ada.jpg"
tags: []
categories: []
image: "img/writing.jpg"
---
The SPARQL CONSTRUCT query form allows clients to extract and transform RDF data into a new graph.
In QLever, the original CONSTRUCT export pipeline was up to 2x slower than an equivalent SELECT export on the same data.
This post describes the analysis of the original implementation, 
the design and implementation of an improved version, 
an empirical evaluation of the speedup achieved, 
and a profiling-based analysis of the remaining overhead that motivates concrete directions for future work.

<!--more-->
# Table of Contents
- [Introduction](#introduction)
- [The RDF Data model](#the-rdf-data-model)
    - [RDF serialization formats](#rdf-serialization-formats)
    - [SPARQL](#sparql)
    - [CONSTRUCT queries](#construct-queries)
    - [QLever](#qlever)
    - [How QLever processes a query](#how-qlever-processes-a-query)
  - [Motivation: The construct export is slow](#motivation-the-construct-export-is-slow)
    - [Benchmarking Setup](#benchmarking-setup)
    - [Results](#results)
  - [Original Implementation](#original-implementation)
    - [How the original implementation worked](#how-the-original-implementation-worked)
    - [Inefficiencies in the Original Implementation](#inefficiencies-in-the-original-implementation)
  - [Improved implementation (contribution)](#improved-implementation-contribution)
    - [Phase 1](#phase-1--template-preprocessing-constructtemplatepreprocessor)
    - [Phase 2](#phase-2--variable-resolution-constructbatchevaluator--evaluatebatch)
    - [Phase 3](#phase-3--template-instantiation-constructtripleinstantiator--instantiatebatch)
    - [Phase 4](#phase-4--formatting-formattedtripleadapter--stringtripleadapter-in-constructtriplegenerator)
    - [Orchestration](#orchestration)
  - [Evaluation](#evaluation)
    - [Methodology](#methodology)
    - [Results](#results)
  - [Profiling the remaining overhead](#profiling-the-remaining-overhead)
    - [Results and Observations](#results-and-observations)
  - [Future Work](#future-work)
  - [Declaration on the Use of Generative AI](#declaration-on-the-use-of-generative-ai)
  - [References](#references)

# Introduction
In the following we will introduce the concepts which are necessary to understand the context of the improvements
to the CONSTRUCT export pipeline.

## The RDF data model
The RDF data model is based on the idea of making statements about resources (in particular web resources) 
in expressions of the form *subject-predicate-object*, known as *triples*.
The *subject* denotes the resource, the *predicate* denotes traits or aspects of the resource, 
and expresses a relationship between the *subject* and the *object*.[^2]
RDF presents data as a directed graph.
An RDF graph statement is, in this directed graph, represented by:
(1) a node for the subject,
(2) a directed edge from subject to object, representing a predicate, and
(3) a node for the object.

Below is an example of a collection of RDF triples from [^1].
```ntriples
<Bob> <is a> <person>.
<Bob> <is a friend of> <Alice>.
<Bob> <is born on> <the 4th of July 1990>. 
<Bob> <is interested in> <the Mona Lisa>.
<the Mona Lisa> <was created by> <Leonardo da Vinci>.
<the video 'La Joconde à Washington'> <is about> <the Mona Lisa>
<Alice> <is interested in> <the Mona Lisa>.
<Alice> <is interested in> <the video 'La Joconde à Washington'>.
```
*Listing 1*\
A set of RDF triples is also called a *knowledge graph*, or *knowledge base*.
There are three types of RDF data that occur in triples: IRIs, literals and blank nodes [^1].

**IRI**. An IRI (International Resource Identifier) is an identifier for a resource such as a person, document, 
or abstract concept. 
URLs, which serve as web addresses, are one form of IRI.
Not all IRIs imply a location or how to access a resource, some solely serve as identifiers. 
The same IRI can be reused across different RDF graphs to refer to the same resource. 
For example, `http://dbpedia.org/resource/Leonardo_da_Vinci` is used in DBpedia 
(a large RDF knowledge base derived from Wikipedia) 
as the identifier for Leonardo da Vinci. 

**Literal**.
A literal is a basic value such as a string, number, or date.
Unlike IRIs, literals do not identify resources but directly represent a value.
For example, `"the 4th of July 1990"` is a string literal representing a date.
Literals may only appear in the object position of a triple.

**Blank node**.
A blank node is a placeholder for a resource that has no IRI.
In contrast to IRIs, a blank node's identity is local to a serialization of a particular RDF graph. 
The same blank node label in two different RDF files refers to two distinct resources.
Blank nodes are used when statements need to be made about a resource without assigning it a globally reusable identifier.

For example, to express that the Mona Lisa has a cypress tree in its background without naming that specific tree:
  ```ntriples
  <Mona Lisa> <has-background-feature> _:tree .
  _:tree <is-a> <cypress tree> .
  ```
  Here, _:tree is a blank node referring to some unnamed tree.

## RDF serialization formats
A number of serialization formats exist for writing down RDF graphs:
N-triples, Turtle, JSON-LD, RDFa, and RDF/XML.
Different serializations of the same RDF graph are logically equivalent.

Below we state the triples of the example knowledge base *Listing 1* in N-triples format, 
which is the simplest of the serialization formats. 

```
<http://example.org/bob#me> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://xmlns.com/foaf/0.1/Person> .
<http://example.org/bob#me> <http://xmlns.com/foaf/0.1/knows> <http://example.org/alice#me> .
<http://example.org/bob#me> <http://schema.org/birthDate> "1990-07-04"^^<http://www.w3.org/2001/XMLSchema#date> .
<http://example.org/bob#me> <http://xmlns.com/foaf/0.1/topic_interest> <http://www.wikidata.org/entity/Q12418> .
<http://www.wikidata.org/entity/Q12418> <http://purl.org/dc/terms/title> "Mona Lisa" .
<http://www.wikidata.org/entity/Q12418> <http://purl.org/dc/terms/creator> <http://dbpedia.org/resource/Leonardo_da_Vinci> .
<http://data.europeana.eu/item/04802/243FA8618938F4117025F17A8B813C5F9AA4D619> <http://purl.org/dc/terms/subject> <http://www.wikidata.org/entity/Q12418> .
```

What follows is a short description of the N-triples syntax, using the listing above as an example. \
The datatype of a literal is appended via `^^`. 
A datatype specifies how the literal value should be interpreted. 
For example, whether "1990-07-04" is a date or just a string. 
Common datatypes are defined by XML Schema (a standard that defines a set of primitive datatypes), 
such as `xsd:date`, `xsd:integer`, `xsd:string`.
For plain string literals the datatype can be omitted: 
`"Mona Lisa"` is shorthand for `"Mona Lisa"^^xsd:string`. 
String literals can optionally carry a language tag, which identifies the natural language the string is written in. 
Language tags are written with an `@` suffix, e.g. `"La Joconde"@fr` for French, or `"Mona Lisa"@en` for English.

## SPARQL 
SPARQL is an RDF query language, that is, a query language for retrieving and manipulating data stored in RDF format.\
The most common query form is SELECT, which returns results as a table of variable bindings.\
The WHERE clause contains a set of triple patterns called a *basic graph pattern*.\
Triple patterns are like RDF triples except that subject, predicate, 
or object may be a variable (a string starting with `?`) 
or a constant (a fixed IRI or literal).

For example, 
the following query finds everyone (`?person`) 
who is interested in something (`?thing`) that was created by someone (`?creator`):


```sparql
SELECT ?person ?thing ?creator WHERE {
?person <is interested in> ?thing .
?thing <was created by> ?creator .
}
```

Against our example knowledge base (Listing 1), this returns:
| ?person | ?thing | ?creator |
---------|--------|----------|
| Bob | the Mona Lisa | Leonardo da Vinci |
| Alice | the Mona Lisa | Leonardo da Vinci |


The query engine (the software component that computes the result of a SPARQL query against an RDF knowledge base) 
finds all combinations of RDF terms that can be subsituted for the variables 
such that every triple pattern in the WHERE clause holds simultaneously against the data.\
Alice's interest in in the video produces no row because no `<was created by>` triple exists for the video 
(only combinations of RDF terms where all triple patterns match appear in the result).

## CONSTRUCT queries 
A CONSTRUCT query produces a new RDF graph rather than a table of variable bindings. 
The CONSTRUCT clause clause specifies a *graph template*: 
a set of triple patterns that may contain variables and constants. \
For each result row produced by the WHERE clause, 
the engine substitutes the variable values into the template and adds the resulting triples to the output graph. 
The final output is the union of all such triples across all result rows.

Consider the following CONSTRUCT query applied to our knowledge base from *Listing 1*:
```
  CONSTRUCT { 
    ?person <has-interest> ?thing .
  }
  WHERE {
    ?person <is interested in> ?thing .
  }
```
This query produces the following RDF graph:
```
<Bob> <has-interest> <the Mona Lisa> .
<Alice> <has-interest> <the Mona Lisa> .
<Alice> <has-interest> <the video 'La Joconde à Washington'> .
```
Unlike the SELECT query from the previous section, the result is not a table but a new set of RDF triples that can be 
stored, exported, or queried further. \
CONSTRUCT queries are particularly useful when the goal is not to inspect data in a table 
but to export or transform it as RDF. 
For example, to extract a subgraph from a large knowledge base for use in another system, 
or to produce a self-contained RDF file for exchange or archival.

## QLever
"QLever is a graph database implementing the RDF and SPARQL standards.
QLever can efficiently load and query very large datasets,
even with hundreds of billions of triples,
on a single commodity PC or server."[^4]
It is a open source project  written in the programming language C++ developed
by the Chair of Algorithms and  Data Structures at the University of Freiburg [^5]

**Index and index permutations**.
Before the QLever engine answers queries to client requests, the RDF knowlege base is built into an **index**
(a set of data structures optimized for fast triple lookup, which are stored on disk) 
using a separate offline indexing step.
Each triple `(subject, predicate, object)` is stored as three integer IDs, one per term (more on the IDs below).

To support arbitrary triple access patterns efficiently, QLever stores the triples in six **permutations**:
all six orderings of the three positions (SPO, SOP, PSO, POS, OSP, OPS).
Each permutation is a sorted list of all triples in that order.
So, the triples in the SPO permutation, for example, are sorted by their ID value of the terms in the subject
position as the first sort key, 
the ID value in the predicate position as the second sort key, 
and the ID value in the object position as third sort key.
This implies that, naturally, in the SPO permutation, there are large blocks where consecutive triples share the same 
RDF term in the subject position.

Each ID is technically a tagged 64-bit integer: 
4 bits encode the *type* of the value, and 60 bits encode the value itself. 
For IRIs and string literals, the value bits are an index into the vocabulary (we will introduce the concept of the
vocabulary in a second).

Conceptually, 
the **vocabulary** is an array containing all distinct IRIs and literals that appear in the RDF knowledge base.
Each term is assigned a unique integer ID.
All triples in the index, and all intermediate query results, are represented using these integer IDs rather than
strings, which keeps memory usage low and makes comparisons fast.
The ID each RDF term is assigned is an index into the *vocabulary* which maps to the corresponding string value for that
RDF term.

The actual vocabulary and index implementation is more complex than this conceptual picture, 
but the essential idea is that the vocabulary a mapping from IDs to RDF term strings, 
consecutive IDs point sequential positions of the vocabulary array on-disk, 
and the QLever engine makes use of *index permutations*, which are lists of RDF triples in particular sorted orders.

## How QLever processes a query
To understand where the CONSTRUCT export fits in, 
it helps to see the big picture of what QLever does when it receives a query.

```
┌──────────────────────────────────────────────┐
│                    Client                    │
└──────────────────────┬───────────────────────┘
                       │ HTTP request
                       │ (query string, requrested output format)
                       ▼
┌──────────────────────────────────────────────┐
│           (1) Parse HTTP request             │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│        (2) Parse SPARQL query string         │
│              -> ParsedQuery                  │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│          (3) Plan and optimize query         │
│          -> QueryExecutionTree               │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│          (4) Evaluate query                  │
│   execute QueryExecutionTree -> IdTable      │
└──────────────────────┬───────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────┐
│          (5) Serialize result                │
│   decode integer IDs -> RDF terms            │
│   [CONSTRUCT: instantiate graph template]    │
│   serialize to requested output format       │
└──────────────────────┬───────────────────────┘
                       │ HTTP response
                       │ (serialized bytes)
                       ▼
┌──────────────────────────────────────────────┐
│                    Client                    │
└──────────────────────────────────────────────┘
Figure 2: The QLever query processing pipeline.
```

**1. Receiving and Parsing the HTTP request.**
The client sends an HTTP GET or POST to QLevers HTTP server.
QLever extracts the query string, the requested output format, and other parameters.

**2. Parsing the SPARQL query.**
The query string is passed to `SparqlParser::parseQuery()`,
which produces a `ParsedQuery`, which is a structured internal representation of the query.

**3. Query planning and optimization**
A `QueryPlanner` transforms the `ParsedQuery` into a `QueryExecutionTree`.
The `QueryExecutionTree` is a tree of concrete operations (index scans, joins, filters, etc.) 
that will be executed to evaluate the query on the given knowledge base.

**4. Query evaluation.**
The `QueryExecutionTree` is executed against the index, producing an `IdTable`.
The `IdTable` is a table of IDs, with one column variable bound by the WHERE clause and one row per query solution.

**5. Result serialization.**
`ExportQueryExecutionTrees::computeResult()` transforms the `IdTable` into the requested output format.
The integer IDs are decoded back into readable RDF terms (IRIs, Literals).
For CONSTRUCT queries, the decoded terms are used to instantiate the graph template, producing the output triples.
The result is then serialized and streamed back to the client as the HTTP response.

# Motivation: The CONSTRUCT Export is Slow
The goal of this project is to improve the performance of the CONSTRUCT query export in QLever.
Before optimizing, we first establish that a meaningful performance gap actually exists.

To isolate the cost of the CONSTRUCT export pipeline, we compare it against an equivalent SELECT query on the same data.
Both queries run the same WHERE clause and therefore perform the same query evaluation work.
The only difference is the export step.
Any gap in export time is therefore attributable to the CONSTRUCT export pipeline itself.

## Benchmarking Setup
**Query.** We use the following query, which retrieves X triples from the dataset:
```sparql
SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT X
```

For the CONSTRUCT variant, the construct template mirrors the SELECT query:
```sparql
CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o } LIMIT X
```

We vary the number of result rows using `LIMIT` (10,000 / 100,000 / 1,000,000) in order to see whether a potential
performance gap scales with the number of rows.

**Output format.** 
We benchmark across multiple common export formats to get a representative picture.
`TSV`, `CSV`, and `qleverJson` are supported by both query forms and are used for the SELECT vs. CONSTRUCT comparison.
We additionally report `Turtle` times for CONSTRUCT queries in isolation, 
as `Turtle` is a common serialization format for RDF graphs.

**Methodology.**
We use QLever's internal query time, 
which covers the full request handling but excludes network transfer. 
Before each timed run, 
we evict the index permutation and vocabulary files from the OS page cache using `vmtouch -e`,
so that each measurement reflects realistic end-to-end query time including the cost of loading data from disk.
We run the same query five times and report the median. 
The script used to produce these measurements is available [here](artefacts/2026-04-07_problem-statement-measurements.sh.txt).
All measurements were taken using a binary compiled in `Release` mode at git commit `a5e4bf7` from the master branch 
of the QLever repository [^5] on a machine with the following specifications: 
CPU: AMD Ryzen 5 4600G, RAM: 30.7GiB, Storage: 1 TB NVMe SSD.

## Results
| Output format | LIMIT | SELECT (ms) | CONSTRUCT (ms) | Ratio |
|---------------|-------|-------------|----------------|-------|
| TSV           | 10k   | 116         | 133            | 1.15x |
| TSV           | 100k  | 510         | 716            | 1.40x |
| TSV           | 1M    | 2087        | 4087           | 1.96x |
| TSV           | 10M   | 11041       | 24832          | 2.25x |
| CSV           | 10k   | 119         | 134            | 1.13x |
| CSV           | 100k  | 514         | 714            | 1.39x |
| CSV           | 1M    | 2105        | 4115           | 1.95x |
| CSV           | 10M   | 11054       | 24867          | 2.25x |
| qleverJson    | 10k   | 124         | 140            | 1.13x |
| qleverJson    | 100k  | 603         | 772            | 1.28x |
| qleverJson    | 1M    | 2923        | 4660           | 1.59x |
| qleverJson    | 10M   | 18899       | 30143          | 1.59x |
| Turtle        | 10k   | n/a         | 133            | n/a   |
| Turtle        | 100k  | n/a         | 706            | n/a   |
| Turtle        | 1M    | n/a         | 4005           | n/a   |
| Turtle        | 10M   | n/a         | 24055          | n/a   |

The `SELECT (ms)` and `CONSTRUCT (ms)` columns report the median wall-clock time in milliseconds over the five measured
runs. The `Ratio` column is the CONSTRUCT time divided by the SELECT time.

**Observation**:
The CONSTRUCT export is consistently slower than the equivalent SELECT export across all formats and row counts. 
For TSV and CSV the CONSTRUCT export takes approximately 2x as long at 10 million rows. 
The ratio grows with the number of rows (from ~1x at 10k rows to ~2x at 10M rows), 
indicating that the overhead of the CONSTRUCT export pipeline scales roughly linearly with the number or result rows.

In the next section we examine the original implementation of the CONSTRUCT Export pipeline to understand how we can
improve it.

# Original Implementation

## How the original implementation worked
The core of the CONSTRUCT export is a single function: `constructQueryResultToTriples`. \
Its structure is a straightforward nested loop: \
(the table which is the result from computing the WHERE clause of the CONSTRUCT query) 
iterate over the triple patterns in the CONSTRUCT template and evaluate each triple. \
Evaluating a triple means resolving each of its three positions (subject, predicate, object) to a concrete string. \
If all three resolve successfully, the triple is emitted.

Let's make this concrete via an example, suppose the query is:
```sparql
CONSTRUCT { ?person <has-interest> ?thing }
WHERE     { ?person <is interested in> ?thing }
```

Let us walk through the execution of this CONSTRUCT query on the example knowledge base from earlier (Listing 1). \
The QLever engine executes the WHERE clause and produces the following `IdTable` as result:

| row | `?person` (col 0) | `?thing` (col 1) |
|-----|-------------------|------------------|
| 0   | `VocabId(42)`     | `VocabId(17)`    |
| 1   | `VocabId(99)`     | `VocabId(17)`    |

Each cell of the table holds a `ValueId` 
(the type used in QLever's implementation to represent the integer ID of an RDF term). \
For IRIs and literals stored in the main vocabulary, this is a `VocabIndex`, 
(which is an integer that serves as an index into the on-disk vocabulary).
We write `VocabId(id)` here to emphasize that the `ValueId` is a `VocabIndex`.

The CONSTRUCT template `{ ?person <has-interest> ?thing }` is represented internally as a list of `GraphTerm` triples. \
Each position in a triple is one of: \
a `Variable`, an `Iri`, a `Literal`, or a `BlankNode`.

How a `GraphTerm` is evaluated depends on its type:
- `Iri` or `Literal`: the string representation is stored directly in the object and is returned immediately,
without any vocabulary lookup.
- `Variable`: based on it's column index in the `IdTable`
(the mapping from variable names to column indices is determined by the query planner and passed in externally),
the `ValueId` for the current result row being processed
is retrieved from the `IdTable`, and then resolved to a string via a vocabulary lookup.
- `BlankNode`: the blank node identifier is constructed from the blank node's label and the current result row number, 
producing a  unique string such as `_:g42_b0`. No vocabulary lookup is needed. 

**Processing row 0:** \
The template triple `?person <has-interest> ?thing` is evaluated term by term. \
The subject `?person` is a `Variable`,
so the implementation reads column 0 of the current result table row, obtaining `VocabId(42)`, and resolves it via a
vocabulary lookup to `"<Bob>"`. \
The predicate `<has-interest>` is an `Iri`, so its string is returned directly from the object. \
The object `?thing` is again a `Variable`; column 1 yields `VocabId(17)`,
which resolves to `"<the Mona Lisa>"`.

The function emits a \
`StringTriple("<Bob>", "<has-interest>", "<the Mona Lisa>")`.

**Processing row 1:** \
The same template triple is evaluated again from scratch. \
The subject `?person` resolves via column 0 to `VocabId(99)`, which a vocabulary lookup turns into `"<Alice>"`. \
The predicate `<has-interest>` is returned directly from the `Iri` object as before. \
The object `?thing` again yields `VocabId(17)` from column 1, the same `ValueId` as in row 0,
which is looked up independently, again producing `"<the Mona Lisa>"`.

The function emits a \
`StringTriple("<Alice>", "<has-interest>", "<the Mona Lisa>")`.

**Serialization.** \
Once `constructQueryResultToTriples` has yielded a `StringTriple`, a format-specific serializer
produces a stream of string objects according to the output serialization format specified for the query. \
The output format is determined once per request from the HTTP `Accept` header. \

## Inefficiencies in the Original Implementation
The walkthrough above reveals three inefficiencies in the original implementation.

**1. Variables appearing in multiple template triples are resolved multiple times per row.**
The old implementation calls evaluateTriple once per (row, template triple) pair, which in turn calls 
`idToStringAndType` for each variable position independently.
If the same variable appears in more than one template triple, for example `?s` in both `?s <p1> ?o` and `?s <p2> ?o`, 
its `ValueId` is looked up separately for each template triple it appears in, on every row.

**2. The same `ValueId` is often resolved multiple times.** \
Result tables frequently contain the same `ValueId` in many rows.
In the original implementation, each occurrence triggers an independent vocabulary lookup.
The walkthrough made this visible: `VocabId(17)` appeared in both row 0 and row 1, but was looked up twice.\

**3. Vocabulary lookups are issued one at a time** \
Resolving a `VocabIndex` requires reading from the on-disk vocabulary, which involves decompression and string
construction (depending on how the vocabulary is actually stored on disk, we do not always need decompression here). \
The original implementation issues these lookups individually: \
one lookup per variable position per result table row. \

# Improved Implementation (Contribution)
The CONSTRUCT query export pipeline is implemented as four sequential phases, each with a single responsibility. 
The diagram below shows the data flow between the four phases.\
The left side shows the CONSTRUCT clause (triple patterns) feeding into template preprocessing; 
the right side shows the WHERE clause result (`IdTable`, `LocalVocab`) being partitioned into chunks by
`getRowIndices()`, which produces a lazy range of result chunks to support streaming the HTTP response incrementally.
Inside `ConstructTripleGenerator`, each chunk is handed to `TableWithRangeEvaluator`, 
which drives variable resolution and triple instantiation. 
Note that the internal batching performed by `ConstructBatchEvaluator` (Phase 2) is a separate concept from these 
streaming chunks.

The two streams meet inside `ConstructTripleGenerator`, 
where variable resolution, triple instantiation, and formatting takes place.
![Data flow diagram](img/data-flow.svg)
### Phase 1 — Template preprocessing (ConstructTemplatePreprocessor)
This corresponds to the *Template Preprocessing* box in the upper-left of the diagram.

In the original implementation, every term in every template triple is evaluated from scratch for each result row.
Phase 1 eliminates repeated work by inspecting the CONSTRUCT template once before any rows are processed and 
precomputing everything that can be determined at that point.

`ConstructTemplatePreprocessor::preprocess` transforms the raw `GraphTerm` triples from the CONSTRUCT clause into a
`PreprocessedConstructTemplate`. 
A `GraphTerm` can be a `Literal`, a `BlankNode`, an `Iri`, or a `Variable`. 
Each term is converted into one of three typed variants:

- `PrecomputedConstant`: for `Iri` and `Literal` terms: the string is resolved immediately and stored as a
`shared_ptr<const EvaluatedTermData>`. 
During triple instantiation (Phase 3), reusing a constant is now a reference-count increment rather than a repeated 
string construction.
- `PrecomputedVariable`: for `Variable` terms: the variable is resolved to its column index in the `IdTable` once. 
The per-row cost is then a direct array lookup by index rather than an additional map lookup by variable name on every
row.
- `PrecomputedBlankNode`: for `BlankNode` terms: the prefix (`_:g` for generated blank nodes, `_:u` for user-defined)
and suffix (`_` + label) are precomputed. 
When iterating over the rows of the result table, only the row number needs to be inserted between them to produce
a valid blank node.

A CONSTRUCT template may contain multiple triple patterns, and the same variable may appear in more than one of them.
In the original implementation, the `ValueId` for that variable would be looked up once per occurrence per row 
(so if `?x` appears in three template triples, it is looked up three times for each result row). 
To avoid this, the preprocessing phase also builds `uniqueVariableColumns_`: 
a deduplicated list of `IdTable` column indices that appear as variables anywhere in the template triples. 
Phase 2 uses this list to resolve each variable column exactly once per batch, 
regardless of how many template triples reference it.

Phase 1 runs once per query, before any rows of the result table are processed.

---
### Phase 2 — Variable resolution (ConstructBatchEvaluator / evaluateBatch)
This corresponds to the *Batch Evaluation / ConstructBatchEvaluator* box inside `ConstructTripleGenerator`, 
which receives a `TableWithRange` from `TableWithRangeEvaluator` and consults the `IdCache` shown to its right the
diagram.

**Motivation.** After Phase 1, what remains is resolving `ValueId`s for the variable positions in the graph template. 
This requires vocabulary lookups, which are expensive since the vocabulary is for the most part stored on disk 
in compressed form, so each lookup may involve a disk read and decompression.

First, the new implementation maintains an `IdCache`: an LRU cache that maps `ValueId`s to their already-resolved
strings. 
The same `ValueId` often recurs across many rows of the `IdTable` 
(for example, a predicate column in a typical SPARQL result may repeat the same IRI thousands or times). 
Without a cache, each occurrence would trigger a separate vocabulary lookup. 
The `IdCache` avoids this by storing recently resolved `ValueId`s in memory. 
The cache persists across batches within the same `TableWithRange`, 
so cache hits are possible even when the same `ValueId` recurs across batch boundaries.

Second, for `ValueId`s that are not in 
the cache, Phase 2 collects and sorts them before issuing vocabulary lookups. 
The vocabulary is an array of RDF term strings stored on disk, 
with `ValueId`s serving as indices into it. 
Sorting the `ValueId`s before lookup means that consecutive lookups access nearby positions in the vocabulary array, 
producing more sequential disk access patterns and better OS page cache utilization.
This is done one variable column at a time: the `IdTable` is stored in column-major order, 
so processing all rows of one variable column before moving to the next follows the memory layout of the `IdTable` 
and avoids the cross-column access pattern of the original per-row approach.

**Implementation.** 
`evaluateBatch` receives `uniqueVariableColumns_` from Phase 1 
and a `BatchEvaluationContext` describing a contiguous slice of the `IdTable`. 
For each variable column, `evaluateVariableByColumn` proceeds in two sub-steps:

1. **Sort and cache check**. The `ValueId`s for that column across all rows in the batch are collected and sorted. 
For each sorted `ValueId`, the `IdCache` is checked first. 
Cache hits are written directly to the result; misses are collected into a separate list.
2. **Batch resolution of misses**. 
The sorted list of cache-miss `ValueId`s  is passed to `idsToStringAndType`, 
which resolves them in bulk. 
The results are inserted into the cache and scattered back to the per-row positions in the
output.

The output is a `BatchEvaluationResult`: a map from column index to a vector of `optional<EvaluatedTerm>`, with one
entry per row in the batch.

---
### Phase 3 — Template instantiation (ConstructTripleInstantiator / instantiateBatch)
This phase corresponds to the *Triple instantiation / ConstructTripleInstantiator* box, 
which sits below `ConstructBatchEvaluator` in the diagram and receives its `BatchEvaluationResult`.

**Motivation**. 
At this point all vocabulary work is done. 
Phase 3 is a pure assembly step: combine the precomputed
template structure from phase 1 with the resolved variable values from phase 2.

`instantiateBatch` iterates over every `(row in batch, template triple)` pair.
For each term position, according to the term variant:
- `PrecomputedConstant`: the precomputed `EvaluatedTerm` shared pointer is copied into the output. This is a
reference-count increment, not a string copy.
- `PrecomputedVariable`: the resolved value is looked up in the `BatchEvaluationResult` by column index and row. If the
  value is `nullopt` the entire triple is dropped.
-`PrecomputedBlankNode`: the blank node string is constructed from the precomputed prefix, the current absolute row
index of the current row, and the precomputed suffix.

The output is a `vector<EvaluatedTriple>` with at most `numRows x number of template triples` entries, 
fewer if any triples were dropped due to unbound variables.

---
### Phase 4 — Formatting (FormattedTripleAdapter / StringTripleAdapter in ConstructTripleGenerator)
This corresponds to the *Formatting / FormattedTripleAdapter / StringTripleAdapter* box at the bottom of the diagram, 
whose two output arrows lead to the HTTP response stream and the QLever JSON serializer respectively.

**Motivation**. 
Phases 1-3 produce `EvaluatedTriple` objects, 
containing the resolved term data, independent of any output format. 
Phase 4 separates format-specific serialization into a dedicated step, 
so that the upstream phases are not concerned with output format details.

Two adapter classes inside `ConstructTripleGenerator.cpp` wrap a `TableWithRangeEvaluator` and pull `EvaluatedTriple`
objects from it one at a time:
- `FormattedTripleAdapter`: serializes each `EvaluatedTriple` into a `std::string`, applying the escaping and separators
  appropriate for the `MediaType` selected from the HTTP Accept header. It handles the Turtle, N-triples, TSV, and CSV
formats.
- `StringTripleAdapter`: formats each term into a string and returns a `StringTriple` (three separate strings), which is
  what the QLever JSON serialier consumes.
---
### Orchestration
`ConstructTripleGenerator` is the entry point for the whole pipeline. 
It runs phase 1 in its constructor, 
producing the `PrecomputedTemplate` that is shared across all subsequent preprocessing.

For each `TableWithRange` in the lazy input range produced by `getRowindices()`, 
`ConstructTripleGenerator` creates a `TableWithRangeEvaluator` that drives phases 2 and 3, 
and wraps it in either a `FormattedTripleAdapter` or a `StringTripleAdapter` (Phase 4), 
depending on the output format requested via the HTTP `Accept` header. 
The per-chunk ranges are joined into a single flat lazy stream, 
which is passed directly to the HTTP response writer, 
allowing its results to be streamed to the client incrementally without materializing the full output in memory.

# Evaluation
We evaluate the improved CONSTRUCT export pipeline against the original implementation on the DBLP dataset.

## Methodology
We use the same machine in the Problem Statement. 
Before each timed run, 
the index permutation and vocabulary files are evicted from the OS page cache using `vmtouch -e`, 
so that each measurement reflects realistic end-to-end query time including the cost of loading data from disk.
We run the query five times and report the median wall-clock time for the query as reported by the QLever engine, 
excluding network transfer overhead.
Each timed run uses a fresh server instance to avoid interference from QLever's internal query cache.
Times are reported in milliseconds. 
The script used to produce the measurements is available [here](artefacts/2026-04-07_evaluation-measurements.sh.txt).

The improved implementation was measured using a binary built in `Release` mode from the 
`construct-pipeline-refactor` branch at commit `0480d959` [^7].

## Evaluation Results
**Select** and **CONSTRUCT old** are the median times for the two query forms under the original implementation 
(commit `a5e4bf7`); **CONSTRUCT new** is the median time under the refactored pipeline (commit `0480d959`). 
**Old ratio** and **New ratio** are CONSTRUCT divided by SELECT for the respective implementation. 
**Speedup** is old CONSTRUCT divided by new CONSTRUCT.

| Format     | Limit | SELECT (ms) | CONSTRUCT old (ms) | CONSTRUCT new (ms) | Old ratio | New ratio | Speedup |
|------------|-------|-------------|--------------------|--------------------|-----------|-----------|---------|
| TSV        | 10k   | 115         | 136                | 91                 | 1.18x     | 0.79x     | 1.49x   |
| TSV        | 100k  | 507         | 706                | 422                | 1.39x     | 0.83x     | 1.67x   |
| TSV        | 1M    | 2091        | 4083               | 1556               | 1.95x     | 0.74x     | 2.62x   |
| TSV        | 10M   | 11008       | 24804              | 6545               | 2.25x     | 0.59x     | 3.79x   |
| CSV        | 10k   | 117         | 135                | 93                 | 1.15x     | 0.79x     | 1.45x   |
| CSV        | 100k  | 510         | 712                | 418                | 1.40x     | 0.82x     | 1.70x   |
| CSV        | 1M    | 2125        | 4086               | 1549               | 1.92x     | 0.73x     | 2.64x   |
| CSV        | 10M   | 11012       | 24881              | 6471               | 2.26x     | 0.59x     | 3.85x   |
| qleverJson | 10k   | 124         | 146                | 95                 | 1.18x     | 0.77x     | 1.54x   |
| qleverJson | 100k  | 597         | 776                | 475                | 1.30x     | 0.80x     | 1.63x   |
| qleverJson | 1M    | 2964        | 4703               | 2013               | 1.59x     | 0.68x     | 2.34x   |
| qleverJson | 10M   | 18868       | 30066              | 10733              | 1.59x     | 0.57x     | 2.80x   |
| Turtle     | 10k   | n/a         | 135                | 92                 | n/a       | n/a       | 1.47x   |
| Turtle     | 100k  | n/a         | 700                | 404                | n/a       | n/a       | 1.73x   |
| Turtle     | 1M    | n/a         | 3995               | 1472               | n/a       | n/a       | 2.71x   |
| Turtle     | 10M   | n/a         | 24099              | 5824               | n/a       | n/a       | 4.14x   |

**Observation.** 
The new implementation is consistently faster than the original across all formats and row counts, 
with speedups ranging from 1.49x at 10k rows to 4.14x at 10M rows. 
The speedup grows with result set size, indicating that the optimizations scale well. 
Also, the CONSTRUCT export now takes significantly less time than the SELECT export (New ratio column).

# Discussion and Future Work

## Profiling the remaining overhead
The new implementation achieves a substantial speedup over the original. 
To understand where the reamaining time goes 
and to motivate concrete directions for future work, 
we profile the new CONSTRUCT export pipeline under two cache conditions.

**Query**. 
We profile `CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o } LIMIT 10000000` exported as TSV. 
This query is an informative subject for profiling: 
every result row contains three variable positions, 
each of which must be resolved via a vocabulary lookup, 
maximising the load on the vocabulary access path.

**Tool.** 
We use perf record, 
a statistical sampling profiler that interrupts the process at a fixed frequency and records the current call stack 
at each sample. 
We visualize the output as a flamegraph: 
each bar represents a function, 
its width proportional to the fraction of samples in which it appeared on the call stack. 
Wide bars near the top of the call stack are hotspots. 
The exact script used to create the profiles can be viewed [here](artefacts/2026-04-07_evaluation-measurements.sh.txt).

**Build configuration**. 
We compile with `RelWithDebInfo` rather than `Release`. 
`RelWithDebInfo` retains debug symbols, 
allowing `perf` to resolve function addresses to human-readable names 
and correctly attribute time to inlined call sites. 
We additionally pass `-fno-omit-frame-pointer` 
to give perf reliable call stack reconstruction at negligible runtime cost.

**Cache conditions.**
We run the query under two conditions.
In the *warm-cache* run, 
we execute the query once before profiling to load the relevant data into the OS page cache, 
so the flamegraph reflects the CPU-bound work rather than IO-wait.
In the *cold-cache* run, 
we evict the index and vocabulary files from the OS page cache using `vmtouch -e` immediately before recording. 
Because `perf record` is an on-CPU profiler, 
it collects no samples while the process is blocked on disk I/O. 
A cold-cache flamegraph with a low total sample count would therefore indicate that the dominant cost is I/O wait rather
than CPU work.

**Recording procedure.** 
For each run we start a fresh server instance to avoid QLever's internal query result cache. 
We attach `perf record` to the server process, and stop recording once the response is complete. 
The full script is available [here](artefacts/2026-04-08_profiling-construct-export.sh.txt).

## Results and Observations
**wall-clock times**.
The construct warm query completed in 6,790 ms and the construct cold query in 6,630 ms,
which is a difference of only 160 ms (less than 2.5%).
Evicting the index permutations and vocabulary files from the OS page cache has almost no 
measurable effect on total query time.
This is likely evidence that the `IdCache` is absorbing the vast majority of vocabulary lookups before they reach disk.

**Flame graph analysis**.
The warm-cache and cold-cache flamegraphs are nearly identical, 
consistent with the negligible wall-clock difference. 
In the warm-cache flamegraph, 
`FormattedTripleAdapter::get` (the top level entry point of the export pipeline) accounts for 80% of total CPU time.
Within that, two cost centers stand out.
First, `VocabularyOnDisk::operator[]` accounts for 13% of total CPU time, 
representing the cost of resolving `ValueId`s to strings.
Second, `formatTriple` accounts for 18% of total CPU time, 
dominated by string manipulation operations 
(`RdfEscaping::escapeForTsv`, `absl::strings_internal::CatPieces`, and `__memmove_avx_unaligned`). 
This suggests that the serialization step is allocating and copying intermediate strings unnecessarily. 
Eliminating these allocations is a promising direction for future work.

[warm cache run interactive flamegraph](artefacts/profiles/construct_warm.svg)
[cold cache run interactive flamegraph](artefacts/profiles/construct_cold.svg)


## Future Work.
The evaluation and profiling results suggest several directions for future investigation.

**A note on the benchmark query.** 
Our evaluation uses a single SPO query (`CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o } LIMIT X`) 
whose result set has an unusual structure. 
The following queries reveal this structure for the 10M-row case:

```sparql
SELECT (COUNT(DISTINCT ?s) AS ?ds) (COUNT(DISTINCT ?p) AS ?dp) (COUNT(DISTINCT ?o) AS ?do) WHERE {
  SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000
}
```

result table:
| ?ds        | ?dp | ?do |
|------------|-----|-----|
|10,000,000  |3    | 3   |


```sparql
SELECT ?p ?o (COUNT(?s) AS ?count) WHERE {
  SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000
} GROUP BY ?p ?o ORDER BY ?p ?o
```

result table:
| ?p              | ?o  | ?count    |
|-----------------|-----|-----------|
|numberOfCreators |0    | 64,366    |
|numberOfCreators |1    | 1,152,843 |
|numberOfCreators |2    | 441,263   |
|signatureOrdinal |1    | 8,338,784 |
|versionOrdinal   |0    | 920       |
|versionOrdinal   |1    | 1,824     |

There are 10 million distinct subjects but only 3 distinct predicates and 3 distinct objects.
The `IdCache` size for this query is 3 variables x 2048 = 6,144 entries.
The six distinct predicate and object values fit entirely within the cache and likely remain hits for the entire query. 
The subject column, with 10 million distinct values, sees effectively no cache hits,
yet the warm/cold wall-clock difference is only 160 ms. 

To understand why, 
we inspect which index permutation QLever chose for this query. 
QLever's `qleverJson` export format includes a field in the response 
that describes the query execution tree 
(the sequence of physical operations the engine performed to compute the result).
We retrieve it by querying the running server (started to listen on localhost port 7001) with:

```
curl -X POST "http://localhost:7001/query" \
    -H "Content-Type: application/sparql-query" \
    -H "Accept: application/qlever-results+json" \
    --data-binary "SELECT ?s ?p ?o WHERE { ?s ?p ?o } LIMIT 10000000"
```

For the benchmark query, the relevant part of the response is:

```
"query_execution_tree": {
    "description": "LIMIT 10000000",
    "children": [
      {
        "description": "IndexScan OPS ?s ?p ?o",
        "column_names": ["?o", "?p", "?s"],
        "result_rows": 10000000
      }
    ]
  }
```

The query planner chose the OPS permutation and performed an index scan on it. 
Within each (object, predicate) block, subject `ValueId`s therefore arrive in ascending order. 
This produces more sequential access patterns in the vocabulary file, 
which likely explains why the cold-cache penalty is small despite the subject column seeing no cache hits. 
A precise explanation would require a detailed analysis of the vocabulary file layout and the actual disk access
patters, which we leave as future work. 

1. **Real-world CONSTRUCT query evaluation.** \
The evaluation and profiling results are based on a single query 
(`CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o } LIMIT X`) on the DBLP dataset, 
whose result set has a specific structure: 
many distinct subjects but very few distinct predicates and objects. 
It is unclear how the `IdCache` and sort-before-lookup optimzation perform  on queries with different result set
structures. 
An open question is also what real-world CONSTRUCT queries look like in practice, 
and whether the benchmark query is representative of them.

2. **`ValueId`-Cache parametrization.** \
The current cache size formula (`# unique variables x 2048`)
was chosen more or less  arbitrarily without proper analysis. \
A structured investigation of cache parametrization would need to address several open questions. \
2.1) What alternative cache parametrization strategies are possible? \
2.2) Along which dimensions can the cache be optimized (example dimensions could be hit rate, memory footprint, query
latency, ...)? \
2.3) Which of the dimensions from 2.2 matters most in practice? \
2.4) Given the most important dimension, how should the cache be parameterized to optimize for it?
miss rates, eviction counts, and memory footprint per query? Possibly also others?) \
2.5) How do we measure the chosen optimization target? \

3. **Investigate blocking I/O and implement batched disk reads.** \
The warm/cold wall-clock difference of only 284 ms suggests the `IdCache` is effective for the SPO query, 
but this may not hold for queries that access a larger number of distinct `ValueIds` 
or on larger RDF knowlege graphs like Wikidata. \
A structured investigation would involve: \
3.1) Understand the vocabulary file layout and access patterns. Understand how `ValueId`s map to positions in the vocabulary file. \
3.2) Establish how to measure blocking I/O time. \
3.3) Define what "representative" queries and datasets mean in this context. \
3.4) Across those representative queries and datasets, quantify the blocking I/O overhead. \
3.5) If blocking I/O is significant, investigate strategies to mitigate it. \
For example replacing individual `pread` calls (system calls that read from disk) for batch misses with batched 
sequential reads, or prefetching vocabulary entries. Understanding how similar systems approach this is a prerequisite. \
3.6) Implement the most promising mitigation strategy. \
3.7) Measure the impact of the implementation across the same representative queries and datasets, comparing blocking
I/O time, wall-clock time, and cache miss rates before and after.

4. **Eliminate unnecessary work in the export pipeline.** \
As identified in the profiling section, `formatTriple` accounts for 18% of CPU time, with the call stack suggesting 
unnecessary intermediate string allocations during escaping and concatenation. \
4.1) In this specific instance, write escaped terms directly into a pre-allocated output buffer. \
4.2) More broadly, the export pipeline should be reviewed for other instances of avoidable work introduced by suboptimal
implementation choices (unnecessary copying, redundant computation, inefficient data structures).

5. **Correctness and testing of the CONSTRUCT export pipeline**. \
5.1) Establish what correct behavior means for the CONSTRUCT export pipeline specifically according to the 
SPARQL 1.1 and RDF standards. Formulate a set of requirements that capture this "correct" behavior. \
5.2) Develop a comprehensive test suite that verifies the pipeline's output against these requirements across a range 
of query templates, edge cases, and output formats. \
5.3) Use this test suite as a safety net for future optimizations, 
ensuring performance improvements do not introduce correctness regressions.

6. **Apply pipeline improvements to the SELECT export.** \
The optimizations developed for the CONSTRUCT export address inefficiencies that are not specific to CONSTRUCT queries. 
The SELECT export pipeline resolves `ValueId`s in the same row-by-row fashion as the original CONSTRUCT implementation. 
Applying the same batching and caching approach to the SELECT export pipeline is a natural next step, 
and could yield similar speedups for SELECT queries

# Declaration on the Use of Generative AI
Generative AI tools (Claude Code, Anthropic) were used in the preparation of this work in the following ways: 
brainstorming and evaluating implementation ideas; 
exploring and analyzing the QLever codebase; 
generating code prototypes and measurement scripts; 
and assisting in drafting, structuring, and formulating text in this report.

All ideas, designs, implementations, measurements, and written content were reviewed, verified, 
and revised by the author. 

The author takes full responsibility for the accuracy and integrity of all content in this report.

# References
[^1]: W3 Org. "RDF Primer" https://www.w3.org/TR/rdf11-primer/ Accessed 2026-04-01.
[^2]: Wikipedia. "RDF" https://en.wikipedia.org/wiki/Resource_Description_Framework Accessed 2026-04-07.
[^3]: W3 Org. "SPARQL 1.1 Query Language" https://www.w3.org/TR/sparql11-query/#introduction Accessed 2026-03-18.
[^4]: "QLever Documentation" https://docs.qlever.dev/ Accessed 2026-03-18.
[^5]: "qlever" https://github.com/ad-freiburg/qlever Accessed 2026-03-18.
[^6]: W3 Org. "RDF Primer, Example 6" https://www.w3.org/TR/rdf11-primer/#section-vocabulary Accessed 2026-04-01.
[^7]: github. "construct-pipeline-refactor branch" https://github.com/marvin7122/qlever/commit/0480d959a02b04d69b017364423ce1670ca833d4 Accessed 2026-04-07.
