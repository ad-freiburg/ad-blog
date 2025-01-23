---
title: "A comprehensive tool for benchmarking and visualizing the performance of various SPARQL engines across diverse datasets, featuring automated result generation and Docker-based environment setup"
date: 2024-10-06T13:10:21+05:30
author: "Tanmay Garg"
authorAvatar: "img/ada.jpg"
tags: ["Qlever", "SPARQL", "docker", "automation", "webapplication"]
categories: []
image: "img/tags.jpg"
draft: false
---

<style>body {text-align: justify}</style>

[QLever](https://qlever.cs.uni-freiburg.de/) is a SPARQL engine that can efficiently index and query very large knowledge graphs with over 100 billion triples on a single standard PC or server. In particular, QLever is supposed to be fast for queries that involve large intermediate or final results, which are notoriously hard for other engines on the market.
To quantify Qlever’s performance advantage, in this project we design and implement a comparison tool to compare Qlever with other prominent SPARQL engines by executing a set of pre-defined SPARQL queries on multiple datasets and benchmarks and visualising the performance metrics with the help of a web application.

## Content

1. [Introduction](#introduction)
2. [Methodology](#methodology)
   - [Qlever Evaluation script](#eval_script)
   - [Automating generation of SPARQL endpoints and Benchmark setup using docker and bash scripts](#automation_all)
     - [Automating Benchmark setup](#automation_bench)
     - [Automating SPARQL endpoint generation](#automation_engine)
   - [Example execution of Qlever evaluation script](#example_exec_script)
   - [Visualise the comparison of SPARQL Engines using a Web application](#visualisation)
3. [Conclusion and future work](#conclusion)

---

## Introduction {#introduction}

The SPARQL Protocol and RDF Query Language (SPARQL) is a query language used to retrieve and manipulate data stored in the Resource Description Framework (RDF) format. It allows users to query RDF data using triple patterns consisting of subject, predicate, and object statements. Various SPARQL engines, like QLever, Blazegraph, and others, have been developed to handle different scales of datasets and query complexities, each offering unique optimizations and performance characteristics. However, due to differences in architecture and execution strategies, the performance of these engines can vary significantly across datasets and query types. This creates a need for systematic performance comparison to identify the best-suited engine for specific use cases.

A robust SPARQL engine comparison tool must accomplish several tasks.

- First, it should automate the process of executing predefined query sets against various SPARQL endpoints, ensuring consistency and reducing manual overhead.
- Additionally, it should provide mechanisms for generating SPARQL endpoints efficiently, such as through Docker containers or similar infrastructure to simplify benchmarking.
- Once queries are executed, the tool must collect and analyse performance metrics such as query execution time, failure rate, and scalability.
- Finally, the results should be displayed in a user-friendly manner, allowing comparison across different engines and datasets, and enabling users to make informed decisions about engine selection.

This project addresses these needs by providing an automated, containerized evaluation environment, along with a web application that visualises performance data, facilitating clear and comprehensive comparisons.

## Methodology {#methodology}

### Qlever Evaluation script {#eval_script}

In this section, we will focus on automating the process of executing predefined query sets against various SPARQL endpoints. [Qlever-evaluation](https://github.com/ad-freiburg/qlever-evaluation) is a project written in python which already exists for evaluating performance and correctness for Qlever, Blazegraph and Virtuoso.

The project consists of eval.py file which runs the evaluation procedure and it supports 2 modes:

1. “Completion” for evaluation of SPARQL query autocompletion
2. “Queries” for execution of given queries against a SPARQL endpoint.

Our goal is to implement the queries mode such that given a file containing queries and a valid SPARQL endpoint, running eval.py executes the queries by sending a GET request to the SPARQL endpoint and saves the results and performance metrics in an output directory.

The project already has a separate python class for Qlever, Blazegraph and Virtuoso which all have a query method that does the job of sending a GET request to the given SPARQL endpoint and processing the returned sparql-results+json response. To implement a new class for every new SPARQL engine would result in a lot of code duplication and repetition. A better way to accomplish this task would be to create a general backend class (called GenBackend) which implements query and process_response methods in a standard way. Specific engine backends can then extend this general backend class, implementing any additional behaviours or quirks required to interact with their respective engines, ensuring compatibility and ease of customization across different SPARQL systems.

The Qlever class does implement a lot of specific functionality related to Qlever such as using a POST request to query for results which returns the results in a qlever-results+json format instead of the official sparql-results+json.This allows us to get some more information from such as execution tree information and exact query runtimes. The processing of the results is also different as the format is different. Therefore, keeping a separate class for Qlever makes sense when we need the additional information. Qlever also supports the GET request and results in official sparql-results+json format and can still be used with our GenBackend class.

When we execute the eval.py script in queries mode, based on the arguments passed to the script, the backend class gets selected and queries are executed against a SPARQL endpoint and the query runtime, failure rate and the query results are recorded in files in the output directory.

### Automating generation of SPARQL endpoints and Benchmark setup using docker and bash scripts {#automation_all}

Now that we have an evaluation script, we need to identify the SPARQL engines to be compared with Qlever and the datasets/benchmarks which will be used to generate the SPARQL endpoint for them.\
As a starter, we will put up Qlever against the following 4 SPARQL engines which have their own strengths:

1. [Oxigraph](https://github.com/oxigraph/oxigraph) is a lightweight, Rust-based engine known for its efficiency and low resource usage.
2. [Apache Jena](https://jena.apache.org/), a well-established Java framework, is widely used for building semantic web applications.
3. [Virtuoso](https://virtuoso.openlinksw.com/) offers high-performance querying with strong support for large datasets and linked data.
4. [Blazegraph](https://blazegraph.com/), popular for its use in large-scale applications like Wikidata, emphasises scalability and high throughput.

To accurately evaluate their performance requires the use of standardised, publicly available benchmarks. These benchmarks ensure that the engines are tested under controlled, repeatable conditions that reflect real-world use cases, allowing for meaningful and fair performance comparisons. By using such benchmarks, we can assess how well each engine handles different query patterns, data scales, and workloads.

In this project, I have selected three well-established benchmarks to provide a comprehensive evaluation:

1. [Berlin SPARQL Benchmark (BSBM)](http://wbsg.informatik.uni-mannheim.de/bizer/berlinsparqlbenchmark/spec/index.html), which focuses on e-commerce scenarios
2. [SP2Bench](https://dbis.informatik.uni-freiburg.de/forschung/projekte/SP2B/), designed for testing on bibliographic data
3. [Wikidata Graph Pattern benchmark (WGPB)](https://zenodo.org/records/4035223#.Y8gsHOzMI0T), which targets complex graph patterns in large, real-world datasets like Wikidata.

Together, these benchmarks cover a wide spectrum of query complexities and dataset structures, offering a robust foundation for assessing SPARQL engine performance.

Setting up SPARQL engines for benchmarking, particularly with datasets from established benchmarks like BSBM, SP2Bench, and WGPB, can be a complex and error-prone process when done manually. Each benchmark involves different data structures and query patterns, requiring customised configurations for each SPARQL engine. This manual setup not only consumes significant time but also introduces the risk of inconsistencies, making it difficult to reproduce results across different environments. To address these challenges, automating the setup process is essential.

### Automating Benchmark setup {#automation_bench}

Now, we will look at the 3 benchmarks mentioned above in detail and how to automate their setup so that the user can easily and quickly generate the dataset and run the benchmark.

1. **Berlin SPARQL Benchmark (BSBM)**\
   The benchmark is built around an e-commerce use case in which a set of products is offered by different vendors and consumers have posted reviews about products. The benchmark query mix illustrates the search and navigation pattern of a consumer looking for a product. The number of products can be varied to produce RDF graphs of different scales. A total of 12 query templates are
   defined with a mix of SPARQL features. The queries run by BSBM can be found here - [BSBM queries](http://wbsg.informatik.uni-mannheim.de/bizer/berlinsparqlbenchmark/spec/ExploreUseCase/index.html#queries) <br><br>
   To streamline the benchmarking process for BSBM, I created a Dockerfile and an accompanying entrypoint.sh script, allowing for the efficient building and execution of a Docker image tailored to the BSBM framework.
   BSBM comes with its own data generator and testdriver for executing the 12 predefined queries against a SPARQL endpoint. Therefore, we can’t use BSBM with our Qlever evaluation script. Nonetheless, once the docker image is built, it can be run by passing in either “generate” or “testdriver” parameters depending on the functionality needed.
   When using the generate argument, the image runs the BSBM data generator, producing the necessary datasets for benchmarking. On the other hand, the testdriver argument triggers the BSBM test driver, which executes predefined queries against a specified SPARQL endpoint to evaluate engine performance.

2. **SP2Bench**\
   SP2Bench comprises a data-generator for arbitrarily large documents, which builds upon the well-known DBLP scenario, and thus comes close to a real-world application scenario. The benchmark queries implement meaningful requests on top of this data, thereby testing typical SPARQL operator constellations and RDF access patterns. The queries run by SP2Bench can be found here - [SP2Bench queries](https://dbis.informatik.uni-freiburg.de/index.php%3Fproject=SP2B%252Fqueries.php.html) <br><br>
   I also created a Dockerfile and accompanying entrypoint.sh for SP2Bench. As SP2Bench only comes with a data generator and a set of fixed queries, it fits well with our Qlever evaluation script. We can run the built Docker image to generate a dataset of arbitrary size, generate a SPARQL endpoint for it and execute the benchmark queries against the endpoint using our Qlever evaluation script.

3. **Wikidata Graph Pattern Benchmark (WGPB)**\
   The Wikidata Graph Pattern Benchmark (WGPB) is a benchmark consisting of 50 instances of 17 different abstract query patterns giving a total of 850 SPARQL queries. The goal of the benchmark is to test the performance of query engines for more complex basic graph patterns. The benchmark was designed for evaluating worst-case optimal join algorithms but also serves as a general-purpose benchmark for evaluating (basic) graph patterns. <br><br>
   As this is a benchmark on a real-world dataset, we don’t need any automation to set up a data generator. All we need is to have a queries file with all 850 queries and execute them against a SPARQl endpoint based on any Wikidata dataset dump. The queries run by WGPB can be found here - [WGPB queries](https://zenodo.org/records/4035223/files/wgpb-queries.zip?download=1)

### Automating SPARQL endpoint generation {#automation_engine}

As the process of manually setting up a SPARQL endpoint for each SPARQL engine and each dataset is extremely tedious and risks introducing inconsistencies, automating it with the help of Docker and bash scripts is extremely essential.
Taking inspiration from the ease of setup of Qlever, the end goal must be to have a docker container for each SPARQL engine as it provides an isolated, standardised environment for each engine, ensuring consistent behaviour. Users should be able to define some basic parameters in a configuration file and a bash script utilising this should provide some neat functions to do the tasks of downloading/finding the dataset, loading the dataset into the docker container for the engine and starting the server.

I have created a docker containerized environment for Jena and Blazegraph and used existing docker images for Oxigraph and Virtuoso. Interaction with the docker image can be abstracted away in the bash script accompanying each SPARQL engine.
Upon execution, the script generates a configuration file in the working directory with default parameters that can be tailored to specific datasets. The config file looks like:

```bash
# Name for the  container
name='engine_dataset'
# Port to expose the sparql server
port='1234'
# Name of the data file to be used (can be .nt, .ttl etc)
file_name='datafile.ttl'
# Optional: Command to download the data
get_data='wget http://datafile.ttl.zip && unzip datafile.ttl.zip && rm datafile.ttl.zip'
# Container tool to use ('docker' or 'wharfer')
container_tool='docker'
# Optional: Path to the data file if already present
file_path='absolute/path/to/datafile.ttl'
```

The script provides several functions that can be called with parameters:

`get_data`: Downloads and decompresses the data file if file_path not provided. \
`load`: Loads the data into Blazegraph. \
`start`: Starts the Blazegraph server. \
`stop`: Stops the Blazegraph server. \
`log`: Display the running log from the docker container.\
\
Load and Start functions are run in detached docker mode and can therefore be safely closed to clear up the terminal. The progress can always be logged by calling the log function of the script.

Here is how a standard execution should look like from beginning to end:

```bash
# Make a folder for the dataset for which a sparql endpoint needs to be created
mkdir dataset_folder
cd dataset_folder
# Call the script to generate a base Configfile
/path/to/automation/script.sh
#------------- Modify the Configfile with the required parameters -------------------

# Download the dataset by executing the get_data command specified in Configfile
# (Can be ignored if file_path mentioned in Configfile)
/path/to/automation/script.sh get_data
# Load the data into Blazegraph
/path/to/automation/script.sh load
# Loading happens in detached mode and can therefore be safely closed to clear up the terminal
# Log the data load progress if terminal was cleared after load
/path/to/automation/script.sh log
# Start the Blazegraph server which makes SPARQL endpoint available at port specified in ConfigFile
/path/to/automation/script.sh start
```

Following these common steps detailed above, all 4 SPARQL engines can be easily and uniformly set up.
This automation makes the benchmarking and evaluation process efficient, repeatable, and scalable.

### Example execution of Qlever evaluation script {#example_exec_script}

Now that we have an automated way of setting up SPARQL endpoints given a SPARQL engine and a dataset, we can look into how a normal execution of Qlever evaluation script looks like and what is the structure and content of the output files that are generated.

To execute eval.py in queries mode, we need to run the following command:

- For Qlever (using the Qlever backend class)

```bash
python eval.py queries --backend-type qlever --qlever-backend $QLEVER_ENDPOINT $DATASET_QUERIES_FILE
```

- For other engines (using the GenBackend class)

```bash
python eval.py queries --backend-type $ENGINE_NAME --backend-official $ENGINE_ENDPOINT $DATASET_QUERIES_FILE
```

Running these 2 commands will execute the queries for the sparql endpoints and generate the result files in the output directory that should look like:

```
output/
    ├── sp2bench.qlever.queries.results.tsv
    ├── sp2bench.qlever.queries.executed.yml
    ├── sp2bench.oxigraph.queries.results.tsv
    ├── sp2bench.oxigraph.queries.executed.yml
    ├── bsbm.qlever.queries.results.tsv
    ├── bsbm.qlever.queries.executed.yml
    ├── bsbm.jena.queries.results.tsv
    ├── bsbm.jena.queries.executed.yml
```

The result files that we are most interested in are of the form:

- dataset.engine.queries.results.tsv
- dataset.engine.queries.executed.yml.

The results file has tab separated columns namely Query ID, Query Time (ms), Total Client Time (ms) and Query Failed. Query time is the same as total client time for all non-qlever engines as we have no way of knowing the exact time it took for the engine to execute the particular query from official sparql format results.

The executed file gives information about the full sparql query that was executed, the results returned and execution tree information (only for qlever).

### Visualise the comparison of SPARQL Engines using a Web application {#visualisation}

With the results.tsv and executed.yml files generated after running the Qlever evaluation script, we can now build a web application and display these results in a user-friendly manner allowing comparison of different engines for different datasets.\
The web application was built using HTML, CSS, JavaScript and Bootstrap for additional styling. Python built-in http server was used to host the web app and visualise the results.

On the main page of the web app, the results are grouped by the dataset and some common performance metrics are compared for the different SPARQL engines. The web app automatically reads the files present in the output directory and groups them and displays the results from results.tsv file.

<!-- ![Main page with the results](/img/project-qlever-queries-mode-webapp/main_page.jpg) -->
### SPARQL Engine Comparison

### DBLP
| SPARQL Engine | Queries Failed | Avg Runtime (s) | Median Runtime (s) | Runtime <= 1.0s | (1.0s, 5.0s] | Runtime > 5s |
|---------------|----------------|------------------|---------------------|-----------------|--------------|--------------|
| blazegraph    | 0.00%          | 4.27             | 0.80                | 50.00%          | 33.33%       | 16.67%       |
| jena          | 16.67%         | 92.47            | 54.80               | 33.33%          | 0.00%        | 50.00%       |
| oxigraph      | 0.00%          | 65.80            | 39.33               | 33.33%          | 16.67%       | 50.00%       |
| qlever        | 0.00%          | 0.12             | 0.12                | 100.00%         | 0.00%        | 0.00%        |
| virtuoso      | 0.00%          | 7.89             | 2.34                | 16.67%          | 66.67%       | 16.67%       |


<center style="margin-top:-35px;margin-bottom:35px;">Figure 1: Main page displaying the results for each SPARQL engine grouped by the dataset</center>

Clicking on the column sorts that particular column in ascending and descending order and by holding shift and clicking on a column preserves the previous sort selected. Clicking on the rows showing the performance of each SPARQL engine takes the user to a page that displays all the queries that were executed and individual runtimes for that particular SPARQL engine and dataset.

<!-- ![Query Details tab 1](/img/project-qlever-queries-mode-webapp/query_details_tab1.jpg) -->
### SPARQL Engine - qlever
### Knowledge graph - DBLP

**<u>Query runtimes</u> | Full query | Execution tree | Query result**

| Query                                   | Runtime (s) |
|-----------------------------------------|-------------|
| All papers published in SIGIR           | 0.02        |
| Number of papers by venue               | 0.00        |
| Author names matching REGEX             | 0.02        |
| All papers in DBLP until 1940           | 0.02        |
| <u>All papers with their title</u>      | <u>0.01</u> |
| All predicates ordered by size          | 0.01        |

<center style="margin-top:-35px;margin-bottom:35px;">Figure 2: Page displaying the runtime for every query for a given SPARQL engine and dataset</center>

Clicking on one of the query rows selects it and displays the second tab with the full SPARQL query. The third tab displays the execution tree for the selected query (only for Qlever). The execution tree tab supports zoom in, zoom out and drag to move functionality. The final tab displays the results returned by executing the query. As the number of results can be quite large, the tab only displays the first 1000 results if it exceeds that. The user can click on the show more button to display the next 1000 results.

<!-- ![Query Details tab 2](/img/project-qlever-queries-mode-webapp/query_details_tab2.jpg) -->
**SPARQL Engine - qlever**

**Query runtimes | <u>Full query</u> | Execution tree | Query result**

PREFIX dblp: <https://dblp.org/rdf/schema#><br>
SELECT ?paper ?title WHERE {<br>
  ?paper dblp:title ?title .<br>
}<br>

<center style="margin-top:-35px;margin-bottom:35px;">Figure 3: Tab displaying the full SPARQL query for the selected query</center>

![Query Details tab 3](/img/project-qlever-queries-mode-webapp/query-details-3.png)

<center style="margin-top:-35px;margin-bottom:35px;">Figure 4: Tab displaying the runtime execution tree for the selected query</center>

<!-- ![Query Details tab 4](/img/project-qlever-queries-mode-webapp/query_details_tab4.jpg) -->
### SPARQL Engine - qlever

**Query runtimes | Full query | Execution tree | <u>Query result</u>**

| URL                                               | Title                                                                                   |
|---------------------------------------------------|-----------------------------------------------------------------------------------------|
| <https://dblp.org/rec/books/acm/0082477>          | The no-nonsense guide to computing careers.                                             |
| <https://dblp.org/rec/books/acm/17/CohenO17>      | Multimodal speech and pen interfaces.                                                  |
| <https://dblp.org/rec/books/acm/17/FreemanWVNPB17>| Multimodal feedback in HCI: haptics, non-speech audio, and their applications.          |
| <https://dblp.org/rec/books/acm/17/Hinckley17>    | A background perspective on touch as a multimodal (and multisensor) construct.          |


<center style="margin-top:-35px;margin-bottom:35px;">Figure 5: Tab displaying the results of executing the selected query</center>

Going back to the main page, we see that there is a compare button for each dataset. Clicking on it takes the user to a screen where each SPARQL engine is compared on performance on an individual query basis. The failed queries are maked in red. The columns are sortable in the same way as on the main screen. Hovering over the query ID displays the full SPARQL query.

<!-- ![Comparison Modal](/img/project-qlever-queries-mode-webapp/comparison_modal.jpg) -->

### Performance Comparison <br><br>

**Olympics** <br>

| Query                                           | blazegraph runtime (s)| jena runtime (s)| oxigraph runtime (s)| qlever runtime (s)| virtuoso runtime (s)|
|-------------------------------------------------|--------------------|--------------|------------------|----------------|------------------|
| All papers published in SIGIR                   |  0.10         |  0.27            |  0.36                |  0.11       |  2.55     |
| Number of papers by venue                       |  1.31         |  56.37           |  1.84                |  0.14       |  3.98     |
| Author names matching REGEX                     |  0.29         |  0.32            |  0.56                |  0.13       |  1.41     |
| All papers in DBLP until 1940                   |  2.69         |  53.22           |  204.88              |  0.19       |  0.22     |
| All papers with their title                     |  21.17        |  144.57          |  76.82               |  0.08       |  37.04    |
| All predicates ordered by size                  |  0.04         | failed (timeout) |  110.32              |  0.08       |  2.12     | 
<center style="margin-top:-35px;margin-bottom:35px;">Figure 6: Page showing the runtime comparison table for all SPARQLngines for given dataset</center>

There is also the section for Comparing Execution trees here (Only for Qlever). The dropdown boxes are automatically populated with all the different versions of Qlever found in the output directory. The user can select a query and the Qlever versions to compare from the dropdown and click on Compare. This takes the user to the Compare Execution trees screen, which looks similar to the Execution tree screen above, but with two of them side by side for easy comparison.

<!-- ![Compare exec trees](/img/project-qlever-queries-mode-webapp/compare_exec_trees.jpg)

<center style="margin-top:-35px;margin-bottom:35px;">Figure 7: Page showing runtime execution tree comparison for 2 versions of Qlever given a query and a dataset</center> -->

The execution trees are automatically sized to fit on the screen as much as possible. Nonetheless, the user can set the zoom level as they please by clicking on the + and - buttons. Drag to move is also supported on the execution trees. Hovering over the query ID on top also shows the full SPARQL query.

### Conclusion and Future Work {#conclusion}

By extending the existing QLever evaluation framework, we implemented a system that automates query execution, performance tracking, and comparison across different engines and datasets. The addition of the GenBackend class streamlined the process of querying each SPARQL endpoint, capturing metrics like query runtime and failure rates. Furthermore, the use of Docker and bash scripts to automate the setup of SPARQL endpoints greatly simplified the deployment process, ensuring consistency and scalability across the evaluations.

The combination of automation in benchmarking and performance measurement allowed for a comprehensive, reproducible comparison between the SPARQL engines, revealing insights into their respective strengths and weaknesses on different query patterns and datasets.

As for future work, the qlever evaluation script, bash automation scripts for setup of different SPARQL engines and benchmarks and the web application can be directly incorporated into the existing [qlever-control](https://github.com/ad-freiburg/qlever-control/tree/main) tool, which is used to create a qlever SPARQL endpoint. This would allow us to have a unified tool for qlever, which would be capable of setting up qlever endpoints, and directly run benchmarks to compare it to other engines and visualise the results.
