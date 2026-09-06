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

## Ontology Matching [Fußnote: "Der folgende Inhalt basiert auf dem Handbuch '' "]
*Ontology Matching* bzw. *Ontology Alignment* (im folgenden OM) wird seit den 1990ern erforscht und betrieben und spielt heute nach wie vor eine wichtige Rolle in der echten Welt. Wenn etwa zwei Firmen fusionieren oder alte Softwaresysteme zusammengelegt werden, müssen deren Datenbanken verknüpft werden. Ohne OM würde das fusionierte System nicht erkennen, dass ```client``` und ```date_of_birth``` in System A dasselbe bedeuten wie ```customer``` und ```DOB``` in System B, wodurch Duplikate entstehen, Datenbestände fragmentiert bleiben und Analysen schlicht falsche Kennzahlen liefern: Kunden würden Rechnungen doppelt erhalten, Suchabfragen würden unvollständige Treffer liefern, und automatisierte Workflows würden an inkompatiblen Feldern scheitern. OM ist auch in der Medizin- und Pharmaforschung, wo Krankenhäuser und Labore weltweit klinische Studien und Wirkstoffdatenbanken harmonisieren müssen. Ebenso unverzichtbar ist es für moderne Web-Suchmaschinen und Wissensgraphen (wie Wikidata oder Google), die Datenbestände global vernetzen, sowie für E-Commerce-Plattformen und Logistikketten, die Produktdaten und Ersatzteilkataloge von tausenden heterogenen Lieferanten in Echtzeit in einem einheitlichen System zusammenführen.

OM ist aus mehreren Gründen schwierig für Computer. Zum einen beruhen Äquivalenz- und andere Beziehungen zwischen den einzelnen Einträgen in den Datenbanken (fachsprachlich *entities*) auf vage semantisch-pragmatische (im Sinne der Linguistik, nicht im mathematischen Sinne!) Kriterien: Dazu zählt zum Beispiel die "Semiotic heterogenity", wie Euzenat & Shvaiko (2013) sie nennen (S. 38). Sie sagen dazu (ebd.): 
> "[Semiotic heterogenity] is concerned with how entities are interpreted by people. Indeed, entities which have exactly the same semantic interpretation are often interpreted by humans with regard to the context, for instance, of how they are ultimately used. This kind of heterogeneity is difficult for the computer to detect and even more difficult to solve, because it is out of its reach. The intended use of entities has a great impact on their interpretation, therefore, matching entities which are not meant to be used in the same context is often error-prone."
Zum anderen spielen neben sprachlich-semantischen Faktoren auch strukturelle Faktoren (also der Aufbau des Wissensgraphen) eine große Rolle. Dies sei anhand eines einfachen Phänomens verdeutlicht: 

![logic violation in ontology alignment](img/logic_violation.svg)

Wenn die jeweiligen Entities ```Corporation``` und ```Client``` in beiden Ontologien als äquivalent gesetzt werden, entsteht das Problem, dass ```Corporation``` in der neu entstanden Gesamtontologie eine Unterkategorie von ```Person``` ist. Eine Suchanfrage auf Personen liefert auf einmal Firmenobjekte. Im schlimmsten Fall machen strukturelle Fehler beim Matching ein Alignment völlig unbrauchbar, wenn dadurch Logikverletzungen entstehen und die Datenbank in einer stark formalisierten Form repräsentiert wird (z. B. OWL/OWL2) und darauf Reasoning ausgeführt wird. Es gibt viele weitere strukturelle Konsistenz- und Ähnlichkeitskritierien, die beim Matching bedacht werden müssen. Auch hier sind Ähnlichkeitsmaße aufgrund von schwer fassbaren semiotischen Unterschieden bei den Graphmodellierungen vage.

Nicht zuletzt betrifft die Matching-Aufgabe häufig große Ontologien (biomedizinische Ontologien umfassen beispielsweise nicht selten Millionen von Einträgen) und muss gut skalieren können.

Aufgrund der Schwierigkeit der Aufgabe für Maschinen stellt Ontology Alignment nach wie vor eine Herausforderung dar. Bezüglich reinem Schema-Matching, der Aufgabe, mit der sich das vorliegende Projekt beschäftigt hat, psotuliert die OAEI (die seit Jahren als die Standard-Evaluationsplattform für Ontology-Matching gilt) (https://inria.hal.science/hal-05447839v1/document, S. 28): 
> "[S]till little substantial progress [is reached] in terms of the quality of the results or runtime of top matching systems. As already reported in the last years, we observe a performance plateau being reached by existing strategies and algorithms. It is also true that established matching systems tend to focus more on new tracks and datasets than on improving their performance in long-standing tracks, whereas new systems typically struggle to compete with established ones. [...] The best-performing systems are not consistent across tasks and settings, demonstrating the diversity of our datasets."

## Ontology Matching mithilfe von LLMs




