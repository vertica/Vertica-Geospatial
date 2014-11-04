/*****************************
 * HP Vertica Analytics Platform
 * Copyright (c) 2005 - 2014 Vertica, an HP company
 *****************************/

/**
 * DESCRIPTION
 *
 * This file contains a series of SQL commands that demonstrate
 * the use of HP Vertica Place.
 *
 * This example is a simulation of a museum tracking their visitors' location as they
 * move through the space. There are 6 different artworks visitors can view.
 * Museum visitors move through the space visiting the different artworks. Each
 * visitor's location is tracked as they move through the space. Visitors view
 * some or all of the artworks and are able to move freely throughout the space.
 * Upon reaching the exit visitors no longer generate location data and their location
 * is no longer recorded.
 * 
 * The goal is to compute different metrics on visitor locations (points) in
 * relation to each artwork (polygons).
 *
 * You need to first install HP Vertica and HP Vertica Place before running
 * the commands in this file.
 *
*/

-- Create the table for the polygons that represent the viewing areas of the artwork.

CREATE TABLE artworks (gid int, g GEOMETRY(1000)) SEGMENTED BY HASH(gid) ALL NODES;

-- Use ST_Buffer to create the polygons that we will run our intersect on.
-- The point used in ST_Buffer is the general location of the artwork.
-- In this example we've set our viewing area diameter to 8.

COPY artworks(gid, gx filler varchar, g AS ST_Buffer(ST_GeomFromText(gx),8)) FROM stdin delimiter ',';

1, POINT(10 45)
2, POINT(25 45)
3, POINT(35 45)
4, POINT(35 15)
5, POINT(30 5)
6, POINT(15 5)
\.

-- Create table for the location data transformed from Well-Known Text (WKT) to Geometry data.

CREATE TABLE usr_data (gid identity,usr_id int,date_time timestamp,g geometry(1000)) SEGMENTED BY HASH(gid) ALL NODES;

-- Transforms the WKT location data into Geometry data during the copy. Loading only the Geometry data into the database.

COPY usr_data(usr_id, date_time, x filler float, y filler float, g as ST_GeomFromText('POINT(' || x || ' ' || y || ')')) from  LOCAL 'place_output.csv' delimiter ',' enclosed by '';

-- Create the Index for the ploygons. This will be used during intersection calculations.

SELECT STV_Create_Index(gid, g USING PARAMETERS index='art_index', overwrite=true) OVER() FROM artworks;

-- Analytics

-- Answers the questions: Which work of art was the most popular? And How many people interacted with each artwork?
-- This finds the most popular work based on the number of intersections.
-- It also finds the number of people who interacted with the artwork with a minimum of 20 intersects.
-- The reason for the 20 intersects is because we don't want to count people who only briefly engage with the artwork. 

SELECT pol_gid,
       COUNT(DISTINCT(usr_id)) count_user_visit
FROM
  (SELECT pol_gid,
          usr_id,
          COUNT(usr_id) user_points_in
   FROM
     (SELECT STV_Intersect(usr_id, g USING PARAMETERS INDEX='art_index') OVER(PARTITION BEST) AS (usr_id,
                                                                                                  pol_gid)
      FROM usr_data
      WHERE date_time BETWEEN '2014-07-02 09:30:20' AND '2014-07-02 17:05:00') AS c
   GROUP BY pol_gid,
            usr_id HAVING COUNT(usr_id) > 20) AS real_visits
GROUP BY pol_gid
ORDER BY count_user_visit DESC;

-- Answers the question: On average, how much time does a visitor spend viewing an artwork?
-- This finds the average amount of time users spend intersecting with a specific polygon (average amount of time)

SELECT AVG(count_seconds)
FROM
  (SELECT usr_id, COUNT(*) count_seconds
   FROM usr_data
   WHERE STV_Intersect(g USING PARAMETER index='art_index') = 4
   GROUP BY usr_id) foo;


-- Answers the question: At the busiest times of day, how physically close are visitors to one another?
-- Average distance from each visitor at a specific time in a polygon (how close visitors are standing next to one another)

CREATE TABLE tmp(i, g) AS
SELECT usr_data.usr_id,
       usr_data.g g1
FROM usr_data,
     artworks
WHERE artworks.gid=4
  AND ST_Intersects(usr_data.g, artworks.g)
  AND date_time='2014-07-02 12:00:00';

SELECT AVG(ST_Distance(foo.g,foo1.g))
FROM tmp foo,
     tmp foo1
WHERE foo.i!=foo1.i;
