# Map data provenance

## `skorea_municipalities_geo_simple.json`

- Source: 국가데이터처, **SGIS 행정구역 통계 및 경계**
- Source page: https://www.data.go.kr/data/15129688/fileData.do
- Boundary reference date: 2025-06-30 (2025 Q2)
- Source layer: `bnd_sigungu_00_2025_2Q`
- Source CRS: Korea 2000 / Unified CS (EPSG:5179)
- Runtime CRS: WGS 84 (EPSG:4326)
- License shown by the public-data portal: 이용허락범위 제한 없음
- Generated: 2026-07-14

The source shapefile was reprojected to WGS 84 and topologically simplified
with Mapshaper's weighted-area algorithm at 1%, using `keep-shapes` and five
decimal places. The processed asset contains all 252 source features. Compared
with the source geometry in EPSG:5179, its combined-area difference is about
0.08%; the retained bounds include Marado and Dokdo.

Only `code`, `name`, and `base_date` are kept as feature properties. App-side
rendering maps all 252 boundary features to 161 travel regions: metropolitan
cities are kept as one region, and non-autonomous districts are dissolved into
their parent city. Every city/county area is interactive; the original 40
travel-region rows retain their IDs and 121 regions are added by migration.
