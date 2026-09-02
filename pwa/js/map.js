const MapView = (() => {
  let map = null;
  let userMarker = null;
  let lockMarker = null;
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

  function resize() {
    map?.resize();
  }

  return { init, setPitch, recenter, updateUser, updateLock, resize, ready };
})();
