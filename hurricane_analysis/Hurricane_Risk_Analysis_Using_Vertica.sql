--********************************************************************
-- HP Vertica Analytics Platform
-- Copyright (c) 2005 - 2017 Vertica, an HPE company
--
-- DESCRIPTION
--
-- This file contains a series of SQL commands that demonstrate
-- the use of HPE Vertica Geospatial Package.
--
-- This example is an analysis of the number of landmarks that intersect
-- with a given polygon (point-in-polygon analysis). 
-- 
-- 1) Load shapefile data into Vertica
-- 2) Perform a spatial join analysis with Vertica
-- 3) Create heat map data with Vertica
-- 4) Export Vertica table to shapefile
--
--********************************************************************


--********************************************************************
-- 1) Load shapefile data into Vertica 
--********************************************************************
--
-- Load the hurricane BONNIE data set (polygons) to Vertica
-- STV_ShpCreateTable returns a CREATE TABLE statement
\set bonnie ''''`echo /home/shapefiles/`'BONNIE.shp'''
SELECT STV_ShpCreateTable(USING PARAMETERS file=:bonnie) OVER();
-- Create a Vertica table to store the polygon objects
CREATE TABLE bonnie(
   gid IDENTITY(64) PRIMARY KEY,
   ADVDATE VARCHAR(36),
   geom GEOMETRY(7453)
);
-- Copy from shipfile to Vertica table
COPY bonnie SOURCE STV_ShpSource(file=:bonnie) PARSER STV_ShpParser(); -- 6 Rows Loaded
--
--
-- Load the landmars data set (points) to Vertica
\set landmarks ''''`echo /home/shapefiles/`'landmarks.shp'''
SELECT STV_ShpCreateTable(USING PARAMETERS file=:landmarks) OVER();
-- Create a Vertica table to store the point objects
CREATE TABLE landmarks(
   gid IDENTITY(64) PRIMARY KEY, 
   STATEFP VARCHAR(18),
   geom GEOMETRY(85)
);
COPY landmarks SOURCE STV_ShpSource(file=:landmarks) PARSER STV_ShpParser(); -- 236268 Rows Loade
--
--
-- US states data set from the United States Census Bureau TIGER database
-- ftp://ftp2.census.gov/geo/tiger/TIGER2015/STATE/
-- Load US states data set (polygons) to Vertica
\set states ''''`echo /home/shapefiles/`'tl_2015_us_state.shp'''
SELECT STV_ShpCreateTable(USING PARAMETERS file=:states) OVER();
CREATE TABLE states(
   gid IDENTITY(64) PRIMARY KEY,
   REGION VARCHAR(2),
   DIVISION VARCHAR(2),
   STATEFP VARCHAR(2),
   STATENS VARCHAR(8),
   GEOID VARCHAR(2),
   STUSPS VARCHAR(2),
   NAME VARCHAR(100),
   LSAD VARCHAR(2),
   MTFCC VARCHAR(5),
   FUNCSTAT VARCHAR(1),
   ALAND INT8,
   AWATER INT8,
   INTPTLAT VARCHAR(11),
   INTPTLON VARCHAR(12),
   geom GEOMETRY(934733)
);
COPY states SOURCE STV_ShpSource(file=:states) PARSER STV_ShpParser(); -- 56 Rows Loaded
--
--********************************************************************
-- 2) Perform a spatial join analysis with Vertica
--********************************************************************
-- 
-- Compute points intersecting polygons
-- Count the landmarks affected by Bonnie, group by state and time frame 
CREATE TABLE counts AS
SELECT ADVDATE,
       STATEFP,
       count(*) counts
FROM bonnie a,
     landmarks b
WHERE ST_Intersects(a.geom,
                    b.geom)
GROUP BY ADVDATE,
         STATEFP;
--
--********************************************************************
-- 3) Create heat map data with Vertica
--********************************************************************
-- 
-- Compute the clipped areas of each state covered by Bonnie
-- Join the counts withe the clipped areas
CREATE TABLE heatmap AS
SELECT c.ADVDATE,
       c.STATEFP,
       s.STUSPS,
       c.counts,
       ST_intersection(b.geom,
                       s.geom) geom
FROM counts c,
     bonnie b,
     states s
WHERE b.ADVDATE = c.ADVDATE
  AND s.STATEFP = c.STATEFP;
--
--********************************************************************
-- 4) Export Vertica table to shapefile
--********************************************************************
-- 
-- Export the heatmap table from Vertica to shapefiles
SELECT STV_SetExportShapefileDirectory(USING PARAMETERS path = '/home/shapefiles');
-- 1) Export polygon objects in heatmap table to a shapefile
SELECT STV_Export2Shapefile(* USING PARAMETERS shapefile = 'heatmap.shp', overwrite = TRUE, shape = 'Polygon') OVER()
FROM heatmap
WHERE st_geometrytype(geom) = 'ST_Polygon'; -- 42 Rows Exported
-- 2) Export multipolygon objects in heatmap table to a shapefile
SELECT STV_Export2Shapefile(* USING PARAMETERS shapefile = 'heatmapMulti.shp', overwrite = TRUE, shape = 'MultiPolygon') OVER()
FROM heatmap
WHERE st_geometrytype(geom) = 'ST_MultiPolygon'; -- 7 Rows Exported

