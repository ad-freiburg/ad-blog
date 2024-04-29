---
title: "Automated standard compliance testing for QLever"
date: 2024-04-21T16:25:11+02:00
author: "Rico Andris"
authorAvatar: "img/ada.jpg"
tags: []
categories: []
image: "img/project-automated-standard-compliance-testing-for-qlever/website-all.jpg"
draft: true
---

The SPARQL engine <a href="https://qlever.cs.uni-freiburg.de/" target="_blank">QLever</a> 
has been designed with the intention of providing comprehensive support for <a href="https://www.w3.org/TR/sparql11-query/" target="_blank">SPARQL 1.1</a>.
In this project, we implement automated standard compliance testing using the SPARQL 1.1
test suite (a collection of test cases) and a web-based visualization tool for the test results.

---
<!--more-->

## Content
<ol>
    <li><a href="#intro">Introduction</a></li>
    <li><a href="#test-suite">SPARQL 1.1 Test Suite</a></li>
    <li><a href="#impl">Implementation</a></li>
    <li><a href="#results">Results</a></li>
    <li><a href="#conc">Conclusion</a></li>
</ol>

----

## 1. Introduction <a id="intro"></a>
The SPARQL Protocol and RDF Query Language (SPARQL) is a query language used to retrieve and manipulate data stored in the Resource Description Framework (RDF) format. This allows users to query RDF data using triple patterns, which consist of subject, predicate and object statements.

QLever is a SPARQL engine designed to efficiently execute queries over large RDF datasets and aims to fully support SPARQL 1.1. To verify the support of the SPARQL 1.1 standard, it is necessary to be able to execute the entire SPARQL 1.1 test suite automatically and to visualise the results. This facilitates the identification of errors and non-compliance with the SPARQL 1.1 standard.

## 2. SPARQL 1.1 Test Suite <a id="test-suite"></a>
The World Wide Web Consortium (W3C) offers developers an evolving test suite for assessing the compliance of their implementations with the SPARQL 1.1 standard. This also enables developers to provide users with a report on the conformity of their implementations.

The SPARQL 1.1 test suite is designed to assess the full range of features included in the SPARQL 1.1 standard. This comprehensive approach results in over 600 tests, which are categorized into the following categories:
<ul>
    <li><b>Query Evaluation Test:</b> Tests containing a SPARQL query, expecting a given result</li>
    <li><b>Syntax Test:</b> Tests containing a SPARQL query, expecting a positive or negative HTTP response</li>
    <li><b>Result Format Test:</b> Similar to the Query Evaluation Test but for formats which need special handling</li>
    <li><b>Update Evaluation Test:</b> Tests containing a SPARQL update query, expecting correct changes to the given graphs</li>
    <li><b>Protocol Test:</b> Tests containing a HTTP request, expecting a given HTTP response</li>
    <li><b>Service Description Test:</b> Testing the service description vocabulary specification</li>
</ul>
These tests are grouped into smaller collections depending on the functionality being tested. Each collection of tests has its own directory and manifest file. The directory contains all necessary files for the tests, for example the graph files and query files. The manifest file declares all tests. For example all the tests testing the SPARQL 1.1 JSON Format standard are in the json directory. Most tests define a default graph, on which a query has to be executed.

Example of how a test is defined in the manifest file (Turtle format):

```
<test-002> a mf:QueryEvaluationTest ;
      mf:name    "test-002" ;
      rdfs:comment  "Comment explaining test-002" ;
      mf:action
          [ qt:query  <test-002.rq> ;
            qt:data   <test-data.ttl> ] ;
      mf:result  <test-002.ttl> .
```

## 3. Implementation <a id="impl"></a>
### Extracting tests from the manifest
To extract the tests from the manifest files we use QLever. 
We simply setup QLever using the manifest file of each collection and run a query for each type of test.

For example the query to retrieve all Query Evaluation Tests:

```
PREFIX rdf:     <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX rdfs:    <http://www.w3.org/2000/01/rdf-schema#>
PREFIX mf:      <http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#>
PREFIX dawgt:   <http://www.w3.org/2001/sw/DataAccess/tests/test-dawg#>
PREFIX qt:      <http://www.w3.org/2001/sw/DataAccess/tests/test-query#>
PREFIX ut:      <http://www.w3.org/2009/sparql/tests/test-update#>
PREFIX sd:      <http://www.w3.org/ns/sparql-service-description#>
PREFIX ent:     <http://www.w3.org/ns/entailment/RDF>
PREFIX rs:      <http://www.w3.org/2001/sw/DataAccess/tests/result-set#>

SELECT DISTINCT ?type ?name ?query ?result ?data ?test (GROUP_CONCAT(DISTINCT ?feature; SEPARATOR=";") AS ?featureList) ?comment ?approval (GROUP_CONCAT(DISTINCT ?approvedBy; SEPARATOR=";") AS ?approvedByList)  ?regime
WHERE {
    ?test rdf:type mf:QueryEvaluationTest .
    BIND ("QueryEvaluationTest" AS ?type) .
    ?test mf:action ?action .
    ?action qt:query ?query .
    OPTIONAL {?action qt:data ?data .}
    OPTIONAL {?action sd:entailmentRegime ?regime .}
    OPTIONAL {?action qt:graphData  ?actionGraphData .}
    ?test mf:result ?result .
    OPTIONAL {?test mf:name ?name .}
    OPTIONAL {?test mf:feature ?feature .}
    OPTIONAL {?test rdfs:comment ?comment .}
    OPTIONAL {?test dawgt:approval ?approval .}
    OPTIONAL {?test dawgt:approvedBy  ?approvedBy .}
}
GROUP BY ?type ?name ?query ?result ?data ?test ?comment ?approval ?regime
```

### Executing the tests

**Setting up QLever**:

QLever currently does not support update actions, which makes it harder to run the tests. 
With the current QLever implementation (24.04.2024) we have to set up QLever for each graph individually. This includes indexing the graph and starting the QLever server for that index.

**Prepare and send the query**:

Most of the time the tests define a file containing the SPARQL query, which will be read and sent, but some need special handling. For example the Protocol tests, where the query is defined as a comment in the manifest file and needs to be extracted and prepared before being sent.

The SPARQL standard defines several ways to send a query. One option would be to use the HTTP GET method, but for our purposes the other option using the POST method is better because we can put the given query into the request message body. We just need to set the correct HTTP headers. The Content-Type header is either `application/sparql-query` or `application/sparql-update` depending on the test. The Accept header lets us define the desired format given by the QLever server. It makes our life easier if the given result format is equal to the result format of the response. We infer the MIME-Type by looking at the file ending of the given result file. For example `.srx` is the ending for the SPARQL 1.1 Query Results XML format which hast the MIME-type `application/sparql-results+xml`.

#### Evaluate response
**Check response**:

Before comparing the results we have to check if the HTTP response headers are correct. If the response status code is 200-399 we can compare the result in the HTTP response body with the test result expected by the test. Except for some tests, where the result is not relevant. For those tests we only compare the HTTP response status code and headers with the status and headers expected by the test. For example some Protocol tests check if the status and the Content-Type to a given HTTP request are correct.

**Compare result**:

If we want to compare the results we have to first consider the format of the results.

The SPARQL 1.1 standard defines the following formats:

<ul>
    <li>Turtle or RDF/XML</li>
    <li>SPARQL 1.1 Query Results XML Format</li>
    <li>SPARQL 1.1 Query Results CSV/TSV Format</li>
    <li>SPARQL 1.1 Query Results JSON Format</li>
</ul>

For each of these formats we need to implement a comparison.
For the Turtle and RDF/XML format which are formats describing an RDF graph we can use the `RDFlib` package.

For the other formats there usually exists a library for the general format. For example for the SPARQL 1.1 Query Results JSON Format we could use a module including JSON comparison. This does not work due to SPARQL specifics and our design choices, which are oriented towards QLever.

We implemented a custom comparison for all formats using the following method:
<ol>
    <li>Iterate over the elements</li>
    <li>Remove matching elements in both results</li>
    <li>If both results are empty the results are equivalent</li>
</ol>

When matching the elements we ignore the order, handle the bank nodes and take the QLever specifics into account.


#### Highlight differences in the result
Highlighting the differences makes them easier to find when we later display the results on our website. To do this we build a string representation of the given result format. Then we highlight the parts that do not have a match in the other result. The part is highlighted by constructing an HTML element. Then we replace the leftover part with the newly created HTML element.

Basic example (CSV format):
```
Result 1:
s,p,o
1,2,3
1,1,1
Result 2:
s,p,o
1,2,3
2,2,2

Replace 1,1,1 with <span class="red">1,1,1</span>
Replace 2,2,2 with <span class="red">2,2,2</span>

Result 1:
s,p,o
1,2,3
<span class="red">1,1,1</span>
Result 2:
s,p,o
1,2,3
<span class="red">2,2,2</span>
```

### Website
The website was build using HTML, CSS, JS and to improve the look and speed up the development we used <a href="https://getbootstrap.com/">Bootstrap</a> and its elements.
We did not implement a custom backend server and instead use the GitHub pages or the python built in http server (`python -m http.server`) to host our website to visualize the results.

![Select test suite run](/img/project-automated-standard-compliance-testing-for-qlever/website-run.jpg)
<center style="margin-top:-35px;margin-bottom:55px;">Figure 1: Selecting different test suite runs.</center>

![Filter tests](/img/project-automated-standard-compliance-testing-for-qlever/website-filter.jpg)
<center style="margin-top:-35px;margin-bottom:55px;">Figure 2: Filter tests.</center>

![Compare results](/img/project-automated-standard-compliance-testing-for-qlever/website-compare.jpg)
<center style="margin-top:-35px;margin-bottom:55px;">Figure 3: Compare results.</center>

## 4. Results <a id="results"></a>
Our implemantation is able to automaticly execute and visualize 600 tests:

<ol>
    <li>282 Query Evalutation Tests</li>
    <li>3 Result Format Tests</li>
    <li>94 Update Evaluation Tests</li>
    <li>169 Syntax Tests</li>
    <li>52 Protocol tests</li>
</ol>

Of these tests 23.83% passed, 69.33% failed and 6.83% "semi-passed". 
"Semi-passed" means that they failed, but the differences between the results are deemed close enough by the
QLever developers.

To get a better understanding we can take a look at the conformance of certain categories of the SPARQL 1.1 standard:

| Category                                      | Tests | Passed | Semi-Passed | Failed | Pass Rate     |
|-----------------------------------------------|-------|--------|-------------|--------|---------------|
| SPARQL 1.1 Query Language                    | 301   | 97     | 39          | 165    | 32.22% / 45.18% |
| SPARQL 1.1 Update                            | 157   | 21     | 0           | 136    | 13.38%        |
| SPARQL 1.1 Query Results, CSV and TSV Formats| 6     | 6      | 0           | 0      | 100%          |
| SPARQL 1.1 Query Results, JSON Format        | 4     | 0      | 2           | 2      | 0% / 50%      |
| SPARQL 1.1 Federation Extensions             | 10    | 0      | 0           | 10     | 0%            |
| SPARQL 1.1 Entailment Regimes                | 70    | 4      | 0           | 66     | 5.71%         |
| SPARQL 1.1 Protocol                          | 34    | 13     | 0           | 21     | 38.24%        |
| SPARQL 1.1 Graph Store HTTP Protocol         | 18    | 2      | 0           | 16     | 11.11%        |
