---
name: Flutter on Replit
description: How to install and run Flutter in this Replit environment, including known type incompatibilities in Flutter 3.32.0
---

## Install

```javascript
await installSystemDependencies({ packages: ["flutter"] });
```

Installs Flutter 3.32.0, Dart 3.8.0. No `installProgrammingLanguage` needed.

## Run (web target)

```bash
cd artifacts/whami && flutter run -d web-server --web-port 3000 --web-hostname 0.0.0.0
```

## Known type changes in Flutter 3.32.0

- `ThemeData.cardTheme` requires `CardThemeData`, not `CardTheme`

**Why:** Flutter 3.x renamed several theme classes to `*ThemeData`. Old code using `CardTheme(...)` directly will fail at compile time.

**How to apply:** Whenever writing ThemeData with card/dialog/etc themes, use the `*ThemeData` variant.

## Workflow command

```
cd artifacts/whami && flutter run -d web-server --web-port 3000 --web-hostname 0.0.0.0
```

Use `waitForPort: 3000` in `configureWorkflow`.
