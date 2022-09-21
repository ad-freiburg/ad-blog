---
title: "Question Answering on Wikidata"
date: 2022-09-21T10:38:25+02:00
author: "David Otte"
authorAvatar: "img/ada.jpg"
tags: [NLP, question answering, qa, knowledge base, NER, SPARQL, QLever, Aqqu]
categories: [project]
image: "img/project-question-answering-on-wikidata/blog.png"
---


Aqqu is an efficient question answering system that was developed using Freebase.
This project aims to implement Aqqu for question answering on Wikidata instead of Freebase and to 
improve the accuracy of previous implementations using Wikidata. 
In short, for a given natural language question, SPARQL queries that 
might answer the question are generated and ranked afterwards in order to get the query that is most likely 
to answer the given question.

<!--more-->

## Content
1. [Introduction](#introduction)
2. [Preprocessing](#preprocessing)
3. [Pipeline](#pipeline)
4. [Evaluation](#evaluation)
5. [Conclusion](#conclusion)


## Introduction {#introduction}

[Wikidata](https://www.wikidata.org/) is an open knowledge base with over 99 million data items.
These items can be entities or relations and the information about them is 
stored in RDF graph format. That means, that the information is expressed in statements, which are triples 
that consist of an entity, a relation and a value, which can also be an entity. 
To get desired information from knowledge bases like Wikidata, the query 
language SPARQL is used. Basic SPARQL queries contain one or
more triple patterns that are similar to the triples in RDF,
with the difference that elements in the triples also can be variables. A basic SPARQL query that 
asks for the height of Mount Everest using Wikidata is the following:
```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX wd: <http://www.wikidata.org/entity/>
SELECT ?height WHERE {
  wd:Q513 wdt:P2044 ?height .
}
```
Q513 is the Wikidata ID for Mount Everest and P2044 for the property *elevation above sea level*. To come 
up with such a query can be very challenging, especially for people that have no experience with Wikidata 
and/or SPARQL queries, since the internal structure of the data as well as the ID's for entities 
and properties are not known. One way to address these problems are question answering 
systems that take the question in natural language as input and then try to translate it to the 
SPARQL query that answers the question.

[Aqqu](https://ad-publications.cs.uni-freiburg.de/CIKM_freebase_qa_BH_2015.pdf) is such a system that was 
built for question answering on [Freebase](https://en.wikipedia.org/wiki/Freebase_(database)), 
another knowledge base, which is not updated anymore. 
The project [Aqqu-Wikidata](https://ad-blog.informatik.uni-freiburg.de/post/simple-question-answering-on-wikidata/) 
implemented a basic version of Aqqu for Wikidata and also provided an evaluation 
frontend. Although this is a rewrite, the logic still relies on both the implementations of Aqqu and Aqqu-Wikidata, 
also some small parts of the implementation as well as the evaluation frontend were taken from there. Similar to 
Aqqu-Wikidata, we will also only focus on simple questions, which are questions that are answerable with one single 
triple.

## Preprocessing {#preprocessing}

Before the pipeline can be used, some preprocessing steps have to be done. First, the relevant entities (id, name, 
popularity score) and relations (id, name, number occurrences), as well as the corresponding aliases for both, are 
acquired from Wikidata. 

Next, two further precomputation steps are done that save time when executing the actual pipeline. The first one simply 
computes the lemmatized version of all relation aliases. The lemmatization of a word is gained by reducing inflectional 
forms, for example the lemmatization of the words *am, are, is* is *be*. The second one precomputes the answer types of 
each relation and each query template in the following way: For a given relation and query template, 
each of the six answer types *Person, Character, Organization, Location, Event* is added to the list 
of answer types if more than one percent of the answers for all corresponding queries have this answer type. 
Additionally, Wikidata allows us to directly check if the relation is of type *Time*, if this is 
the case, we can add *Date* to the list of answer types for that relation.

As a last step, two RocksDB indices are built, one for the entities and one for the relations. The entity index 
helps to quickly get all stored information of an entity and to get all matching entities for a given lemmatized 
sequence of words. The relation index gives all information for a given relation and also all relation aliases, 
which is useful in the relation matching step.


## Pipeline {#pipeline}
The pipeline builds up on the natural language processing library [spaCy](https://spacy.io/).
<h4>Entity matching</h4>

As a first step, we tokenize the given natural language question and remove the question mark symbol if existing. 
For example, for the question *Where was Albert Einstein born?*, we get the Tokens ["Where", "was", "Albert", "Einstein", 
"born"]. With generating the tokens, spaCy already tags the words with part of speech tags. The goal is to look at all 
subsequences of tokens that might be an alias for an entity, therefore it makes sense to merge neighbored tokens that 
are both tagged as proper nouns to prevent looking on unnecessary subsequences. 
In the previous example, "Albert" and "Einstein" are combined to "Albert Einstein". 
Now a list of all subsequences of tokens which have at least one proper noun or at least two tokens is generated. Then, for 
every subsequence, we look in the entity index for all entities that have this subsequence as their alias and 
save them. In the end, the list of identified entities gets sorted by the number of tokens and by the popularity score 
and the best 50 are kept for the following steps.

<h4>Candidate generation</h4>

For each entity, we generate all query candidates that might answer the question by combining the entity with the 
possible relations that can occur with this entity. Since 
the focus are simple questions, there are two possible types of queries: One asks for the third element of 
the triple, like the Mount Everest example in the introduction, and the other one asks for the first element 
of the triple. The second template is appropriate for questions like *Who is a person that was born in Munich?*. 
We also save the number of answers that each query has.

<h4>Relation matching</h4>

In this step, the goal is to gain values that indicate how well the relation of a query candidate matches the given 
question. First, we select all relevant tokens of the question by removing the ones that were already matched by an 
entity and then also remove the tokens that are not tagged by a content tag. 
The first metric is the literal score, which is the highest number of lemmatized tokens of one of the relation 
aliases of the candidate, that also appears in the content tokens of the question. The second one is the number of 
exact relation matches, which is one, if the lemmatized version of one relation alias appears exactly in this order in 
the lemmatized question without entity tokens, and zero otherwise.

<h4>Candidate features</h4>

For the ranking process, the following features are used:


|             Feature             |                                                       Descripttion                                                        |
|:-------------------------------:|:-------------------------------------------------------------------------------------------------------------------------:|
|      Exact entity matches       |                                              Number of exact entity matches.                                              |
|   Exact entity token matches    |            Binary value that is one if a subsequence of the question exactly matches the label of the entity.             |
|     Entity popularity score     |                                       Number of wikipedia sitelinks the entity has.                                       |
|     Exact relation matches      | Binary value that is one if the lemma of a relation alias matches the lemmatized question tokens of a question perfectly. |
|          Literal score          |       Max number of tokens that appear in a relation alias and match a token of the content tokens of the question.       |
|     Occurrences relation KB     |                                Number of times the relation occurs in the knowledge base.                                 |
|       Exact token matches       |                                   Sum of exact entity token matches and literal score.                                    |
| Proportion matched/total tokens |             Number of question tokens that were matched in any way divided by the number of question tokens.              |
|          Result size 0          |                              Binary value that is one if the candidate query has no results.                              |
|        Result size 1-20         |                 Binary value that is one if the result size of the candidate query lies between 1 and 20.                 |
|        Result size > 20         |                         Binary value that is one if the candidate query has more than 20 results.                         |
|           Ngram value           |          Output logistic regression model that learned correlations between relation and words in the question.           |
|        Answer type match        |      Binary value that is one if the beginning of the question gets matched to one of the precomputed answer types.       |


The ngram value is a measure of the correspondence between one- or two-word phrases of the question and the relation 
of a query candidate. 
It can be very useful because it indicates how well the relation of a candidate corresponds to 
the question, even if the features of the relation matching itself don't indicate a correspondence. 
One example that illustrates that is the question *Who is Cristiano Ronaldo?*. The expected answer 
may be *a football player*. This correspondence, that *Who is* asks for the profession of a person, cannot be 
measured by the other features.
To get this ngram value, we train a logistic regression model in the following way: For each candidate that is 
generated while processing the training questions, we combine each one- or two-word phrase of the question with 
the relation of the candidate. Then, we one-hot-encode the collected data for the training process and use 
the values of the correct candidates as positive examples and all other values as negative examples. To get realistic 
values for the following learning steps, the training data is divided into six folds and the predictions for 
the instances of one fold are done with a model that was trained on the other five folds.


The answer type match feature states whether the words of the given question indicate a certain answer type, 
that is also an answer type of the relation of the candidate, or not. For the six answer types 
*Person, Character, Organization, Location, Event, Date*, we decide this as follows: 
If the first word of the question is *Who*, we check if *Person, Character* or *Organization* are in the set of precomputed 
answer types for that candidate. If the first word is *Where*, we check for the answer types *Location* and 
*Event*. When the question starts with *When* or *Since when*, we look for the answer type *Date*.


<h4>Ranking</h4>

A pairwise ranking approach is used, that infers a ranking of the candidates with binary classification that states 
whether one candidate should be ranked higher than another one. Therefore, a random forest with 100 estimators is 
trained by giving positive examples (true candidate, false candidate) and negative examples (false candidate, true 
candidate) from the processed training set. The performance of this ranking step can be improved significantly by using 
a simple candidate pruning step. It turned out that just removing all the candidates, which have both a ngram value 
smaller than 0.5 and a literal score of 0, eliminates around 90% of the candidates without a considerable decrease in 
accuracy.


<a name="desc"></a>
## Evaluation {#evaluation}

For the evaluation, we use the answerable test set of the dataset 
[wikidata-simplequestions](https://github.com/askplatypus/wikidata-simplequestions). It currently contains 5622 
simple (and answerable) questions, which means that they are answerable with a query that uses only one triple. 
For the evaluation, we derive useful measures that describe how well the pipeline performs on the 
test set. The accuracy gives the fraction of the questions where the answer of the gold query is exactly the same as the 
answer of the highest ranked query. T*X* is the fraction of questions where the correct candidate was among the top 
*X* candidates. Also, average precision and recall as well as average F1 and the median F1 score are given. AD is the 
average duration in seconds that was needed to answer a question.

![evaluation results](/img/project-question-answering-on-wikidata/evaluation.png "Evaluation results")

The run wd_answerable_test shows the evaluation on the entire test set. It has an accuracy of 79% and a T1 score of 77%, 
having an average duration of 1.6 seconds per question. The two wd_answerable_test_500 runs show the differences when 
using no candidate pruning. The average duration increases by 4.5 seconds and in the other scores there 
are only very small changes. The own_benchmark run evaluates the pipeline on 10 own question that are answerable with 
Wikidata. Here it is clearly noticeable that the pipeline doesn't perform good. The reason might be that the 
structure of the questions slightly differs from the questions were the pairwise ranker model was trained on.


## Conclusion {#conclusion}

The pipeline performs good on the given simplequestions dataset, the accuracy and the performance of the 
pipeline could be improved considerably, compared to previous implementations of Aqqu on Wikidata. Still, as the 
performance on the benchmark shows, there are many things to improve. 

<h4>Possible improvements</h4>

- Generalize to more complex questions that use more than only one triple of the knowledgebase. 
- Introduce further features that can also describe that words of the question correspond to a relation even if the (lemmatized) words don't match. One possibility would be to introduce a similarity score using word vectors. 
- Test other machine learning methods, try deep learning for the ranking. 
- Enhanced answer type matching that has more than six answer types. 
- Machine learning model for candidate pruning to further reduce the runtime. 
- Optimize candidate generation step - the execution of the queries that get all possible candidates and also computes the answer size of each candidate currently needs the largest amount of time. 
- Improve the entity matching such that also entities can be recognized even if no words match directly. Currently, for a large number of the questions that aren't answered correctly, the reason for the failure is that the correct candidate was not generated because the entity was not recognized. This is a very difficult topic because recognizing more entities also means that there are many more candidates. 


