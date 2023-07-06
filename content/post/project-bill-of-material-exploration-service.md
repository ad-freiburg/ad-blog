---
title: "Bill of Material Exploration Service"
date: 2023-02-10T15:29:49+01:00
author: "Johannes Herrmann"
authorAvatar: "img/project_btc_trading_app/portrait.jpg"
tags: ["Bill of Material", "Microservices", "Industry 4.0", "Supply Chain", "Semantic Web", "Product Lifecycle Management"]
categories: ["project"]
image: "img/project_bill_of_material_exploration_service/exploded_view.jpg"
draft: false
---

To make business decisions based on data, the accessibility of information is essential.
In the current supply chain situation and the resulting shortage of materials, the structure 
of products has gained importance. Bills of materials (BoMs) govern this structure. At the same time, the complexity of BoMs is constantly increasing due to global production and procurement. 

With classical relational data models and databases, BoM analysis is often time consuming and requires
expert knowledge.
To be able to evaluate these structures efficiently and reliably, the Bill of Material Exploration Service was developed based on graph technology.

<!--more-->

# Content

1. [Introduction](#1-introduction)
1. [Project](#2-project)
1. [Implementation](#3-implementation)
    1. [Data Model](#31-data-model)
    1. [Data Provision](#32-data-provision)
1. [Outlook & Result](#4-outlook)

# 1. Introduction

## Bill of material

Bills of materials (BoMs) contain essential information for manufacturers. In essence, a BoM is a list of components or raw materials that are necessary to manufacture a specific item. While there are software BoMs as well, this project primarily focuses on hardware BoMs, as it was conducted in collaboration with an industrial manufacturer, which primarily deals with the production of hardware.

Material can be any component, from a simple screw to a high-tech piece of hardware.
This gives rise to recursion: a BoM may contain materials that are also produced in-house
and so these components themselves have their own BoM. And then these BoMs in turn might contain
components that have a BoM and so on.

For example, let's consider an (oversimplified) BoM for a sensor. The list representing the BoM might include components such as a sensor module, a housing, and electronic circuitry. The sensor module, being a crucial part of the sensor, may have its own BoM, comprising items like lenses, photodetectors, and signal processors. Furthermore, the lenses used in the sensor module might have their own BoMs, including elements such as glass, coatings, and mounting fixtures.

<img src="/../../img/project_bill_of_material_exploration_service/BoM-simple.png" width=80%>

BoMs provide an important interface between the engineers who develop and design
the hardware and the production facilities. The engineers need to specify which components
are required in which quantities, such that the production can be transferred and scaled
to factories. But there lies more vital information within a BoM. For example, an engineer
who is designing a new product might need information on which parts were used in a similar, already
existing product. And BoMs are just as important in production. If the production of a certain
product is stopped, it is relevant to know which components are not needed anymore.

Moreover, BoMs not only play a large role in development and manufacturing but
also in other processes. The ability to link the BoM data with other relevant data points provides many opportunities
to answer questions that are important for an industrial manufacturer. For instance, by connecting BoM data with vendors, it becomes possible to enhance the early detection of potential supply chain risks. Additionally, BoM data can be leveraged to determine the extent and impact on products when there is a price alteration or a halt in the delivery of a particular component.

Within a company, any of these contexts may give rise to complex questions about the
BoM structure. A service that can answer each of these questions in detail is
out of scope for this project. Instead, the service(s) implemented in this project will
focus on answering the most basic question "How often is material X part of material Y?".
The answer produced by the service should be generic while being detailed enough to
derive the answers to more complex questions.

## Alternative Materials, Parallel Production, and Validity
The simple structure of BoMs and the parthood relation is made more complicated by the reality of hardware manufacturing. 

### Alternative Materials
A BoM may specify alternatives for certain materials to be used instead of others. There
might be, for example, two types of screws that are very similar and can be used
interchangeably to manufacture some product. In this case, it is not possible to determine
the components of this product in general. Each of these screws might have been used. Only when handed a specific instance of the product, it is possible to determine which screws were used.

### Parallel Production
Parallel production refers to the simultaneous production of a material in two plants.
The problem is that plants can be very different from one another. They may differ for
example in machinery or staff. And they can be located in different countries. This
necessitates that each plant has its own BoM version of every material produced
there.
For example, consider a sensor that has to be assembled by gluing the hull
together. There are two plants; one plant has advanced machinery which can glue parts
together and in the other plant humans do the same work. Both plants can produce the
sensor, but the plant with advanced machinery would require less glue than
the plant operated by humans. So the sensor has effectively two BoMs, one for each plant.

The fact that there can be completely different BoMs for the same material affects
the parthood relation between the materials. There are three cases:

1. Both plants use the same material in the same quantity
1. Both plants use the same material but in different quantities
1. One plant uses another material than the other plant (or none at all)


In the first case, the parallel production is identical and thus the parthood is virtually the same. In the second and third cases, however, two distinct parthood relations need to be taken into account.

## Validity
Each BoM entry has a date range associated with it, during which it is considered valid.
A BoM may change during its lifetime and these changes are recorded using these validity
time ranges. However, this implies that the parthood connections between materials are
not static. A material that has been used a year ago might not be used in the current
version of the BoM.

# 2. Project
The goal of this project is to answer the question "How often is material X part of material Y?" efficiently and as accurately as possible.
It should be an improvement over the software used typically in industrial manufacturing.

The legacy system has several drawbacks to answer the question above. It can only display the parent
materials directly above the given materials. Though the system is capable to display all child
materials of a given material, it does not take into account parallel production, alternatives, or
validities. Furthermore, there does not exist an API interface to query parent or child materials of
some given materials. The functionalities described above are only accessible via the user interface.
This legacy system uses a relational database to store the BoM data. Finding usage paths from one
material to another requires many self-joins of the underlying table and is thus very inefficient for
the kind of questions this project aims to answer. So, even if this system would implement a REST API
or something similar, its technology is not well suited for this specific problem.

The software should also be able to answer which materials have alternatives or parallel production.
For all queries, it needs to be possible to specify a _validity_ date, at which all data in the query
result has to be valid. As mentioned above, it is not always possible to determine how often exactly one material occurs on the BoM of other materials. In this case, the answer should be the upper bound 
of how often the material might occur.
When these goals are met, the software will provide an improvement over the current solution and
enable new use cases.

Furthermore, the software should be extensible and scalable in the long term. It is
supposed to be used by the Research and Development department of the company. Some of the planned
features are filtering based on plant, position type, or other fields. Another important feature is
the front end. It is developed separately from this project and integrated into a company-internal marketplace of data products.

# 3. Implementation
## 3.1 Data model
The data is modeled as a graph and stored in a graph database. Each material is
represented by a node in the graph. There is a directed edge between two materials,
if one is part of the other, i.e. one material appears on the BoM of another material.
The direction of the edge is from the containing material (parent) to the contained
material (child). So an edge can be interpreted as **hasPart** (or parthood) predicate.
The relevant data regarding that usage, such as usage quantity, unit, plant, and so on
can be stored at each edge and is described in more detail in the section below.

<img src="/../../img/project_bill_of_material_exploration_service/hasPart.png" width=30%>

Because these multiple uses may have different data associated with them, it is necessary
to make a distinction between these usages in the data model. This can be done by inserting
multi-edges into the graph, such that each edge can hold the data for one usage.

Furthermore, there may not be cycles in the graph. A cycle would entail that some
material is made from itself. From a philosophical perspective, it could be argued
that this might be the case. However, in the practical context of engineering and
manufacturing, this does not make sense. Thus, if a cycle is found the underlying dataset
is faulty and needs to be fixed at the data source. So, for this project, we may
treat the graph as being acyclic.

To summarize; the data can be represented by a directed, acyclic graph with multi-edges.

### Attributes of hasPart

Most of the relevant data concerns the edges between the materials. First and foremost
is the quantity and the unit of how much of the child material is used in the parent
material. Other important attributes of the hasPart relation are the plant where the
parent material is produced, which position the child material has on its parent's BoM,
and the position type (which is used to mark alternative materials).

To store the data in a regular RDF format, it is necessary to use an n-ary hasPart property. For each hasPart edge between two materials, a node is inserted representing this composition of child and parent material. The additional attributes are stored at the composition node via properties. The following properties have been added to the data model:

 - Object properties
   - hasPlant: The plant where the parent material is produced
   - hasPosition: The position of the child on its parent's BoM
   - hasPosType: The position type (indicates alternative materials)
 - Data properties
   - hasQuantity (float): Quantity of child material needed to produce one parent material
   - hasUnit (string): The unit of the quantity (pieces, meter, kg, ...)
   - validFrom (datetime): Timestamp, when this BoM started to be valid
   - validUntil (datetime): Timestamp, when this BoM stops to be valid
   - hasProbability (float, optional): Probability, that this child is used as an alternative (if it is an alternative material)

<img src="/../../img/project_bill_of_material_exploration_service/datamodel.png" width=100%>

The object properties are required for alternative materials and parallel production
and are explained in more detail in the sections below.

The name "composition" for these nodes has been chosen to reflect
the nature of parthood in the case of BoMs. There are many ways in which one thing
can be part of another thing. For example, bronze is part of a bronze statue and
wheels are part of a car. But while it is possible to remove the wheels from the car
with the car still existing afterward, the same is not possible with the bronze of
a bronze statue. This is because both cases refer to different sub-properties of hasPart:
constitution and composition.
Bronze constitutes a bronze statue and wheels are components of a car.
Similarly, a BoM can be seen as a list of components that make up the parent material
(i.e. the composites). Thus the name composition appears to match the semantics of BoMS.
Note, however, that the study of parthood has its philosophical field of study
(Mereology) which investigates the many subtleties of this property. So a more in-depth
examination of this property is out of the scope of this project.

### Alternatives
Each (child) material that appears on a BoM has a certain position. As mentioned above,
a BoM can be thought of as a list, and this BoM position simply refers to the position
of the child on its parent's list of materials.
Multiple materials in the same position indicate that there are alternative
materials or parallel production.
Alternative materials are marked as such by their position type.
The position type is a simple string, which originates from the data source and is
stored at the composition node.

Thus a material has an alternative, if and only if:

 1. Both materials appear in the same position
 1. Both materials are used in the same plant
 1. One of the materials has the position type "alternative"

As mentioned above, alternatives also have a probability associated with it. In theory, it is
possible to determine after production how many of each alternative material was used and from
that calculate a distribution. With this, it could be possible to determine which alternatives
are the most important. In practice, however, this probability field at the data source is only
used to indicate, whether an alternative is used at all.

## Parallel Production
Like alternative materials, parallel production can also be identified by position, but it
is not indicated by the position type. There is parallel production between two materials, if:

 1. Both materials appear in the same position
 1. Both materials are used in different plants

Note, that the conditions of parallel production and alternative materials theoretically partition
the data: If two materials appear on the same position they either are produced in the same plant
or they are not. If they are, then one of them should be an alternative material. If they are not,
then there is parallel production between them. This invariance can be used to ensure proper
data quality. If there are two materials in the same position and the same plant, but the
position type does not indicate an alternative material, then a human needs to intervene and
examine the data in detail.

A case distinction can be made to assess how much information is entailed by the parallel production
between two child materials:

1. Both plants use the same material in the same quantity. Then the usage quantity of the child material can be precisely determined.
1. Both plants use the same material in different quantities. Then it is not possible to determine
a precise quantity, but it is possible to aggregate them. E.g. compute the maximum, minimum,
average, or others, depending on the application.
1. The plants use different materials. As in the case above, it is not possible to determine a precise quantity and an aggregate needs to be computed. However, because different materials are used it is also possible that the units do not match. This is not necessarily a problem, as long as the user gets notified.

## 3.2 Application Architecture
The application was built using a microservice architecture. Each step in the line has been
implemented as a microservice. These microservices will run on a Kubernetes cluster. Kubernetes
in conjunction with a microservice architecture are easily scalable by simply deploying more instances
of the microservice in the cluster. So, if one of the microservices proves to be a bottleneck in the
pipeline, then it is possible to only scale this specific component of the pipeline without affecting
the rest. If the whole pipeline would be managed by a monolithic architecture, then either the code
would need to be changed or the whole monolith deployed multiple times.

The drawback of a microservice architecture is the increased overhead and special importance of the
service's API: it is the only interface between the microservices, as they should otherwise be completely independent. A breaking change in some API may affect multiple other microservices down the line, causing a cascade. Each of the microservices needs to have its own Docker image to be
independently deployable from each other. In most cases, the service also requires its own web server.
With this comes the overhead of handling multiple, often similar configurations which can be mostly
mitigated by the automatic mechanisms of a Kubernetes cluster. Some overhead also occurs in the form
of code redundancy, because similar data objects have to be specified in each microservice. However,
these internal data representations are independent of other microservices. This places more
importance on the external REST APIs of the services.

The microservices were implemented using a specification-first approach, in which the specification was
written first and then implemented. For this approach, the connexion package developed by Zalando was
used. This framework was built on top of the Python Flask web framework and requires an Openapi
specification, which is a widely used standard. Connexion connects the YAML file of this specification
directly with the source code of the web server. It is also capable to check whether the server's JSON
responses fit the specification.

<img src="/../../img/project_bill_of_material_exploration_service/architecture.png" width=100%>

### Data Loading
The origin of the data is a legacy system that stores the BoM data in a relational database. The
full dataset needs to be downloaded from this legacy system and uploaded into a graph database.
At the company, the database GraphDB from the vendor Ontotext is used. It provides an RDF-quad store with a SPARQL engine. The
microservice which does these bulk down- and uploads is called Bulky.

The legacy system provides the data through a SOAP-XML interface. The purpose of the first microservice is to download the XML data, transform it into turtle format and insert it into
GraphDB. The following services only depend on the data in the GraphDB. So this stage needs to
ensure the data integrity of the data in the GraphDB. This means checking that the graph is acyclic,
ensuring necessary data fields are filled and all data can be parsed. If one of these checks
fails, then the data is not uploaded to GraphDB. Thus, if data is present in the GraphDB, it has
to conform to the quality standards defined in this service.

### Finding Paths
Computing how often one material is part of another material can be done by finding all paths between
these materials and then aggregating them. These tasks are split into two microservices. The first
microservice is called "Pathfinder" and as the name implies, its purpose is to find all paths between two
materials. Because the underlying graph is acyclic, there is a finite number of paths between materials.

Finding these paths can be done with a simple breadth- or depth-first-search. As all paths need to be
enumerated, using more sophisticated algorithms such as Dijkstra's or A* does not provide a performance
improvement.
The pathfinder service uses the NetworkX Python library, which relies on C and Fortran libraries like
other performant Python libraries such as NumPy.

Each path consists of at least two materials, the start and the end of the path. For a single path,
it is straightforward to calculate the quantity of how often the end material is part of the start material.
This quantity is equal to the product over all edge quantities which the path consists of.
Only if multiple paths are aggregated, ambiguity over the quantity arises.

The Pathfinder service can find all parents or all children of a given list of materials.
It will download the relevant subgraph from GraphDB, consisting of either all predecessors
or all successors and the edges between them. Then all paths that end or start on the input materials are
computed using NetworkX. These paths are converted into JSON and returned by the service.

### Aggregating Paths
The next service is called the "Bill of Material Exploration Service", or BoMES for short. Its purpose is
to aggregate a list of paths into answer objects. This object carries all relevant information about how often one material is part of another material.

Most important is the aggregated quantity. The quantity has to be aggregated because of the different
ways a set of materials might be part of another material. Consider four materials: _A_, _B_, _C_ and _D_.
Material _D_ is part of _B_ and _C_. The materials _B_ and _C_ are both part of _A_.
So there are two paths from _A_ to _D_: (_A_, _B_, _D_) and (_A_, _C_, _D_). The query is how often
material _D_ is part of material _A_.

<img src="/../../img/project_bill_of_material_exploration_service/parallels.png" width=60%>

There are two cases:

1. Both material _B_ **and** material _C_ are used to manufacture material _D_
1. Either material _B_ **or** material _C_ are used to manufacture material _D_

In the first case, the quantities of both paths need to be added together and result in a precise
quantity. In the second case, either of the paths may have been used in manufacturing so there is not
one precise quantity of how often material _D_ is part of material _A_. This may be the case in either
parallel production or alternative materials (as detailed above) and the minimum or maximum overall
path quantities should be returned.

Because of this aggregation, it is necessary to include further information. Firstly, the parallel
production type, and secondly, whether there are alternatives on one of the paths. This is done in such a way that the user can determine how much information was lost by the aggregation.

# 4. Result and Outlook

The software which was developed in this project provides an improvement over the existing
solution which uses relational databases. It is capable to compute all parent and child materials of a given list of input materials. It can accurately compute how often one material is part of another and in cases where this is not directly possible, it will return the most helpful approximation to the user. It enables new use cases
based on the BoM data product and BoMES.

One example is the phase-out process in which the production of a certain material is discontinued in
one or more plants. It is necessary to find all parts of the discontinued material, which are not used
in any other production. These materials can be found with some queries to the BoMES. Whereas before, this required manual labor to go through all BoMs in the user interface of the old system.

Some features are already planned for future versions. Filtering options are planned that can, for example, filter out results from certain plants. It is also possible to link the data in the knowledge graph with other material classifications to use for filtering.
In the current versions, BoMs can be filtered based on validity by providing a point in time at which the BoM is valid. Future versions could include an option to provide a time range during which BoMs may be valid.