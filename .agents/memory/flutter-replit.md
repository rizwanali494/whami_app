---
name: Flutter on Replit
description: How to install and run Flutter in this Replit environment, including known type incompatibilities in Flutter 3.32.0
---

## Install

```javascript
await installSystemDependencies({ packages: ["flutter"] });
```

Installs Flutter 3.32.0, Dart 3.8.0. No `installProgrammingLanguage` needed.

## REQUIRED after creating a new Flutter project

Always run `flutter pub get` inside the project directory before starting the workflow. Without it the pub cache is empty and the Flutter SDK itself fails to compile (Matrix4, Vector3, @visibleForTesting, @protected all become undefined — these come from `vector_math` and `meta` which are Flutter SDK internal dependencies fetched via pub).

```bash
cd artifacts/whami && flutter pub get
```

**Why:** The Nix-wrapped Flutter SDK does not pre-populate the pub cache. The first `flutter run` will fail with hundreds of "type not found" errors from inside Flutter's own source files unless pub has fetched the deps first.

**How to apply:** After `flutter create` or after any `pubspec.yaml` change, always run `flutter pub get` before restarting the workflow.

## Run (web target)

```bash
cd artifacts/whami && flutter run -d web-server --web-port 3000 --web-hostname 0.0.0.0
```

## Known type changes in Flutter 3.32.0

- `ThemeData.cardTheme` requires `CardThemeData`, not `CardTheme`

**Why:** Flutter 3.x renamed several theme classes to `*ThemeData`. Old code using `CardTheme(...)` directly will fail at compile time.

**How to apply:** Whenever writing ThemeData with card/dialog/etc themes, use the `*ThemeData` variant.

## Map package: use flutter_map, NOT maplibre_gl, for Flutter web

`maplibre_gl 0.19.0+2` fails on Flutter 3.32.0 with `Undefined name 'platformViewRegistry'` — the package uses the old `ui.platformViewRegistry` API removed in Flutter 3.x. The newer `maplibre_gl 0.26.1` requires `meta ^1.17.0` but Flutter SDK pins `meta 1.16.0`. Both versions are blocked on Flutter 3.32.0.

Use `flutter_map: ^7.0.0` + `latlong2: ^0.9.1` instead — pure Dart, no platform view bridges, works on web + native, supports CARTO/OSM tiles, meter-accurate uncertainty circles via `useRadiusInMeter: true`, dashed lines via `StrokePattern.dashed(segments: [8, 4])` (not `isDotted`).

**Why:** maplibre_gl is incompatible with Flutter 3.32.0 on web in any available pub.dev version. flutter_map covers all the same capabilities for this prototype.

**How to apply:** Any new Flutter web map work should use flutter_map. For the production native build, the client can switch to maplibre_gl which works fine on Android/iOS native.

## Workflow command

```
cd artifacts/whami && flutter run -d web-server --web-port 3000 --web-hostname 0.0.0.0
```

Use `waitForPort: 3000` in `configureWorkflow`.
