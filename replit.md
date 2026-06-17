# WHAMI — Where Am I?

A Flutter mobile app prototype for verified navigation and position trust. WHAMI compares GPS, landmark/seamap, magnetic field, IMU movement, and sextant/sky validation to tell users whether their GPS is believable.

Tagline: *"Verified by the real world."*

## Run & Operate

- **Flutter app**: `cd artifacts/whami && flutter run -d web-server --web-port 3000 --web-hostname 0.0.0.0`
- Workflow: `WHAMI Flutter App` — runs on port 3000
- `pnpm --filter @workspace/api-server run dev` — API server (port 5000, not used by WHAMI)
- Required env: none (all mock data, no API keys needed)

## Stack

- Flutter 3.32.0 (Dart 3.8.0), web target
- No backend, no Firebase, no paid APIs
- All data: centralized mock repositories
- State: StatefulWidget + shared `WhamiMockRepository`

## Where things live

- `artifacts/whami/lib/` — Flutter app source
- `artifacts/whami/lib/data/mock/` — All mock data (easy to swap for real sensors)
- `artifacts/whami/lib/data/repositories/whami_mock_repository.dart` — Central data access
- `artifacts/whami/lib/features/` — All screens by feature
- `artifacts/whami/lib/core/constants/app_colors.dart` — Color system

## Architecture decisions

- All sensor/GPS data is mocked via `WhamiMockRepository` — replace each method with real sensor calls
- `TrustScenario` objects bundle opinions + sensor states per scenario — switching scenarios just calls `repo.setScenario(index)`
- CustomPaint used for map canvas and AR grid — no map API required
- Trust formula: `0.45×Landmark + 0.20×GPS + 0.15×Magnetic + 0.10×IMU + 0.10×Sky`
- Flutter web target chosen so the prototype runs in Replit browser preview

## Product

10 screens: Splash, Map (with scenario switcher + live trust badge), Landmark Scan, ARCore Scan, Sensors Dashboard, Region Packs, Pack Detail, Alerts/History, Trust Details, Settings/Disclaimer.

5-tab bottom navigation: Map | Scan | Sensors | Packs | Alerts. Settings via FAB.

## User preferences

_Populate as you build._

## Gotchas

- **Run `flutter pub get` first**: After any fresh checkout or `pubspec.yaml` change, run `cd artifacts/whami && flutter pub get` before starting the workflow. Without it the pub cache is empty and Flutter's own SDK files fail to compile with hundreds of "Matrix4/Vector3 not a type" errors.
- Flutter 3.32.0 uses `CardThemeData` not `CardTheme` in `ThemeData`
- Flutter web runs in debug mode via `flutter run -d web-server` — production build uses `flutter build web`
- `flutter run` must be restarted (not hot-reloaded) after structural Dart changes in Replit

## Pointers

- See `artifacts/whami/lib/data/mock/` to update mock values
- See `artifacts/whami/lib/data/repositories/whami_mock_repository.dart` for TODO integration points
