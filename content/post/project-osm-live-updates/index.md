---
title: "Osm Live Updates for SPARQL Endpoints"
date: 2024-12-05T13:30:48+01:00
author: "Nicolas von Trott"
authorAvatar: ""
tags: [osm, osc, sparql, updates]
categories: []
image: "img/project_osm_live_updates.png"
draft: false
---

The [osm-live-updates](https://github.com/nicolano/osm-live-updates) (`olu`) tool is designed to keep SPARQL endpoints containing [*OpenStreetMap*](https://www.openstreetmap.org) (OSM) data up to date. It processes [*OsmChange*](https://wiki.openstreetmap.org/wiki/OsmChange) files and works with OSM data that has been converted into RDF triples using `osm2rdf`. `olu` aims to preserve the correctness of the complete object geometry of the OSM data. The tool is open-source and available on Github.

# Content
1. <a href="#introduction">Introduction</a>
 
   1.1. <a href="#osm">Open Street Map (OSM)</a>

   1.2. <a href="#osc">OsmChange Files</a>

   1.3. <a href="#sparql">SPARQL</a>

   1.4. <a href="#osm2rdf">osm2rdf</a>

   1.5. <a href="#related_work">Related Work</a>

2. <a href="#implementation">Implementation</a>
 
    2.1. <a href="#problem_def">Problem Definition</a>

    2.2. <a href="#provide_osc">Providing Change Files</a>

    2.3. <a href="#process_osc">Processing Change File</a>

    2.4. <a href="#fetching_refs">Fetching References</a>

    2.5. <a href="#dummies">Creating Dummy Objects</a>

    2.6. <a href="#conversion">Conversion to RDF</a>

    2.7. <a href="#updating">Updating the Database</a> 

3. <a href="#testing">Discussion</a>
 
    3.1 <a href="#correctness">Correctness</a>

    3.2 <a href="#performance">Performance</a>

    3.3 <a href="#improvements">Possible Improvements</a>

4. <a href="#conclusion">Conclusion and Future Work</a>

* * *

# <a id="introduction"></a>1. Introduction

In this chapter, we introduce the foundational concepts necessary to understand the functionality of `olu`. We begin with an overview of OpenStreetMap (OSM), explaining its structure and how changes to its dataset are captured. Next, we explore SPARQL and RDF, the technologies enabling flexible querying and representation of structured data. Finally, we present a tool for converting OSM data into RDF triples, bridging the gap between geospatial datasets and semantic web technologies. 

## <a id="osm"></a>1.1. Open Street Map (OSM)

[*OpenStreetMap*](https://www.openstreetmap.org/about) (OSM) is a collaborative geospatial database that provides free, editable, openly licensed geographic data contributed by a global community of volunteers. The core data structures in OSM are nodes, ways, and relations, each playing a specific role in representing geographic information:

- Nodes: Points on the map, defined by latitude and longitude coordinates 
- Ways: Ordered collections of nodes that form lines or boundaries, representing features like roads, rivers, or areas. 
- Relations: Groups of nodes, ways, or other relations that define logical or geographic relationships, such as multipolygons or complex road networks.
  
Each OSM object can include tags, which are key-value pairs that provide descriptive information. For instance, a node might have a tag indicating it's a shop, or a way might have a tag designating it as a freeway. Among the three structures, relations are the only ones that must include at least one tag defining their type. 

Every OSM object has a unique ID, a version number (which is increased each time the object is modified), and a timestamp indicating when it was created or last edited. While only nodes directly contain geographic coordinates, ways and relations derive their geometry from their references. For example, a way's geometry is determined by its referenced nodes, and a relation's geometry depends on its members, which can include nodes, ways, and other relations. This hierarchical referencing means interpreting an objects geometry can require tracing through multiple levels of references.

## <a id="osc"></a>1.2. OsmChange Files

[*OsmChange*](https://wiki.openstreetmap.org/wiki/OsmChange) (`.osc`) is an XML file format used to describe incremental updates to the OpenStreetMap (OSM) database. It contains information about newly created, modified, or deleted OSM objects within a specific timeframe. Below is an example of an OsmChange file for the modification of a single node <a href="#osm_wiki"> [1]</a>:

```xml
<osmChange version="0.6" generator="acme osm editor">
    <modify>
        <node id="1234" changeset="42" version="2" lat="12.1234567" lon="-8.7654321">
            <tag k="amenity" v="school"/>
        </node>
    </modify>
</osmChange>
```

The tag that encloses the OSM object indicates the type of change to the database

- `create`: Adding a new object
- `modify`: Modifying an existing object
- `delete`: Deleting an object
  
The OSM element within these tags represents its complete state, including all attributes and tags, at the time the change file was created. This also makes it impossible to find out what changes have been made to an element in a modify-tag without further information. Since ways and relations derive their geometry from referenced nodes, they may not need to be explicitly included in the file if their geometry changes. For example, if a node referenced by a way changes its position, only the node would appear in the change file.

OpenStreetMap provides change files at minute, hour, and day intervals through its [replication server](https://planet.openstreetmap.org/replication/). Each change file is accompanied by a state file, which includes the timestamp of the file's creation and a running sequence number, ensuring updates can be processed in sequence.

## <a id="sparql"></a>1.3. SPARQL and RDF

[*SPARQL*](https://www.w3.org/TR/sparql11-query/) (SPARQL Protocol and RDF Query Language) is a standardized query language specifically designed for querying and manipulating data stored in [*RDF*](https://www.w3.org/TR/WD-rdf-syntax-971002/) (Resource Description Framework) format. It allows users to perform complex and flexible queries on RDF datasets. RDF represents data as a collection of subject-predicate-object statements, known as triples, where each component is identified by a Uniform Resource Identifier (URI). To simplify repeated URIs, prefixes can be defined and reused throughout queries. 

**Example SPARQL Query**

To retrieve all triples associated with an OSM node object, the following query can be used:

```
PREFIX osmnode: <https://www.openstreetmap.org/node/>
SELECT * WHERE {
  osmnode:1 ?p ?o
}
```

**Communication with SPARQL Endpoints**

SPARQL queries are submitted to SPARQL endpoints via [*HTTP*](https://datatracker.ietf.org/doc/html/rfc2616) requests, following the [*SPARQL 1.1 Protocol*](https://www.w3.org/TR/2013/REC-sparql11-protocol-20130321/). For instance, the query above can be sent using the following HTTP POST request:

```HTTP
POST /sparql/ HTTP/1.1
Host: localhost:8888
Content-Type: application/x-www-form-urlencoded
Accept: application/sparql-results+xml
Content-Length: 149

query=PREFIX%20osmnode%3A%20%3Chttps%3A%2F%2Fwww.openstreetmap.org%2Fnode%2F%3E%
0ASELECT%20%2A%20WHERE%20%7B%0A%20%20osmnode%3A1%20%3Fp%20%3Fo%0A%7D
```

The SPARQL endpoint processes the query and returns the results in the requested format, in this case XML.

**SPARQL Update Example**

SPARQL can also modify RDF data using the [*SPARQL 1.1 Update*](https://www.w3.org/TR/2013/REC-sparql11-update-20130321/) language. For example, to insert a single triple indicating that a node is of type `osm:node`, the following command can be used:

```
PREFIX osmnode: <https://www.openstreetmap.org/node/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX osm: <https://www.openstreetmap.org/>
INSERT DATA {
  osmnode:1 rdf:type osm:node
}
```

This update is submitted via an HTTP POST request, where the body specifies the `update` parameter instead of `query`:

```HTTP
POST /sparql/ HTTP/1.1
Host: localhost:8888
Accept: text/plain
Content-Type: application/x-www-form-urlencoded
Content-Length: 303

update=PREFIX%20osmnode%3A%20%3Chttps%3A%2F%2Fwww.openstreetmap.org%2Fnode%2F%3E
%0APREFIX%20rdf%3A%20%3Chttp%3A%2F%2Fwww.w3org%2F1999%2F02%2F22-rdf-syntax-ns%23
%3E%0APREFIX%20osm%3A%20%3Chttps%3A%2F%2Fwww.openstreetmap.org%2F%3E%0AINSERT%20
DATA%20%7B%0A%20%20osmnode%3A1%20rdf%3Atype%20osm%3Anode%0A%7D
```

## <a id="osm2rdf"></a>1.4. osm2rdf

[`osm2rdf`](https://github.com/ad-freiburg/osm2rdf) is a tool for converting OSM data into RDF triples while preserving all the geometric information of the OSM data <a href="#osm2rdf_paper"> [2]</a>. It creates RDF triples for each OSM object, encoding information such as the element ID, timestamp, tags, and geometric attributes. For ways and relations, `osm2rdf` also captures member relationships. The tool also calculates comprehensive geometric data for each element, including:

- Polygon or multipolygon representing the enclosed area, for closed ways and relations
- Convex hull: The smallest convex boundary that encloses the geometry
- Envelope: The minimum bounding rectangle aligned with coordinate axes
- Oriented bounding box (obb): A minimum rectangle rotated to align with the geometry

For the following OSM node:

```xml
<node id="1" timestamp="2024-07-07T19:48:37Z" lat="42.7957187" lon="13.5690032">
  <tag k="name" v="Monte Piselli - San Giacomo"/>
  <tag k="note" v="This is the very first node on OpenStreetMap."/>
</node>
```

`osm2rdf` would generate the following triples:

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

**Geometric Representation**

Geometric features are stored as string literals in the [Well-Known Text](http://giswiki.org/wiki/Well_Known_Text) (WKT) format. Common geometry types include:

- Points: Represent node locations or centroids, formatted as POINT(LONGITUDE LATITUDE).
- Lines: Represent non-closed ways, formatted as LINESTRING(LONGITUDE_1 LATITUDE_1, LONGITUDE_2 LATITUDE_2, ...).
- Polygons: Represent simple closed areas, formatted as POLYGON((...)).
- Multipolygons: Represent complex or disjoint areas, formatted as MULTIPOLYGON((...)).

`osm2rdf` also produces triples supporting GeoSPARQL predicates such as `ogc:sfContains`, `ogc:sfIntersects`, and `ogc:sfOverlaps`. These predicates enable efficient spatial queries, enhancing the usability of the converted data for geospatial analysis.

## <a id="related_work"></a>1.4. Related Work

There are tools available for SQL-like databases with similar functionality to `olu` like [*OSM2PGSQL*](https://osm2pgsql.org) which uses PostgreSQL/PostGIS databases. [*Sophox*](https://github.com/Sophox/sophox) provides a tool to generate RDF triples from OSM data and a corresponding SPARQL endpoint. It also has the ability to continuously update a SPARQL endpoint from OsmChange files. However, it simplifies the geometric information of ways and relations to single points rather than retaining their full geometric shapes. Therefore, the geometries of the referencing objects are not updated.

# <a id="implementation"></a>2. Implementation

In this section we will first define the problem we are trying to solve with our tool and then show how we have implemented the update process in our tool.

## <a id="problem_def"></a>2.1. Problem Definition

In Chapter 1, we introduced the concepts of OpenStreetMap (OSM) and osm2rdf, highlighting their potential to enable (geospatial) queries on the complete OSM dataset. However, the dynamic nature of OSM, which data is constantly modified by millions of registered OpenStreetMap users, poses a significant challenge. Re-converting the entire OSM dataset into RDF triples and reinitializing the SPARQL endpoint with every change or at regular intervals is computationally expensive and impractical. A more efficient approach involves updating only the objects in the SPARQL endpoint that have actually changed.

The OsmChange file format, as described in Section 1.2, provides a mechanism to describe incremental changes in OSM data. However, before these changes can be applied to the SPARQL endpoint, the objects in the change files must first be converted into RDF triples. Updating the geometries of OSM objects in the database adds complexity to this process. Since ways and relations do not have explicit location information, their geometries depend on referenced nodes, ways or relations. For instance, a change in a node’s position can indirectly impact the geometry of objects that reference the modified node but are not explicitly mentioned in the change file. To address this, the update process must:

- Read all objects deleted, created or modified in the OsmChange file.
- Retrieve all objects in the database that reference the modified objects.
- Retrieve all ways and nodes that are referenced by these objects.

In order for osm2rdf to determine all geometries, we need a file containing all the OSM objects mentioned above. Once we have this data, we can generate the triples, and use them to update the SPARQL endpoint. The following chapters describe the implementation of this update process within `olu`,

## <a id="providing_osc"></a>2.2. Providing Change Files

The update process is managed by the `OsmUpdater` class, which allows users to provide OsmChange files either locally or via a replication server, such as the before mentioned one from OSM. If a replication server is used and no sequence number is specified, the process determines the starting sequence number by querying the SPARQL endpoint for the node with the most recent timestamp. From this timestamp, the sequence number of the change file containing the creation or modification of this node can be determined as a starting point.

**Merging Change Files**

Since OsmChange files are commonly generated at regular intervals (e.g., minutely, hourly, or daily), multiple files may need to be processed to reflect all changes up to the latest sequence. To optimize this process, these files are merged to prevent redundant updates, like objects that are modified multiple times within the timeframe. 

The C++ library [`libosmium`](https://osmcode.org/libosmium/) is used to merge the change files. This library offers tools to read OSM objects into a buffer and sort them by type (node, way, or relation), ID, version, and timestamp. As deleting objects does not increase the version number, we also need to consider whether the object appeared in a delete-tag in the change files and sort them so that the deleted object appears last. By retaining only the latest version of each object, the merged output file reflects the cumulative changes, resulting in a single change file to process in the subsequent steps.

## <a id="process_osc"></a>2.3. Processing Change File

The resulting OsmChange file is processed by the `OsmChangeHandler` class, which executes a two-phase operation to identify and prepare OSM elements for updating.

In the first iteration, the handler reads through the change file and organizes the IDs of all OSM elements into nine sets based on their type (node, way, or relation) and the type of change (`create`, `modify`, or `delete`). These sets act as a catalog of all changes that are explicitly mentioned in the file.

During the second iteration, the handler focuses on elements within `create` and `modify` tags. Each XML representation of the objects are temporarily stored in a file. Additionally, the handler inspects the members of ways and relations and stores the IDs of these referenced elements in one of three sets: `referencedNodes`, `referencedWays`, or `referencedRelations`.

Updating the geometries of ways or relations in the database requires additional processing. For instance, when a node or way is modified, all ways or relations that reference it must also be updated. To fetch objects that reference a modified node or way in the change file, the handler sends SPARQL queries to the endpoint. For example, the following query retrieves ways referencing modified nodes:

```SQL
SELECT ?way WHERE {
  VALUES ?node { MODIFIED_NODES ... }
  ?member osmway:node ?node .
  ?way osmway:node ?member .
}
GROUP BY ?way
```

Similar queries are used to identify relations referencing modified nodes or ways. The IDs of these objects are added to two additional sets, `waysToUpdateGeometry` and `relationsToUpdateGeometry`.

At the end of this process, the handler has identified the IDs of all OSM elements that need to be updated. However, the `referencedNodes`, `referencedWays`, and `referencedRelations` sets remain incomplete, as they only include elements that are explicitly referenced by ways and relations already present in the OsmChange file. These gaps are addressed in subsequent steps.

## <a id="fetching_refs"></a>2.4. Fetching References and Creating Dummy Objects

We start by retrieving all members of relations in the `referencedRelations` or `relationsToUpdateGeometry` set with the following query:

```sql
SELECT ?uri WHERE {
  VALUES ?rel { relations }
  ?rel osmrel:member ?member .
  ?member osm2rdfmember:id ?uri .
}
GROUP BY ?uri
```

This query fetches the referenced nodes, ways, and relations which are then added to the `referencedRelations`, `referencedWays`, and `referencedNodes` sets. The same approach is applied to fetch members for each way in the `referencedWays` and `waysToUpdateGeometry` sets.

**Creating Dummy Objects**

Once all referenced object IDs are collected, dummy objects are created for each referenced object. These dummy objects are placeholders that provide only the essential geometric and relational information required by the referencing objects. This means we have to retrieve the location for each referenced node, and the members of each referenced way and relation in correct order.

As the location is stored in a triple with the subject `osm2rdfgeom:osm_node_`, we can fetch them with the following query:

```sql
SELECT ?nodeGeo ?location WHERE {
  VALUES ?nodeGeo {  }
  ?nodeGeo geo:asWKT ?location .
}
```

The query returns the node’s location in Well-Known Text (WKT) format, which is then parsed to extract latitude and longitude. Using this information, an XML element is created for each referenced node, such as:

```xml
<node id="NODE_ID" lat="LATITUDE" lon="LONGITUDE"/>
```

For referenced ways and relations we need to fetch information about all members, whereby we maintain the correct order of the members. This information is stored in a triple with the predicate `osm2rdfmember:pos`, that is generated by osm2rdf when using the `--add-way-node-order` option. For ways, this information is fetched using the following query:

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

For relations, the query must also include the type (using the `osmkey:type` predicate) and the role of each member. This distinction is important because only relations of type `multipolygon` or `boundary` have polygonal geometries. The role of each member (e.g., inner or outer edges of a polygon) further defines its contribution to the overall geometry.

At this stage, dummy objects have been created for all referenced nodes, ways, and relations. Therefore, we can start to convert the objects to RDF triples.

## <a id="conversion"></a>2.6. Conversion to RDF

With the XML objects now containing all relevant information for each OSM element, the data can be converted into RDF using the `osm2rdf` tool. For this process, a modified version of the tool is used from a forked [repository](https://github.com/nicolano/osm2rdf). This version avoids the use of blank nodes in member relationships by generating unique identifiers. These identifiers are created by combining the parent object's ID with the member's ID and position, using the `osm2rdf:member` namespace.

For example, the original output:

```
osmrel:1189 osmrel:member _:6_0 .
_:6_0 osm2rdfmember:id osmway:1069 .
```
is transformed into:

```
osmrel:1189 osmrel:member osm2rdfmember:osmrel_1189_osmway_1096 .
osm2rdfmember:osmrel_1189_osmway_1096 osm2rdfmember:id osmway:1069 .
```

This adjustment eliminates arbitrary blank node identifiers, making it easier to verify the correctness of results during testing and debugging.

Before converting OSM data to RDF, the elements (nodes, ways, and relations) are gathered in an ordered `.osm` file, which is then processed using the `osm2rdf` tool.

## <a id="updating"></a>2.7. Updating the Database

The database update process starts by removing all triples from the database that belong to objects that were in a `delete`, `create` or `modify` tag in the OsmChange file, or that belong to objects, which geometries need to be updated, e.g. the elements in the `waysToUpdateGeometry` and `relationsToUpdateGeometry` sets. This is achieved using the following SPARQL query:

```sql
DELETE {
  ?s ?p1 ?o1 .
  ?o1 ?p2 ?o2 .
}
WHERE {
  VALUES ?s { NODES | WAYS | RELATIONS }
  ?s ?p1 ?o1 .
  OPTIONAL {
    ?o1 ?p2 ?o2 .
  }
}
```

This query ensures that:

- All triples with the specified subjects `osmnode:`, `osmnway:`, and `osmnrel:` combined with their ID, are deleted.
- Any nested relationships `?o1`, such as geometries and member-relationships, are also removed.

**Filtering the Triples**

Before inserting new triples generated by `osm2rdf`, the data is filtered to exclude triples originating from referenced nodes, ways, or relations, ensuring that only relevant triples are inserted into the database.

The filtering process involves iterating through each generated triple, extracting the corresponding OSM object ID, and verifying whether the ID belongs to a relevant object. Relevant objects are those directly impacted by the changes, excluding those included solely as references.

**Inserting the Updated Triples**

The filtered triples are added to the database using the following SPARQL update query:

```sql
INSERT DATA { TRIPLES ... }
```

# <a href="testing"></a>3. Discussion

In this section, we evaluate the results of our implementation, testing the tool's ability to correctly update the database and analysing its performance. We also suggest potential improvements to increase its functionality and efficiency.
 
## <a href="correctness"></a>3.1. Correctness

We tested the implementation using OSM data provided by [*Geofabrik*](https://download.geofabrik.de), focusing on the subset for the federal state of [Bremen](https://download.geofabrik.de/europe/germany/bremen.html). Geofabrik offers full datasets and daily change files for specified regions. For testing, we downloaded a three-month-old dataset and the latest dataset, converted them to RDF using `osm2rdf` with the options `--add-way-node-order --write-ogc-geo-triples none`, and imported the triples into two empty graphs: `http://example.com/updated` and `http://example.com/latest`.

The update process was performed on the `http://example.com/updated` graph, which can be specified with `-g`, using the following command:

```bash
olu SPARQL_ENPOINT_URI -d http://download.geofabrik.de/europe/germany/bremen-updates/ -g http://example.com/updated
```

Once the update process was complete, the following query was used to compare the two graphs and identify any differing triples:

```sparql
SELECT ?s ?p ?o
WHERE {
  {
    {
      GRAPH <http://example.com/updated> {
        ?s ?p ?o.
      }
    } MINUS {
      GRAPH <http://example.com/latest> {
        ?s ?p ?o.
      }
    }
  } UNION {
    {
      GRAPH <http://example.com/latest> {
        ?s ?p ?o.
      }
    } MINUS {
      GRAPH <http://example.com/updated> {
        ?s ?p ?o.
      }
    }
  }
}
```

An empty query result, would confirm that the `http://example.com/updated` graph contains the same triples as the `http://example.com/latest` graph, proving that the tool is correctly processing changes from the OsmChange files.

**Results**

The query revealed that the graphs differed in approx. 1.5 million triples before the update process. After the update, this number was reduced to two triples where only the encoding of special characters differed. This shows that the tool has correctly applied all the changes from the OsmChange files to the `http://example.com/updated` graph. 

The encoding differences occur because OSM tag values are free text with undefined encoding, which can lead to variations in the representation of special characters (e.g. line breaks). During processing, our tool decodes and re-encodes these strings before adding them to the database. While these encoding variations may appear in the SPARQL query results, they do not affect the actual information content of the tags and are therefore ignored during correctness checking.

## <a id="performance"></a>3.2. Performance

A practical benchmark for usability are the [hourly diffs](https://planet.openstreetmap.org/replication/hour/) for the full OSM planet data, which reflect all changes made to the global OSM database on an hourly basis. To maintain synchronization with the OSM planet data, these files must be processed in less than an hour on average.

We used a publicly available [QLever instance](https://qlever.cs.uni-freiburg.de/osm-planet) of the full OSM planet data to test our tool. To isolate the processing time, we skipped the delete and insert operations on the SPARQL endpoint and instead wrote the update queries to an output file using the `-o` option. We also specified the start sequence number using `-s` to ensure that only one change file was processed:

```bash
olu https://qlever.cs.uni-freiburg.de/api/osm-planet -d https://planet.openstreetmap.org/replication/minute/ -s -o sparqlUpdateOutput.txt
```

**Results**

We achieved a processing time of 44 minutes for the change file. This result demonstrates that the tool can handle updates efficiently enough to keep a SPARQL instance synchronized with the OSM planet data. While the number of changes in each diff can vary, leading to occasional delays, these variations tend to average out over longer periods, ensuring that updates remain within the required timeframe.

## <a id="improvements"></a>3.3. Improvements

While our tests demonstrate that `olu` is performant enough to handle updates for the complete OSM dataset, there remains room for optimization. The tool’s performance is influenced by several factors, including the efficiency of the SPARQL endpoint and the size of the OSM dataset being processed. A straightforward approach to improve performance would be to use a faster SPARQL endpoint or work with a smaller subset of the OSM data. However, there are also opportunities to enhance the implementation itself:

- **Multithreading Support**: Currently, `olu` does not support multithreading. Tasks such as filtering triples and creating dummy objects could be parallelized, reducing processing times and improving overall efficiency.

- **Optimizing Deletion Queries**: The deletion query presented in Section 2.7 is designed to be generalized, so that all OSM objects can be deleted without requiring knowledge of the exact triples generated by osm2rdf. While this approach provides flexibility and future proofing, it is not optimized for performance. By restricting the query to specific namespaces that correspond to triples actually present in the database, the deletion process could be made significantly faster.

- **Efficient Insertion of Triples**: An hourly diff of the full OSM dataset requires about 16 million triples to be inserted into the database. Optimizing this process is essential for scalability.One potential improvement could be leveraging the [*SPARQL LOAD*](https://www.w3.org/TR/sparql11-update/#load) operation, which allows the SPARQL endpoint to directly read an RDF document and insert triples. This method could reduce the number of HTTP requests and improve performance. However, this feature is not supported by all SPARQL endpoints, which may limit its applicability.

**Support for Bounding Boxes**

[*Geofabrik*](https://download.geofabrik.de) offers a comprehensive catalog of OSM subsets for most countries and smaller regions, such as the federal state of Bremen, which was used for testing in Chapter 3.1. While these subsets are useful, they have limitations: the selection of regions is fixed, and change files are only provided on a daily basis.

A valuable addition to `olu` would be the ability to specify a bounding box as an option. This feature would allow the tool to efficiently update smaller subsets of the OSM dataset using planet-wide diffs from OpenStreetMap. Rather than relying on pre-defined subsets, users would be able to define their own regions of interest, allowing greater flexibility when working with localized datasets and more frequent updates.

# <a id="conclusion"></a>4. Conclusion and Future Work

In this work, we presented the implementation of our tool, `olu`, designed to update SPARQL endpoints containing OpenStreetMap (OSM) data. We demonstrated that `olu` produces correct results and offers sufficient performance for practical use. However, the tool currently does not support the update of [*GeoSPARQL*](https://en.wikipedia.org/wiki/GeoSPARQL) triples, such as `ogc:contains` or `ogc:intersects`. Generating these triples requires more than just resolving direct references between OSM objects, as is done in `olu`. It also necessitates identifying all OSM elements that are geometrically linked to updated objects, for instance, all areas containing a modified node or all ways intersecting a modified way. Addressing this limitation is both a challenging and significant task, making it a promising direction for future work and a valuable enhancement to the functionality of `olu`.

<footer>
    <h2 id="footnote-label"> References </h2>
    <ol>
        <li id="osm_wiki"> OpenStreetMap Wiki, "OsmChange", https://wiki.openstreetmap.org/wiki/OsmChange, accessed on 11.12.2024. </li>
        <li id="osm_wiki_diffs"> OpenStreetMap Wiki, "Planet.osm/diffs", https://wiki.openstreetmap.org/wiki/Planet.osm/diffs, accessed on 13.12.2024. </li>
        <li id="osm2rdf_paper"> Hannah Bast, Patrick Brosi, Johannes Kalmbach, and Axel Lehmann. 2021.
        An Efficient RDF Converter and SPARQL Endpoint for the Complete Open-
        StreetMap Data. In <i>29th International Conference on Advances in Geographic
        Information Systems (SIGSPATIAL ’21), November 2–5, 2021, Beijing, China.</i>
        ACM, New York, NY, USA, 4 pages. https://doi.org/10.1145/3474717.3484256 </li>
    </ol>
</footer>    
