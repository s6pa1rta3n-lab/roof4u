---
name: gis-roof-intelligence
description: Queries and computes roof spatial polygons, surface areas, building heights, and architectural pitch classifications from municipal GIS databases.
---

# GIS Roof Intelligence Skill

## Purpose
This skill answers: **"Where can I find the GIS for roofs in a neighborhood?"**
It accesses municipal GIS spatial datasets, 3D building footprint layers, and LiDAR elevation maps to acquire polygon boundaries, calculate exact roof square footage, and classify roof architectural types (Victorian Pitched, Flat Membrane, Mansard Slate/Copper).

## Public Record Sources
1. **San Francisco Green Roofs & Building Footprints GIS**:
   - SODA Endpoint: `https://data.sfgov.org/resource/sfnk-6tdn.json`
   - Spatial Fields: `the_geom` (GeoJSON Point, Polygon, MultiPolygon), `size_sf` (roof square footage), `design` (architectural style), `cost`, `retrofit_s`.
2. **San Francisco Planning Department Property Information Map (PIM)**:
   - Portal: `https://sfplanninggis.org/pim/`
   - Data Layers: Building Heights, Parcel Polygons, Zoning Overlays, Historic Resource Status.
3. **USGS 3D Elevation Program (3DEP) / NOAA LiDAR**:
   - Point cloud data providing ground elevation and building apex elevation.

## OCaml Programmatic Interface

```ocaml
open Roof_engine
open Types

val Gis_roofs.build_gis_roofs_query_url :
  ?base_url:string ->
  ?limit:int ->
  ?address:string ->
  ?neighborhood:string ->
  unit -> (string, string) result

val Gis_roofs.fetch_gis_roofs :
  ?base_url:string ->
  ?limit:int ->
  ?timeout:float ->
  ?address:string ->
  ?neighborhood:string ->
  unit -> (gis_roof_record list, string) result
```

## CLI Execution

```bash
roof_pipeline --gis-roofs "Pacific Heights" --limit 10
```

## Output Schema (`gis_roof_record`)

| Field | Type | Description |
|---|---|---|
| `parcel_number` | `string` | Assessor Parcel Number (APN) |
| `property_location` | `string` | Matched property address |
| `roof_size_sqft` | `float` | Exact roof surface area in square feet |
| `roof_type_classified` | `roof_type` | `Victorian`, `Flat`, `Mansard`, `Gable`, `Hip`, `Metal` |
| `ground_elevation_ft` | `float option` | Elevation above sea level in feet |
| `roof_height_ft` | `float option` | Building vertical height in feet |
| `coordinates_latitude` | `float option` | Geographic centroid latitude |
| `coordinates_longitude` | `float option` | Geographic centroid longitude |
| `polygon_points_count` | `int` | Number of vertices in roof geometry |
| `is_green_roof_or_solar` | `bool` | True if eco-roof or solar installation is recorded |
