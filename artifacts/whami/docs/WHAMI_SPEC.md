# WHAMI Offline Region Pack Specification (`.whami`)

## Archive Format
A `.whami` file is a standard ZIP archive with no compression applied to SQLite and MBTiles files to allow for random access if needed (or standard DEFLATE compression if fully extracting to disk).

## Structure
The root of the `.whami` ZIP archive MUST contain the following files and directories:

```
[region_name].whami
 ├── metadata.json
 ├── map.mbtiles
 ├── landmarks.sqlite
 ├── terrain.mbtiles      (Optional)
 ├── magnetic.sqlite      (Optional)
 ├── images/              (Optional)
 └── icons/               (Optional)
```

## Catalog Entry / `metadata.json` Schema
The `metadata.json` acts as the definitive manifest for the pack. When served via CDN, the catalog is simply a JSON array of these objects.

```json
{
  "id": "pakistan_punjab",
  "name": "Punjab",
  "country": "Pakistan",
  "version": "1.0.2",
  "downloadUrl": "https://cdn.whami.com/packs/pakistan_punjab.whami",
  "checksum": "a3f8c... (SHA256 of the zip)",
  "size": 184597000,
  "minAppVersion": "2.0.0",
  "schemaVersion": "1.0.0",
  "previewImage": "https://cdn.whami.com/previews/punjab.jpg",
  "bounds": [73.5, 29.5, 75.0, 31.0],
  "categories": [
    "hiking",
    "marine"
  ],
  "supportsAR": true,
  "supportsMagnetic": true,
  "supportsTerrain": true,
  "languages": [
    "en",
    "ur"
  ]
}
```
