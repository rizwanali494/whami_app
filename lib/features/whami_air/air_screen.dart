import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/whami_repository.dart';
import 'air_preferences.dart';
import 'widgets/air_trust_strip.dart';

/// WHAMI-Air research mode: disclaimer, toggles, recorder, export, calibration.
class AirScreen extends StatefulWidget {
  final WhamiRepository repository;

  const AirScreen({super.key, required this.repository});

  @override
  State<AirScreen> createState() => _AirScreenState();
}

class _AirScreenState extends State<AirScreen> {
  final List<(double, double, double)> _calSamples = [];
  String? _exportPath;
  String? _status;

  WhamiRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    repo.addListener(_refresh);
  }

  @override
  void dispose() {
    repo.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _enableAirMode(AirPreferences air) async {
    if (!air.disclaimerAccepted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Advisory only'),
          content: const Text(
            'WHAMI-Air is a research / advisory position-trust layer.\n\n'
            'It does NOT replace certified aircraft navigation.\n'
            'Do not use WHAMI to navigate the aircraft.\n\n'
            'WHAMI does not fly the aircraft. WHAMI tells you when the '
            'position story no longer makes sense.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('I understand'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await air.setDisclaimerAccepted(true);
    }
    await air.setAirModeEnabled(true);
  }

  Future<void> _exportLatest() async {
    try {
      final id = await repo.airRecorder.latestFlightId();
      if (id == null) {
        setState(() => _status = 'No flight logs yet. Start tracking in Air mode.');
        return;
      }
      final zip = await repo.airRecorder.exportFlightZip(id);
      setState(() {
        _exportPath = zip.path;
        _status = 'Exported ${zip.path}';
      });
    } catch (e) {
      setState(() => _status = 'Export failed: $e');
    }
  }

  void _captureCalSample() {
    final mag = repo.sensors.magnetometerService.lastReading;
    if (mag == null) {
      setState(() => _status = 'No magnetometer sample');
      return;
    }
    setState(() {
      _calSamples.add((mag.x, mag.y, mag.z));
      _status = 'Calibration samples: ${_calSamples.length} (need ≥8, rotate phone)';
    });
  }

  void _fitCalibration() {
    repo.magCalibration.fitHardIron(_calSamples);
    setState(() {
      _status = repo.magCalibration.calibrated
          ? 'Hard-iron calibration applied'
          : 'Need at least 8 samples while rotating the device';
    });
  }

  @override
  Widget build(BuildContext context) {
    final air = context.watch<AirPreferences>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('WHAMI-Air Research'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.alertWarning,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.trustMediumDark.withValues(alpha: 0.4),
              ),
            ),
            child: const Text(
              'RESEARCH / ADVISORY ONLY — Do not use to navigate the aircraft. '
              'WHAMI-Air logs passive witnesses (WMM magnetic, baro, IMU, sky) '
              'to help bound INS-like drift when GNSS is degraded.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
          const SizedBox(height: 14),
          AirTrustStrip(snapshot: repo.airTrust),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('WHAMI-Air Research Mode'),
            subtitle: const Text('Advisory position-trust + WMM residuals'),
            value: air.airModeEnabled,
            onChanged: (v) async {
              if (v) {
                await _enableAirMode(air);
              } else {
                await air.setAirModeEnabled(false);
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Flight research recorder'),
            subtitle: Text(
              repo.airRecorder.isRecording
                  ? 'Recording ${repo.airRecorder.flightId} · ${repo.airRecorder.sampleCount} samples'
                  : 'Writes NDJSON under Documents/WHAMI/air/flights/',
            ),
            value: air.recordingEnabled,
            onChanged: air.setRecordingEnabled,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('EFB large-type layout'),
            subtitle: const Text('Tablet-oriented advisory screens'),
            value: air.efbLayout,
            onChanged: air.setEfbLayout,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Kp index: ${air.kpIndex.toStringAsFixed(0)}'),
            subtitle: const Text('Space-weather awareness (manual / stub)'),
          ),
          Slider(
            value: air.kpIndex,
            min: 0,
            max: 9,
            divisions: 9,
            label: air.kpIndex.toStringAsFixed(0),
            onChanged: (v) => air.setKpIndex(v),
          ),
          const Divider(),
          Text(
            'WMM: ${repo.wmmService.isReady ? repo.wmmService.statusMessage : "loading…"}',
            style: const TextStyle(fontSize: 13),
          ),
          if (repo.lastWmmResidual != null)
            Text(
              'Last residual: ${repo.lastWmmResidual!.residualMicroTesla.toStringAsFixed(1)} µT',
              style: const TextStyle(fontSize: 13),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _captureCalSample,
                  child: const Text('Mag sample'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _fitCalibration,
                  child: const Text('Fit hard-iron'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _exportLatest,
            child: const Text('Export latest flight (ZIP)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/air/efb'),
            child: const Text('Open EFB Advisory'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/air/ground-station'),
            child: const Text('Open Ground Station view'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: const TextStyle(fontSize: 12)),
          ],
          if (_exportPath != null) ...[
            const SizedBox(height: 4),
            SelectableText(
              _exportPath!,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
