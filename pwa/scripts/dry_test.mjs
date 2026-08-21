import { readFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const findings = [];
const ok = (msg) => console.log(`  ok   ${msg}`);
const fail = (msg) => {
  findings.push(msg);
  console.log(`  FAIL ${msg}`);
};

function read(rel) {
  return readFileSync(join(root, rel), "utf8");
}

console.log("WHAMI PWA dry test\n");

console.log("1. Files");
for (const f of [
  "index.html",
  "manifest.json",
  "sw.js",
  "css/app.css",
  "js/app.js",
  "js/map.js",
  "js/trust.js",
  "js/sensors.js",
  "js/storage.js",
  "icons/app_icon.png",
  "icons/Icon-192.png",
  "favicon.png",
]) {
  existsSync(join(root, f)) ? ok(f) : fail(`missing ${f}`);
}

console.log("\n2. JS syntax");
for (const f of ["js/app.js", "js/map.js", "js/trust.js", "js/sensors.js", "js/storage.js", "sw.js"]) {
  const r = spawnSync("node", ["--check", join(root, f)], { encoding: "utf8" });
  r.status === 0 ? ok(f) : fail(`${f}: ${r.stderr.trim()}`);
}

console.log("\n3. HTML contract");
const html = read("index.html");
for (const id of [
  "map",
  "app-nav",
  "chrome",
  "status-bar",
  "sheet",
  "track-pill",
  "pack-list",
  "landmark-list",
  "sensor-list",
  "activity-list",
]) {
  html.includes(`id="${id}"`) ? ok(`#${id}`) : fail(`missing #${id}`);
}
html.includes("chrome-brand") ? ok("desktop brand") : fail("missing chrome-brand");
/app\.css\?v=\d+/.test(html) ? ok("css cache bust") : fail("css not cache-busted");

console.log("\n4. Desktop CSS");
const css = read("css/app.css");
css.includes("@media (min-width: 900px)") ? ok("900px breakpoint") : fail("no desktop breakpoint");
css.includes("width: 248px") ? ok("sidebar width") : fail("no sidebar");
css.includes("min(920px") || /@media \(min-width: 520px\)/.test(css)
    ? fail("old phone-frame media query still present")
    : ok("phone-frame media query removed");
css.includes(".screen { left: 248px; }") || css.includes(".screen { left: 248px")
  ? ok("screens offset for sidebar")
  : fail("screens not offset for sidebar");

console.log("\n5. Local server");
try {
  const res = await fetch("http://127.0.0.1:4173/");
  res.ok ? ok(`GET / → ${res.status}`) : fail(`GET / → ${res.status}`);
  const page = await res.text();
  page.includes('id="app-nav"') ? ok("served HTML has nav") : fail("served HTML missing nav");
  page.includes("chrome-brand") ? ok("served HTML has desktop brand") : fail("server still on old HTML");

  for (const url of [
    "/css/app.css?v=5",
    "/js/app.js?v=5",
    "/manifest.json",
    "/icons/app_icon.png",
  ]) {
    const r = await fetch(`http://127.0.0.1:4173${url}`);
    r.ok ? ok(`GET ${url} → ${r.status}`) : fail(`GET ${url} → ${r.status}`);
  }

  const cssLive = await (await fetch("http://127.0.0.1:4173/css/app.css?v=5")).text();
  cssLive.includes("min-width: 900px")
    ? ok("live CSS has desktop layout")
    : fail("live CSS missing desktop layout");
} catch (e) {
  fail(`server unreachable: ${e.message}`);
}

console.log("\n6. Map style contract");
const mapJs = read("js/map.js");
/maxzoom:\s*18/.test(mapJs) ? ok("raster source maxzoom 18") : fail("map source maxzoom not 18");
/maxzoom:\s*22/.test(mapJs) ? ok("raster layer maxzoom 22") : fail("map layer maxzoom not 22");

console.log("\n---");
if (findings.length) {
  console.log(`${findings.length} finding(s):`);
  findings.forEach((f) => console.log(` - ${f}`));
  process.exit(1);
}
console.log("No blocking findings.");
