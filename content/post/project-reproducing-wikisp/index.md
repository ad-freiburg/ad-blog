---
title: "Reproducing WikiSP"
date: 2025-12-15T15:15:54+01:00
author: "Luis Drayer"
authorAvatar: "img/ada.jpg"
tags: []
categories: []
image: "img/writing.jpg"
---

This project reimplements the WikiSP pipeline for semantic parsing from natural language questions to SPARQL queries. The reimplementation faithfully reproduces the original models’ behavior and evaluation metrics, while providing a complete, self-contained framework for dataset adaptation, training, prediction, and evaluation. It supports experiments with arbitrary datasets and base models, enabling controlled studies on dataset composition, size, quality, and model choice, and facilitating reproducible research in SPARQL semantic parsing.

## Content
1. [Introduction](#introduction)
2. [WikiSP Methodology](#methodology)
   - [Dataset Structure](#structure)
   - [Evaluation](#wikisp_eval)
3. [Reimplemented Pipeline](#pipeline)
   - [Dataset Adaption](#adaption)
   - [Dataset Splitting](#splitting)
   - [Model setup and training](#setup_training)
   - [Evaluation](#eval)
4. [Results](#results)
   - [Comparing local WikiSP checkpoints to Paper Results](#comp1)
   - [Retrain Results](#retrain_results)
   - [Analyzing LOCAL EM on QALD-7](#analyze)
5. [Further Experiments](#further)
   - [Evaluating WikiSP on more datasets](#more_datasets)
   - [Training a new model](#new_model)
6. [Conclusion](#conclusion)


## Introduction {#introduction}

Semantic parsing from natural language questions to SPARQL queries is a central task in question answering over knowledge graphs. Systems addressing this problem aim to translate user queries expressed in natural language into executable SPARQL queries that retrieve correct answers from structured knowledge bases such as Wikidata. Recent approaches increasingly rely on large language models to perform this translation, often combining pretrained models with task-specific fine-tuning and structured postprocessing.

WikiSP is one such approach, proposing a training and evaluation pipeline for SPARQL generation based on instruction-tuned language models. The method demonstrates strong performance on benchmarks such as WikiWebQuestions by leveraging a combination of instruction-style training data, named entity detection, and structured evaluation based on query execution results. However, despite its promising results, WikiSP is difficult to reuse or extend in practice. The original implementation provides pretrained model checkpoints and evaluation scripts, but omits critical components such as training code, dataset preprocessing pipelines, and a complete prediction workflow.

As a result, researchers and practitioners are limited in their ability to apply the WikiSP method to alternative datasets, experiment with different base models, or conduct controlled studies on dataset quality and training strategies. This lack of reproducibility and extensibility creates a barrier to systematic experimentation and fair comparison with other approaches.

This project addresses these limitations by reimplementing the WikiSP pipeline entirely in a local and self-contained manner. The reconstructed pipeline covers dataset adaptation, named entity detection, model training, prediction, and evaluation, closely following the methodology described in the original paper where it makes sense and is possible to do so. By validating the reimplementation against the published WikiSP results, this work enables the WikiSP method to be applied to arbitrary models and datasets, facilitating reproducible research and controlled experimentation in SPARQL semantic parsing.


### Core Challenge

WikiSP does not provide a complete, reusable pipeline covering dataset adaptation, model training, and evaluation. While the repository includes several artifacts, critical components required for reproduction are missing.

**Provided by WikiSP:**
- Two pretrained model checkpoints
- Saved predictions of the best-performing model on WikiWebQuestions Dev set (`best.json`); available in the [official WikiSP repository](https://github.com/stanford-oval/wikidata-emnlp23/blob/master/predicted_results/best.json)
- A partial evaluation script
- High-level descriptions of the training methodology and selected hyperparameters

**Missing components:**
- A dataset adaptation or preprocessing pipeline matching WikiSP’s training format
- The inference step required by the evaluation pipeline
- Any training code or end-to-end training script

As a result, reproducing or extending WikiSP requires reconstructing most of the pipeline from scratch, including data preparation, prediction, training, and evaluation.

---

# WikiSP Methodology {#methodology}

## Dataset Structure {#structure}

WikiSP uses different formats for training and evaluation, which is a key source of complexity.

### Training Set

The training data is formatted in an Alpaca-style instruction format containing:

- An English Question with provided entity IDs from the Named Entity Disambiguation (NED) step (`input`)
- A SPARQL query without resolved predicate IDs (`output`)
- An instruction text (`instruction`)
- A unique ID (`id`)
- A final SPARQL query with resolved predicate IDs (`sparql`)

```json
{
  "input": "Query: what is the name of justin bieber brother?\nEntities:Justin Bieber with QID Q34086;",
  "output": "SELECT DISTINCT ?x WHERE { wd:Q34086 wdt:sibling ?x. ?x wdt:sex_or_gender wd:male. }",
  "instruction": "Given a Wikidata query with resolved entities, generate the corresponding SPARQL. Use property names instead of PIDs.",
  "id": "WebQTrn-0",
  "sparql": "SELECT DISTINCT ?x WHERE { wd:Q34086 wdt:P3373 ?x. ?x wdt:P21 wd:Q6581097. }"
}
```

### Dev / Test Set
The dev and test sets contain:

- A unique ID (`id`)
- An English Question without any provided entity IDs (`utterance`)
- The corresponding Sparql Query with resolved predicate IDs, but including prefixes (`sparql`)
- The query results (from wikidata) (`results`)

```json
{
  "id": "WebQTrn-3129",
  "utterance": "what is the political system in argentina?",
  "sparql": "PREFIX wd: <http://www.wikidata.org/entity/> PREFIX wdt: <http://www.wikidata.org/prop/direct/> SELECT DISTINCT ?x WHERE { wd:Q414 wdt:P122 ?x. }",
  "results": [
    {
      "x": {
        "type": "uri",
        "value": "http://www.wikidata.org/entity/Q512187"
      }
    }
  ]
}

```

---

## Evaluation {#wikisp_eval}

The WikiSP evaluation pipeline consists of several steps, combining entity detection, SPARQL generation, postprocessing, and result-based evaluation.

### 1. Named Entity Detection (NED)
The input English question is processed using [ReFinEd](https://github.com/amazon-science/ReFinED) to extract Wikidata entity IDs present in the question.  
This step is imperfect by design; the model must handle missing or incorrect entities.

### 2. SPARQL Generation
The model receives a single input composed of:

- An Alpaca-style instruction
- The English question
- Entities detected by ReFinEd

From this input, the model generates:

- A human-readable SPARQL query
- Predicate names instead of PIDs
- QIDs only for entities provided by ReFinEd; otherwise, entity names are used

### 3. Postprocessing
The human-readable query is converted into a fully Wikidata-compliant SPARQL query:

- Predicate names → Wikidata PIDs
- Entity names → Wikidata QIDs (if not already resolved)


### 4. Evaluation

Predictions are evaluated using two complementary metrics: Exact Match (`EM`) and F1 score (`F1`).  
Note: examples where the model produces an empty prediction are excluded from evaluation.

1. **Exact Match (EM)**  
   A prediction is counted as an exact match if either:
   - The generated SPARQL query matches the gold SPARQL exactly, or
   - The query results of the generated SPARQL match the results of the gold query exactly.

2. **F1 Score**  
   F1 is computed based on the relative overlap between the predicted and gold query results, capturing partial correctness when predictions are not fully exact.


---

# Reimplemented Pipeline {#pipeline}


## Dataset Adaptation {#adaption}

`adapt_dataset.py` transforms the raw dataset into exactly the format expected by WikiSP training or evaluation.

It turns a raw dataset from this (in this case an example from [lcquad2](https://ad-publications.cs.uni-freiburg.de/grasp/benchmark/wikidata/lcquad2/)):
```json
{
  "id":"train_0",
  "question":"What periodical literature does Delta Air Lines use as a moutpiece?",
  "sparql":"PREFIX wdt: <http://www.wikidata.org/prop/direct/> PREFIX wd: <http://www.wikidata.org/entity/> select distinct ?obj where { wd:Q188920 wdt:P2813 ?obj . ?obj wdt:P31 wd:Q1002697 }",
  "paraphrases":["What is Delta Air Line's periodical literature mouthpiece?"],
  "info":{"invalid":false}
}
```
Into the training convention expected by WikiSP:
```json
{
  "id": "train_0",
  "input": "Query: What periodical literature does Delta Air Lines use as a moutpiece?\nEntities:Delta Air Lines with QID Q188920;",
  "output": "PREFIX wdt: <http://www.wikidata.org/prop/direct/> PREFIX wd: <http://www.wikidata.org/entity/> select distinct ?obj where { wd:Q188920 wdt:house_publication ?obj . ?obj wdt:instance_of wd:periodical }",
  "instruction": "Given a Wikidata query with resolved entities, generate the corresponding SPARQL. Use property names instead of PIDs.",
  "sparql": "PREFIX wdt: <http://www.wikidata.org/prop/direct/> PREFIX wd: <http://www.wikidata.org/entity/> select distinct ?obj where { wd:Q188920 wdt:P2813 ?obj . ?obj wdt:P31 wd:Q1002697 }"
}
```

Or dev / test convention (different example here):
```json
{
    "id": "test_0",
    "utterance": "What was the population of Somalia in 2009-0-0?",
    "sparql": "SELECT ?obj WHERE { wd:Q1045 p:P1082 ?s . ?s ps:P1082 ?obj . ?s pq:P585 ?x filter ( contains ( YEAR ( ?x ) , '2009' ) ) }",
    "results": [
      {
        "obj": {
          "datatype": "http://www.w3.org/2001/XMLSchema#decimal",
          "type": "literal",
          "value": "9380854"
        }
      }
    ]
  }
```

All raw datasets used later on were successfully transformed into this format, with entity IDs resolved where available, enabling direct compatibility with the WikiSP training and evaluation pipeline.

---

## Dataset Splitting {#splitting}

The `split_dataset.py` script splits a dataset into two separate files of the desired size.  
It is typically used in combination with `adapt_dataset.py` to produce a complete train, dev, and test set from a raw dataset.  
This ensures that both training and evaluation data conform to WikiSP conventions.

---

## Model Setup and Training {#setup_training}

### Base Model

WikiSP is built on LLaMA-7B, so the same base model is used here.  
Changing the base model is possible, but not the goal of this validation step.

---

### Training Method

The `train.py` script provides a framework for training models using LoRA fine-tuning on the desired training sets.

Key points:

- The learning rate was adjusted for LoRA, since LoRa only updates a small subset of parameters and as such changing the optimization dynamics compared to full fine-tuning.  
- While WikiSP trained for 3 epochs, this script allows longer training and selection of the best-performing checkpoint.  
- Checkpoints can be evaluated at configurable intervals on any dataset, allowing monitoring during training.

For a full overview of what this script allows, check out the [Makefile help entry](https://github.com/Ludraaa/Bachelorprojekt/blob/main/Makefile).

---

## Evaluation {#eval}

The `eval.py` script implements the core WikiSP evaluation steps:

- Named Entity Detection using ReFinED  
- Generating SPARQL predictions  
- Executing the predictions to obtain results  
- Calculating Exact Match (EM) and F1 scores

Additional functionality includes:

- Comparing predictions not only to the gold SPARQL/results, but also to another model’s saved predictions  
- Comparing to the dataset’s stored results as well as the fresh results from Wikidata, which may have changed since the dataset was created
---

Much more detailed instructions on how to actually use this pipeline can be found in the [Makefile](https://github.com/Ludraaa/Bachelorprojekt/blob/main/Makefile)!

---

# Results {#results} 

## Comparing local WikiSP checkpoints to Paper Results {#comp1}

To validate correctness, the downloaded WikiSP models were evaluated on WikiWebQuestions Dev, Test and Qald7 Test and compared to the results reported in the paper.

`PRED EM` refers to the exact match with respect to WikiSP's [provided predictions](https://github.com/stanford-oval/wikidata-emnlp23/blob/master/predicted_results/best.json). 

<table>
  <!-- Dataset group header -->
  <tr>
    <th></th>
    <th style="text-align:center" colspan="3">WWQ Dev</th>
    <th style="text-align:center" colspan="2">WWQ Test</th>
    <th style="text-align:center" colspan="2">QALD-7</th>
  </tr>

  <!-- Metric names header -->
  <tr>
    <th style="border-bottom:2px double black;">Model</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Pred EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
  </tr>

  <!-- WWQ models -->
  <tr>
    <td>WikiSP_WWQ (Paper)</td>
    <td>75.6</td>
    <td>76.9</td>
    <td>-</td>
    <td>65.5</td>
    <td>71.9</td>
    <td>-</td>
    <td>-</td>
  </tr>
  <tr>
    <td style="border-bottom:1px double black;">WikiSP_WWQ</td>
    <td style="border-bottom:1px double black;">74.2</td>
    <td style="border-bottom:1px double black;">75.6</td>
    <td style="border-bottom:1px double black;">97.8</td>
    <td style="border-bottom:1px double black;">65.9</td>
    <td style="border-bottom:1px double black;">70.5</td>
    <td style="border-bottom:1px double black;">24.4</td>
    <td style="border-bottom:1px double black;">29.8</td>
  </tr>
  <!-- Q7 models -->
  <tr>
    <td>WikiSP_WWQ_Q7 (Paper)</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>38.0</td>
    <td>43.6</td>
  </tr>
  <tr>
    <td>WikiSP_WWQ_Q7</td>
    <td>73.8</td>
    <td>75.5</td>
    <td>90.7</td>
    <td>66.5</td>
    <td>71.0</td>
    <td>35.6</td>
    <td>42.4</td>
  </tr>
</table>

Both models closely match the values published in the [WikiSP paper](https://arxiv.org/pdf/2305.14202).

Furthermore, WikiSP_WWQ achieves an impressive 97% EM with respect to the published predictions of WikiSP.

---


## Retrain Results {#retrain_results}

### Training Method {#retrain_method}

The [WikiSP Paper](https://arxiv.org/pdf/2305.14202) states that they upsampled WikiWebQuestions by 5 and Qald7 by 20 during training. They also used additional Alpaca data, but it is unknown how much.

As such, i trained 6 models in total.

In the following section, WWQ refers to WikiWebQuestions, Q7 to Qald7 and x 5/20 to upsampled by 5/20.

These models are:

- **MyWikiSP_WWQ_NoAlpaca** - Trained on only WWQ x 5
- **MyWikiSP_WWQ_EqualAlpaca** - Trained on WWQ x 5 and an equal amount of Alpaca Data (so ~15k alpaca)
- **MyWikiSP_WWQ_FullAlpaca** - Trained on WWQ x 5 and the full alpaca dataset (~52k)
- **MyWikiSP_WWQ_Q7_NoAlpaca** - Trained on WWQ x 5 and Q7 x 20
- **MyWikiSP_WWQ_Q7_EqualAlpaca** - Trained on WWQ x 5, Q7 x 20 and an equal amount of Alpaca Data as WWQ (~15k)
- **MyWikiSP_WWQ_Q7_FullAlpaca** - Trained on WWQ x 5, Q7 x 20 and the full alpaca dataset (~52k)

---

### Training Results {#retrain_results2}

The following table reports the best-performing checkpoint for each model on the WikiWebQuestions Dev set.

The best checkpoint is selected using the following criteria, in descending order:

- Highest EM on WWQ Dev
- Highest F1 on WWQ Dev
- Earliest checkpoint

If multiple checkpoints achieve the same EM, the one with higher F1 is selected. If both EM and F1 are identical, the earlier checkpoint is chosen.

From this point onward, `Local EM` denotes exact match with respect to predictions generated by the corresponding local WikiSP model.

Retrained models without QALD-7 data are compared against `WikiSP_WWQ predictions`, while retrained models trained with QALD-7 data are compared against `WikiSP_WWQ_Q7` predictions, as these represent the respective training targets.

For the complete training results, including all evaluated checkpoints, see the full results table [here](https://docs.google.com/spreadsheets/d/1-BO7qMILrNWteJzbPzJhkhgTvbI_168jPk6JCtK_fuE/edit?usp=sharing).

<table>
  <!-- Dataset group header -->
  <tr>
    <th></th>
    <th style="text-align:center" colspan="3">WikiWebQuestions Dev</th>
  </tr>

  <!-- Metric names header -->
  <tr>
    <th style="border-bottom:2px double black;">Model</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
  </tr>

  <!-- WWQ models -->
  <tr>
    <td>WikiSP_WWQ (Paper)</td>
    <td>75.6</td>
    <td>76.9</td>
    <td>-</td>
  </tr>
  <tr>
    <td style="border-bottom:1px double black;">WikiSP_WWQ</td>
    <td style="border-bottom:1px double black;">74.2</td>
    <td style="border-bottom:1px double black;">75.6</td>
    <td style="border-bottom:1px double black;">-</td>
  </tr>

  <tr>
    <td>MyWSP_WWQ_NoAlpaca</td>
    <td>76</td>
    <td>77.4</td>
    <td>86.7</td>
  </tr>
  <tr>
    <td>MyWSP_WWQ_EqualAlpaca</td>
    <td>77.5</td>
    <td>78.7</td>
    <td>89.1</td>
  </tr>
  <tr>
    <td style="border-bottom:2px double black;">MyWSP_WWQ_FullAlpaca</td>
    <td style="border-bottom:2px double black;">76.2</td>
    <td style="border-bottom:2px double black;">77.5</td>
    <td style="border-bottom:2px double black;">89.5</td>
  </tr>

  <!-- Q7 models -->
  <tr>
    <td>WikiSP_WWQ_Q7 (Paper)</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
  </tr>
  <tr>
    <td style="border-bottom:1px double black;">WikiSP_WWQ_Q7</td>
    <td style="border-bottom:1px double black;">73.8</td>
    <td style="border-bottom:1px double black;">75.5</td>
    <td style="border-bottom:1px double black;">-</td>
  </tr>
  <tr>
    <td>MyWikiSP_WWQ_Q7_NoAlpaca</td>
    <td>76.2</td>
    <td>77.8</td>
    <td>89.4</td>
  </tr>
  <tr>
    <td>MyWikiSP_WWQ_Q7_EqualAlpaca</td>
    <td>76.2</td>
    <td>77.7</td>
    <td>88.2</td>
  </tr>
  <tr>
    <td>MyWikiSP_WWQ_Q7_FullAlpaca</td>
    <td>76.4</td>
    <td>78.1</td>
    <td>87.8</td>
  </tr>
</table>

All of these results outperform the values reported in the [WikiSP Paper](https://arxiv.org/pdf/2305.14202) by a few points, while remaining largely comparable.

All of the models also have a `LOCAL EM` of around 90 points, which makes them functionally equivalent to the original WikiSP models.



### Comparing Retrain to Local WikiSP {#comparison2}

This table shows the evaluation results of the retrained models on all datasets that appear in the original [WikiSP Paper](https://arxiv.org/pdf/2305.14202).

<table>
  <!-- Dataset group header -->
  <tr>
    <th></th>
    <th style="text-align:center" colspan="3">WikiWebQuestions Dev</th>
    <th style="text-align:center" colspan="3">WikiWebQuestions Test</th>
    <th style="text-align:center" colspan="3">QALD-7</th>
  </tr>

  <!-- Metric names header -->
  <tr>
    <th style="border-bottom:2px double black;">Model</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
  </tr>

  <!-- WWQ models -->
  <tr>
    <td>WikiSP_WWQ (Paper)</td>
    <td>75.6</td>
    <td>76.9</td>
    <td>-</td>
    <td>65.5</td>
    <td>71.9</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
  </tr>
  <tr>
    <td style="border-bottom:1px double black;">WikiSP_WWQ</td>
    <td style="border-bottom:1px double black;">74.2</td>
    <td style="border-bottom:1px double black;">75.6</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">65.9</td>
    <td style="border-bottom:1px double black;">70.5</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">24.4</td>
    <td style="border-bottom:1px double black;">29.8</td>
    <td style="border-bottom:1px double black;">-</td>
  </tr>

  <tr>
    <td>MyWSP_WWQ_NoAlpaca</td>
    <td>76</td>
    <td>77.4</td>
    <td>86.7</td>
    <td>67.6</td>
    <td>72</td>
    <td>87.8</td>
    <td>35.6</td>
    <td>37.7</td>
    <td>43.6</td>
  </tr>
  <tr>
    <td>MyWSP_WWQ_EqualAlpaca</td>
    <td>77.5</td>
    <td>78.7</td>
    <td>89.1</td>
    <td>67.9</td>
    <td>72.3</td>
    <td>89.2</td>
    <td>26.7</td>
    <td>33.2</td>
    <td>59.5</td>
  </tr>
  <tr>
    <td style="border-bottom:2px double black;">MyWSP_WWQ_FullAlpaca</td>
    <td style="border-bottom:2px double black;">76.2</td>
    <td style="border-bottom:2px double black;">77.5</td>
    <td style="border-bottom:2px double black;">89.5</td>
    <td style="border-bottom:2px double black;">67.4</td>
    <td style="border-bottom:2px double black;">72</td>
    <td style="border-bottom:2px double black;">89.4</td>
    <td style="border-bottom:2px double black;">28.9</td>
    <td style="border-bottom:2px double black;">34.5</td>
    <td style="border-bottom:2px double black;">54.3</td>
  </tr>

  <!-- Q7 models -->
  <tr>
    <td>WikiSP_WWQ_Q7 (Paper)</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>38.0</td>
    <td>43.6</td>
    <td>-</td>
  </tr>
  <tr>
    <td style="border-bottom:1px double black;">WikiSP_WWQ_Q7</td>
    <td style="border-bottom:1px double black;">73.8</td>
    <td style="border-bottom:1px double black;">75.5</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">66.5</td>
    <td style="border-bottom:1px double black;">71</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">35.6</td>
    <td style="border-bottom:1px double black;">42.4</td>
    <td style="border-bottom:1px double black;">-</td>
  </tr>
  <tr>
    <td>MyWikiSP_WWQ_Q7_NoAlpaca</td>
    <td>76.2</td>
    <td>77.8</td>
    <td>89.4</td>
    <td>68.2</td>
    <td>72.4</td>
    <td>88.6</td>
    <td>33.8</td>
    <td>36.7</td>
    <td>40</td>
  </tr>
  <tr>
    <td>MyWikiSP_WWQ_Q7_EqualAlpaca</td>
    <td>76.2</td>
    <td>77.7</td>
    <td>88.2</td>
    <td>66.1</td>
    <td>70.6</td>
    <td>86.7</td>
    <td>26.6</td>
    <td>28</td>
    <td>48.6</td>
  </tr>
  <tr>
    <td>MyWikiSP_WWQ_Q7_FullAlpaca</td>
    <td>76.4</td>
    <td>78.1</td>
    <td>87.8</td>
    <td>66.8</td>
    <td>71.2</td>
    <td>88.7</td>
    <td>37.8</td>
    <td>41.8</td>
    <td>54.3</td>
  </tr>
</table>

Once again, the evaluated values are mostly comparable to the original WikiSP's performance on WikiWebQuestions, consistently outperforming it by 1-3 points while maintaining the 85~90 `LOCAL EM`.

On QALD-7, the retrained models' performances stay either comparable or outperform the original WikiSP by a lot in many cases, with the big exception of `MyWikiSP_WWQ_Q7_EqualAlpaca`.

While Alpaca data does not seem to help much on QALD-7 nor WikiWebQuestions, it does in most cases improve `LOCAL EM`, and as such make it behave more like the original WikiSP.


## Analyzing LOCAL EM on QALD-7 {#analyze}

Looking at the table above, the retrained models only have around 40-60 points in `LOCAL EM`.

The following table shows a manual analysis of `MyWikiSP_WWQ_Q7_EqualAlpaca` and the Original `WikiSP_WWQ_Q7`'s predictions and categorizes them into the following categories:

It should be noted, that comparisons with both different sparql but both empty results were not evaluated, as that would inflate the score.


<table>
  <tr>
    <td style="border-bottom:3px double black;">Category</td>
    <td style="border-bottom:3px double black;">#Occurances</td>
    <td style="border-bottom:3px double black;">%</td>
  </tr>
  <tr>
    <td>Absolute Query Match</td>
    <td>2</td>
    <td>5.71</td>
  </tr> 
  <tr>
    <td>Query Match (allows different var names)</td>
    <td>13</td>
    <td>37.14</td>
  </tr>
  <tr>
    <td style="border-bottom:2px double black;">Result Match</td>
    <td style="border-bottom:2px double black;">2</td>
    <td style="border-bottom:2px double black;">5.71</td>
  </tr>
  <tr>
    <td style="border-bottom:3px double black;">Match Total</td>
    <td style="border-bottom:3px double black;">17</td>
    <td style="border-bottom:3px double black;">48.57</td>
  </tr>
  <tr>
    <td>Differing Prediction (both wrong)</td>
    <td>14</td>
    <td>40.0</td>
  </tr>
<tr>
    <td>Differing Prediction (only reproduction wrong)</td>
    <td>2</td>
    <td>5.71</td>
  </tr>
<tr>
    <td style="border-bottom:2px double black;">Differing Prediction (only original wrong)</td>
    <td style="border-bottom:2px double black;">2</td>
    <td style="border-bottom:2px double black;">5.71</td>
</tr>
<tr>
    <td style="border-bottom:3px double black;">No Match Total</td>
    <td style="border-bottom:3px double black;">18</td>
    <td style="border-bottom:3px double black;">51.43</td>
</tr>
<tr>
  <td>Excluded (both empty results with different sparql)</td>
  <td>10</td>
  <td></td>
</tr>
<tr>
  <td>Total Evaluated</td>
  <td>35</td>
  <td>100</td>
</tr>
</table>

While `LOCAL EM` is only around 48%, this reflects both the inherent difficulty of the dataset and the fact that many questions are answered incorrectly by both the original and retrained models. The reproduction pipeline behaves in the same way as the original, producing similar patterns of errors and correct predictions.

Only in a small fraction of examples (10%) do the models disagree, and these disagreements are balanced: the reproduction outperforms the original in some instances and vice versa.

When looking at all of the results so far, the reimplemented pipeline can be deemed as functionally equivalent with respect to the original WikiSP pipeline and as such, enables us to experiment on new datasets and models.

# Further Experiments {#further}

## Evaluating WikiSP on more Datasets {#more_datasets}

Now that we have our faithful reproduction of the original WikiSP Pipeline, it is time for some further experiments. 

This table shows evaluations of both the original WikiSP models, as well as the retrains on the following Datasets:

- WikiWebQuestions
- QALD-7
- QALD-10
- LC-QuAD22

<table>
  <!-- Dataset group header -->
  <tr>
    <th></th>
    <th style="text-align:center" colspan="3">WikiWebQuestions Dev</th>
    <th style="text-align:center" colspan="3">WikiWebQuestions Test</th>
    <th style="text-align:center" colspan="3">QALD-7</th>
    <th style="text-align:center" colspan="3">QALD-10</th>
    <th style="text-align:center" colspan="3">LC-QuAD2</th>
  </tr>

  <!-- Metric names header -->
  <tr>
    <th style="border-bottom:2px double black;">Model</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
  </tr>

  <!-- WWQ models -->
  <tr>
    <td>WikiSP_WWQ (Paper)</td>
    <td>75.6</td>
    <td>76.9</td>
    <td>-</td>
    <td>65.5</td>
    <td>71.9</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
  </tr>
  <tr>
    <td style="border-bottom:1px double black;">WikiSP_WWQ</td>
    <td style="border-bottom:1px double black;">74.2</td>
    <td style="border-bottom:1px double black;">75.6</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">65.9</td>
    <td style="border-bottom:1px double black;">70.5</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">24.4</td>
    <td style="border-bottom:1px double black;">29.8</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">17.5</td>
    <td style="border-bottom:1px double black;">18.8</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">9.4</td>
    <td style="border-bottom:1px double black;">13.2</td>
    <td style="border-bottom:1px double black;">-</td>
  </tr>

  <tr>
    <td>MyWSP_WWQ_NoAlpaca</td>
    <td>76</td>
    <td>77.4</td>
    <td>86.7</td>
    <td>67.6</td>
    <td>72</td>
    <td>87.8</td>
    <td>35.6</td>
    <td>37.7</td>
    <td>43.6</td>
    <td>23.8</td>
    <td>24.6</td>
    <td>37.7</td>
    <td>11.9</td>
    <td>16.1</td>
    <td>42.9</td>
  </tr>
  <tr>
    <td>MyWSP_WWQ_EqualAlpaca</td>
    <td>77.5</td>
    <td>78.7</td>
    <td>89.1</td>
    <td>67.9</td>
    <td>72.3</td>
    <td>89.2</td>
    <td>26.7</td>
    <td>33.2</td>
    <td>59.5</td>
    <td>22.5</td>
    <td>24</td>
    <td>36.4</td>
    <td>11</td>
    <td>15.2</td>
    <td>47.5</td>
  </tr>
  <tr>
    <td style="border-bottom:2px double black;">MyWSP_WWQ_FullAlpaca</td>
    <td style="border-bottom:2px double black;">76.2</td>
    <td style="border-bottom:2px double black;">77.5</td>
    <td style="border-bottom:2px double black;">89.5</td>
    <td style="border-bottom:2px double black;">67.4</td>
    <td style="border-bottom:2px double black;">72</td>
    <td style="border-bottom:2px double black;">89.4</td>
    <td style="border-bottom:2px double black;">28.9</td>
    <td style="border-bottom:2px double black;">34.5</td>
    <td style="border-bottom:2px double black;">54.3</td>
    <td style="border-bottom:2px double black;">23.3</td>
    <td style="border-bottom:2px double black;">24.8</td>
    <td style="border-bottom:2px double black;">40</td>
    <td style="border-bottom:2px double black;">11.2</td>
    <td style="border-bottom:2px double black;">15.5</td>
    <td style="border-bottom:2px double black;">46.5</td>
  </tr>

  <!-- Q7 models -->
  <tr>
    <td>WikiSP_WWQ_Q7 (Paper)</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>38.0</td>
    <td>43.6</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
    <td>-</td>
  </tr>
  <tr>
    <td style="border-bottom:1px double black;">WikiSP_WWQ_Q7</td>
    <td style="border-bottom:1px double black;">73.8</td>
    <td style="border-bottom:1px double black;">75.5</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">66.5</td>
    <td style="border-bottom:1px double black;">71</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">35.6</td>
    <td style="border-bottom:1px double black;">42.4</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">22.5</td>
    <td style="border-bottom:1px double black;">24.1</td>
    <td style="border-bottom:1px double black;">-</td>
    <td style="border-bottom:1px double black;">13.7</td>
    <td style="border-bottom:1px double black;">17.4</td>
    <td style="border-bottom:1px double black;">-</td>
  </tr>
  <tr>
    <td>MyWikiSP_WWQ_Q7_NoAlpaca</td>
    <td>76.2</td>
    <td>77.8</td>
    <td>89.4</td>
    <td>68.2</td>
    <td>72.4</td>
    <td>88.6</td>
    <td>33.8</td>
    <td>36.7</td>
    <td>40</td>
    <td>28.5</td>
    <td>29.5</td>
    <td>36.6</td>
    <td>11.9</td>
    <td>15.5</td>
    <td>31.8</td>
  </tr>
  <tr>
    <td>MyWikiSP_WWQ_Q7_EqualAlpaca</td>
    <td>76.2</td>
    <td>77.7</td>
    <td>88.2</td>
    <td>66.1</td>
    <td>70.6</td>
    <td>86.7</td>
    <td>26.6</td>
    <td>28</td>
    <td>48.6</td>
    <td>30.9</td>
    <td>32</td>
    <td>39.5</td>
    <td>15.1</td>
    <td>19</td>
    <td>30.3</td>
  </tr>
  <tr>
    <td>MyWikiSP_WWQ_Q7_FullAlpaca</td>
    <td>76.4</td>
    <td>78.1</td>
    <td>87.8</td>
    <td>66.8</td>
    <td>71.2</td>
    <td>88.7</td>
    <td>37.8</td>
    <td>41.8</td>
    <td>54.3</td>
    <td>33.5</td>
    <td>33.9</td>
    <td>40.6</td>
    <td>13.3</td>
    <td>16.6</td>
    <td>27.6</td>
  </tr>
</table>

## Training a new model {#new_model}

Out of curiosity, i wanted to see how well a WikiSP style model could do, if it was trained on more of the hard datasets.

This model is trained on:

- WikiWebQuestions x 5
- QALD-7 x 20
- QALD-100 x 5 
- LC-QuAD2 x 1/4 
- Alpaca to WWQ 1:1 (~15k)

The table below shows the performance of the best model checkpoint on all of these datasets. For the full training progress itself, check this table [here](https://docs.google.com/spreadsheets/d/1-BO7qMILrNWteJzbPzJhkhgTvbI_168jPk6JCtK_fuE/edit?usp=sharing).

<table>
  <!-- Dataset group header -->
  <tr>
    <th></th>
    <th style="text-align:center" colspan="3">WikiWebQuestions Dev</th>
    <th style="text-align:center" colspan="3">WikiWebQuestions Test</th>
    <th style="text-align:center" colspan="3">QALD-7</th>
    <th style="text-align:center" colspan="3">QALD-10</th>
    <th style="text-align:center" colspan="3">LC-QuAD2</th>
  </tr>

  <!-- Metric names header -->
  <tr>
    <th style="border-bottom:2px double black;">Model</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
    <th style="border-bottom:2px double black;">EM</th>
    <th style="border-bottom:2px double black;">F1</th>
    <th style="border-bottom:2px double black;">Local EM*</th>
  </tr>

  <tr>
    <td>WikiSP_All</td>
    <td>75.6</td>
    <td>77.1</td>
    <td>87.3</td>
    <td>68.3</td>
    <td>72.6</td>
    <td>89.2</td>
    <td>60.0</td>
    <td>61.6</td>
    <td>43.6</td>
    <td>22.0</td>
    <td>22.9</td>
    <td>25.7</td>
    <td>28.1</td>
    <td>28.6</td>
    <td>10.0</td>
  </tr>
</table>

As one would expect, this model does not achieve anything groundbreaking on WikiWebQuestions, as WikiSP is already quite optimized there. On all other datasets, except for QALD-10, where it does considerably worse than the other models, this model blows the others out of the water.

# Conclusion {#conclusion}

This reimplementation successfully reproduces the WikiSP pipeline, matching the metrics and systemic behavior of the original models on relevant datasets. 

As such, this pipeline can now be used to train and evaluate WikiSP-style models on arbitrary datasets and base models, enabling controlled experiments on:

- dataset quality
- dataset size
- dataset composition
- base model choice


