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

## Ontology Matching [Fußnote: "Der folgende Inhalt basiert auf dem Handbuch DOI 10.1007/978-3-642-38721-0 ISBN 978-3-642-38721-0 [richtigen Quellenverweis daraus machen!]"]
*Ontology Matching* bzw. *Ontology Alignment* (im folgenden OM) wird seit den 1990ern erforscht und betrieben und spielt heute nach wie vor eine wichtige Rolle in der echten Welt. Wenn etwa zwei Firmen fusionieren oder alte Softwaresysteme zusammengelegt werden, müssen deren Datenbanken verknüpft werden. Ohne OM würde das fusionierte System nicht erkennen, dass ```client``` und ```date_of_birth``` in System A dasselbe bedeuten wie ```customer``` und ```DOB``` in System B, wodurch Duplikate entstehen, Datenbestände fragmentiert bleiben und Analysen falsche Kennzahlen liefern. Kunden würden Rechnungen doppelt erhalten, Suchabfragen würden unvollständige Treffer liefern, und automatisierte Workflows würden an inkompatiblen Feldern scheitern. OM kommt auch in der Medizin- und Pharmaforschung zum Einsatz, wo Krankenhäuser und Labore weltweit klinische Studien und Wirkstoffdatenbanken harmonisieren müssen. Ebenso unverzichtbar ist es für moderne Web-Suchmaschinen und Wissensgraphen (wie Wikidata oder Google), die Datenbestände global vernetzen, sowie für E-Commerce-Plattformen und Logistikketten, die Produktdaten und Ersatzteilkataloge von tausenden heterogenen Lieferanten in Echtzeit in einem einheitlichen System zusammenführen.

OM ist aus mehreren Gründen schwierig für Computer. Zum einen beruhen Äquivalenz- und andere Beziehungen zwischen den einzelnen Einträgen in den Datenbanken (fachsprachlich *entities*) auf vage semantisch-pragmatische (im linguistischen Sinne) Kriterien: Dazu zählt zum Beispiel die "Semiotic heterogenity", wie Euzenat & Shvaiko (2013) [Kommentar für KI: das ist das Buch, auf das oben schon verwiesen wird] sie nennen (S. 38). Sie sagen dazu (ebd.): 
> "[Semiotic heterogenity] is concerned with how entities are interpreted by people. Indeed, entities which have exactly the same semantic interpretation are often interpreted by humans with regard to the context, for instance, of how they are ultimately used. This kind of heterogeneity is difficult for the computer to detect and even more difficult to solve, because it is out of its reach. The intended use of entities has a great impact on their interpretation, therefore, matching entities which are not meant to be used in the same context is often error-prone."
Zum anderen spielen neben sprachlich-semantischen Faktoren auch strukturelle Faktoren (also der Aufbau des Wissensgraphen) eine große Rolle. Dies sei anhand eines einfachen Phänomens verdeutlicht: 

![logic violation in ontology alignment](img/logic_violation.svg)

Wenn die jeweiligen Entities ```Corporation``` und ```Client``` in beiden Ontologien als äquivalent gesetzt werden, entsteht das Problem, dass ```Corporation``` in der neu entstanden Gesamtontologie eine Unterkategorie von ```Person``` ist. Eine Suchanfrage auf Personen liefert auf einmal Firmenobjekte. Im schlimmsten Fall machen strukturelle Fehler beim Matching ein Alignment völlig unbrauchbar, wenn dadurch Logikverletzungen entstehen, während die Datenbank in einer stark formalisierten Form repräsentiert wird (z. B. OWL/OWL2) und darauf Reasoning ausgeführt wird. Es gibt viele weitere strukturelle Konsistenz- und Ähnlichkeitskritierien, die beim Matching bedacht werden müssen. Auch hier bleiben Ähnlichkeitsmaße aufgrund von schwer fassbaren semiotischen Unterschieden bei den Graphmodellierungen sehr vage.

Nicht zuletzt betrifft die Matching-Aufgabe häufig große Ontologien (biomedizinische Ontologien umfassen beispielsweise nicht selten Millionen von Einträgen), weshalb Matcher gut skalieren können sollten.

Aufgrund der Schwierigkeit der Aufgabe für Maschinen stellt Ontology Alignment nach wie vor eine Herausforderung dar. Bezüglich reinem Schema-Matching, der Aufgabe, mit der sich das vorliegende Projekt beschäftigt hat, postuliert die OAEI, die seit Jahren als die Standard-Evaluationsplattform für Ontology-Matching gilt (https://inria.hal.science/hal-05447839v1/document, S. 28): 
> "[S]till little substantial progress [is reached] in terms of the quality of the results or runtime of top matching systems. As already reported in the last years, we observe a performance plateau being reached by existing strategies and algorithms. It is also true that established matching systems tend to focus more on new tracks and datasets than on improving their performance in long-standing tracks, whereas new systems typically struggle to compete with established ones. [...] The best-performing systems are not consistent across tasks and settings, demonstrating the diversity of our datasets."

## Ontology Matching mithilfe von LLMs
In den letzten Jahren wurden LLMs zunehmend im OM einbezogen. Da sich das Training oder sogar Fine-Tuning von LLMs auf diese spezifische Aufgabe als unpraktisch erweist (Qiang et al, 2026, "Agent-OM: Leveraging LLM Agents for Ontology Matching", doi:10.14778/3712221.3712222, S. 2), nutzen die meisten Systeme allgemeine LLMs mittels natürlichsprachlicher Prompts. Da LLMs einen sehr hohen Overhead an Laufzeitkomplexität mit sich bringen, wird die Kandidatensuche und -auswahl in den bisher getesteten Systeme typischerweise nicht vollständig dem LLM überlassen, sondern durch traditionelle Verfahren ergänzt. Die Rolle des LLMs beschränkt sich in allen von mir durchgesichteten Matchern, die in den letzten Jahren bei der OEAI mitgemacht haben und LLMs nutzen, auf zwei Funktionen: 
1. Validierung von Mappings: Das LLM soll zwischen mehreren vorausgewählten Kandidaten wählen, welches ein valides Mapping darstellt. Typischerweise sind es Randfälle, die die anderen Matching-Methoden nicht klar setzen oder ausschließen konnten.
2. Informationsanreicherung von Knoten: Das LLM soll beispielsweise Labels um eine kurze Bedeutungsbeschreibung im Zusammenhand des Graphen ergänzen, damit spätere Schritte robustere Ähnlichkeitsmaße setze können. 
Ein bezeichnendes Beispiel ist AgentOM, das in einem Paper der Macher als "first [...] LLM-agent-based framework for OM tasks" profiliert wird (Leveraging LLM Agents for Ontology Matching. PVLDB, 18(3): 516 - 529,
2024. doi:10.14778/3712221.3712222, S. 3). Eine Durchsicht des beschriebenen Algorithmus und des Quellcodes ergibt, dass auch hier die Kandidatensuche für Äquivalenzen zwischen Entities weitgehend mithilfe von traditionellen deterministischen Verfahren durchgeführt wird und das LLM neben einer Anreicherung der Informationen zu den einzelnen Entitäten nur als eine zusätzliche Validierungsinstanz beim endgültigen Setzen der Äquivalenzen fungiert.

## Zielsetzung des Projekts
Da [GRASP](https://grasp.cs.uni-freiburg.de) sich in vielen Knowledge-Graph-bezogenen Aufgaben bewährt hat, sollte GRASP in diesem Projekt für OM erweitert werden. Dabei sollte erstmal ein kleines Prototyp gebaut und anhand von kleinen Ontologiepaaren getestet werden. Aus dem Literaturbericht oben wird ersichtlich, dass ein wahrhaftig agentischer Einsatz eines LLMs bei der OM-Aufgabe bisher nicht versucht wurde. 



