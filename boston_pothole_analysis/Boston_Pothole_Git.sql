/*****************************
 * HP Vertica Analytics Platform
 * Copyright (c) 2005 - 2015 Vertica, an HP company
 *****************************/

/**
 * DESCRIPTION
 *
 * This file contains a series of SQL commands that demonstrate
 * the use of HP Vertica Place.
 *
 * This example is an analysis of the number of potholes that intersect
 * with a given polygon (point-in-polygon analysis). The shapefile used
 * in the example is FROM the US Census Bureau. The Closed Posthole Cases
 * data set is FROM the City of Boston.
 * https://data.cityofboston.gov/City-Services/Closed-Pothole-Cases/wivc-syw7
 * https://www.census.gov/cgi-bin/geo/shapefiles2013/main
 * http://www.mass.gov/anf/research-and-tech/it-serv-and-support/application-serv/office-of-geographic-information-massgis/datalayers/ftpeotroads.html
 *
 * 
 * The goal is to compute the number of potholes/streets (points)
 * per US Census Block (polygons).
 *
 * You need to first install HP Vertica and HP Vertica Place before running
 * the commands in this file.
 *
*/

-- Load raw pothole data into a flex table
CREATE flexible table boston_potholes_raw();
COPY boston_potholes_raw FROM 'potholes/Closed_Pothole_Cases.csv' PARSER public.FDelimitedParser (delimiter=',');

-- Sanity check query
SELECT MAPTOSTRING(__raw__) FROM boston_potholes_raw LIMIT 1;

-- Load pothole geometry points into a regular table
CREATE TABLE boston_potholes(gid identity, case_enquiry_id varchar(100), lat float, lon float, geom geometry(100)) SEGMENTED BY hash(gid) all nodes;
INSERT /*+direct*/ INTO boston_potholes(case_enquiry_id, lat, lon, geom)
SELECT case_enquiry_id::varchar(100), latitutde, longitude, ST_GeomFromText('POINT('||longitude||' '||latitude||')', 4326) FROM boston_potholes_raw;
COMMIT;

-- Reproject shapefile geometries to WGS84 coordinate system
-- US Census Bureau blocks SRID=4269
ogr2ogr -f "ESRI Shapefile" blocks_wgs84 tl_2014_25_tabblock10.shp -s_srs EPSG:4269 -t_srs EPSG:4326

-- Massachusetts road segment dataset SRID=26986
ogr2ogr -f "ESRI Shapefile" roads_wgs84 eotroads_35.shp -s_srs EPSG:26986 -t_srs EPSG:4326

-- Load shapefile block data
SELECT STV_ShpCreateTable(using parameters file='/home/dbadmin/BOS/shapefiles/blocks_2013_wgs84/tl_2013_25_tabblock.shp') OVER();
COPY tl_2013_25_tabblock WITH SOURCE STV_ShpSource(file='/home/dbadmin/BOS/shapefiles/blocks_2013_wgs84/tl_2013_25_tabblock.shp', srid=4326) PARSER STV_ShpParser() DIRECT;

-- Sanity check query
SELECT ST_GeometryType(geom), count(geom) FROM tl_2013_25_tabblock GROUP BY ST_GeometryType(geom);
SELECT gid, ST_AsText(geom) FROM tl_2013_25_tabblock LIMIT 10;

-- Load shapefile Boston road network data
SELECT STV_ShpCreateTable(using parameters file='/home/dbadmin/BOS/shapefiles/roads_wgs84/eotroads_35.shp') OVER();
-- Add segmentation clause to distribute road segment accross cluster nodes
CREATE TABLE eotroads_35(
   gid IDENTITY(64) PRIMARY KEY, 
   CLASS INT8,
   ADMIN_TYPE INT8,
   STREET_NAM VARCHAR(80),
   RT_NUMBER VARCHAR(4),
   ALTRTNUM1 VARCHAR(4),
   ALTRTNUM2 VARCHAR(4),
   ALTRTNUM3 VARCHAR(4),
   ALTRTNUM4 VARCHAR(4),
   ALTRT1TYPE INT8,
   RDTYPE INT8,
   MGIS_TOWN VARCHAR(25),
   ROADINVENT INT8,
   CRN VARCHAR(9),
   ROADSEGMEN INT8,
   FROMMEASUR FLOAT8,
   TOMEASURE FLOAT8,
   ASSIGNEDLE FLOAT8,
   ASSIGNED_1 INT8,
   STREETLIST INT8,
   STREETNAME VARCHAR(75),
   CITY INT8,
   COUNTY VARCHAR(1),
   MUNICIPALS INT8,
   FROMENDTYP INT8,
   FROMSTREET VARCHAR(75),
   FROMCITY INT8,
   FROMSTATE INT8,
   TOENDTYPE INT8,
   TOSTREETNA VARCHAR(75),
   TOCITY INT8,
   TOSTATE INT8,
   MILEAGECOU INT8,
   ROUTEKEY VARCHAR(20),
   ROUTEFROM FLOAT8,
   ROUTETO FLOAT8,
   EQUATIONRO FLOAT8,
   EQUATION_1 FLOAT8,
   ROUTESYSTE VARCHAR(2),
   ROUTENUMBE VARCHAR(10),
   SUBROUTE VARCHAR(10),
   ROUTEDIREC VARCHAR(2),
   ROUTETYPE INT8,
   ROUTEQUALI INT8,
   RPA VARCHAR(20),
   MPO VARCHAR(35),
   MASSDOTHIG INT8,
   URBANTYPE INT8,
   URBANIZEDA VARCHAR(5),
   FUNCTIONAL INT8,
   FEDERALFUN INT8,
   JURISDICTI VARCHAR(1),
   TRUCKROUTE INT8,
   NHSSTATUS INT8,
   FEDERALAID VARCHAR(10),
   FACILITYTY INT8,
   STREETOPER INT8,
   ACCESSCONT INT8,
   TOLLROAD INT8,
   NUMBEROFPE INT8,
   RIGHTSIDEW INT8,
   RIGHTSHOUL INT8,
   RIGHTSHO_1 INT8,
   MEDIANTYPE INT8,
   MEDIANWIDT INT8,
   LEFTSIDEWA INT8,
   LEFTSHOULD INT8,
   UNDIVIDEDL INT8,
   UNDIVIDE_1 INT8,
   LEFTSHOU_1 INT8,
   SURFACETYP INT8,
   SURFACEWID INT8,
   RIGHTOFWAY INT8,
   NUMBEROFTR INT8,
   OPPOSITENU INT8,
   CURBS INT8,
   TERRAIN INT8,
   SPEEDLIMIT INT8,
   OPPOSINGDI INT8,
   STRUCTURAL INT8,
   ADT INT8,
   ADTSTATION INT8,
   ADTDERIVAT INT8,
   ADTYEAR INT8,
   IRI INT8,
   IRIYEAR INT8,
   IRISTATUS INT8,
   PSI FLOAT8,
   PSIYEAR INT8,
   HPMSCODE INT8,
   HPMSSAMPLE VARCHAR(50),
   ADDEDROADT INT8,
   DATEACTIVE DATE,
   LIFECYCLES INT8,
   ITEM_ID INT8,
   SHAPE_LEN FLOAT8,
   geom GEOMETRY(7785)
 )
SEGMENTED BY HASH(gid) ALL NODES;

COPY eotroads_35 WITH SOURCE STV_ShpSource(file='/home/dbadmin/BOS/shapefiles/roads_wgs84/eotroads_35.shp', srid=4326) PARSER STV_ShpParser() DIRECT;

-- Create a Spatial Index on the US Census Blocks
SELECT STV_Create_Index(gid, geom using parameters index='blocks_idx', max_mem_mb=500) OVER() FROM tl_2013_25_tabblock;

-- Count the number of road segments that intersect with every block
-- Simplify by counting the number of distinct road segment end points that intersect every block
SELECT block_gid, count(distinct road_gid) road_segs
FROM (SELECT stv_intersect(road_gid, road_pt using parameters index='blocks_idx') over(partition by road_gid) AS (road_gid, block_gid)
      FROM (SELECT gid road_gid, stv_linestringpoint(geom) over(partition by gid) AS road_pt FROM eotroads_35) t) t
GROUP BY block_gid
LIMIT 20;

-- Final query to find the number of potholes per road segment in every block
SELECT ph.block_gid, round(ph.potholes/rd.road_segs, 2.0) ph_per_rseg
FROM
-- Potholes per block
(SELECT block_gid, count(ph_gid) potholes
FROM (SELECT stv_intersect(gid, geom using parameters index='blocks_idx') OVER(PARTITION BEST) AS (ph_gid, block_gid) FROM boston_potholes) t
GROUP BY block_gid) ph,
-- Road segments per block
(SELECT block_gid, count(distinct road_gid) road_segs
FROM (SELECT stv_intersect(road_gid, road_pt using parameters index='blocks_idx') over(partition by road_gid) AS (road_gid, block_gid)
      FROM (SELECT gid road_gid, stv_linestringpoint(geom) over(partition by gid) AS road_pt FROM eotroads_35) t) t
GROUP BY block_gid) rd
WHERE ph.block_gid = rd.block_gid
ORDER BY ph_per_rseg DESC
LIMIT 20;

-- Final query for R output
\t
\o heatmap.dat
SELECT block_gid || ',' || st_x(block_vertex) || ',' || st_y(block_vertex) || ',' || ph_per_rseg
FROM (
SELECT block_gid, ph_per_rseg, stv_polygonpoint(block_shape) over(partition by block_gid, ph_per_rseg) AS block_vertex FROM
(SELECT ph.block_gid, round(ph.potholes/rd.road_segs, 8.0) ph_per_rseg, bk.geom block_shape
FROM
-- Potholes per block
(SELECT block_gid, count(ph_gid) potholes
FROM (SELECT stv_intersect(gid, geom using parameters index='blocks_idx') OVER(PARTITION BEST) AS (ph_gid, block_gid) FROM boston_potholes) t
GROUP BY block_gid) ph,
-- Road segments per block
(SELECT block_gid, count(distinct road_gid) road_segs
FROM (SELECT stv_intersect(road_gid, road_pt using parameters index='boston_blocks') OVER(PARTITION BY road_gid) AS (road_gid, block_gid)
      FROM (SELECT gid road_gid, stv_linestringpoint(geom) over(partition by gid) AS road_pt FROM eotroads_35) t) t
GROUP BY block_gid) rd,
tl_2013_25_tabblock bk
WHERE ph.block_gid = rd.block_gid and bk.gid = ph.block_gid
) t) t;
\o
