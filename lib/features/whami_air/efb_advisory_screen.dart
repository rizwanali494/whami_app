import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../data/repositories/whami_repository.dart';
import 'air_preferences.dart';
import 'air_trust.dart';
import 'widgets/air_trust_strip.dart';

/// Phase 2 — EFB-style advisory UI (large type, 4-state trust only).
class EfbAdvisoryScreen extends StatelessWidget {
  final WhamiRepository repository;

  const EfbAdvisoryScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    final air = context.watch<AirPreferences>();
    final large = air.efbLayout;
    final snap = repository.airTrust;
    final band = snap?.band ?? AirTrustBand.grey;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('WHAMI-Air EFB Advisory'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ADVISORY ONLY — DO NOT NAVIGATE BY WHAMI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.amber.shade200,
                  fontWeight: FontWeight.w800,
                  fontSize: large ? 16 : 13,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: band.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        band.label,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: large ? 56 : 42,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        band.pilotLine,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: large ? 22 : 18,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AirTrustStrip(snapshot: snap, compact: true),
              const SizedBox(height: 16),
              _EfbRow(
                label: 'GNSS',
                value: snap == null
                    ? '—'
                    : snap.gnssUnavailable
                        ? 'UNAVAILABLE'
                        : snap.gnssSuspicious
                            ? 'SUSPICIOUS'
                            : 'OK',
                large: large,
              ),
              _EfbRow(
                label: 'Magnetic / WMM',
                value: snap == null
                    ? '—'
                    : '${snap.magneticAgreement}%'
                        '${snap.wmmResidualUt != null ? " · Δ ${snap.wmmResidualUt!.toStringAsFixed(1)} µT" : ""}',
                large: large,
              ),
              _EfbRow(
                label: 'Baro consistency',
                value: snap == null
                    ? '—'
                    : '${snap.baroConsistency}%'
                        '${snap.baroGpsAltDeltaM != null ? " · Δ ${snap.baroGpsAltDeltaM!.toStringAsFixed(0)} m" : ""}',
                large: large,
              ),
              _EfbRow(
                label: 'Celestial',
                value: snap == null ? '—' : '${snap.celestialAgreement}%',
                large: large,
              ),
              _EfbRow(
                label: 'Confidence radius',
                value: snap == null
                    ? '—'
                    : '±${snap.confidenceRadiusM.round()} m',
                large: large,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EfbRow extends StatelessWidget {
  final String label;
  final String value;
  final bool large;

  const _EfbRow({
    required this.label,
    required this.value,
    required this.large,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white70,
                fontSize: large ? 18 : 14,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: large ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
