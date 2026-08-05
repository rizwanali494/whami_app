# WHAMI

**Where Am I?** — verified navigation and position trust for Android (and iOS).

WHAMI fuses multiple on-device witnesses (GPS, landmarks, magnetometer, IMU, sky) so the first answer is plain language: **Reliable / Caution / Unreliable** — not a raw specialist score.

## Product surface

| Tab | Purpose |
|-----|---------|
| **Map** | Full-screen map, trust banner, Start/Stop tracking, collapsible source details |
| **Verify** | Landmark / AR confirmation when confidence is low |
| **Offline** | Download and activate region packs (SHA-256 verified) |
| **Activity** | Actionable alerts + trust history |

Diagnostics, sensors, units, outdoor mode, storage, and privacy live under the Map overflow menu (**Diagnostics & Settings**).

## Run

```bash
flutter pub get
flutter run
```

Release Android:

```bash
flutter build apk --release
flutter build appbundle --release
```

Upload signing uses `android/key.properties` + `android/app/upload-keystore.jks` (gitignored).

## Architecture (high level)

- `lib/features/` — UI by destination
- `lib/data/services/` — sensors, fusion, downloads, local tile/glyph servers
- `lib/data/repositories/` — app-facing state (`WhamiRepository`)
- `lib/navigation/whami_router.dart` — GoRouter shell (4 tabs)

Local MBTiles and glyph HTTP servers start in `bootstrapWhamiServices()` from `main.dart` (not as side effects of field initializers).

## Trust bands

| Score | Label |
|------:|-------|
| ≥ 75 | Position reliable |
| 55–74 | Use with caution |
| < 55 | Position unreliable |

Expand the map bottom sheet for per-source opinions and the weighted formula.

## Tests

```bash
flutter test
```

## Brand

Use the supplied WHAMI logo asset under `assets/images/` unchanged (do not redraw, recolor, crop, or replace it for product chrome).
