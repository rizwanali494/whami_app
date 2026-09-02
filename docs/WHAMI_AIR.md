# WHAMI-Air

Advisory verified-position trust for GNSS-denied flight research.

**WHAMI does not fly the aircraft. WHAMI tells the pilot when the position story no longer makes sense.**

## Product rule

WHAMI-Air is **research / advisory only**. It is not certified primary navigation and must not be used to navigate the aircraft.

## Phase 1 (shipped in app)

| Capability | Location |
|------------|----------|
| Air Research Mode + disclaimer | Settings → WHAMI-Air Research (`/air`) |
| WMM2025 model (`assets/wmm/WMM.COF`) | `lib/data/services/wmm/` |
| Magnetic residual witness | `TrustFusionEngine` + repository |
| Barometric vertical consistency | `TrustFusionEngine` baro opinion |
| Flight research recorder (NDJSON) | `Documents/WHAMI/air/flights/{id}/` |
| Green / Amber / Red / Grey strip | Map (Air mode) + EFB |
| Export ZIP | Air screen / Ground Station |

## Phase 1b

- Demo anomaly corridor: `assets/magnetic/demo_anomaly_corridor.json`
- Manual Kp index (storm-degraded WMM trust)
- Hard-iron magnetometer calibration routine on Air screen

## Phase 2 — EFB Advisory

Route: `/air/efb` — large 4-state advisory panel for tablet use.

## Phase 3 — WHAMI Pro Ground Station

Route: `/air/ground-station` — mission log review, opinion dashboard.
Flutter **Windows** (and Linux) desktop targets enabled for Panasonic TOUGHBOOK 40 style deployments. Phone remains the live sensor host; Ground Station is the rugged command / replay screen.

## Architecture

```
Sky-Mag-Baro Pack (future) → Phone WHAMI-Air → logs / Wi‑Fi sync → Toughbook Ground Station
```

## Messaging

> WHAMI-Air is not another GPS receiver. It is a passive position-trust layer for GNSS-denied flight, designed to help bound INS drift when GPS is spoofed, jammed, or unavailable and DME/DME coverage is weak or absent.

Built on official NOAA **WMM2025** coefficients. WMMHR / EMAG2 corridor packs are intended as later data layers, not hobby magnetic maps.
