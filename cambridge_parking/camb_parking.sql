/*****************************************************
 * Hewlett Packard Enterprise
 * Copyright (c) 2005 - 2016 Vertica, an HPE company
 *****************************************************/

/* DESCRIPTION
 *
 * This demo does a spatial analysis of the parking data in
 * Cambridge, MA. The points are parking tickets issued. The polygons
 * are the metered parking spaces.
 *
 * The goal is to find the parking meters with thelargest number of tickets.
 * These are the parking meters we want to avoid.
 *
 * Download the Cambridge metered parking spaces from:
 * https://data.cambridgema.gov/Traffic-Parking-and-Transportation/Metered-Parking-Spaces/6h7q-rwhf
 * Download the Cambridge parking ticket data from:
 * https://data.cambridgema.gov/api/views/vnxa-cuyr/rows.csv?accessType=DOWNLOAD
 *
 * You need to first install HPE Vertica and HPE Vertica Place before running
 * the commands in this file.
 *
 */


-- Get the create table statement for the shapefile.
SELECT STV_ShpCreateTable(USING PARAMETERS file='/camb_parking/park_spaces_shapefile/cambridge_metered_parking.shp') OVER();

-- Returns the following:
CREATE TABLE cambridge_metered_parking(
   gid IDENTITY(64) PRIMARY KEY, 
   editor VARCHAR(254),
   shape_len FLOAT8,
   space_id VARCHAR(254),
   src_date FLOAT8,
   shape_area FLOAT8,
   editdate VARCHAR(254),
   geom GEOMETRY(669)
 ) SEGMENTED BY HASH(gid) ALL NODES;

-- Load the shapefile data.
COPY cambridge_metered_parking(editor, shape_len, space_id, src_date,
                               shape_area, editdate, geom)
      WITH SOURCE STV_ShpSource(file='/camb_parking/shapefile/cambridge_metered_parking.shp')
      PARSER STV_ShpParser();

/* Create the table for the parking tickets.
 * This is the tidy version (park_meter.csv), not the raw
 * version of the data (cambridge_parking_tickets_Jan2014_July2015.csv).
 */

CREATE TABLE parking_tickets(
  gid IDENTITY(64) PRIMARY KEY,
  ticket_issue_date DATE,
  issue_time TIME,
  violation_desc varchar(80),
  meter varchar(20),
  address varchar(100),
  city_state varchar(40),
  geo_loc varchar(60),
  geom geometry(100)
) SEGMENTED BY HASH(gid) ALL NODES;

-- Load the parking ticket data.
COPY parking_tickets (ticket_issue_date, issue_time, violation_desc, meter,
                      lat filler LONG VARCHAR, lon filler LONG VARCHAR, address,
                      city_state, geo_loc,
                      geom AS ST_GeomFromText('POINT(' || lon || ' ' || lat || ')'))
FROM LOCAL '/home/dbadmin/data/camb_parking/park_meter.csv' DELIMITER ',' ENCLOSED BY '"';

/* The Four Troublesome Parking Spaces
 *
 * These spaces contain multipolygons. And after doing some further investigation,
 * it turns out that one of the polygons in each of the MULTIPOLYGONs isn't even
 * a space. Feel free to investigate these Four Troublesome Parking
 * spaces on your own. For this analysis, we want to fix these rows of data
 * and give them the correct information.
 */

-- These are the Four Troublesome Parking spaces.
SELECT space_id, st_astext(geom)
    FROM cambridge_metered_parking WHERE gid = 1211 OR gid = 1067
                                         OR gid = 1153 OR gid = 3037;

/* To fix the issue of the Four Troublesome Parking spaces, we'll need to
 * load the correct POLYGONs and do an update on the offending rows.
 */

CREATE TABLE four_troublesome_spaces (space_id varchar(15), geom GEOMETRY);
COPY four_troublesome_spaces (space_id, gx filler LONG VARCHAR, geom AS ST_GeomFromText(gx)) FROM stdin delimiter '|';
MAIN-0793|POLYGON ((-71.0971375532 42.3632802884, -71.0971346018 42.3633021484, -71.0970742065 42.3632976286, -71.0970771577 42.363275796, -71.0971375532 42.3632802884))
MTA-0115|POLYGON ((-71.1188657961 42.3721158772, -71.1188799011 42.3720965782, -71.1189066663 42.3721073413, -71.1189074414 42.3721076732, -71.1189341652 42.3721191771, -71.1189455369 42.3721235778, -71.118931875 42.3721430429, -71.1189198756 42.3721384206, -71.1188925614 42.3721266403, -71.1188657961 42.3721158772))
MAIN-0027|POLYGON ((-71.0819466639 42.3621520135, -71.0819496203 42.3621301814, -71.0819744731 42.3621320005, -71.0820176701 42.3621350936, -71.0820219602 42.3621354111, -71.0820191146 42.3621572711, -71.0820148246 42.3621569537, -71.0819715906 42.3621538604, -71.0819466639 42.3621520135))
MASS-1595|POLYGON ((-71.1198862798 42.3793907781, -71.1198806889 42.3794436739, -71.1198510415 42.3794431163, -71.1198576491 42.3793806068, -71.1198568869 42.3793902256, -71.1198862798 42.3793907781))
\.

-- Update the table with the parking space polygons.
UPDATE cambridge_metered_parking AS original
SET geom=new_val.geom
FROM four_troublesome_spaces AS new_val
WHERE original.space_id=new_val.space_id;
COMMIT;

-- Clean up after ourselves and drop the correct POLYGONs when we are done.
DROP TABLE four_troublesome_spaces;


/* Export the expired_output data to a shapefile.
 *
 * Create a view with only the expired meters from the parking ticket data and
 * join this with the Cambridge Metered Parking data. We will need to return the
 * geom during the join. We will export this view to the shapefile.
 */

CREATE VIEW expired_output AS SELECT foo.meter AS space, foo.num_tickets, bar.geom
FROM (SELECT meter, count(gid) AS num_tickets 
      FROM parking_tickets
      WHERE violation_desc = 'METER EXPIRED' GROUP BY meter) AS foo
JOIN (SELECT space_id, geom
      FROM cambridge_metered_parking) AS bar
ON foo.meter = bar.space_id;

-- Set the export directory (only dbadmin can do this).
SELECT STV_SetExportShapefileDirectory(USING PARAMETERS path = '/home/user/place/parking_demo');
 
-- Export to shapefile.
SELECT STV_Export2Shapefile(* USING PARAMETERS shapefile = '/expired_meters/expired_meters.shp',
		                    overwrite = TRUE, shape = 'Polygon') OVER()
FROM expired_output;
