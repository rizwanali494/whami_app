const Trust = (() => {
  const CATALOG = [
    {
      id: "usa_san_francisco",
      name: "San Francisco",
      country: "United States",
      type: "Urban",
      size: "31 MB",
      bounds: [37.596, -122.734, 37.954, -122.107],
      landmarks: [
        { name: "Ferry Building", lat: 37.7955, lng: -122.3937 },
        { name: "Coit Tower", lat: 37.8024, lng: -122.4058 },
        { name: "Painted Ladies", lat: 37.7763, lng: -122.4328 },
        { name: "Golden Gate Bridge", lat: 37.8199, lng: -122.4783 },
        { name: "Oracle Park", lat: 37.7786, lng: -122.3893 },
      ],
    },
    {
      id: "usa_california",
      name: "California",
      country: "United States",
      type: "Urban",
      size: "866 MB",
      bounds: [32.48171, -125.8935, 42.01618, -114.1291],
      landmarks: [
        { name: "Golden Gate Bridge", lat: 37.8199, lng: -122.4783 },
        { name: "Hollywood Sign", lat: 34.1341, lng: -118.3215 },
      ],
    },
    {
      id: "usa_nevada",
      name: "Nevada",
      country: "United States",
      type: "Urban",
      size: "118 MB",
      bounds: [35.00053, -120.0074, 42.00391, -114.0379],
      landmarks: [{ name: "Las Vegas Strip", lat: 36.1147, lng: -115.1728 }],
    },
    {
      id: "usa_texas",
      name: "Texas",
      country: "United States",
      type: "Urban",
      size: "610 MB",
      bounds: [25.66764, -106.9125, 36.52618, -93.01897],
      landmarks: [{ name: "Texas Capitol", lat: 30.2747, lng: -97.7404 }],
    },
  ];

  function haversine(aLat, aLng, bLat, bLng) {
    const R = 6371000;
    const dLat = ((bLat - aLat) * Math.PI) / 180;
    const dLng = ((bLng - aLng) * Math.PI) / 180;
    const s =
      Math.sin(dLat / 2) ** 2 +
      Math.cos((aLat * Math.PI) / 180) *
        Math.cos((bLat * Math.PI) / 180) *
        Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(s));
  }

  function levelFor(score, tracking) {
    if (!tracking) return "unknown";
    if (score >= 75) return "reliable";
    if (score >= 55) return "caution";
    return "unreliable";
  }

  function labelFor(level) {
    return {
      reliable: "Position reliable",
      caution: "Verify position",
      unreliable: "Position unreliable",
      unknown: "Checking position",
    }[level];
  }

  function colorFor(level) {
    return {
      reliable: "#43A047",
      caution: "#B28704",
      unreliable: "#E53935",
      unknown: "#546E7A",
    }[level];
  }

  function explanation(level, score) {
    return {
      reliable: `Score ${score} means most witnesses agree. You can navigate with this fix.`,
      caution: `Score ${score} means sources partially disagree. Prefer open sky or verify a landmark.`,
      unreliable: `Score ${score} means sources conflict or are missing. Do not rely on this position alone.`,
      unknown: "WHAMI is still gathering sensor and offline witnesses.",
    }[level];
  }

  function packFor(id) {
    return CATALOG.find((p) => p.id === id) || null;
  }

  function inBounds(lat, lng, bounds) {
    return lat >= bounds[0] && lat <= bounds[2] && lng >= bounds[1] && lng <= bounds[3];
  }

  function fuse(state) {
    const opinions = [];
    const gps = state.gps;
    const mag = state.magnetic;
    const imu = state.imu;
    const sky = state.sky;
    const landmark = state.landmark;
    const pack = packFor(state.activePackId);
    const hasPack = Boolean(pack && state.packs[pack.id]?.status === "downloaded");

    if (gps) {
      const acc = gps.accuracy || 50;
      const conf = Math.max(20, Math.min(98, Math.round(100 - acc / 2.2)));
      opinions.push({
        sourceType: "gps",
        name: "GPS",
        status: acc > 80 ? "unstable" : "active",
        confidence: conf,
        uncertaintyRadius: acc,
        description: acc > 80 ? "Weak GNSS fix" : "Live GPS fix",
      });
    }

    if (landmark) {
      opinions.push({
        sourceType: "landmark",
        name: "Landmark",
        status: "active",
        confidence: landmark.confidence,
        uncertaintyRadius: landmark.radius,
        description: landmark.name,
      });
    }

    if (mag && mag.heading != null) {
      const strength = mag.absolute ? 88 : 62;
      opinions.push({
        sourceType: "magnetic",
        name: "Magnetic",
        status: mag.absolute ? "active" : "unstable",
        confidence: strength,
        uncertaintyRadius: mag.absolute ? 40 : 90,
        description: mag.absolute ? "Compass heading locked" : "Relative heading only",
      });
    }

    if (imu && imu.moving != null) {
      opinions.push({
        sourceType: "imu",
        name: "Motion",
        status: "active",
        confidence: imu.moving ? 70 : 78,
        uncertaintyRadius: imu.moving ? 25 : 12,
        description: imu.moving ? "Pedestrian motion" : "Device steady",
      });
    }

    if (sky) {
      opinions.push({
        sourceType: "sextant",
        name: "Sky",
        status: "active",
        confidence: sky.confidence,
        uncertaintyRadius: 80,
        description: sky.description,
      });
    } else if (hasPack && gps && pack && inBounds(gps.lat, gps.lng, pack.bounds)) {
      opinions.push({
        sourceType: "sextant",
        name: "Sky",
        status: "active",
        confidence: 64,
        uncertaintyRadius: 120,
        description: "Celestial model from region pack",
      });
    }

    const active = opinions.filter((o) => o.status !== "unavailable");
    const agreeing = active.filter((o) => o.status !== "unstable" && o.confidence >= 55);
    let score = 0;
    if (active.length) {
      const weights = { gps: 0.4, landmark: 0.25, magnetic: 0.15, imu: 0.1, sextant: 0.1 };
      let wsum = 0;
      let acc = 0;
      for (const o of active) {
        const w = weights[o.sourceType] || 0.1;
        acc += o.confidence * w * (o.status === "unstable" ? 0.6 : 1);
        wsum += w;
      }
      score = Math.round(acc / wsum);
      if (hasPack) score = Math.min(100, score + 4);
    }

    if (!state.tracking) score = Math.min(score, 40);

    const level = levelFor(score, state.tracking);
    const uncertainty = active.length
      ? Math.min(...active.map((o) => o.uncertaintyRadius))
      : 0;
    const radiusLabel =
      uncertainty <= 0
        ? "acquiring fix"
        : uncertainty >= 1000
          ? `±${(uncertainty / 1000).toFixed(1)} km`
          : `±${Math.round(uncertainty)} m`;

    return {
      score,
      level,
      color: colorFor(level),
      headline: labelFor(level),
      subtitle: state.tracking
        ? `${agreeing.length} of ${Math.max(opinions.length, 5)} sources agree · ${radiusLabel}`
        : "Start tracking to verify your position",
      explanation: explanation(level, score),
      opinions,
      agreeing: agreeing.length,
      total: Math.max(opinions.length, 5),
      uncertainty,
    };
  }

  return { CATALOG, haversine, fuse, packFor, inBounds, colorFor };
})();
