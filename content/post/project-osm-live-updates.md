---
title: "Osm Live Updates for SPARQL Endpoints"
date: 2024-12-05T13:30:48+01:00
author: "Nicolas von Trott"
authorAvatar: "img/ada.jpg"
tags: []
categories: []
image: "img/writing.jpg"
draft: true
---

The [osm-live-updates](https://github.com/nicolano/osm-live-updates) (`olu`) tool is designed to keep SPARQL databases containing [OpenStreetMap](https://www.openstreetmap.org) (OSM) data up to date by processing OsmChange files. It not only applies the changes to osm objects described in these files but also updates the geometries of objects affected by modifications to referenced elements, such as ways or relations.

# Content
1. <a href="#introduction">Introduction</a>
 
   1.1. <a href="#osm">Open Street Map (OSM)</a>

   1.1. <a href="#osc">OsmChange Files</a>

   1.1. <a href="#sparql">SPARQL</a>

   1.1. <a href="#osm2rdf">osm2rdf</a>

   1.1. <a href="#Related Work">Related Work</a>

2. <a href="#implementation">Implementation</a>
 
    2.1. <a href="#process_osc">Processing of ChangeFile</a>

    2.2. <a id="fetching_refs">Fetching References</a>

    2.3. <a id="dummies">Creating Dummy Objects</a>

    2.4. <a id="conversion">Conversion to RDF</a>

    2.5. <a id="updating"></a> Updating the Database

3. <a href="#testing-benchmarking">Testing and Benchmarking</a>
 
    3.1 <a href="#testing">Testing</a>

    3.2 <a href="#benchmarking">Benchmarking</a>

4. <a href="#conclusion">Conclusion and Future Work</a>

* * *

# <a id="introduction"></a>1. Introduction
## <a id="osm"></a>1.1. Open Street Map (OSM)

OpenStreetMap (OSM) is a collaborative geospatial database that provides free, editable, openly licensed geographic data contributed by a global community of volunteers. The OSM data consist of three core structures: nodes, ways, and relations. Nodes are points on the map with locations given in latitude and longitude coordinates. Ways are connected lines of nodes. Ways can represent, for example, roads, rivers, or the boundaries of an area. A distinction can be made between open and closed ways. Open ways are ways that start at one point and end at another. Closed ways end at the same node they started at, i.e. they enclose an area. Relations are collections of nodes, ways or other relations. They represent logical or geographical relationships between these elements. In particular, relations can represent multipolygons, for example areas with holes. Each of the three structures can contain tags. A tag is a key-value pair that adds information to the element. For example, a node might have a tag indicating that there is a shop at that location, or a way might have a tag indicating that it is a freeway. Relations are the only of the three structures that must have at least one tag that defines the type of relation. Each element in the OSM database has a unique ID and a timestamp that describes when the element was created or last modified.

## <a id="osc"></a>1.2. OsmChange Files (OSM)

[OsmChange](https://wiki.openstreetmap.org/wiki/OsmChange) (`.osc`) is an XML file format used to describe incremental updates to the OpenStreetMap (OSM) database. It contains information about newly created, modified, or deleted OSM elements (nodes, ways, and relations) within a specific timeframe. An example of an OsmChangeFile for the modification of a single node can be seen here [TODO]:

```xml
<osmChange version="0.6" generator="acme osm editor">
    <modify>
        <node id="1234" changeset="42" version="2" lat="12.1234567" lon="-8.7654321">
            <tag k="amenity" v="school"/>
        </node>
    </modify>
</osmChange>
```

The tag that encloses an object indicates the type of change that has been made to it, e.g. `create` for creating a new object, `modify` for modifying an existing object, or `delete` for deleting an object. The OSM element inside the tag always represents the complete state of the object with all attributes and tags. However, this also makes it impossible to find out what changes have been made to an element in a modify tag without further information. Multiple elements are ordered by their IDs, with nodes appearing first, followed by ways, and then relations.

## <a id="sparql"></a>1.2. SPARQL and RDF

SPARQL (SPARQL Protocol and RDF Query Language) \cite{SPARQL} is a standardized query language specifically designed for querying and manipulating data stored in RDF (Resource Description Framework) format. It allows users to perform complex and flexible queries on datasets. RDF is a data model in which data is represented as a set of subject-predicate-object statements. 

## <a href="#osm2rdf">1.3 osm2rdf</a>

[Osm2rdf]() [TODO] is a tool for converting OSM data into RDF triples while preserving all the geometric information of the OSM data. For each element in the OSM database *osm2rdf* creates triples containing information about the element id, tags and geometric features. For ways and relations, the member relationships are also captured. The geometric features of the objects are stored as string literals written in Well-Known Text (WKT) format. For each element, geometric information about the enclosed area is also stored in a triple, including the polygon or multipolygon describing the enclosed area, the convex hull, the envelope and the oriented bounding box. For example, for the following node:

```xml
 <node id="1" timestamp="2024-07-07T19:48:37Z" lat="42.7957187" lon="13.5690032">
  <tag k="name" v="Monte Piselli - San Giacomo"/>
  <tag k="note" v="This is the very first node on OpenStreetMap."/>
 </node>
```

*osm2rdf* would produce the following triple:

```
osmnode:1 rdf:type osm:node .
osmnode:1 osmmeta:timestamp "2024-07-07T19:48:37"^^xsd:dateTime .
osmnode:1 osmkey:note "This is the very first node on OpenStreetMap." .
osmnode:1 osmkey:name "Monte Piselli - San Giacomo" .
osmnode:1 osm2rdf:facts "2"^^xsd:integer .
osmnode:1 geo:hasGeometry osm2rdfgeom:osm_node_1 .
osm2rdfgeom:osm_node_1 geo:asWKT "POINT(13.5690032 42.7957187)"^^geo:wktLiteral .
osmnode:1 osm2rdfgeom:convex_hull "POLYGON((13.5690032 42.7957187,13.5690032 42.7957187,13.5690032 42.7957187,13.5690032 42.7957187,13.5690032 42.7957187))"^^geo:wktLiteral .
osmnode:1 osm2rdfgeom:envelope "POLYGON((13.5690032 42.7957187,13.5690032 42.7957187,13.5690032 42.7957187,13.5690032 42.7957187,13.5690032 42.7957187))"^^geo:wktLiteral .
osmnode:1 osm2rdfgeom:obb "POLYGON((13.5690032 42.7957187,13.5690032 42.7957187,13.5690032 42.7957187,13.5690032 42.7957187,13.5690032 42.7957187))"^^geo:wktLiteral .
```

# <a id="implementation"></a>2. Implementation

In this section we will show how we have implemented our tool \texttt{olu} in \texttt{C++}. We will show how we read and process the OsmChange files that are in XML format, how we communicate with the SPARQL endpoint that manages the graph storage, and finally how we can convert the contents of the changesets into SPARQL queries.

## <a id="process_osc"></a>2.1. Processing of ChangeFile

We process the OsmChange file by iterating to times over it. The first time we store the ids of all OSM elements inside a set for their tag. Subsequently we have nine sets that contain all created, modified, and deleted nodes, ways and relations.

The second time we only iterate over elements that where inside a modify or create tag. The XML object for each element is stored in a temporary file. We also take a look at the members of the ways and relations that where in a modify or create tag. We store the id of the member if it was not already in the OSMChange file depending on which type it is in a set we call `referencedNodes`, `referencedWays` or `referencedRelations`. 

This already allows us to process all members of the change file. However, we also want to update the geometry of ways or relations that reference a node or way that was modified. For this purpose we send a query to the SPARQL endpoint that asks for each way that reference a modified node:

```SQL
SELECT ?way WHERE {
  VALUES ?node { (All modified nodes) }
  ?member osmway:node ?node .
  ?way osmway:node ?member .
}
GROUP BY ?way
```

We do the same again for each modified node and way to fetch all relations that reference one of them. If the ways and relations are not already in the OsmChange file we store their id in a set we call `waysToUpdateGeometry` and `relationsToUpdateGeometry`. We now have the ID of each OSM element that we need to update. However, the sets for the referenced nodes, ways and relations are incomplete because they contain only the ID's of elements that where members of ways and relation which where already in the ChangeFile.

## <a id="fetching_refs"></a>2.2. Fetching References

We start with fetching all members for relations in the `referencedRealtions` or `relationsToUpdateGeometry` set with the following query:

```sql
SELECT ?uri WHERE {
  VALUES ?rel { relations }
  ?rel osmrel:member ?member .
  ?member osm2rdfmember:id ?uri .
}
GROUP BY ?uri
```

This gives us each referenced node and way which we can then store in the `referencedWays` and `referencedNodes` set. We do the same no for each way in the `referencedWays` and `waysToUpdateGeometry` set to get each node that was referenced.

We now have the ID's of each referenced OSM object. We now need to create a dummy object to store it in the responding file for the conversion with osm2rdf.

## <a id="dummies"></a>2.3. Creating Dummy Objects

We start with creating a dummy objects for each node that was referenced. The only information we need to create a node dummy is the location of the node. Since the location is stored in a triple with the subject `osm2rdfgeom:osm_node_`, we can fetch them with the following query:

```sql
SELECT ?nodeGeo ?location WHERE {
  VALUES ?nodeGeo {  }
  ?nodeGeo geo:asWKT ?location .
}
```

The returned location is a point in WKT format, from which we can extract langitude and longitude of the location. Consequential we can create an XML element for each node 

```xml
<node id="..." lat="..." lon="..."/>
```

For ways and relations we need to fetch all members, whereby it is important to maintain the correct order of the members. This information is stored in a triple with the predicate `osm2rdfmember:pos`. For ways the query looks like this:

```sql
SELECT ?way 
    (GROUP_CONCAT(?nodeUri;SEPARATOR=";") AS ?nodeUris) 
    (GROUP_CONCAT(?nodePos;SEPARATOR=";") AS ?nodePositions) 
WHERE {
  VALUES ?way { }
  ?way osmway:node ?member .
  ?member osmway:node ?nodeUri .
  ?member osm2rdfmember:pos ?nodePos
}
GROUP BY ?way
```

For relations we also have to fetch the type with the predicate `osmkey:type`. This is important, because osm2rdf only calculates geometries for relations with type *multipolygon* or *boundary*.

For ways and relations we need to make a distinction between objects that are simply there because they are a reference (`referencedWays` and `referencedRelations`) and objects which need to be updated in the database (`waysToUpdateGeometry` and `relationsToUpdateGeometry`). Since referenced elements are not updated in the database we do not need to know their tags or timestamp. However, for the ways and relations we update the geometry for we do need this information.

## <a id="conversion"></a> 2.4. Conversion to RDF

As we have an XML object containing all relevant information for each OSM element, we can now convert the OSM data to RDF using the *osm2rdf* tool. For testing purposes, we use a (fork)[https://github.com/nicolano/osm-live-updates] of the tool that avoids the use of blank nodes in member relationships, by using unique identifier by combining the ID of the parent object with the ID of the member and his position using the `osm2rdf:member` namespace. 

```
osmrel:1189 osmrel:member _:6_0 .
_:6_0 osm2rdfmember:id osmway:1069 .
```
will become

```
osmrel:1189 osmrel:member osm2rdfmember:osmrel_1189_osmway_1096 .
osm2rdfmember:osmrel_1189_osmway_1096 osm2rdfmember:id osmway:1069 .
```

This makes it much easier for us to find out later whether the results are correct. 

Before we start the conversion of the OSM data we have to order the nodes, ways and relations after their ID's. We use the (Osmium Tool)[https://osmcode.org/osmium-tool/] for this purpose:

```bash
osmium sort PATH_TO_NODE_FILE PATH_TO_WAY_FILE PATH_TO_RELATION_FILE -o PATH_TO_INPUT_FILE --overwrite
```

After performing this, we have a single ordered `.osm` which we can now convert to RDF. We have now a file that contains all triple that we need to update the database.

## <a id="updating"></a> 2.5. Updating the Database

We start the update process with deleting all elements from the database that we want to update by using the following query, which will also delete all linked triples

```sql
DELETE {
  ?s ?p1 ?o1 .
  ?o1 ?p2 ?o2 .
}
WHERE {
  VALUES ?s { TODO }
  ?s ?p1 ?o1 .
  OPTIONAL {
    ?o1 ?p2 ?o2 .
  }
}
```

Before inserting the triples that resulted from the conversion we have to filter the result, because we do not want to insert triples that resulted from referenced nodes, ways or relations.

We can then insert the filtered triples using the following INSERT query:

```sql
INSERT DATA { Triples ... }
```

# <a href="#testing-benchmarking"></a>3. Testing and Benchmarking
 
## <a href="#testing"></a>3.1 Testing

We tested our implementation with data provided by \textit{Geofabrik}. The dataset contains a subset of the OSM data for a bounding box enclosing the boundaries of the administrative district of Freiburg. \textit{Geofabrik} provides full downloads of the dataset for different days as well as daily changeFiles. We started by downloading a week old dataset and the latest dataset, converted them to RDF with \textit{osm2rdf} using options \textsc{--add-way-node-order --write-ogc-geo-triples none} and imported the triples into previously empty graphs we named \texttt{updated} and \texttt{latest}. We then performed the update process on the \texttt{updated} graph with the following command

```sql
SELECT ?s ?p ?o
WHERE {
  {
    GRAPH <http://updated> {
       ?s ?p ?o.  
    }
    FILTER NOT EXISTS {
      GRAPH <http://latest> {
        ?s ?p ?o.
      }
    }
  }
  UNION
  {
    GRAPH <http://latest> {
      ?s ?p ?o.
      FILTER NOT EXISTS {
          GRAPH <http://updated> {
            ?s ?p ?o.  
          }
       }
    }
  }
}
```

## <a href="#benchmarking">3.2 Benchmarking</a>

# <a href="#conclusion"></a>4. Conclusion and Future Work
- ogc erweiterung