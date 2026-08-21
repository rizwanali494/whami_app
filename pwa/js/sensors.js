const Sensors = (() => {
  let watchId = null;
  let motionHandler = null;
  let orientHandler = null;
  let lastAccel = null;

  async function requestLocation() {
    if (!navigator.geolocation) throw new Error("Geolocation unavailable");
    if (navigator.permissions?.query) {
      try {
        const p = await navigator.permissions.query({ name: "geolocation" });
        if (p.state === "denied") throw new Error("Location permission denied");
      } catch {
        /* Safari may throw on permissions.query */
      }
    }
  }

  function start({ onGps, onMagnetic, onImu }) {
    stop();

    if (navigator.geolocation) {
      watchId = navigator.geolocation.watchPosition(
        (pos) => {
          onGps?.({
            lat: pos.coords.latitude,
            lng: pos.coords.longitude,
            accuracy: pos.coords.accuracy,
            altitude: pos.coords.altitude,
            heading: pos.coords.heading,
            speed: pos.coords.speed || 0,
            at: pos.timestamp,
          });
        },
        (err) => onGps?.({ error: err.message }),
        { enableHighAccuracy: true, maximumAge: 2000, timeout: 15000 },
      );
    }

    orientHandler = (e) => {
      const heading =
        e.webkitCompassHeading != null
          ? e.webkitCompassHeading
          : e.alpha != null
            ? 360 - e.alpha
            : null;
      onMagnetic?.({
        heading,
        absolute: Boolean(e.absolute || e.webkitCompassHeading != null),
        beta: e.beta,
        gamma: e.gamma,
      });
    };
    window.addEventListener("deviceorientationabsolute", orientHandler, true);
    window.addEventListener("deviceorientation", orientHandler, true);

    motionHandler = (e) => {
      const a = e.accelerationIncludingGravity;
      if (!a) return;
      const mag = Math.hypot(a.x || 0, a.y || 0, a.z || 0);
      const delta = lastAccel == null ? 0 : Math.abs(mag - lastAccel);
      lastAccel = mag;
      onImu?.({
        moving: delta > 0.35,
        magnitude: mag,
        rotation: e.rotationRate,
      });
    };
    window.addEventListener("devicemotion", motionHandler, true);
  }

  function stop() {
    if (watchId != null) {
      navigator.geolocation.clearWatch(watchId);
      watchId = null;
    }
    if (orientHandler) {
      window.removeEventListener("deviceorientationabsolute", orientHandler, true);
      window.removeEventListener("deviceorientation", orientHandler, true);
      orientHandler = null;
    }
    if (motionHandler) {
      window.removeEventListener("devicemotion", motionHandler, true);
      motionHandler = null;
    }
  }

  async function unlockIOS() {
    const DOE = window.DeviceOrientationEvent;
    if (DOE && typeof DOE.requestPermission === "function") {
      try {
        await DOE.requestPermission();
      } catch {
        /* user declined */
      }
    }
    const DME = window.DeviceMotionEvent;
    if (DME && typeof DME.requestPermission === "function") {
      try {
        await DME.requestPermission();
      } catch {
        /* user declined */
      }
    }
  }

  function skyFromGps(gps) {
    if (!gps || gps.lat == null) return null;
    const hour = new Date().getHours();
    const day = hour >= 6 && hour <= 19;
    return {
      confidence: day ? 72 : 58,
      description: day ? "Daylight celestial window" : "Night sky model",
    };
  }

  return { requestLocation, start, stop, unlockIOS, skyFromGps };
})();
