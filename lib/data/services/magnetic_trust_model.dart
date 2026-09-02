import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

/// Optional crustal / corridor anomaly delta (nT) layered on WMM.
class MagneticAnomalyLayer {
  final String name;
  final List<_AnomalyCell> _cells;

  MagneticAnomalyLayer._(this.name, this._cells);

  static MagneticAnomalyLayer empty() => MagneticAnomalyLayer._('none', const []);

  /// Load a lightweight JSON corridor grid from assets.
  /// Format: { "name": "...", "cells": [ {"lat":..,"lng":..,"dF_nT":..}, ... ] }
  static Future<MagneticAnomalyLayer> loadAsset(String assetPath) async {
    try {
      final text = await rootBundle.loadString(assetPath);
      final json = jsonDecode(text) as Map<String, dynamic>;
      final name = json['name'] as String? ?? 'anomaly';
      final cells = <_AnomalyCell>[];
      for (final c in (json['cells'] as List? ?? const [])) {
        final m = c as Map<String, dynamic>;
        cells.add(
          _AnomalyCell(
            lat: (m['lat'] as num).toDouble(),
            lng: (m['lng'] as num).toDouble(),
            dF: (m['dF_nT'] as num).toDouble(),
          ),
        );
      }
      return MagneticAnomalyLayer._(name, cells);
    } catch (_) {
      return MagneticAnomalyLayer.empty();
    }
  }

  bool get hasData => _cells.isNotEmpty;

  /// Nearest-neighbour anomaly delta in nT (added to WMM F).
  double deltaFnT(double lat, double lng) {
    if (_cells.isEmpty) return 0;
    var best = _cells.first;
    var bestD = double.infinity;
    for (final c in _cells) {
      final d = (c.lat - lat) * (c.lat - lat) + (c.lng - lng) * (c.lng - lng);
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    // Only apply within ~2° (~200 km) of a cell.
    if (sqrt(bestD) > 2.0) return 0;
    return best.dF;
  }
}

class _AnomalyCell {
  final double lat;
  final double lng;
  final double dF;
  const _AnomalyCell({
    required this.lat,
    required this.lng,
    required this.dF,
  });
}

/// Hard-iron / soft-iron style phone magnetometer calibration.
class MagCalibration {
  double offsetX;
  double offsetY;
  double offsetZ;
  bool calibrated;

  MagCalibration({
    this.offsetX = 0,
    this.offsetY = 0,
    this.offsetZ = 0,
    this.calibrated = false,
  });

  /// Estimate hard-iron offsets from a set of (x,y,z) samples (µT).
  void fitHardIron(List<(double, double, double)> samples) {
    if (samples.length < 8) return;
    double minX = samples.first.$1, maxX = samples.first.$1;
    double minY = samples.first.$2, maxY = samples.first.$2;
    double minZ = samples.first.$3, maxZ = samples.first.$3;
    for (final s in samples) {
      minX = min(minX, s.$1);
      maxX = max(maxX, s.$1);
      minY = min(minY, s.$2);
      maxY = max(maxY, s.$2);
      minZ = min(minZ, s.$3);
      maxZ = max(maxZ, s.$3);
    }
    offsetX = (minX + maxX) / 2;
    offsetY = (minY + maxY) / 2;
    offsetZ = (minZ + maxZ) / 2;
    calibrated = true;
  }

  (double, double, double) apply(double x, double y, double z) {
    if (!calibrated) return (x, y, z);
    return (x - offsetX, y - offsetY, z - offsetZ);
  }

  double fieldStrength(double x, double y, double z) {
    final c = apply(x, y, z);
    return sqrt(c.$1 * c.$1 + c.$2 * c.$2 + c.$3 * c.$3);
  }

  Map<String, dynamic> toJson() => {
        'offsetX': offsetX,
        'offsetY': offsetY,
        'offsetZ': offsetZ,
        'calibrated': calibrated,
      };

  factory MagCalibration.fromJson(Map<String, dynamic>? json) {
    if (json == null) return MagCalibration();
    return MagCalibration(
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
      offsetZ: (json['offsetZ'] as num?)?.toDouble() ?? 0,
      calibrated: json['calibrated'] as bool? ?? false,
    );
  }
}

/// Fetches / stubs planetary Kp for space-weather awareness.
class KpIndexService {
  double _kp = 3.0;
  DateTime? _updatedAt;
  String _source = 'manual';

  double get kp => _kp;
  DateTime? get updatedAt => _updatedAt;
  String get source => _source;

  void setManual(double value) {
    _kp = value.clamp(0, 9);
    _updatedAt = DateTime.now().toUtc();
    _source = 'manual';
  }

  /// Best-effort NOAA SWPC JSON (fails soft → keep last / default).
  Future<double> refreshFromNoaa() async {
    try {
      // Soft stub: live fetch can be wired later; Phase 1b stores Kp in logs.
      _updatedAt = DateTime.now().toUtc();
      _source = 'stub';
      return _kp;
    } catch (_) {
      return _kp;
    }
  }

  bool get modelDegraded => _kp >= 8.0;
}
