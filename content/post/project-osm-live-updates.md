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

The [osm-live-updates](https://github.com/nicolano/osm-live-updates) (`olu`) tool is designed to keep SPARQL endpoints containing [*OpenStreetMap*](https://www.openstreetmap.org) (OSM) data, which has been converted to RDF triples with [*osm2rdf*](https://github.com/ad-freiburg/osm2rdf), up to date by processing [*OsmChange*](https://wiki.openstreetmap.org/wiki/OsmChange) files. Since *osm2rdf* retains the complete object geometry of the OSM data, `olu` also preserves the correctness of this geometries by updating the geometry of OSM objects in the database that reference a changed object in the *OsmChange* file.

# Content
1. <a href="#introduction">Introduction</a>
 
   1.1. <a href="#osm">Open Street Map (OSM)</a>

   1.2. <a href="#osc">OsmChange Files</a>

   1.3. <a href="#sparql">SPARQL</a>

   1.4. <a href="#osm2rdf">osm2rdf</a>

   1.5. <a href="#related_work">Related Work</a>

2. <a href="#implementation">Implementation</a>
 
    2.1. <a href="#process_osc">Processing of ChangeFile</a>

    2.2. <a href="#fetching_refs">Fetching References</a>

    2.3. <a href="#dummies">Creating Dummy Objects</a>

    2.4. <a href="#conversion">Conversion to RDF</a>

    2.5. <a href="#updating">Updating the Database</a> 

3. <a href="#testing">Testing</a>
 
    3.1 <a href="#correctness">Correctness</a>

    3.2 <a href="#performance">Performance</a>

4. <a href="#conclusion">Conclusion and Future Work</a>

* * *

# <a id="introduction"></a>1. Introduction

## <a id="osm"></a>1.1. Open Street Map (OSM)

[*OpenStreetMap*](https://www.openstreetmap.org/about) (OSM) is a collaborative geospatial database that provides free, editable, openly licensed geographic data contributed by a global community of volunteers. The OSM data consists of three core structures: nodes, ways, and relations. Nodes are points on the map with locations given in latitude and longitude coordinates. Ways are an ordered collection of nodes that logically connect them with a line. They can represent roads, rivers, or the boundaries of an area, for example. Relations are collections of nodes, ways or/and other relations. They represent logical or geographical relationships between these elements. Each of these three structures can contain tags. A tag is a key-value pair that adds information to the object. For example, a node might have a tag indicating that there is a shop at that location, or a way might have a tag indicating that it is a freeway. Relations are the only of the three structures that must have at least one tag that defines the type of relation. Each OSM object has a unique ID and a timestamp that describes when the element was created or last modified.

Nodes are the only OSM objects that explicitly contain geographic information. Ways and relations derive their geography from their references. So to know the geometry of a way, you also need to know the nodes it references. The same is true for relations, but with the difference that you need not only the direct references of nodes, but also the nodes that are referenced by ways that are members of the relation, and since relations can be members of other relations, you would also need their references. 

While nodes represent simple point geometry, ways can represent lines or polygons if they are closed, i.e. the first and last nodes of the path are the same. Relations can be a collection of these geometries as well as [multipolygons](https://wiki.openstreetmap.org/wiki/Relation:multipolygon) to represent complex areas with holes or multiple disjoint parts.

## <a id="osc"></a>1.2. OsmChange Files (OSM)

[*OsmChange*](https://wiki.openstreetmap.org/wiki/OsmChange) (`.osc`) is an XML file format used to describe incremental updates to the OpenStreetMap (OSM) database. It contains information about newly created, modified, or deleted OSM objects within a specific timeframe. An example of an *OsmChange* file for the modification of a single node can be seen here <a href="#osm_wiki"> [1]</a>:

```xml
<osmChange version="0.6" generator="acme osm editor">
    <modify>
        <node id="1234" changeset="42" version="2" lat="12.1234567" lon="-8.7654321">
            <tag k="amenity" v="school"/>
        </node>
    </modify>
</osmChange>
```

The tag that encloses the OSM object indicates the type of change that has been made to it, e.g. `create` for creating a new object, `modify` for modifying an existing object, or `delete` for deleting an object. The OSM element inside the tag always represents the complete state of the object with all attributes and tags, at the moment the file is created. However, this also makes it impossible to find out what changes have been made to an element in a modify tag without further information. Multiple elements are ordered by their IDs, with nodes appearing first, followed by ways, and then relations.

As ways and relations inherit their geometry from their references, they do not have to appear explicitly in the *OsmChange* file if their geometry changes. For example, if a node, which is referenced by a way, changes its position, only this node would appear in the file.  

## <a id="sparql"></a>1.3. SPARQL and RDF

[SPARQL](https://www.w3.org/TR/sparql11-query/) (SPARQL Protocol and RDF Query Language) is a standardized query language specifically designed for querying and manipulating data stored in RDF (Resource Description Framework) format. It allows users to perform complex and flexible queries on datasets. RDF represents data as a collection of subject-predicate-object statements, known as triples, which are stored in a graph structure. A single SPARQL endpoint can manage multiple graphs, and if no specific graph is mentioned in a query, the default graph is used.

A simple SPARQL query to get all triples for an OSM node object would look like this: 

```
PREFIX osmnode: <https://www.openstreetmap.org/node/>
SELECT * WHERE {
  osmnode:1 ?p ?o
}
```

Communication with SPARQL endpoints takes place via [HTTP](https://datatracker.ietf.org/doc/html/rfc2616) requests. The [SPARQL 1.1 Protocol](https://www.w3.org/TR/2013/REC-sparql11-protocol-20130321/) defines how the queries must be formulated. The communication for the above SPARQL query could be done with the following PUT request:

```HTTP
POST /sparql/ HTTP/1.1
Host: localhost:8888
Content-Type: application/x-www-form-urlencoded
Accept: application/sparql-results+xml
Content-Length: 149

query=PREFIX%20osmnode%3A%20%3Chttps%3A%2F%2Fwww.openstreetmap.org%2Fnode%2F%3E%
0ASELECT%20%2A%20WHERE%20%7B%0A%20%20osmnode%3A1%20%3Fp%20%3Fo%0A%7D
```

The SPARQL endpoint would then return a response in XML format with the results of the query. 

The [SPARQL Update](https://www.w3.org/TR/2013/REC-sparql11-update-20130321/) language can be used to modify data in RDF graphs, for example to insert a single triple, as shown below:

```
PREFIX osmnode: <https://www.openstreetmap.org/node/>
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX osm: <https://www.openstreetmap.org/>
INSERT DATA {
  osmnode:1 rdf:type osm:node
}
```

The PUT requests for the update language have a slightly different form than the query language. The PUT request to insert the above-mentioned triple could look like this, using `update` instead of `query` in the request message body:

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

[*Osm2rdf*](https://github.com/ad-freiburg/osm2rdf) is a tool for converting OSM data into RDF triples while preserving all the geometric information of the OSM data <a href="#osm2rdf_paper"> [2]</a>. For each element in the OSM database *osm2rdf* creates triples containing information about the element id, timestamp, tags, and geometric features. For ways and relations, the member relationships are also captured. For each element, geometric information about the enclosed area is also stored in a triple, including the polygon or multipolygon describing the enclosed area, the convex hull, the envelope and the oriented bounding box. For example, for the following node:

```xml
 <node id="1" timestamp="2024-07-07T19:48:37Z" lat="42.7957187" lon="13.5690032">
  <tag k="name" v="Monte Piselli - San Giacomo"/>
  <tag k="note" v="This is the very first node on OpenStreetMap."/>
 </node>
```

*osm2rdf* would produce the following triples:

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

The geometric features of the objects are stored as string literals written in Well-Known Text (WKT) format. *Osm2rdf* can also procude triples for GeoSPARQL predicates like `ogc:sfContains`, `ogc:sfIntersects`, or `ogc:sfOverlaps`, that allow the efficient use of spatial queries.

## <a id="related_work"></a>1.4. Related Work

There are tools available for SQL-like databases with similar functionality to `olu` like [*OSM2PGSQL*](https://osm2pgsql.org) which uses PostgreSQL/PostGIS databases. [*Sophox*](https://github.com/Sophox/sophox) provides a tool to generate RDF triples from OSM data and a corresponding SPARQL endpoint. It also has the ability to continuously update a SPARQL endpoint from *OsmChange* files. However, *Sophox* does not retain the geometric shape information of ways and relations, but simplifies them to a single point. Therefore, the geometries of the referencing objects are not updated.

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

We start the update process with deleting all elements from the database that we want to update by using the following query, which will also delete all linked triples, like for example geometries of member nodes.

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

# <a href="#testing"></a>3. Testing
 
## <a href="#correctness"></a>3.1 Correctness

We tested our implementation with data provided by [*Geofabrik*](https://download.geofabrik.de). The dataset contains a subset of the OSM data for a bounding box enclosing the boundaries of the federal state of [Bremen](https://download.geofabrik.de/europe/germany/bremen.html). *Geofabrik* provides full downloads of all OSM objects within these bounds for different days as well as daily change files. We started by downloading a three months old dataset and the latest dataset, converted them to RDF with *osm2rdf* using options `--add-way-node-order --write-ogc-geo-triples none` and imported the triples into previously empty graphs we named `http://example.com/updated` and `http://example.com/latest`. We then performed the update process on the `http://example.com/updated` graph with the following command

```bash
olu -u SPARQL_ENPOINT_URI -d http://download.geofabrik.de/europe/germany/bremen-updates/ 
```

Once the update process was complete, we used the following query to compare the two datasets and find all the triples that were different between them:

```
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

If the result of this query is empty, i.e. both graphs now contain the same triple, proving that our tool is correctly processing the changes in the *OsmChange* file.

The values of OSM object tags are free text, i.e. it is not specified how these strings are encoded. However, in order to process them in our tool, we decode these strings before processing them and decode them before entering them into the database. This may result in the SPARQL endpoint for the above query returning triples that are actually the same, except that special characters such as newline are encoded differently. However, this does not change the information content of the tag, so we ignore these differences when testing the correctness of our tool.

The result of our test was that, apart from the above exception, our tool correctly applied the changes from the *OsmChange* file. 

## <a id="#performance"></a>3.2 Performance

It is difficult to make an accurate statement about the performance of our tool as it depends heavily on the performance of the SPARQL endpoint it is used with and the size of the OSM dataset that needs to be updated. However, a good test of the usability of our tool are the [minutely diffs](https://planet.openstreetmap.org/replication/minute/) for the OSM-planet data, which include all changes made to the complete OSM database within a minute-by-minute time frame. These files should be able to be processed in less than a minute, as it would otherwise not be possible to keep a SPARQL instance with the OSM planet data up to date. 

To test this we used a publicly available [QLever instance](https://qlever.cs.uni-freiburg.de/osm-planet) of the complete OSM planet data. For our tests we excluded the update process (i.e. the deletion and insertion of triples) from the timing

As the number of changes made to the OSM data can vary greatly from minute to minute, we cannot guarantee that each of the change files will be processed in less than a minute, but with a longer time frame the differences should even out so that they should be able to be executed in under a minute on average.


# <a id="#conclusion"></a>4. Conclusion and Future Work

We have shown how we have implemented our tool `olu` to perform the update process for SPARQL queries containing OSM data. We have also shown that our tool returns correct results and has sufficient performance. However, the tool does not currently support the update of [GeoSPARQL](https://en.wikipedia.org/wiki/GeoSPARQL) triples such as `ogc:contains` or `ogc:intersects`. To compute these triples, it is not enough to get the information for OSM objects that reference each other, as is the case for `olu`, but one needs to get the information for each OSM element that is geometrically linked to an updated object, such as all areas where a modified node is located, or all ways that intersect a modified way. We find this problem very interesting and relevant, it would be a great expansion for our tool.


<footer>
    <h2 id="footnote-label"> References </h2>
    <ol>
        <li id="osm_wiki"> OpenStreetMap Wiki, "OsmChange", https://wiki.openstreetmap.org/wiki/OsmChange, accessed on 11.12.2024. </li>
        <li id="osm2rdf_paper"> Hannah Bast, Patrick Brosi, Johannes Kalmbach, and Axel Lehmann. 2021.
        An Efficient RDF Converter and SPARQL Endpoint for the Complete Open-
        StreetMap Data. In <i>29th International Conference on Advances in Geographic
        Information Systems (SIGSPATIAL ’21), November 2–5, 2021, Beijing, China.</i>
        ACM, New York, NY, USA, 4 pages. https://doi.org/10.1145/3474717.3484256 </li>
    </ol>
</footer>    