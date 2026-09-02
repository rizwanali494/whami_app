# WHAMI PWA

Installable web twin of the native WHAMI app. Same map-first chrome, trust bands, and five tabs — built for the browser because Flutter web cannot host the local MBTiles / sensor stack cleanly.

## Live

https://whami-8a0ce.web.app

```bash
firebase deploy --only hosting --project whami-8a0ce
```

## Local

```bash
cd pwa
python3 -m http.server 4173
```

Open http://localhost:4173

- Desktop Chrome/Edge: install from the address bar or **Settings → Install WHAMI**
- iPhone Safari: Share → Add to Home Screen
- Android Chrome: Install app / Add to Home Screen

Geolocation only works on **localhost** or **HTTPS**.

## What it does

| Tab | Web behavior |
|-----|----------------|
| **Map** | MapLibre + OSM France street tiles (`maxzoom` 19 / layer 22) |
| **Verify** | **Lock to Real World** on pack landmarks; optional rear camera |
| **Sensors** | GPS, compass (`DeviceOrientation`), motion, GNSS altitude, fusion score |
| **Offline** | Caches OSM France tiles for a region bbox in Cache Storage |
| **Activity** | Local trust event log + **Trust Timeline Replay** |

Trust bands match the native app: ≥75 reliable, 55–74 caution, &lt;55 unreliable.

### Mind-changing features (v2.1)

1. **GPS spoof / jump alarm** — red banner when GPS jumps or disagrees with a locked landmark  
2. **Trust Timeline Replay** — scrub samples after a walk (Map → Replay, or Activity)  
3. **Lock to Real World** — freeze a landmark anchor from Verify  

## Limits vs native

- No Planetiler / `map.mbtiles` vector packs (those need the Flutter tile server)
- No hardware barometer on most browsers
- Compass needs an orientation-permission tap on iOS
- First load needs the network (MapLibre CDN + tiles)
- Spoof detection on web uses GPS jump + lock distance (no full mag/baro stack)

## Files

```
pwa/
  index.html
  manifest.json
  sw.js
  css/app.css
  js/{storage,trust,sensors,map,app}.js
  icons/
```
