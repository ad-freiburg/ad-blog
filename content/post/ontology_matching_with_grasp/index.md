---
title: "Extending GRASP to Run Ontology Alignment"
date: 2026-09-05T09:05:29+02:00
author: "Tuvia Navon"
authorAvatar: "img/ada.jpg"
tags: [ontology-alignment, ontology-matching, grasp, sparql, oaei]
categories: ["project"]
image: "img/writing.jpg"
---

Some summary

<!--more-->

## Introduction

## Ontology Matching

*This section is based largely on the standard reference by Euzenat and Shvaiko <a href="#euzenat2013">[1]</a>.*

*Ontology matching* or *ontology alignment* (hereafter OM) has been an active field of research since the 1990s and still plays an important role in the real world today. When two companies merge, for instance, or legacy software systems are consolidated, their databases have to be linked. Without OM, the merged system would not recognize that ```client``` and ```date_of_birth``` in system A mean the same thing as ```customer``` and ```DOB``` in system B, leading to duplicate records, fragmented data, and analyses that report incorrect figures. Customers would receive duplicate invoices, search queries would return incomplete results, and automated workflows would fail on incompatible fields. OM is likewise used extensively in medical and pharmaceutical research, where hospitals and laboratories worldwide need to harmonize clinical trial data and drug databases. It is equally indispensable for modern web search engines and knowledge graphs (such as Wikidata or Google), which connect data globally, as well as for e-commerce platforms and supply chains that merge product data and spare-parts catalogs from thousands of heterogeneous suppliers into a single system in real time.

OM is difficult for computers for several reasons. First, equivalence and other relations between the individual entries in the databases (in technical terms, *entities*) rest on vague semantic-pragmatic (in the linguistic sense) criteria. One example is what Euzenat and Shvaiko call "semiotic heterogeneity" <a href="#euzenat2013">[1, p. 38]</a>. On this, they write <a href="#euzenat2013">[1, p. 38]</a>: 
> "[Semiotic heterogenity] is concerned with how entities are interpreted by people. Indeed, entities which have exactly the same semantic interpretation are often interpreted by humans with regard to the context, for instance, of how they are ultimately used. This kind of heterogeneity is difficult for the computer to detect and even more difficult to solve, because it is out of its reach. The intended use of entities has a great impact on their interpretation, therefore, matching entities which are not meant to be used in the same context is often error-prone."

Besides linguistic-semantic factors, structural factors (i.e., how the knowledge graph is built) also play a major role. This can be illustrated with a simple phenomenon: 

![logic violation in ontology alignment](img/logic_violation.svg)

If the entities ```Corporation``` and ```Client``` in the two ontologies are set as equivalent, a problem arises: in the newly merged ontology, ```Corporation``` becomes a subcategory of ```Person```. A query for persons would then suddenly also return company objects. In the worst case, structural errors in matching can render an alignment completely unusable if they introduce logical violations, particularly when the database is represented in a highly formalized form (e.g., OWL/OWL2) on which reasoning is performed. There are many other structural consistency and similarity criteria that must be considered during matching. Here too, similarity measures remain quite vague, owing to subtle semiotic differences between graph models.

Finally, matching tasks often involve large ontologies (biomedical ontologies, for example, frequently comprise millions of entries), which is why matchers need to scale well.

Because the task is so difficult for machines, ontology alignment remains a challenge to this day. Regarding pure schema matching — the task this project is concerned with — the OAEI, which has for years been the standard evaluation platform for ontology matching, states <a href="#oaei2025">[2, p. 28]</a>: 
> "[S]till little substantial progress [is reached] in terms of the quality of the results or runtime of top matching systems. As already reported in the last years, we observe a performance plateau being reached by existing strategies and algorithms. It is also true that established matching systems tend to focus more on new tracks and datasets than on improving their performance in long-standing tracks, whereas new systems typically struggle to compete with established ones. [...] The best-performing systems are not consistent across tasks and settings, demonstrating the diversity of our datasets."

## Ontology Matching with LLMs
In recent years, LLMs have increasingly been incorporated into OM. Since training or even fine-tuning LLMs for this specific task has proven impractical <a href="#qiang2024">[3, p. 2]</a>, most systems instead use general-purpose LLMs via natural-language prompts. Because LLMs come with a very high runtime-complexity overhead, candidate search and selection in the systems tested so far is typically not left entirely to the LLM, but is complemented by traditional methods. Across every matcher I reviewed that uses LLMs and has taken part in the OAEI in recent years, the LLM's role is limited to two functions: 
1. Validating mappings: the LLM is asked to choose, among several pre-selected candidates, which one constitutes a valid mapping. These are typically edge cases that the other matching methods could not clearly confirm or rule out.
2. Enriching node information: the LLM is asked, for example, to augment labels with a short description of their meaning in the context of the graph, so that later steps can apply more robust similarity measures.

A notable example is AgentOM, which its creators describe, in a paper of theirs, as the "first [...] LLM-agent-based framework for OM tasks" <a href="#qiang2024">[3, p. 519]</a>. A review of the described algorithm and its source code shows that here, too, candidate search for equivalences between entities is largely carried out using traditional, deterministic methods, and that the LLM — besides enriching information about individual entities — functions only as an additional validation instance when equivalences are finally set.

## Project Goals and Research Questions
Since [GRASP](https://grasp.cs.uni-freiburg.de) has proven itself on many knowledge-graph-related tasks, this project set out to extend GRASP for OM. The plan was to first build a small prototype and test it on small pairs of ontologies. The literature review above shows that a genuinely agentic use of an LLM for the OM task has not yet been attempted. 

Accordingly, the project's central questions are:
1. Are agentic LLMs in general a promising approach for OM?
2. To what extent can GRASP help an agentic LLM perform the OM task faster and/or more accurately?


## The Test Track
As a point of reference for the first prototype, the OAEI's "Conference track" was chosen. As mentioned above, the OAEI's tracks are "the" standard benchmarks for OM. The Conference track in particular was chosen because it involves setting simple 1:1 equivalences between small ontologies (roughly 80–200 entities per ontology). With a few minor and negligible exceptions, these ontologies contain only classes and properties, no instances or literals (so-called "T-Box matching"). In doing so, the OAEI deliberately separates pure schema matching from instance matching (A-Box), which is more concerned with attribute similarity, duplicate detection, and scaling to large volumes of data, and instead focuses on the core question of ontology matching: whether two independently created concept hierarchies model the same concepts. This suits a first GRASP prototype well, because it keeps both the search space (80–200 rather than potentially millions of entities) and the number of tool calls needed per chat loop manageable, while the signals that LLM's strengths rely on, i.e. lexical context in diverse forms, are at the center of the task. 

It is also worth highlighting that, like most other OAEI tracks, all ontologies in this track are represented in the strongly formalized, reasoning-capable OWL format. This may be surprising, since in practice — in company databases, for instance — simpler and not always logically consistent models are far more common. The likely reason is that such logically consistent models are simply easier to evaluate. It also makes it possible to test whether matchers can read and exploit deeper relations between entities, such as disjointness and sub-entity relations. Here, GRASP's strength lies in the fact that it is not restricted to a single format and does not require logical consistency to perform the task well, but can instead respond flexibly to different formats and contexts. In that sense, the strong (artificial) focus on OWL ontologies is, if anything, an additional challenge for measuring GRASP's capabilities.

Overall, the Conference track is therefore a good test baseline for a first prototype that applies an agentic LLM to OM: it consists of small ontologies, requires good NLP — which is where LLMs excel — while at the same time it can expose potential weaknesses, since top-down reasoning and logical consistency are still a challenge for LLMs (as the tests also show).


## Implementation
The prototype aimed to stay within the GRASP framework as much as possible, initially forgoing other external modules or task-specific extensions, in order to have a baseline for further development. GRASP works with RAG by equipping a freely chosen LLM with elaborate search functions over the knowledge graphs involved. It further implements an agentic loop in which the LLM receives an input instruction and then works out a solution to the given task over several rounds <a href="#walter-bast2025">[4]</a>. Accordingly, implementing the OM task within the GRASP framework involved:
1. formulating a suitable prompt for the LLM.
2. writing dedicated tools for the LLM to set and remove correspondences.
3. implementing injectivity enforcement when setting equivalences.
4. integrating the remaining GRASP components, namely the GRASP tools and `Shapes`, an index that provides a quick overview of a class's graph context for each class (see below in the example agentic loop).


## Tests
To evaluate matchers, the OAEI implements the [MELT](https://dwslab.github.io/melt/) framework. All tests described below were evaluated using this evaluation environment, in order to compare results with current state-of-the-art matchers that have taken part in the OAEI in recent years. The full evaluation comprises 7 ontologies to be aligned pairwise (out of 16 ontologies in the track in total), yielding 21 test pairs. I carried out the following tests:

1. First, a full test run over the 21 ontology pairs from the Conference track was carried out natively with Claude Code in the Claude Code CLI, i.e., completely without GRASP. Here, only the same prompt used for the OM task in GRASP was used. The goal was to get an initial sample of how a powerful middle-tier model performs in an agentic environment that allows an LLM to work on tasks over multiple steps.

2. Second, several test runs were carried out on a sub-sample of 4 ontologies, and thus 6 ontology pairs instead of 21, since tests are costly due to the use of an LLM via API. Here, my GRASP extension was tested with OpenAI's GPT-5.6 Terra. First, the task was organized — following the pattern of other GRASP tasks — so that the LLM had to map only a single entity from the source ontology to the target ontology per chat loop. A matching task therefore consisted of many chat loops, e.g., 100 individual chat loops when the source ontology had 100 entities. For comparison, a test was run with OpenAI's GPT-5.6 Terra without GRASP, similar to the test with Claude Code, to see whether differences emerge when working on the task within the GRASP framework. All model configurations (verbosity, reasoning effort, etc.) were kept identical to the GRASP test run. Based on the results of these two tests, a further test run was then carried out on the same 6 ontology pairs with GRASP, but this time without matching individual entities per chat loop; instead, the entire source ontology was provided at once. This meant that, within a single chat loop, the LLM had to find equivalent counterparts in the target ontology for up to 185 entities.

## Test Results

<footer>
    <h1 id="references"> References </h1>
    <ol id="references-ol">
        <li id="euzenat2013"> J. Euzenat and P. Shvaiko, <em>Ontology Matching</em>, 2nd ed. Berlin, Heidelberg: Springer, 2013. doi: <a href="https://doi.org/10.1007/978-3-642-38721-0">10.1007/978-3-642-38721-0</a>. </li>
        <li id="oaei2025"> M. Abd Nikooie Pour et al., "Results of the Ontology Alignment Evaluation Initiative 2025," CEUR Workshop Proceedings, vol. 4144, 2025. <a href="https://inria.hal.science/hal-05447839v1/document">https://inria.hal.science/hal-05447839v1/document</a>. </li>
        <li id="qiang2024"> Z. Qiang, W. Wang, and K. Taylor, "Agent-OM: Leveraging LLM Agents for Ontology Matching," Proceedings of the VLDB Endowment, vol. 18, no. 3, pp. 516–529, 2024. doi: <a href="https://doi.org/10.14778/3712221.3712222">10.14778/3712221.3712222</a>. </li>
        <li id="walter-bast2025"> S. Walter and H. Bast, "GRASP: Generic Reasoning And SPARQL Generation across Knowledge Graphs," in <em>The Semantic Web – ISWC 2025</em>, Lecture Notes in Computer Science, Springer, 2026. doi: <a href="https://doi.org/10.1007/978-3-032-09527-5_15">10.1007/978-3-032-09527-5_15</a>. </li>
    </ol>
</footer>
