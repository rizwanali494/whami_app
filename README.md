# WHAMI

**Where Am I?** — verified navigation and position trust for Android, iOS, and a browser PWA.

WHAMI fuses multiple on-device witnesses (GPS, landmarks, magnetometer, IMU, sky) so the first answer is plain language: **Reliable / Caution / Unreliable** — not a raw specialist score.

## Product surface

| Tab | Purpose |
|-----|---------|
| **Map** | Full-screen map, trust banner, Start/Stop tracking, collapsible source details |
| **Verify** | Landmark / AR confirmation when confidence is low |
| **Sensors** | GPS, geomagnetic, IMU, barometer, landmark scanner, celestial, fusion |
| **Offline** | Download and activate region packs (SHA-256 verified) |
| **Activity** | Actionable alerts + trust history |

Diagnostics, sensors, units, outdoor mode, storage, and privacy live under the Map overflow menu (**Diagnostics & Settings**).

## Run

```bash
flutter pub get
flutter run
```

Release Android:

```bash
flutter build apk --release
flutter build appbundle --release
```

Upload signing uses `android/key.properties` + `android/app/upload-keystore.jks` (gitignored).

## PWA

A standalone installable web app lives in `pwa/` (MapLibre GL JS, same Map / Verify / Sensors / Offline / Activity chrome). First visit needs the network; after that the shell and cached tiles work offline.

```bash
cd pwa
python3 -m http.server 4173
```

Open http://localhost:4173 — on a phone use **Add to Home Screen**. HTTPS (or localhost) is required for GPS.

Live: https://whami-8a0ce.web.app (`firebase deploy --only hosting`).

See `pwa/README.md` for what the browser can and cannot do versus the native app.

## Architecture (high level)

- `lib/features/` — UI by destination
- `lib/data/services/` — sensors, fusion, downloads, local tile/glyph servers
- `lib/data/repositories/` — app-facing state (`WhamiRepository`)
- `lib/navigation/whami_router.dart` — GoRouter shell (4 tabs)

Local MBTiles and glyph HTTP servers start concurrently in `bootstrapWhamiServices()` (UI appears first; sensors initialize in the background).

## Default map (no pack)

With no offline region pack active, the MapLibre style embeds a **light OSM-derived raster basemap** (CARTO `light_all`) on first paint so streets appear immediately. Settings live in `lib/core/config/map_basemap_config.dart` (tile URLs, OpenStreetMap attribution, source maxzoom 18 / layer maxzoom 22).

Tiles are proxied through `RasterTileCacheService` (keep-alive HTTP, coalesced fetches, 7-day TTL). When a pack is activated, local vector MBTiles replace the raster layer.

## Trust bands

| Score | Label |
|------:|-------|
| ≥ 75 | Position reliable |
| 55–74 | Use with caution |
| < 55 | Position unreliable |

Expand the map bottom sheet for per-source opinions and the weighted formula.

## Tests

```bash
flutter test
```

## Brand

Use the supplied WHAMI logo asset under `assets/images/` unchanged (do not redraw, recolor, crop, or replace it for product chrome).
