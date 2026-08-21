const App = (() => {
  const state = {
    route: "map",
    tracking: false,
    gps: null,
    magnetic: null,
    imu: null,
    sky: null,
    landmark: null,
    locError: null,
    detailsOpen: true,
    sheet: 0.42,
    pitch: false,
    online: navigator.onLine,
    installEvent: null,
    verifyTab: "landmark",
    packFilter: "All",
    packQuery: "",
    ...Storage.read(),
  };

  if (new URLSearchParams(location.search).has("skipOnboard")) {
    state.onboardingSeen = true;
  }

  const $ = (id) => document.getElementById(id);

  function persist() {
    Storage.write({
      onboardingSeen: state.onboardingSeen,
      outdoor: state.outdoor,
      metric: state.metric,
      activePackId: state.activePackId,
      packs: state.packs,
      lastFix: state.gps
        ? { lat: state.gps.lat, lng: state.gps.lng, at: Date.now() }
        : state.lastFix,
    });
  }

  function showScreen(id) {
    document.querySelectorAll(".screen").forEach((el) => el.classList.remove("active"));
    $(id)?.classList.add("active");
  }

  function setChrome(visible) {
    $("chrome").hidden = !visible;
  }

  function go(route) {
    state.route = route;
    if (!state.onboardingSeen && route !== "onboarding" && route !== "splash") {
      setChrome(false);
      showScreen("onboarding-screen");
      return;
    }
    const map = {
      map: "map-screen",
      verify: "verify-screen",
      sensors: "sensors-screen",
      packs: "packs-screen",
      activity: "activity-screen",
      settings: "settings-screen",
    };
    showScreen(map[route] || "map-screen");
    setChrome(true);
    $("app-nav").querySelectorAll("button").forEach((b) => {
      b.classList.toggle("on", b.dataset.route === route);
    });
    if (route === "map") {
      requestAnimationFrame(() => {
        MapView.init();
        MapView.resize();
      });
    }
    render();
  }

  function fused() {
    return Trust.fuse({
      tracking: state.tracking,
      gps: state.gps,
      magnetic: state.magnetic,
      imu: state.imu,
      sky: state.sky,
      landmark: state.landmark,
      activePackId: state.activePackId,
      packs: state.packs,
    });
  }

  function activePack() {
    return Trust.packFor(state.activePackId);
  }

  function packLoaded() {
    const p = activePack();
    return Boolean(p && state.packs[p.id]?.status === "downloaded");
  }

  function statusText() {
    const net = state.online ? "Online" : "Offline";
    const pack = packLoaded() ? `${activePack().name} Loaded` : "No Pack Loaded";
    return `${net} · ${pack} · All Sources Active`;
  }

  function renderStatus() {
    const el = $("status-bar");
    if (!el) return;
    el.textContent = statusText();
    el.classList.toggle("warn", !state.online);
    el.classList.toggle("off", !state.online);
  }

  function renderTrust() {
    const t = fused();
    $("trust-headline").textContent = t.headline;
    $("trust-subtitle").textContent = t.subtitle;
    $("trust-explain").textContent = t.explanation;
    $("trust-score").textContent = t.score;
    $("trust-score-wrap").style.color = t.color;
    $("trust-icon").style.background = t.color;
    $("trust-icon").innerHTML =
      t.level === "reliable"
        ? icon("check")
        : t.level === "caution"
          ? icon("warn")
          : t.level === "unreliable"
            ? icon("bad")
            : icon("wait");

    const cta = $("verify-cta");
    if (t.level === "caution" || t.level === "unreliable") {
      cta.classList.remove("hidden");
      cta.textContent = t.level === "caution" ? "Open Verify" : "Verify or get offline pack";
      cta.style.border = `1px solid ${t.color}`;
      cta.style.color = t.color;
    } else {
      cta.classList.add("hidden");
    }

    const list = $("source-list");
    const active = t.opinions.filter((o) => o.status !== "unavailable");
    if (!state.detailsOpen) {
      list.innerHTML = "";
    } else if (!active.length) {
      list.innerHTML =
        '<p class="muted">Start tracking to collect GPS, landmark, and motion witnesses.</p>';
    } else {
      list.innerHTML = active
        .map(
          (o) => `
        <div class="source-row">
          <div class="source-ico">${sourceIcon(o.sourceType)}</div>
          <div>
            <h4>${sourceTitle(o.sourceType)}</h4>
            <p>${o.description}</p>
          </div>
          <div class="source-pct" style="color:${Trust.colorFor(
            o.confidence >= 75 ? "reliable" : o.confidence >= 55 ? "caution" : "unreliable",
          )}">${o.confidence}%</div>
        </div>`,
        )
        .join("");
    }

    $("track-pill").innerHTML = state.tracking
      ? '<span class="live-dot"></span> TRACKING LIVE'
      : `${icon("play")} START TRACKING`;

    const notice = $("map-notice");
    if (state.locError) {
      notice.classList.remove("hidden");
      notice.innerHTML = `<h3>Location permission needed</h3><p>${state.locError}</p><button id="ask-loc">Allow location</button>`;
      $("ask-loc").onclick = startTracking;
    } else if (!packLoaded() && !state.tracking) {
      notice.classList.remove("hidden");
      notice.innerHTML = `<h3>No active region pack</h3><p>Download an offline pack so landmarks and magnetic witnesses can vote.</p><button id="open-packs">Open Offline</button>`;
      $("open-packs").onclick = () => go("packs");
    } else {
      notice.classList.add("hidden");
    }
  }

  function renderSensors() {
    const t = fused();
    const items = [
      {
        id: "gps",
        title: "GPS / GNSS",
        body: state.gps
          ? `${state.gps.lat.toFixed(5)}, ${state.gps.lng.toFixed(5)} · ±${Math.round(state.gps.accuracy || 0)} m`
          : "Waiting for a fix",
        value: t.opinions.find((o) => o.sourceType === "gps")?.confidence || 0,
        color: "var(--gps)",
      },
      {
        id: "mag",
        title: "Magnetometer",
        body:
          state.magnetic?.heading != null
            ? `Heading ${Math.round(state.magnetic.heading)}°`
            : "No compass reading yet",
        value: t.opinions.find((o) => o.sourceType === "magnetic")?.confidence || 0,
        color: "var(--magnetic)",
      },
      {
        id: "imu",
        title: "IMU",
        body: state.imu ? (state.imu.moving ? "Motion detected" : "Device steady") : "Idle",
        value: t.opinions.find((o) => o.sourceType === "imu")?.confidence || 0,
        color: "var(--imu)",
      },
      {
        id: "baro",
        title: "Barometer",
        body:
          state.gps?.altitude != null
            ? `Altitude ${Math.round(state.gps.altitude)} m (from GNSS)`
            : "Not exposed by this browser",
        value: state.gps?.altitude != null ? 60 : 0,
        color: "#00897b",
      },
      {
        id: "cam",
        title: "Landmark camera",
        body: state.landmark ? `Verified ${state.landmark.name}` : "Open Verify to scan",
        value: state.landmark?.confidence || 0,
        color: "var(--landmark)",
      },
      {
        id: "sky",
        title: "Celestial / sky",
        body: state.sky?.description || "Needs a live fix",
        value: t.opinions.find((o) => o.sourceType === "sextant")?.confidence || 0,
        color: "var(--sky)",
      },
      {
        id: "fusion",
        title: "Trust fusion",
        body: `${t.headline} · ${t.agreeing}/${t.total} witnesses`,
        value: t.score,
        color: t.color,
      },
    ];
    const active = items.filter((i) => i.value > 0).length;
    $("sensor-count").textContent = `${active}/${items.length} Active`;
    $("sensor-list").innerHTML = `
      <div class="section-label">Physical Sensors</div>
      ${items.slice(0, 4).map(sensorCard).join("")}
      <div class="section-label">Vision & Sky</div>
      ${items.slice(4, 6).map(sensorCard).join("")}
      <div class="section-label">Fusion Engine</div>
      ${items.slice(6).map(sensorCard).join("")}
    `;
  }

  function sensorCard(s) {
    return `<article class="card">
      <div class="row-between">
        <h3>${s.title}</h3>
        <strong style="color:${s.color}">${s.value}%</strong>
      </div>
      <p>${s.body}</p>
      <div class="bar"><i style="width:${s.value}%;background:${s.color}"></i></div>
    </article>`;
  }

  function renderPacks() {
    const q = state.packQuery.toLowerCase();
    const rows = Trust.CATALOG.filter((p) => {
      const typeOk = state.packFilter === "All" || p.type === state.packFilter;
      const textOk =
        !q ||
        p.name.toLowerCase().includes(q) ||
        p.country.toLowerCase().includes(q);
      return typeOk && textOk;
    });
    $("pack-list").innerHTML = rows
      .map((p) => {
        const st = state.packs[p.id]?.status;
        const active = state.activePackId === p.id && st === "downloaded";
        return `<article class="card pack-card">
          <div class="row-between">
            <div>
              <h3>${p.name}</h3>
              <p>${p.country} · ${p.type}</p>
              <div class="size">${p.size} web cache</div>
            </div>
            ${
              active
                ? '<span class="badge active">Active</span>'
                : st === "downloaded"
                  ? '<span class="badge ready">Ready</span>'
                  : ""
            }
          </div>
          <div class="pack-actions">
            ${
              st === "downloaded"
                ? `<button class="btn btn-primary" data-activate="${p.id}">${active ? "Active" : "Activate"}</button>
                   <button class="btn btn-ghost" data-remove="${p.id}">Remove</button>`
                : `<button class="btn btn-primary" data-dl="${p.id}">Cache region</button>`
            }
          </div>
        </article>`;
      })
      .join("");
  }

  function renderActivity() {
    const events = Storage.read().events;
    const crit = events.filter((e) => e.severity === "critical").length;
    const warn = events.filter((e) => e.severity === "warning").length;
    $("act-crit").textContent = crit;
    $("act-warn").textContent = warn;
    $("act-info").textContent = events.length - crit - warn;
    $("activity-list").innerHTML = events.length
      ? events
          .map(
            (e) => `<article class="card event ${e.severity || "info"}">
              <h3>${e.title}</h3>
              <p>${e.body}</p>
              <time>${new Date(e.at).toLocaleString()}</time>
            </article>`,
          )
          .join("")
      : '<article class="card"><h3>No activity yet</h3><p>Start tracking to record trust events.</p></article>';
  }

  function renderVerify() {
    const pack = activePack();
    const gps = state.gps;
    let landmarks = pack?.landmarks || Trust.CATALOG[0].landmarks;
    if (gps) {
      landmarks = [...landmarks].sort(
        (a, b) =>
          Trust.haversine(gps.lat, gps.lng, a.lat, a.lng) -
          Trust.haversine(gps.lat, gps.lng, b.lat, b.lng),
      );
    }
    const hint = packLoaded()
      ? ""
      : `<article class="card"><h3>Using San Francisco landmarks</h3><p>Cache a region under Offline for local witnesses. You can still confirm a landmark now.</p>
         <button class="btn btn-primary" id="verify-open-packs" type="button" style="margin-top:10px">Open Offline</button></article>`;
    $("landmark-list").innerHTML =
      hint +
      landmarks
        .map((lm) => {
          const dist = gps
            ? Math.round(Trust.haversine(gps.lat, gps.lng, lm.lat, lm.lng))
            : null;
          const on = state.landmark?.name === lm.name;
          return `<article class="card">
              <div class="row-between">
                <div>
                  <h3>${lm.name}</h3>
                  <p>${dist != null ? `${dist} m away` : "Distance needs a GPS fix"}</p>
                </div>
                <button class="btn ${on ? "btn-primary" : "btn-outline"}" data-confirm="${lm.name}">
                  ${on ? "Verified" : "I see this"}
                </button>
              </div>
            </article>`;
        })
        .join("");
    $("verify-open-packs")?.addEventListener("click", () => go("packs"));
  }

  function renderSettings() {
    $("toggle-outdoor").classList.toggle("on", state.outdoor);
    $("toggle-metric").classList.toggle("on", state.metric);
    $("settings-version").textContent = "WHAMI PWA v2.0.0";
    $("settings-pack").textContent = packLoaded()
      ? `${activePack().name} cached in this browser`
      : "No region pack cached";
    $("install-banner").classList.toggle("show", Boolean(state.installEvent));
    document.documentElement.style.filter = state.outdoor ? "contrast(1.08)" : "";
  }

  function render() {
    renderStatus();
    renderTrust();
    if (state.route === "sensors") renderSensors();
    if (state.route === "packs") renderPacks();
    if (state.route === "activity") renderActivity();
    if (state.route === "verify") renderVerify();
    if (state.route === "settings") renderSettings();
  }

  async function startTracking() {
    try {
      await Sensors.requestLocation();
      await Sensors.unlockIOS();
      state.locError = null;
      state.tracking = true;
      Sensors.start({
        onGps: (g) => {
          if (g.error) {
            state.locError = g.error;
            render();
            return;
          }
          state.gps = g;
          state.sky = Sensors.skyFromGps(g);
          MapView.updateUser(g.lng, g.lat, g.accuracy);
          persist();
          render();
        },
        onMagnetic: (m) => {
          state.magnetic = m;
          renderTrust();
        },
        onImu: (i) => {
          state.imu = i;
        },
      });
      Storage.addEvent({
        severity: "info",
        title: "Tracking started",
        body: "GPS, compass, and motion witnesses are live in this browser.",
      });
    } catch (e) {
      state.locError = e.message;
    }
    render();
  }

  function stopTracking() {
    state.tracking = false;
    Sensors.stop();
    Storage.addEvent({
      severity: "info",
      title: "Tracking stopped",
      body: "Live witnesses paused.",
    });
    render();
  }

  async function cachePack(id) {
    const pack = Trust.packFor(id);
    if (!pack) return;
    Storage.setPack(id, "downloading");
    state.packs = Storage.read().packs;
    renderPacks();
    try {
      if ("caches" in window) {
        const cache = await caches.open("whami-tiles-v1");
        const [south, west, north, east] = pack.bounds;
        const z = id === "usa_san_francisco" ? 12 : 8;
        const urls = tileUrls(west, south, east, north, z).slice(0, 80);
        await Promise.allSettled(urls.map((u) => cache.add(u)));
      }
      state.packs = Storage.setPack(id, "downloaded").packs;
      state.activePackId = id;
      persist();
      Storage.addEvent({
        severity: "info",
        title: `${pack.name} ready`,
        body: "Region cache stored in this browser for offline map tiles.",
      });
    } catch {
      Storage.addEvent({
        severity: "warning",
        title: "Pack cache incomplete",
        body: `${pack.name} was marked ready, but some tiles may still need the network.`,
      });
      state.packs = Storage.setPack(id, "downloaded").packs;
      state.activePackId = id;
      persist();
    }
    render();
  }

  function tileUrls(west, south, east, north, z) {
    const urls = [];
    const n = 2 ** z;
    const x0 = lon2tile(west, z);
    const x1 = lon2tile(east, z);
    const y0 = lat2tile(north, z);
    const y1 = lat2tile(south, z);
    for (let x = x0; x <= x1; x++) {
      for (let y = y0; y <= y1; y++) {
        urls.push(`https://a.basemaps.cartocdn.com/light_all/${z}/${x}/${y}.png`);
      }
    }
    return urls;
  }

  function lon2tile(lon, z) {
    return Math.floor(((lon + 180) / 360) * 2 ** z);
  }
  function lat2tile(lat, z) {
    return Math.floor(
      ((1 - Math.log(Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180)) / Math.PI) / 2) *
        2 ** z,
    );
  }

  function sourceTitle(t) {
    return { gps: "GPS", landmark: "Landmark", imu: "Motion", magnetic: "Magnetic", sextant: "Sky" }[t] || t;
  }

  function sourceIcon(t) {
    return { gps: icon("sat"), landmark: icon("pin"), imu: icon("walk"), magnetic: icon("compass"), sextant: icon("sun") }[t] || icon("shield");
  }

  function icon(name) {
    const paths = {
      check: '<svg width="26" height="26" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M6 14l5 5 10-11"/></svg>',
      warn: '<svg width="26" height="26" fill="none" stroke="currentColor" stroke-width="2"><path d="M13 6l9 16H4L13 6z"/><path d="M13 12v4M13 18h.01"/></svg>',
      bad: '<svg width="26" height="26" fill="none" stroke="currentColor" stroke-width="2"><circle cx="13" cy="13" r="9"/><path d="M9 9l8 8M17 9l-8 8"/></svg>',
      wait: '<svg width="26" height="26" fill="none" stroke="currentColor" stroke-width="2"><circle cx="13" cy="13" r="9"/><path d="M13 7v6l4 2"/></svg>',
      play: '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>',
      sat: '<svg width="18" height="18" fill="none" stroke="#0A1628" stroke-width="1.8"><path d="M4 14l6-6 3 3-6 6zM13 5l6 6"/><path d="M4 20h6"/></svg>',
      pin: '<svg width="18" height="18" fill="none" stroke="#0A1628" stroke-width="1.8"><path d="M9 16s5-4.2 5-8a5 5 0 10-10 0c0 3.8 5 8 5 8z"/><circle cx="9" cy="8" r="1.4"/></svg>',
      walk: '<svg width="18" height="18" fill="none" stroke="#0A1628" stroke-width="1.8"><circle cx="10" cy="4" r="1.4"/><path d="M8 17l2-5 3 2 2 4M7 9l3 1 3-2"/></svg>',
      compass: '<svg width="18" height="18" fill="none" stroke="#0A1628" stroke-width="1.8"><circle cx="9" cy="9" r="7"/><path d="M11.5 6.5L8 8l-1.5 3.5L10 10z"/></svg>',
      sun: '<svg width="18" height="18" fill="none" stroke="#0A1628" stroke-width="1.8"><circle cx="9" cy="9" r="3"/><path d="M9 2v2M9 14v2M2 9h2M14 9h2M4 4l1.4 1.4M12.6 12.6L14 14M14 4l-1.4 1.4M5.4 12.6L4 14"/></svg>',
      shield: '<svg width="18" height="18" fill="none" stroke="#0A1628" stroke-width="1.8"><path d="M9 2l6 3v5c0 4-2.5 6.5-6 8-3.5-1.5-6-4-6-8V5z"/></svg>',
    };
    return paths[name] || "";
  }

  async function startCamera() {
    const video = $("verify-video");
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment" },
        audio: false,
      });
      video.srcObject = stream;
      await video.play();
    } catch {
      $("cam-status").textContent = "Camera blocked — confirm a landmark from the list instead.";
    }
  }

  function stopCamera() {
    const video = $("verify-video");
    video.srcObject?.getTracks().forEach((t) => t.stop());
    video.srcObject = null;
  }

  function bind() {
    $("app-nav").querySelectorAll("button").forEach((b) => {
      b.onclick = () => {
        if (state.route === "verify") stopCamera();
        go(b.dataset.route);
      };
    });
    $("menu-btn").onclick = () => go("settings");
    $("back-settings").onclick = () => go("map");
    $("track-pill").onclick = () => (state.tracking ? stopTracking() : startTracking());
    $("recenter-btn").onclick = () => {
      if (state.gps) MapView.recenter(state.gps.lng, state.gps.lat);
    };
    $("pitch-btn").onclick = () => {
      state.pitch = !state.pitch;
      MapView.setPitch(state.pitch);
    };
    $("sources-toggle").onclick = () => {
      state.detailsOpen = !state.detailsOpen;
      renderTrust();
    };
    $("verify-cta").onclick = () => go("verify");

    $("sheet").addEventListener("pointerdown", (e) => {
      if (window.matchMedia("(min-width: 900px)").matches) return;
      if (e.target.closest("button")) return;
      const startY = e.clientY;
      const start = state.sheet;
      const move = (ev) => {
        const dy = startY - ev.clientY;
        state.sheet = Math.min(0.78, Math.max(0.26, start + dy / window.innerHeight));
        document.documentElement.style.setProperty("--sheet", `${state.sheet * 100}vh`);
      };
      const up = () => {
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", up);
      };
      window.addEventListener("pointermove", move);
      window.addEventListener("pointerup", up);
    });

    $("skip-onboard").onclick = finishOnboard;
    $("next-onboard").onclick = () => {
      if (window.matchMedia("(min-width: 900px)").matches) {
        finishOnboard();
        return;
      }
      const slides = [...document.querySelectorAll(".onboarding-slide")];
      const i = slides.findIndex((s) => !s.classList.contains("hidden"));
      if (i >= slides.length - 1) {
        finishOnboard();
        return;
      }
      slides[i].classList.add("hidden");
      slides[i + 1].classList.remove("hidden");
      document.querySelectorAll(".dot").forEach((d, n) => d.classList.toggle("on", n === i + 1));
      $("next-onboard").textContent = i + 1 === slides.length - 1 ? "Continue" : "Next";
    };

    $("pack-search").oninput = (e) => {
      state.packQuery = e.target.value;
      renderPacks();
    };
    $("pack-filters").onclick = (e) => {
      const btn = e.target.closest("[data-filter]");
      if (!btn) return;
      state.packFilter = btn.dataset.filter;
      [...$("pack-filters").children].forEach((c) => c.classList.toggle("on", c === btn));
      renderPacks();
    };
    $("pack-list").onclick = (e) => {
      const dl = e.target.closest("[data-dl]");
      const act = e.target.closest("[data-activate]");
      const rm = e.target.closest("[data-remove]");
      if (dl) cachePack(dl.dataset.dl);
      if (act) {
        state.activePackId = act.dataset.activate;
        persist();
        render();
      }
      if (rm) {
        const next = { ...state.packs };
        delete next[rm.dataset.remove];
        state.packs = next;
        if (state.activePackId === rm.dataset.remove) state.activePackId = "";
        persist();
        render();
      }
    };

    $("verify-tabs").onclick = (e) => {
      const btn = e.target.closest("[data-vtab]");
      if (!btn) return;
      state.verifyTab = btn.dataset.vtab;
      [...$("verify-tabs").children].forEach((c) => c.classList.toggle("on", c === btn));
      $("verify-landmark").classList.toggle("hidden", state.verifyTab !== "landmark");
      $("verify-ar").classList.toggle("hidden", state.verifyTab !== "ar");
      if (state.verifyTab === "ar") startCamera();
      else stopCamera();
    };
    $("landmark-list").onclick = (e) => {
      const btn = e.target.closest("[data-confirm]");
      if (!btn) return;
      state.landmark = { name: btn.dataset.confirm, confidence: 91, radius: 25 };
      Storage.addEvent({
        severity: "info",
        title: "Landmark verified",
        body: `${btn.dataset.confirm} added as a position witness.`,
      });
      render();
    };

    $("toggle-outdoor").onclick = () => {
      state.outdoor = !state.outdoor;
      persist();
      renderSettings();
    };
    $("toggle-metric").onclick = () => {
      state.metric = !state.metric;
      persist();
      renderSettings();
    };
    $("install-btn").onclick = async () => {
      if (!state.installEvent) return;
      state.installEvent.prompt();
      await state.installEvent.userChoice;
      state.installEvent = null;
      renderSettings();
    };

    window.addEventListener("online", () => {
      state.online = true;
      renderStatus();
    });
    window.addEventListener("offline", () => {
      state.online = false;
      renderStatus();
    });
    window.addEventListener("beforeinstallprompt", (e) => {
      e.preventDefault();
      state.installEvent = e;
      if (state.route === "settings") renderSettings();
    });
    window.addEventListener("resize", () => {
      if (state.route === "map") MapView.resize();
    });
  }

  function finishOnboard() {
    state.onboardingSeen = true;
    persist();
    go("map");
  }

  function boot() {
    bind();
    setChrome(false);
    showScreen("splash-screen");
    setTimeout(() => {
      if (!state.onboardingSeen) {
        showScreen("onboarding-screen");
        $("next-onboard").textContent = window.matchMedia("(min-width: 900px)").matches
          ? "Continue"
          : "Next";
      } else {
        go("map");
        MapView.init();
        if (state.lastFix) MapView.updateUser(state.lastFix.lng, state.lastFix.lat, 40);
      }
    }, 900);

    const mapObs = new MutationObserver(() => {
      if ($("map-screen").classList.contains("active")) MapView.init();
    });
    mapObs.observe($("map-screen"), { attributes: true, attributeFilter: ["class"] });

    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("./sw.js");
    }
  }

  return { boot };
})();

document.addEventListener("DOMContentLoaded", App.boot);
