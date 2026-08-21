const Storage = (() => {
  const KEY = "whami.pwa.v1";

  const defaults = {
    onboardingSeen: false,
    outdoor: false,
    metric: true,
    tracking: false,
    activePackId: "",
    packs: {},
    events: [],
    lastFix: null,
  };

  function read() {
    try {
      return { ...defaults, ...JSON.parse(localStorage.getItem(KEY) || "{}") };
    } catch {
      return { ...defaults };
    }
  }

  function write(patch) {
    const next = { ...read(), ...patch };
    localStorage.setItem(KEY, JSON.stringify(next));
    return next;
  }

  function addEvent(event) {
    const data = read();
    data.events = [
      { id: crypto.randomUUID(), at: Date.now(), ...event },
      ...data.events,
    ].slice(0, 80);
    localStorage.setItem(KEY, JSON.stringify(data));
    return data.events;
  }

  function setPack(id, status) {
    const data = read();
    data.packs = { ...data.packs, [id]: { status, at: Date.now() } };
    localStorage.setItem(KEY, JSON.stringify(data));
    return data;
  }

  return { read, write, addEvent, setPack };
})();
