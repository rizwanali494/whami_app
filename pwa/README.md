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
| **Map** | MapLibre + Carto `light_all` tiles (`maxzoom` 18 / layer 22 so streets stay when you zoom in) |
| **Verify** | Confirm pack landmarks; optional rear camera preview |
| **Sensors** | GPS, compass (`DeviceOrientation`), motion, GNSS altitude, fusion score |
| **Offline** | Caches Carto tiles for a region bbox in Cache Storage |
| **Activity** | Local trust event log |

Trust bands match the native app: ≥75 reliable, 55–74 caution, &lt;55 unreliable.

## Limits vs native

- No Planetiler / `map.mbtiles` vector packs (those need the Flutter tile server)
- No hardware barometer on most browsers
- Compass needs an orientation-permission tap on iOS
- First load needs the network (MapLibre CDN + tiles)

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
