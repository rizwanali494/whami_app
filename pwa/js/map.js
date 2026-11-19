const MapView = (() => {
  let map = null;
  let userMarker = null;
  let lockMarker = null;
  let ghostMarker = null;
  let trustedMarker = null;
  let observer = null;
  let creating = false;

  const STYLE = {
    version: 8,
    name: "WHAMI Streets",
    sources: {
      osmfr: {
        type: "raster",
        tiles: [
          "https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png",
          "https://b.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png",
          "https://c.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png",
        ],
        tileSize: 256,
        maxzoom: 19,
        attribution:
          '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://www.openstreetmap.fr/">OSM France</a>',
      },
    },
    layers: [
      {
        id: "background",
        type: "background",
        paint: { "background-color": "#E8EEF2" },
      },
      {
        id: "base-tiles",
        type: "raster",
        source: "osmfr",
        minzoom: 0,
        maxzoom: 22,
      },
    ],
  };

  function ready() {
    return typeof maplibregl !== "undefined";
  }

  function init() {
    const el = document.getElementById("map");
    if (!el) return null;
    if (!ready()) {
      el.dataset.error = "1";
      console.error("MapLibre failed to load");
      return null;
    }
    if (map || creating) {
      resize();
      return map;
    }
    if (el.clientWidth < 8 || el.clientHeight < 8) {
      requestAnimationFrame(init);
      return null;
    }
    creating = true;
    try {
      map = new maplibregl.Map({
        container: el,
        style: STYLE,
        center: [-122.4194, 37.7749],
        zoom: 12.5,
        maxZoom: 20,
        attributionControl: true,
      });
      map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
      map.on("load", () => map.resize());
      if (!observer && typeof ResizeObserver !== "undefined") {
        observer = new ResizeObserver(() => map?.resize());
        observer.observe(el);
      }
    } catch (err) {
      console.error("Map init failed", err);
      return null;
    }
    return map;
  }

  function setPitch(on) {
    if (!map) return;
    map.easeTo({ pitch: on ? 45 : 0, duration: 400 });
  }

  function recenter(lng, lat, zoom = 16) {
    if (!map || lat == null) return;
    map.easeTo({ center: [lng, lat], zoom, duration: 500 });
  }

  function ensureAccuracy(lng, lat, accuracy) {
    if (!map || map.getSource("accuracy")) return;
    map.addSource("accuracy", {
      type: "geojson",
      data: circleGeo(lng, lat, accuracy || 30),
    });
    map.addLayer({
      id: "accuracy-fill",
      type: "fill",
      source: "accuracy",
      paint: { "fill-color": "#2196F3", "fill-opacity": 0.12 },
    });
  }

  function circleGeo(lng, lat, meters) {
    const points = 64;
    const coords = [];
    const km = meters / 1000;
    const dLat = km / 110.574;
    const dLng = km / (111.32 * Math.cos((lat * Math.PI) / 180));
    for (let i = 0; i <= points; i++) {
      const t = (i / points) * 2 * Math.PI;
      coords.push([lng + dLng * Math.cos(t), lat + dLat * Math.sin(t)]);
    }
    return { type: "Feature", geometry: { type: "Polygon", coordinates: [coords] } };
  }

  function updateUser(lng, lat, accuracy) {
    if (!map || lat == null) return;
    const el = userMarker?.getElement() || document.createElement("div");
    if (!userMarker) {
      el.className = "user-dot";
      el.innerHTML = '<span class="ring"></span><span class="core"></span>';
      Object.assign(el.style, { width: "22px", height: "22px", position: "relative" });
      if (!document.getElementById("user-dot-style")) {
        const style = document.createElement("style");
        style.id = "user-dot-style";
        style.textContent = `
          .user-dot .core {
            position:absolute; inset:5px; background:#2196F3; border:2px solid #fff;
            border-radius:50%; box-shadow:0 0 0 1px rgba(33,150,243,.35);
          }
          .user-dot .ring {
            position:absolute; inset:0; border-radius:50%;
            background:rgba(33,150,243,.22);
            animation: userpulse 1.8s ease-out infinite;
          }
          @keyframes userpulse {
            from { transform:scale(.7); opacity:.9; }
            to { transform:scale(1.6); opacity:0; }
          }
          .ghost-dot .ghost-core {
            display:block; width:18px; height:18px; border-radius:50%;
            background:rgba(144,202,249,.45); border:2px solid #1565C0;
          }
          .trusted-dot .trusted-core {
            display:block; width:16px; height:16px; border-radius:50%;
            background:#43A047; border:2px solid #fff;
            box-shadow:0 0 0 2px rgba(67,160,71,.4);
          }
        `;
        document.head.appendChild(style);
      }
      userMarker = new maplibregl.Marker({ element: el, anchor: "center" })
        .setLngLat([lng, lat])
        .addTo(map);
    } else {
      userMarker.setLngLat([lng, lat]);
    }

    if (map.getSource("accuracy")) {
      map.getSource("accuracy").setData(circleGeo(lng, lat, accuracy || 30));
    } else if (map.isStyleLoaded()) {
      ensureAccuracy(lng, lat, accuracy);
    } else {
      map.once("load", () => ensureAccuracy(lng, lat, accuracy));
    }
  }

  function updateLock(lng, lat, name) {
    if (!map) return;
    if (lat == null || lng == null) {
      lockMarker?.remove();
      lockMarker = null;
      return;
    }
    if (!lockMarker) {
      const el = document.createElement("div");
      el.className = "lock-dot";
      el.title = name || "Locked to Real World";
      el.innerHTML = '<span class="lock-core"></span>';
      lockMarker = new maplibregl.Marker({ element: el, anchor: "center" })
        .setLngLat([lng, lat])
        .addTo(map);
    } else {
      lockMarker.setLngLat([lng, lat]);
    }
  }

  function updateGhostLie({ visible, gpsLng, gpsLat, trustedLng, trustedLat, lieDistanceM }) {
    if (!map) return;
    const clear = () => {
      ghostMarker?.remove();
      trustedMarker?.remove();
      ghostMarker = null;
      trustedMarker = null;
      if (map.getLayer("ghost-lie-line")) map.removeLayer("ghost-lie-line");
      if (map.getLayer("ghost-lie-label")) map.removeLayer("ghost-lie-label");
      if (map.getSource("ghost-lie")) map.removeSource("ghost-lie");
    };
    if (!visible || gpsLat == null || trustedLat == null) {
      clear();
      return;
    }
    const label =
      lieDistanceM == null
        ? "GPS claim"
        : lieDistanceM >= 1000
          ? `GPS is ${(lieDistanceM / 1000).toFixed(1)} km from reality`
          : `GPS is ${Math.round(lieDistanceM)} m from reality`;

    const geo = {
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          properties: { label },
          geometry: {
            type: "LineString",
            coordinates: [
              [gpsLng, gpsLat],
              [trustedLng, trustedLat],
            ],
          },
        },
        {
          type: "Feature",
          properties: { label },
          geometry: {
            type: "Point",
            coordinates: [(gpsLng + trustedLng) / 2, (gpsLat + trustedLat) / 2],
          },
        },
      ],
    };

    if (map.getSource("ghost-lie")) {
      map.getSource("ghost-lie").setData(geo);
    } else if (map.isStyleLoaded()) {
      map.addSource("ghost-lie", { type: "geojson", data: geo });
      map.addLayer({
        id: "ghost-lie-line",
        type: "line",
        source: "ghost-lie",
        filter: ["==", ["geometry-type"], "LineString"],
        paint: {
          "line-color": "#E53935",
          "line-width": 3,
          "line-opacity": 0.9,
          "line-dasharray": [2, 1.5],
        },
      });
      map.addLayer({
        id: "ghost-lie-label",
        type: "symbol",
        source: "ghost-lie",
        filter: ["==", ["geometry-type"], "Point"],
        layout: {
          "text-field": ["get", "label"],
          "text-size": 12,
          "text-offset": [0, -1.2],
        },
        paint: {
          "text-color": "#B71C1C",
          "text-halo-color": "#fff",
          "text-halo-width": 1.5,
        },
      });
    }

    if (!ghostMarker) {
      const el = document.createElement("div");
      el.className = "ghost-dot";
      el.innerHTML = '<span class="ghost-core"></span>';
      ghostMarker = new maplibregl.Marker({ element: el, anchor: "center" })
        .setLngLat([gpsLng, gpsLat])
        .addTo(map);
    } else {
      ghostMarker.setLngLat([gpsLng, gpsLat]);
    }
    if (!trustedMarker) {
      const el = document.createElement("div");
      el.className = "trusted-dot";
      el.innerHTML = '<span class="trusted-core"></span>';
      trustedMarker = new maplibregl.Marker({ element: el, anchor: "center" })
        .setLngLat([trustedLng, trustedLat])
        .addTo(map);
    } else {
      trustedMarker.setLngLat([trustedLng, trustedLat]);
    }
  }

  function fitPair(lng1, lat1, lng2, lat2) {
    if (!map) return;
    const bounds = new maplibregl.LngLatBounds();
    bounds.extend([lng1, lat1]);
    bounds.extend([lng2, lat2]);
    map.fitBounds(bounds, { padding: 64, maxZoom: 15, duration: 700 });
  }

  function updateCrossfire(cf) {
    if (!map) return;
    const clear = () => {
      ["crossfire-agree", "crossfire-outlier", "crossfire-soft", "crossfire-labels"].forEach((id) => {
        if (map.getLayer(id)) map.removeLayer(id);
      });
      if (map.getSource("crossfire")) map.removeSource("crossfire");
    };
    if (!cf?.visible || !cf.witnesses?.length) {
      clear();
      return;
    }
    const features = [];
    for (const w of cf.witnesses) {
      if (w.lat == null || Math.abs(w.lat - cf.trustedLat) < 1e-6) continue;
      const kind = w.isOutlier ? "outlier" : w.agrees ? "agree" : "soft";
      features.push({
        type: "Feature",
        properties: { kind, label: w.shortCode },
        geometry: {
          type: "LineString",
          coordinates: [
            [cf.trustedLng, cf.trustedLat],
            [w.lng, w.lat],
          ],
        },
      });
      features.push({
        type: "Feature",
        properties: { kind: `${kind}_pt`, label: w.shortCode },
        geometry: { type: "Point", coordinates: [w.lng, w.lat] },
      });
    }
    const geo = { type: "FeatureCollection", features };
    if (map.getSource("crossfire")) {
      map.getSource("crossfire").setData(geo);
    } else if (map.isStyleLoaded()) {
      map.addSource("crossfire", { type: "geojson", data: geo });
      map.addLayer({
        id: "crossfire-agree",
        type: "line",
        source: "crossfire",
        filter: ["==", ["get", "kind"], "agree"],
        paint: { "line-color": "#43A047", "line-width": 2.5, "line-opacity": 0.85 },
      });
      map.addLayer({
        id: "crossfire-outlier",
        type: "line",
        source: "crossfire",
        filter: ["==", ["get", "kind"], "outlier"],
        paint: {
          "line-color": "#E53935",
          "line-width": 3,
          "line-opacity": 0.95,
          "line-dasharray": [1.5, 1.2],
        },
      });
      map.addLayer({
        id: "crossfire-soft",
        type: "line",
        source: "crossfire",
        filter: ["==", ["get", "kind"], "soft"],
        paint: { "line-color": "#B28704", "line-width": 2, "line-opacity": 0.75 },
      });
      map.addLayer({
        id: "crossfire-labels",
        type: "symbol",
        source: "crossfire",
        filter: ["in", ["get", "kind"], ["literal", ["agree_pt", "outlier_pt", "soft_pt"]]],
        layout: {
          "text-field": ["get", "label"],
          "text-size": 12,
          "text-offset": [0, -1.1],
        },
        paint: {
          "text-color": "#fff",
          "text-halo-color": "#0A1628",
          "text-halo-width": 1.5,
        },
      });
    }
  }

  function resize() {
    map?.resize();
  }

  return {
    init,
    setPitch,
    recenter,
    updateUser,
    updateLock,
    updateGhostLie,
    updateCrossfire,
    fitPair,
    resize,
    ready,
  };
})();
