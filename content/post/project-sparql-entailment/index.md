---
title: "Beyond Simple Triple Matching: An Introduction to SPARQL Entailment"
date: 2026-09-07T10:37:38+02:00
author: "Paul Brummack"
authorAvatar: "img/dragon.jpeg"
tags: []
categories: []
image: "img/writing.jpg"
---

The Resource Description Framework (RDF) is a framework for representing data as triples, consisting of a subject, predicate, and object. QLever is a graph database that can be used to store and query RDF data using SPARQL. In RDF, some triples can be logically implied by other triples. If these implied triples are not explicitly stored in the graph, queries over the graph may not return all information that follows from the stored data. The aim of this project is to derive implied triples from the triples stored in a graph and extend the graph with these triples. Queries over the extended graph can then return additional results that would not be obtained from the original graph.

## Disclaimer
I used Open WebUI and ChatGPT to improve wording and to identify grammatical and spelling mistakes. I did not use a Large Language Model to write entire text passages.

## Content
- [Disclaimer](#disclaimer)
- [Content](#content)
- [Introduction](#introduction)
- [RDF Entailment Regime](#rdf-entailment-regime)
  - [Properties](#properties)
  - [Axiomatic Triples](#axiomatic-triples)
  - [Reification of Literals](#reification-of-literals)
- [RDFS Entailment Regime](#rdfs-entailment-regime)
  - [Hierarchies](#hierarchies)
  - [Domain and Range](#domain-and-range)
  - [Datatypes](#datatypes)
  - [Additional axiomatic triples](#additional-axiomatic-triples)
- [OWL 2 RL Entailment Regime](#owl-2-rl-entailment-regime)
  - [Equality](#equality)
  - [Domain and Range](#domain-and-range-1)
  - [Classes](#classes)
    - [Equivalent classes](#equivalent-classes)
    - [Intersections, unions and owl:oneOf](#intersections-unions-and-owloneof)
    - [owl:someValuesFrom, owl:allValuesFrom and owl:hasValue](#owlsomevaluesfrom-owlallvaluesfrom-and-owlhasvalue)
    - [owl:hasKey](#owlhaskey)
    - [Cardinality restrictions](#cardinality-restrictions)
  - [Properties](#properties-1)
  - [Datatypes](#datatypes-1)
- [Implementation](#implementation)
- [Materialization Performance and Triple Counts](#materialization-performance-and-triple-counts)
- [Conclusion](#conclusion)

## Introduction
Suppose we have an RDF graph containing information about German cities, such as `:Berlin :type :CityState`. A query to find all city states (autonomous states consisting of only a city) could be 
```
SELECT ?city 
WHERE {
    ?city rdf:type :CityState.
}
```

and return `:Berlin` as a result. A query to find all cities could be written as 
```
SELECT ?city 
WHERE {
    ?city :type :City.
}
```

One problem that occurs with such queries is that the latter query will not return `:Berlin` if `:Berlin :type :City` is not explicitly contained in the graph, but only `:Berlin :type :CityState`.
The fact that Berlin is a city state implies that Berlin is a city, we say that the triple `:Berlin :type :CityState` entails `:Berlin :type :City`. There are two approaches to how to implement entailment rules. One is to alter the query, for example:
```
SELECT ?city 
WHERE {
    { ?city :type :City. } 
    UNION 
    { ?city :type :CityState. }
}
```

The other approach is to materialize entailed triples by adding them to the graph, that is to add `:Berlin :type :City` in advance and then run the original query. This blog post focuses on the second approach, namely materialization.
The World Wide Web Consortium (W3C) specifies several standards for SPARQL entailment, the so-called Entailment Regimes. This blog post will discuss three Entailment Regimes: RDF, RDFS, and OWL 2 RL.

## RDF Entailment Regime
[RDF](https://www.w3.org/TR/rdf11-mt/) defines a vocabulary of standardized terms. These contain classes such as `rdf:List` or `rdf:Property` which can be used in combination with `rdf:type` to describe the types of resources. 


### Properties
Every term that occurs in predicate position in a graph is an RDF property. Thus, for every predicate `p`, `p rdf:type rdf:Property` is entailed. For example, `:Berlin :country :Germany` entails the triple `:country rdf:type rdf:Property`. 

### Axiomatic Triples
RDF defines a set of axiomatic triples that are entailed by any graph. The axiomatic triples describe some of the standard RDF vocabulary terms:
```
rdf:type rdf:type rdf:Property.
rdf:subject rdf:type rdf:Property.
rdf:predicate rdf:type rdf:Property.
rdf:object rdf:type rdf:Property.
rdf:first rdf:type rdf:Property.
rdf:rest rdf:type rdf:Property.
rdf:value rdf:type rdf:Property.
rdf:nil rdf:type rdf:List.
```

More axiomatic triples are derived from the so-called container membership properties. There are three types of containers defined in RDF: bags, sequences, and alternatives. They can be used to represent collections of resources. For instance, a bag that contains first names of persons could be materialized as follows:
```
:firstnames rdf:type rdf:Bag.
:firstnames rdf:_1 "Anika"^^xsd:string.
:firstnames rdf:_2 "Felix"^^xsd:string.
:firstnames rdf:_3 "Jack"^^xsd:string.
:firstnames rdf:_4 "Paul"^^xsd:string.
``` 
The container membership properties `rdf:_1`, `rdf:_2`, `rdf:_3`, ... are used to define the elements of a container. Since each container membership property is a property, additional axiomatic triples are `rdf:_i rdf:type rdf:Property` for every natural number i.
Since there are infinitely many possible container membership properties, an implementation cannot materialize all axiomatic triples. Instead, only the triples are added for which `rdf:_i` occurs in the graph.

### Reification of Literals
For every literal (such as a string or integer) occurring in an RDF graph, there will be a blank node introduced representing that literal value. For instance, from `:Person :name "Jack"^^xsd:string` it will be entailed `:Person :name _:b` and `_:b rdf:type xsd:string`. A blank node (`_:b`) is a resource that does not have an IRI. Here, it is used to represent the value of the literal.

## RDFS Entailment Regime
RDF Schema ([RDFS](https://www.w3.org/TR/rdf11-mt/)) introduces a number of new standard vocabulary terms. 
RDFS extends the RDF vocabulary with terms for describing relationships between classes and properties as well as the domains and ranges of properties. It also introduces vocabulary for describing datatypes and additional vocabulary for datatypes and containers.

### Hierarchies
`rdfs:subClassOf` and `rdfs:subPropertyOf` are used for describing hierarchies such as the one in the introductory example. The triple `:CityState rdfs:subClassOf :City` states that every city state is also a city. If a graph contains that triple and `x rdf:type :CityState`, then `x rdf:type :City` will be entailed. `:Berlin rdf:type :CityState` will entail `:Berlin rdf:type :City`.

`rdfs:subPropertyOf` works similarly but is used for properties. For example, if a person has a sister, they also have a sibling. From `:hasSister rdfs:subPropertyOf :hasSibling` and `:Luke :hasSister :Leia`, it will be entailed `:Luke :hasSibling :Leia`.


Both `rdfs:subClassOf` and `rdfs:subPropertyOf` are reflexive relations. Therefore, the RDFS Entailment Regime also states that every class is a subclass of itself, and every property is a subproperty of itself. `:hasSibling rdfs:subPropertyOf :hasSibling` is being entailed, for example.

Both `rdfs:subClassOf` and `rdfs:subPropertyOf` are transitive: If `a` is a subclass of `b` and `b` is a subclass of `c`, then it follows that `a` is a subclass of `c`. The same applies to `rdfs:subPropertyOf`. For example, from `:hasTwinSister rdfs:subPropertyOf :hasSister`, and `:hasSister rdfs:subPropertyOf :hasSibling` it will be entailed `:hasTwinSister rdfs:subPropertyOf :hasSibling`. With this, `:Luke :hasTwinSister :Leia` entails `:Luke :hasSibling :Leia`.


`rdfs:Resource` represents the class of all RDF resources. Every class is a subclass of `rdfs:Resource` and every term that occurs at least once in a subject or object position is of type `rdfs:Resource`.
### Domain and Range
The domain condition introduces a rule that applies for all subjects that occur in triples with a certain property. 
If a property `p` has a domain `x`, then every subject of a triple using `p` as its predicate is inferred to be an instance of `x`. For instance, `:hasDaughter rdfs:domain :Parent` says that everything that has a child is a parent. The triple `:Anakin :hasDaughter :Leia` entails `:Anakin rdf:type :Parent`.

The range condition works similarly but applies to the object rather than the subject of the triple that contains the range property.
This allows us to make a statement about the object, such as `:hasDaughter rdfs:range :FemalePerson` (If a person has a daughter, that daughter is a female person). With this range condition, `:Anakin :hasDaughter :Leia` entails `:Leia rdf:type :FemalePerson`.
### Datatypes
A graph can make use of any number of datatypes. They are used to determine the type of literals, such as `:Anakin :favoriteColor "black"^^xsd:string`. Every datatype that occurs in the graph is of type `rdfs:Datatype`, and a subclass of `rdfs:Literal`. In a graph that contains the latter triple, it is entailed `xsd:string rdf:type rdfs:Datatype` and `xsd:string rdf:subClassOf rdfs:Literal`.

### Additional axiomatic triples

In addition to the RDF axiomatic triples, RDFS defines further axiomatic triples, describing some of the introduced RDFS standard vocabulary terms.
```
rdf:type rdfs:domain rdfs:Resource.
rdfs:domain rdfs:domain rdf:Property.
rdfs:range rdfs:domain rdf:Property.
rdfs:subPropertyOf rdfs:domain rdf:Property.
rdfs:subClassOf rdfs:domain rdfs:Class.
rdf:subject rdfs:domain rdf:Statement.
rdf:predicate rdfs:domain rdf:Statement.
rdf:object rdfs:domain rdf:Statement.
rdfs:member rdfs:domain rdfs:Resource.
rdf:first rdfs:domain rdf:List.
rdf:rest rdfs:domain rdf:List.
rdfs:seeAlso rdfs:domain rdfs:Resource.
rdfs:isDefinedBy rdfs:domain rdfs:Resource.
rdfs:comment rdfs:domain rdfs:Resource.
rdfs:label rdfs:domain rdfs:Resource.
rdf:value rdfs:domain rdfs:Resource.
rdf:type rdfs:range rdfs:Class.
rdfs:domain rdfs:range rdfs:Class.
rdfs:range rdfs:range rdfs:Class.
rdfs:subPropertyOf rdfs:range rdf:Property.
rdfs:subClassOf rdfs:range rdfs:Class.
rdf:subject rdfs:range rdfs:Resource.
rdf:predicate rdfs:range rdfs:Resource.
rdf:object rdfs:range rdfs:Resource.
rdfs:member rdfs:range rdfs:Resource.
rdf:first rdfs:range rdfs:Resource.
rdf:rest rdfs:range rdf:List.
rdfs:seeAlso rdfs:range rdfs:Resource.
rdfs:isDefinedBy rdfs:range rdfs:Resource.
rdfs:comment rdfs:range rdfs:Literal.
rdfs:label rdfs:range rdfs:Literal.
rdf:value rdfs:range rdfs:Resource.
rdf:Alt rdfs:subClassOf rdfs:Container.
rdf:Bag rdfs:subClassOf rdfs:Container.
rdf:Seq rdfs:subClassOf rdfs:Container.
rdfs:ContainerMembershipProperty rdfs:subClassOf rdf:Property.
rdfs:isDefinedBy rdfs:subPropertyOf rdfs:seeAlso.
rdfs:Datatype rdfs:subClassOf rdfs:Class.

```
Additionally, there are more axiomatic triples concerning the container membership properties (such as `rdf:_1`, `rdf:_2`, ...). The type `rdfs:ContainerMembershipProperty` is introduced. Furthermore, its domain and range are `rdfs:Resource`. Thus, for every natural number i, it is now entailed:

```
rdf:_i rdf:type rdf:Property.
rdf:_i rdf:type rdfs:ContainerMembershipProperty.
rdf:_i rdfs:range rdfs:Resource.
rdf:_i rdfs:domain rdfs:Resource.
```

Again, these triples are only materialized if `rdf:_i` occurs in the graph.
## OWL 2 RL Entailment Regime
In the following, we will discuss a subset of the Web Ontology Language (OWL 2), the so-called OWL 2 Rule Language ([OWL 2 RL](https://www.w3.org/TR/owl2-profiles/)). It is designed so that its entailments can be computed using a set of rules, making it suitable for materialization.
OWL 2 RL does not only define rules that result in new triples. It also defines rules that state if a graph is inconsistent. For example, a graph containing `"Some String" rdf:type xsd:integer` is considered inconsistent. The inconsistency rules are not discussed in this blog post, since that would go beyond the scope.
### Equality
OWL introduces `owl:sameAs`, a property used to describe equality of terms. If a graph contains `x owl:sameAs y`, then the resources `x` and `y` can be treated as identical resources in every triple, in subject, predicate and object position. For example, if a graph contains `:Anakin owl:sameAs :DarthVader` and `:Anakin :hasSon :Luke`, it will be entailed `:DarthVader :hasSon :Luke`.

`owl:sameAs` is a symmetric, transitive and reflexive relation. Thus, a triple `x owl:sameAs y` entails `y owl:sameAs x`. If `x owl:sameAs y` and `y owl:sameAs z`, it will be entailed `x owl:sameAs z`. Also, for every resource `x` occurring in the graph `x owl:sameAs x` is entailed. Note that `x owl:sameAs x` is not materialized for literals, such as strings or integers. This is because RDF currently does not allow literals to occur in the subject position of a triple.


### Domain and Range
`rdfs:domain` and `rdfs:range` work in the same way as in the RDFS Entailment Regime. OWL 2 RL adds rules that pass domain and range information along subclass and subproperty hierarchies. Consider a graph containing:

```
p rdfs:domain c1
c1 rdfs:subClassOf c2.
```
Recall that the domain condition means that the triple `x p y` will entail `x rdf:type c1`. Together with `c1 rdfs:subClassOf c2`, it will be entailed `x rdf:type c2`. Therefore, in OWL it will be entailed `p rdfs:domain c2`. Similarly, in a graph containing:

```
p2 rdfs:domain c.
p1 rdfs:subPropertyOf p2.
```
It will be entailed `p1 rdfs:domain c`. If we replace `rdfs:domain` with `rdfs:range`, the latter rules will work in the exact same way.


### Classes

OWL introduces `owl:Thing` and `owl:Nothing` as the opposite ends of the class hierarchy. `owl:Thing` represents the class of all individuals, which means that `c rdfs:subClassOf owl:Thing` is entailed for every class `c`. `owl:Nothing` represents the empty class, there is no resource `x` for which `x rdfs:subPropertyOf owl:Nothing` is in a graph. `owl:Nothing owl:subClassOf c` is entailed for every class `c`. Since both `owl:Thing` and `owl:Nothing` are classes, `owl:Thing rdf:type owl:Class` and `owl:Nothing rdf:type owl:Class` are entailed for every graph.

#### Equivalent classes
In OWL, the same rules for subclasses are applied. Therefore, if `x rdf:type c1` and `c1 rdfs:subClassOf c2`, `x rdf:type c2` will be entailed. Reflexivity and transitivity are applied in the same way as in RDFS.
Additionally, OWL introduces equivalent classes. Two classes are equivalent if they are subclasses of each other. `c1 owl:equivalentClass c2` entails `c1 rdfs:subClassOf c2` and `c2 rdfs:subClassOf c1`, and vice versa: `c1 rdfs:subClassOf c2` and `c2 rdfs:subClassOf c1` together entail `c1 owl:equivalentClass c2`. Therefore, if `x` is type of one of `c1` or `c2`, it will also be type of the equivalent class, respectively.
`owl:equivalentClass` is a symmetric, transitive and reflexive relation. Therefore, `c1 owl:equivalentClass c2` entails `c2 owl:equivalentClass c1`. The two triples `c1 owl:equivalentClass c2` and `c2 owl:equivalentClass c3` entail the triple `c1 owl:equivalentClass c3`. From reflexivity follows that for every class `c`, `c owl:equivalentClass c`.

#### Intersections, unions and owl:oneOf
`owl:oneOf`, `owl:intersectionOf`, `owl:unionOf` are all properties used to assign a list of terms to a class. A list containing elements `element1`, `element2`, ..., `elementN` in RDF is formatted as follows:
```
head rdf:first element1.
head rdf:rest list2.

list2 rdf:first element2.
list2 rdf:rest list3.

...

listN rdf:first elementN.
listN rdf:rest rdf:nil.
```
In the following, we will write `LIST[head, element1, element2, ..., elementN]` instead.


`owl:oneOf` assigns to a class a list of individuals which are all instances of that class. That means, from
```
c owl:oneOf h.
LIST[h, y1, y2, ..., yn].
```
it will be entailed `y rdf:type c` for every `y` that is an element of the list.


A class can be the intersection of a set of other classes:
```
c owl:intersectionOf h.
LIST[h, c1, c2, ..., cn].
```

For every `ci` contained in the list, `c rdfs:subClassOf ci` will be entailed. `y rdf:type c` will entail `y rdf:type ci` for every class `ci`.
If `y rdf:type ci` for every `ci` contained in the list, it will be entailed `y rdf:type c`.


Similarly, a class can be the union of a set of other classes:
```
c owl:unionOf h.
LIST[h, c1, c2, ..., cn].
```

It will be entailed `ci rdf:subClassOf c` for every class `ci` contained in the list. If `y rdf:type ci` for any `ci`, it will be entailed `y rdf:type c`.

#### owl:someValuesFrom, owl:allValuesFrom and owl:hasValue
`owl:someValuesFrom` and `owl:onProperty` are properties used in combination to describe features of a class. For a class `x` and another class `y` and a property `p`, if `x owl:someValuesFrom y` and `x owl:onProperty p`, then a resource `u` will be of type `x` if `u p v` and `v rdf:type y`. Consider the following triples that make a statement about the class `:Student` and one example person `:Rosa`:
```
:Student owl:someValuesFrom :BachelorProgram.
:Student owl:onProperty :studies.

:Rosa :studies :BScMaths.
:BScMaths rdf:type :BachelorProgram.
```

The first two triples describe the rule that "every person that studies in a bachelor's program is a student." It will be entailed `:Rosa rdf:type :Student`, since `:Rosa` fulfills these requirements. An interesting case occurs, if the `owl:someValuesFrom`-class is `owl:Thing`. Recall that every class is a subclass of `owl:Thing`. Thus, the type of the object of the triple with the `owl:onProperty`-property is now extraneous. If we changed the example to:

```
:Student owl:someValuesFrom owl:Thing.
:Student owl:onProperty :studies.
```

The program now does not need to fulfill any requirements. `:Jack :studies :TamingLions` will entail `:Jack rdf:type :Student`.


Going back to the original example with `:Student owl:someValuesFrom :BachelorProgram`, and considering another student:
```
:Anika rdf:type :Student.
:Anika :studies :SustainableSystems.
```
It will not be entailed `:SustainableSystems rdf:type :BachelorProgram` - not all students study in a bachelor's program. This behaviour can be altered by replacing `owl:someValuesFrom` with `owl:allValuesFrom`. Consider the following class `:Program` and the student `:Anika`: 
```
:Student owl:allValuesFrom :Program.
:Student owl:onProperty :studies.

:Anika rdf:type :Student.
:Anika :studies :SustainableSystems.
```
In a graph containing the latter four triples, it will be entailed `:SustainableSystems rdf:type :Program` - every student studies in a program. Note that in the latter example with `owl:allValuesFrom`, the inference in the original direction will not work anymore. `:Geography rdf:type :Program` and `:Felix :studies :Geography` will not entail `:Felix rdf:type :Student`. If the inference is to work in both directions, both triples `:Student owl:allValuesFrom :Program` and `:Student owl:someValuesFrom :Program` must be added to the graph.


`owl:hasValue` works similarly. For the class `x`, a value `y` and a property `p`, if
```
x owl:hasValue y.
x owl:onProperty p.
```

then for any resource `u`, `u p y` entails `u rdf:type x`, and vice versa: `u rdf:type x` entails `u p y`. The difference from `owl:someValuesFrom` and `owl:allValuesFrom` is that the object of the triple with the property `p` has to be the `owl:hasValue`-value `y`, whilst in the other cases it had to be of the type specified by `owl:someValuesFrom`/`owl:allValuesFrom`. With the `owl:hasValue` term, it is possible to state similar rules but specify one certain object. For example:

```
:MathStudent owl:hasValue :Maths.
:MathStudent owl:onProperty :studies.

```
With this, `:Rosa :studies :Maths` entails `:Rosa rdf:type :MathStudent`, and vice versa.

Consider two classes both using the `owl:onProperty`-property `p` and having `owl:someValuesFrom`-classes that are subclasses of each other:
```
c1 owl:someValuesFrom y1.
c1 owl:onProperty p.
c2 owl:someValuesFrom y2.
c2 owl:onProperty p.

y1 rdfs:subClassOf y2.
```

We can entail `c1 rdfs:subClassOf c2`. The same thing applies to two classes using the same `owl:someValuesFrom`-class and `owl:onProperty`-properties that are subproperties of each other:

```
c1 owl:someValuesFrom y.
c1 owl:onProperty p1.
c2 owl:someValuesFrom y.
c2 owl:onProperty p2.

p1 rdfs:subPropertyOf p2.
```
Again, it will be entailed `c1 rdfs:subClassOf c2`. The latter two entailment rules work in the same way for `owl:allValuesFrom` instead of `owl:someValuesFrom`. The latter rule regarding subproperties also works for classes using the same `owl:hasValue`-value. The following triples will entail `c1 rdfs:subClassOf c2` as well:
```
c1 owl:hasValue i.
c1 owl:onProperty p1.
c2 owl:hasValue i.
c2 owl:onProperty p2.

p1 rdfs:subPropertyOf p2.
```

#### owl:hasKey

In OWL, a list of properties can be specified as the key of a class. If then two instances of that class have the same values for every property in the key, the individuals are considered identical. For example, a student could be identified by their matriculation number and the university at which they are studying:
```
:Student owl:hasKey :h.
LIST[:h, :matriculation, :university].
```
If two students study at the same university and have the same matriculation number, they are the same student. The following will entail `:Student1 owl:sameAs :Student2`:
```
:Student1 rdf:type :Student.
:Student2 rdf:type :Student.

:Student1 owl:matriculation "571234"^^xsd:string.
:Student1 owl:university :AlbertLudwigsUniversity.

:Student2 owl:matriculation "571234"^^xsd:string.
:Student2 owl:university :AlbertLudwigsUniversity.
```

#### Cardinality restrictions

Additional properties used to describe features of a class are `owl:maxQualifiedCardinality` and `owl:maxCardinality`.

`owl:maxQualifiedCardinality`, together with `owl:onProperty` and `owl:onClass`,
can be used to specify a maximum number of distinct values of a property for instances of a particular class:
```
c owl:maxQualifiedCardinality :xsd:nonNegativeInteger.
c owl:onProperty p.
c owl:onClass d.
```
This means that for every individual `v` with `v rdf:type c`, there can be at most `n` distinct resources `u` such that `v p u` and `u rdf:type d`. If `n = 1`, the restriction can lead to new entailments. For example:

```
:Person owl:maxQualifiedCardinality "1"^^xsd:nonNegativeInteger.
:Person owl:onProperty :hasTaxNumber.
:Person owl:onClass :TaxIdentificationNumber.
```
This states that every person has at most one tax identification number. If there are two tax identification numbers assigned to the same person, this implies that these numbers are the same. Thus, in a graph containing

```
:Jack rdf:type :Person.
:Jack :hasTaxNumber :ID1.
:Jack :hasTaxNumber :ID2.

:ID1 rdf:type :TaxIdentificationNumber.
:ID2 rdf:type :TaxIdentificationNumber.
```
it will be entailed `:ID1 owl:sameAs :ID2`. An interesting case is again the case with `c owl:onClass owl:Thing`. Since every individual is of type `owl:Thing`, the objects of the triples with the `owl:onProperty`-property as predicate do not have to be of a certain type:
```
:Person owl:maxQualifiedCardinality "1"^^xsd:nonNegativeInteger.
:Person owl:onProperty :hasTaxNumber.
:Person owl:onClass owl:Thing.
```
This is equivalent to using `owl:maxCardinality` instead, and omitting the `owl:onClass` term:
```
:Person owl:maxCardinality "1"^^xsd:nonNegativeInteger.
:Person owl:onProperty :hasTaxNumber.
```
In both cases, `:Jack :hasTaxNumber :ID1` and `:Jack :hasTaxNumber :ID2` will together entail `:ID1 owl:sameAs :ID2`. 
Note that the entailment described above relies on a maximum cardinality of 1. For larger cardinalities, no such entailment is possible.

### Properties
The rules for `rdfs:subPropertyOf` from the RDFS Entailment Regime also apply to OWL 2 RL. Additionally, OWL introduces `owl:equivalentProperty`, which works similarly to `owl:equivalentClass`. If two properties are subproperties of each other, they are equivalent to each other. The reverse is also true: `p1 owl:equivalentProperty p2` entails `p1 owl:subPropertyOf p2` and `p2 owl:subPropertyOf p1`.
Similarly to `owl:equivalentClass`, `owl:equivalentProperty` is a symmetric, transitive and reflexive relation: `p1 owl:equivalentProperty p2` entails `p2 owl:equivalentProperty p1`. `p1 owl:equivalentProperty p2` and `p2 owl:equivalentProperty p3` together entail `p1 owl:equivalentProperty p3`. For every property `p`, `p owl:equivalentProperty p`.

OWL distinguishes between `owl:DatatypeProperty` and `owl:ObjectProperty`. A datatype property `dtp` with `dtp rdf:type owl:DatatypeProperty` is a property that is intended to have literals as its objects. Similarly, an object property `op` with `op rdf:type owl:ObjectProperty` is a property that is intended to have individuals as its objects. For every datatype property and ever object property, it will be entailed `p rdfs:subPropertyOf p` and `p owl:equivalentProperty p`. The following triples are an example for the use of these properties:
```
:age rdf:type owl:DatatypeProperty.
:hasFriend rdf:type owl:ObjectProperty.

:Jack :age "42"^^xsd:nonNegativeInteger.
:Jack :hasFriend :Rita.

```

An `owl:FunctionalProperty` is a property for which each subject can have at most one object. For a functional property `fp`, `x fp y1` and `x fp y2` will together entail `y1 owl:sameAs y2`. For example,

```
:hasTaxNumber rdf:type owl:FunctionalProperty.
:Jack :hasTaxNumber :ID1.
:Jack :hasTaxNumber :ID2.
```
entails `:ID1 owl:sameAs :ID2`.
`owl:InverseFunctionalProperty` works similarly but constrains the subjects instead of the objects. For an inverse functional property `ifp`, `x1 ifp y` and `x2 ifp y` together entail `x1 owl:sameAs x2`. For example, `:phoneNumber rdf:type owl:InverseFunctionalProperty` states that every phone number belongs to at most one person. If two persons have the same phone number, they are the same person.

`owl:SymmetricProperty` and `owl:TransitiveProperty` can be used to state the Symmetry and Transitivity of properties. Examples for properties that are both transitive and symmetric are `owl:sameAs`, `owl:equivalentClass` and `owl:equivalentProperty`.
The symmetry of a property `p` can be stated using `p rdf:type owl:SymmetricProperty`. For triples having a symmetric property in predicate position, subject and object can be switched: If `x p y`, `y p x` is entailed. For example, `:hasSibling rdf:type owl:SymmetricProperty`. `:Luke :hasSibling :Leia` will entail `:Leia :hasSibling :Luke`.
Similarly, the transitivity of a property `p` can be stated as `p rdf:type owl:TransitiveProperty`. `x p y` and `y p z` together entail `x p z`. The following example triples will entail `:Jack :hasSibling :Arthur`:

```
:hasSibling rdf:type owl:TransitiveProperty.
:Jack :hasSibling :Rita.
:Rita :hasSibling :Arthur.
```

A property `p1` can be the inverse of a property `p2`, expressed as `p1 owl:inverseOf p2`. That means a triple using `p1` as predicate entails a corresponding triple using `p2` as its predicate, with the subject and object exchanged. `x p1 y` entails `y p2 x`, and vice versa. An example for two inverse properties is `:hasChild owl:inverseOf :hasParent`. `:DarthVader :hasChild :Leia` entails `:Leia :hasParent :DarthVader`.

More complex relations between properties can be specified using `owl:propertyChainAxiom` and a list of properties. If `p owl:propertyChainAxiom h` and `LIST[h, p1, p2, ..., pn]`, and there is a chain `u1 p1 u2`, `u2 p2 u3`, ..., `un pn u(n+1)`, then `u1 p u(n+1)`. Consider the following example:

```
:hasUncle owl:propertyChainAxiom :h.
LIST[:h, :hasParent, :hasBrother].

:Felix :hasParent :Leia.
:Leia :hasBrother :Jack.
```
If a person has a parent and that parent has a brother, that brother is an uncle of the person. Thus, `:Felix :hasUncle :Jack` will be entailed.

### Datatypes
OWL 2 RL defines a set of supported datatypes. For each of these datatypes `dt`, `dt rdf:type rdfs:Datatype` is entailed:

```
rdf:PlainLiteral
rdf:XMLLiteral
rdfs:Literal
owl:real
owl:rational
xsd:decimal
xsd:integer
xsd:nonNegativeInteger
xsd:string
xsd:normalizedString
xsd:token
xsd:Name
xsd:NCName
xsd:NMTOKEN
xsd:hexBinary 
xsd:base64Binary
xsd:anyURI
xsd:dateTime
xsd:dateTimeStamp
```

## Implementation


To implement the entailment rules discussed above, SPARQL Update queries are used. Some of the rules can be implemented by using a single `INSERT {...} WHERE {...}` query. For example, to implement the `rdfs:subClassOf` relation:
```
INSERT {
  ?s rdf:type ?d.
}
WHERE {
  ?c rdfs:subClassOf ?d.
  ?s rdf:type ?c.
}
```

To implement the rule that `a rdfs:subClassOf b`, `b rdfs:subClassOf c` entails `a rdfs:subClassOf c`, the following update query can be used: 

```
INSERT {
  ?a rdfs:subClassOf ?c.
}
WHERE {
  ?a rdfs:subClassOf ?b.
  ?b rdfs:subClassOf ?c.
}
```
Note that this query does not materialize all triples one might expect at first. Consider a graph containing the following triples:
```
ex:LeopardCat rdfs:subClassOf ex:Cat.
ex:Cat rdfs:subClassOf ex:Mammal.
ex:Mammal rdfs:subClassOf ex:Animal.
```

Running the update query will result in the triples `ex:LeopardCat rdfs:subClassOf ex:Mammal` and `ex:Cat rdfs:subClassOf ex:Animal`. `ex:LeopardCat rdfs:subClassOf ex:Animal` will not be materialized yet. This is because there is no `c` in the graph for which both `ex:LeopardCat rdfs:subClassOf c` and `c rdfs:subClassOf ex:Animal` exist when the query is executed.
Running the same update query a second time will then materialize `ex:LeopardCat rdfs:subClassOf Animal`. This illustrates why some entailment rules require running an update query repeatedly. After each execution, we check if the update query has added triples. Once a run does not add triples, applying the rule again will not compute new triples, and all by the rule entailed triples are materialized.

Some entailment rules are more complex. For example, the rule regarding `owl:intersectionOf` requires processing all elements of an RDF list. In the implementation, multiple different SPARQL queries have to be executed. Recall that `c owl:intersectionOf h` and `LIST[h, c1, c2, ..., cn]` will together entail `c rdfs:subClassOf ci` for every `ci` contained in the list. To implement this, we first use a query to find all classes `c` for which `c owl:intersectionOf h`. The query also returns the first element of the list `c1` and the remainder of the list, `lst`, which contains the remaining classes `c2, c3, ..., cn`:

```
SELECT ?c ?c1 ?lst1
WHERE {
  ?c owl:intersectionOf ?h.
  ?h rdf:first ?c1.
  ?h rdf:rest ?lst1.
}
```
For every class `c`, all classes `ci` contained in its intersection list have to be found. Starting with `c1` and the remainder of the list `lst1`, we iteratively retrieve the next class and the new remainder of the list using a query of the following form:

```
SELECT c(i+1) ?lst(i+1)
WHERE {
  ?lsti rdf:first ?c(i+1).
  ?lsti rdf:rest ?lst(i+1).
}
```

Recall that an RDF list ends with `rdf:nil` as the value of the `rdf:rest` property of the last list node. Before each iteration, we therefore check whether the current remainder of the list is `rdf:nil`. Once this is the case, all classes `c1, ..., cn` belonging to the intersection of `c` have been found.
For every class `c` and the classes in its intersection `c1, ..., cn`, we then apply an update query that is supposed to find all individuals `y` that are type of the class `c`. For every of these individuals `y` and every `ci`, we materialize `y rdf:type ci`. Additionally, we want to find all individuals `y` that are type of all classes `ci` of the intersection in order to entail `y rdf:type c`:

```
INSERT {
  ?y rdf:type c1.
  ?y rdf:type c2.
  ...
  ?y rdf:type cn.
}
WHERE {
  ?y rdf:type c.
};

INSERT {
  ?y rdf:type c.
}
WHERE {
  ?y rdf:type c1.
  ?y rdf:type c2.
  ...
  ?y rdf:type cn.
}
```
In another update query, we will entail `c rdfs:subClassOf ci` for every `ci` in the list:

```
INSERT DATA {
  ?c rdf:subClassOf c1.
  ?c rdf:subClassOf c2.
  ...
  ?c rdfs:subClassOf cn.
}
```
Other entailment rules which also require processing elements of a list can be implemented in a similar way. Examples for these are the previously discussed rules involving `owl:unionOf`, `owl:hasKey`, `owl:oneOf`, and `owl:propertyChainAxiom`.

Another more complex rule is the one concerning the reification of resources in RDF Entailment. As discussed previously, for every literal occuring in the graph, a blank node is introduced. If a literal occurs multiple times, it is represented by the same blank node. For example:

```
:Jack :age "42"^^xsd:integer.
:Rita :favoriteNumber "42"^^xsd:integer.
```
will add one new blank node `_:b`, resulting in:

```
:Jack :age _:b.
:Rita :favoriteNumber _:b.
_:b rdf:type xsd:integer.
```

To implement this, we first use a query to find all literals occurring in the graph. For each literal, we find all triples with that literal in its object position. The update query for adding the new triples to the graph will look schematically as follows:


```
INSERT {
  ?b1 rdf:type d1.
  s1a p1a ?b1.
  s1b p1b ?b1.
  ...
  ?b2 rdf:type d2.
  s2a p2a ?b1
  s2b p2b ?b2
  ...
}
WHERE {
  BIND(BNODE() AS ?b1)
  BIND(BNODE() AS ?b1)
  ...
}
```
`d1`, `s1a`, `p1a`, etc. represent the concrete values obtained from the graph. A separate blank node is generated for each distinct literal.

For large graphs, this can add a large number of triples. Therefore, instead of processing all literals in one query, we process them in small batches of 40 blank nodes per batch.

One aspect that hast to be kept in mind is that, in RDF, literals are not allowed to occur in subject position. For example, a graph must not contain the triple `"42"^^xsd:integer :answerTo :Universe`. Consider the following query, which implements the `owl:allValuesFrom` functionality:
```
INSERT {
  ?v rdf:type ?y.
}
WHERE {
  ?x owl:allValuesFrom ?y.
  ?x owl:onProperty ?p.
  ?u rdf:type ?x.
  ?u ?p ?v.
}
```

Now consider a graph containing:

```
:Student owl:allValuesFrom :Program.
:Student owl:onProperty :studies.

:Anika rdf:type :Student.
:Anika :studies "SustainableSystems"^^xsd:string.
```
The update query would entail `"SustainableSystems"^^xsd:string rdf:type :Program`. However, this triple is not allowed in an RDF graph because its subject is a literal. Therefore, in update queries that add a triple with term `v` in subject position without guaranteeing that `v` is not a literal, a filter 
```FILTER(!isLiteral(?v))```
needs to be added to the `WHERE` clause. If we already know that `v` occurs in the subject position of a triple in the graph, the filter is not necessary, since we then know it cannot be a literal.


An important aspect is that newly entailed triples can themselves be premises for other entailment rules. Therefore, applying every rule once is not sufficient to compute all entailed triples. Instead, all rules have to be applied repeatedly. After each iteration, we will count the triples in the graph and compare that number to the number of the last iteration. As soon as an iteration ends without adding new triples, applying any of the entailment rules again will not compute any new triples. We then know that all entailed triples were added.


Note that when applying all discussed entailment rules to a graph, some rules or parts of rules can be redundant. For example, consider again the previously discussed rule regarding `owl:interSectionOf` and the following graph: 
```
c owl:intersectionOf h.
LIST[h, c1, c2, ..., cn].
y type c.

```
The discussed implementation materializes both `y rdf:type c1` and `c rdfs:subClassOf c1`. If it materialized only the latter triple, the former would still be entailed by the rule regarding subclasses: `y rdf:type c` and `c rdfs:subClassOf c1` together entail `y rdf:type c1`. Thus, the update query adding `y rdf:type ci` for every `ci` in the intersection could be omitted. The drawback of this approach, however, would be that this specific `owl:intersectionOf` entailment rule could no longer be used independently. To obtain `y rdf:type c1`, the rules for subclass entailment would also have to be applied.

## Materialization Performance and Triple Counts

The implementation of each of the entailment rules was tested in a unit test. Additionally, all entailment rules were applied to graphs consisting of different numbers of triples to find the number of triples entailed and to measure the time required to materialize them in QLever. All measurements were performed on an AMD Ryzen 7 3700X.


The dataset [Olympics RDF](https://github.com/wallscope/olympics-rdf), published by Wallscope, is an RDF graph containing roughly 1.8 million triples. It contains information about the Olympic games, athletes, sport disciplines, results and medals, and more. One rule that requires a significant amount of computation and produces a large number of triples is the reification of the RDF Entailment Regime previously discussed. Running only the reification rule takes roughly seven minutes and adds about 700,000 triples. Running all other rules from RDF, RDFS, and OWL 2 RL takes another five minutes and adds 1.2 million triples. The fully entailed graph consists of 3.7 million triples.

[WikiPathways](https://sandbox.wikipathways.org/rdf.html) is a dataset containing information about genes, proteins, metabolites and other biological entities and how they interact with each other. The graph used for testing consists of roughly 11.3 million triples.
Running the reification rule introduces 700,000 new blank nodes and 7.8 million triples that use these blank nodes. Materializing these triples takes roughly 3.5 hours. Applying all other rules takes roughly 1.5 hours and adds 16 million triples. The fully entailed graph consists of 35 million triples.

[IMDb](https://www.imdb.com/) is a dataset containing information about movies, actors, directors, release information and more. The graph used for testing contains 41.8 million triples.
Running the reification rule would introduce 18.5 million new blank nodes and 60.4 million triples that use these blank nodes. Materializing these triples would take an impractically long time, making it no longer reasonable to perform the reification for this dataset. Materializing all entailment rules except the reification takes about 2.5 hours. It adds 25.6 million triples. The entailed graph consists of 67.4 million triples.

For larger datasets, materialization would theoretically still be feasible. However, the materialization process will take an impractically long time. Another limitation when applying the rules to larger datasets is the amount of RAM used by QLever. When materializing new triples, QLever initially stores them in RAM. When entailing IMDb, the largest graph discussed, QLever uses 40 GB of RAM after applying all entailment rules except reification. For larger datasets, the process may therefore run out of available memory. This problem can be addressed by periodically rebuilding the index using QLever's `rebuild-index` command during the materialization process. Rebuilding the index moves the newly added triples from RAM to disk storage, freeing up RAM for further materialization.

## Conclusion

The entailment rules defined by the RDF, RDFS, and OWL 2 RL Entailment Regimes were discussed and implemented. Given an RDF graph, it is now possible to materialize triples that are entailed by triples in that graph. This is achieved by executing SPARQL Update queries in QLever, resulting in an extended version of the original graph.


A query to the extended graph will yield all results obtainable from the original triples, as well as all additional results that follow from the discussed entailment rules. No changes to the queries themselves will be required. In the future, QLever could be extended to support the discussed entailment rules.