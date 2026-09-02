import 'dart:math';
import 'package:flutter/services.dart';
import 'wmm_field.dart';

/// World Magnetic Model WMM2025 evaluator using official NOAA WMM.COF coefficients.
///
/// Algorithm adapted from NOAA geomagc / Christopher Weiss GeoMag (public domain
/// WMM software lineage). Input altitude is kilometres above WGS84 ellipsoid.
/// Output field strengths are nanotesla (nT); phone sensors use µT (÷1000).
class WmmService {
  static const _cofAsset = 'assets/wmm/WMM.COF';
  static const int _maxord = 12;

  bool _ready = false;
  String _status = 'Not loaded';
  double _epoch = 2025.0;
  String _cofName = 'WMM-2025';

  late List<List<double>> _c;
  late List<List<double>> _cd;
  late List<List<double>> _tc;
  late List<List<double>> _p;
  late List<List<double>> _dp;
  late List<List<double>> _k;
  late List<double> _sp;
  late List<double> _cp;
  late List<double> _pp;
  late List<double> _fn;
  late List<double> _fm;

  final double _a = 6378.137;
  final double _b = 6356.7523142;
  final double _re = 6371.2;
  late final double _a2;
  late final double _b2;
  late final double _c2;
  late final double _a4;
  late final double _c4;

  bool get isReady => _ready;
  String get statusMessage => _status;
  double get epoch => _epoch;
  String get modelName => _cofName;

  WmmService() {
    _a2 = _a * _a;
    _b2 = _b * _b;
    _c2 = _a2 - _b2;
    _a4 = _a2 * _a2;
    final b4 = _b2 * _b2;
    _c4 = _a4 - b4;
  }

  Future<void> initialize() async {
    if (_ready) return;
    final text = await rootBundle.loadString(_cofAsset);
    loadFromCofString(text);
  }

  void loadFromCofString(String text) {
    final entries = <_CofEntry>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length == 3 ||
          (parts.length >= 3 && double.tryParse(parts[0]) != null &&
              int.tryParse(parts[1]) == null)) {
        // Header: epoch name date
        if (parts.length >= 3 && double.tryParse(parts[0]) != null) {
          _epoch = double.parse(parts[0]);
          _cofName = parts[1];
        }
        continue;
      }
      if (parts.length >= 6) {
        final n = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (n == null || m == null) continue;
        if (n > _maxord) continue;
        entries.add(
          _CofEntry(
            n: n,
            m: m,
            gnm: double.parse(parts[2]),
            hnm: double.parse(parts[3]),
            dgnm: double.parse(parts[4]),
            dhnm: double.parse(parts[5]),
          ),
        );
      }
    }

    _alloc();
    for (final e in entries) {
      if (e.m <= e.n) {
        _c[e.m][e.n] = e.gnm;
        _cd[e.m][e.n] = e.dgnm;
        if (e.m != 0) {
          _c[e.n][e.m - 1] = e.hnm;
          _cd[e.n][e.m - 1] = e.dhnm;
        }
      }
    }

    // Convert Schmidt-normalized Gauss coefficients to unnormalized.
    final snorm = List.generate(13, (_) => List.filled(13, 0.0));
    snorm[0][0] = 1.0;
    _k[1][1] = 0.0;
    for (var n = 1; n <= _maxord; n++) {
      snorm[0][n] = snorm[0][n - 1] * (2.0 * n - 1) / n;
      var j = 2.0;
      var m = 0;
      var d2 = (n - m + 1) / 1;
      while (d2 > 0) {
        _k[m][n] =
            (((n - 1) * (n - 1)) - (m * m)) / ((2.0 * n - 1) * (2.0 * n - 3.0));
        if (m > 0) {
          final flnmj = ((n - m + 1.0) * j) / (n + m);
          snorm[m][n] = snorm[m - 1][n] * sqrt(flnmj);
          j = 1.0;
          _c[n][m - 1] = snorm[m][n] * _c[n][m - 1];
          _cd[n][m - 1] = snorm[m][n] * _cd[n][m - 1];
        }
        _c[m][n] = snorm[m][n] * _c[m][n];
        _cd[m][n] = snorm[m][n] * _cd[m][n];
        d2 -= 1;
        m += 1;
      }
    }

    _ready = true;
    _status = '$_cofName ready (epoch $_epoch)';
  }

  void _alloc() {
    List<double> z(int n) => List.filled(n, 0.0);
    _tc = List.generate(14, (_) => z(14));
    _sp = z(14);
    _cp = z(14)..[0] = 1.0;
    _pp = z(13)..[0] = 1.0;
    _p = List.generate(14, (_) => z(14));
    _p[0][0] = 1.0;
    _dp = List.generate(14, (_) => z(13));
    _c = List.generate(14, (_) => z(14));
    _cd = List.generate(14, (_) => z(14));
    _k = List.generate(13, (_) => z(13));
    _fn = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
    _fm = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  }

  static double decimalYear(DateTime date) {
    final utc = date.toUtc();
    final start = DateTime.utc(utc.year, 1, 1);
    final days = utc.difference(start).inMilliseconds / (1000 * 60 * 60 * 24);
    return utc.year + days / 365.0;
  }

  /// [altitudeKm] height above ellipsoid in kilometres.
  WmmField calculate({
    required double latitudeDeg,
    required double longitudeDeg,
    double altitudeKm = 0,
    DateTime? date,
  }) {
    if (!_ready) throw StateError('WmmService not initialized');

    var glat = latitudeDeg.clamp(-89.999999, 89.999999);
    var glon = longitudeDeg;
    while (glon > 180) {
      glon -= 360;
    }
    while (glon < -180) {
      glon += 360;
    }

    final time = decimalYear(date ?? DateTime.now().toUtc());
    final alt = altitudeKm; // already km (GeoMag used feet→km)
    final dt = time - _epoch;

    final rlat = glat * pi / 180.0;
    final rlon = glon * pi / 180.0;
    final srlon = sin(rlon);
    final srlat = sin(rlat);
    final crlon = cos(rlon);
    final crlat = cos(rlat);
    final srlat2 = srlat * srlat;
    final crlat2 = crlat * crlat;
    _sp[1] = srlon;
    _cp[1] = crlon;

    final q = sqrt(_a2 - _c2 * srlat2);
    final q1 = alt * q;
    final q2 = ((q1 + _a2) / (q1 + _b2)) * ((q1 + _a2) / (q1 + _b2));
    final ct = srlat / sqrt(q2 * crlat2 + srlat2);
    final st = sqrt(1.0 - (ct * ct));
    final r2 = (alt * alt) + 2.0 * q1 + (_a4 - _c4 * srlat2) / (q * q);
    final r = sqrt(r2);
    final d = sqrt(_a2 * crlat2 + _b2 * srlat2);
    final ca = (alt + d) / r;
    final sa = _c2 * crlat * srlat / (r * d);

    for (var m = 2; m <= _maxord; m++) {
      _sp[m] = _sp[1] * _cp[m - 1] + _cp[1] * _sp[m - 1];
      _cp[m] = _cp[1] * _cp[m - 1] - _sp[1] * _sp[m - 1];
    }

    final aor = _re / r;
    var ar = aor * aor;
    var br = 0.0;
    var bt = 0.0;
    var bp = 0.0;
    var bpp = 0.0;

    for (var n = 1; n <= _maxord; n++) {
      ar = ar * aor;
      var m = 0;
      var d4 = n + m + 1;
      while (d4 > 0) {
        if (n == m) {
          _p[m][n] = st * _p[m - 1][n - 1];
          _dp[m][n] = st * _dp[m - 1][n - 1] + ct * _p[m - 1][n - 1];
        } else if (n == 1 && m == 0) {
          _p[m][n] = ct * _p[m][n - 1];
          _dp[m][n] = ct * _dp[m][n - 1] - st * _p[m][n - 1];
        } else if (n > 1 && n != m) {
          if (m > n - 2) {
            _p[m][n - 2] = 0;
            _dp[m][n - 2] = 0.0;
          }
          _p[m][n] = ct * _p[m][n - 1] - _k[m][n] * _p[m][n - 2];
          _dp[m][n] = ct * _dp[m][n - 1] -
              st * _p[m][n - 1] -
              _k[m][n] * _dp[m][n - 2];
        }

        _tc[m][n] = _c[m][n] + dt * _cd[m][n];
        if (m != 0) {
          _tc[n][m - 1] = _c[n][m - 1] + dt * _cd[n][m - 1];
        }

        final par = ar * _p[m][n];
        late final double temp1;
        late final double temp2;
        if (m == 0) {
          temp1 = _tc[m][n] * _cp[m];
          temp2 = _tc[m][n] * _sp[m];
        } else {
          temp1 = _tc[m][n] * _cp[m] + _tc[n][m - 1] * _sp[m];
          temp2 = _tc[m][n] * _sp[m] - _tc[n][m - 1] * _cp[m];
        }

        bt = bt - ar * temp1 * _dp[m][n];
        bp = bp + (_fm[m] * temp2 * par);
        br = br + (_fn[n] * temp1 * par);

        if (st == 0.0 && m == 1) {
          if (n == 1) {
            _pp[n] = _pp[n - 1];
          } else {
            _pp[n] = ct * _pp[n - 1] - _k[m][n] * _pp[n - 2];
          }
          final parp = ar * _pp[n];
          bpp = bpp + (_fm[m] * temp2 * parp);
        }

        d4 -= 1;
        m += 1;
      }
    }

    if (st == 0.0) {
      bp = bpp;
    } else {
      bp = bp / st;
    }

    final bx = -bt * ca - br * sa;
    final by = bp;
    final bz = bt * sa - br * ca;
    final bh = sqrt((bx * bx) + (by * by));
    final ti = sqrt((bh * bh) + (bz * bz));
    final dec = atan2(by, bx) * 180.0 / pi;
    final dip = atan2(bz, bh) * 180.0 / pi;

    return WmmField(
      x: bx,
      y: by,
      z: bz,
      h: bh,
      f: ti,
      declination: dec,
      inclination: dip,
      epoch: _epoch,
      decimalYear: time,
    );
  }

  WmmResidual residual({
    required double latitudeDeg,
    required double longitudeDeg,
    required double measuredFMicroTesla,
    double altitudeKm = 0,
    DateTime? date,
    double kpIndex = 3.0,
  }) {
    final model = calculate(
      latitudeDeg: latitudeDeg,
      longitudeDeg: longitudeDeg,
      altitudeKm: altitudeKm,
      date: date,
    );
    final residualUt = (measuredFMicroTesla - model.fMicroTesla).abs();
    final stormDegraded = kpIndex >= 8.0;
    final thresholdGood = stormDegraded ? 6.0 : 4.0;
    final thresholdBad = stormDegraded ? 18.0 : 12.0;

    late final int score;
    late final String status;
    late final String desc;
    if (stormDegraded) {
      score = max(10, (55 - residualUt * 2).round());
      status = 'unstable';
      desc =
          'WMM residual ${residualUt.toStringAsFixed(1)} µT — model degraded (Kp ${kpIndex.toStringAsFixed(0)})';
    } else if (residualUt <= thresholdGood) {
      score = (95 - residualUt * 5).clamp(70, 95).round();
      status = 'active';
      desc =
          'WMM agrees: residual ${residualUt.toStringAsFixed(1)} µT (F=${model.fMicroTesla.toStringAsFixed(1)} µT)';
    } else if (residualUt <= thresholdBad) {
      score = (70 - (residualUt - thresholdGood) * 4).clamp(35, 70).round();
      status = 'active';
      desc =
          'WMM soft mismatch: ${residualUt.toStringAsFixed(1)} µT residual';
    } else {
      score = (30 - (residualUt - thresholdBad)).clamp(5, 30).round();
      status = 'unstable';
      desc =
          'WMM disagreement: ${residualUt.toStringAsFixed(1)} µT — interference or corridor mismatch';
    }

    return WmmResidual(
      model: model,
      measuredFMicroTesla: measuredFMicroTesla,
      residualMicroTesla: residualUt,
      agreementScore: score,
      status: status,
      description: desc,
    );
  }
}

class _CofEntry {
  final int n;
  final int m;
  final double gnm;
  final double hnm;
  final double dgnm;
  final double dhnm;

  const _CofEntry({
    required this.n,
    required this.m,
    required this.gnm,
    required this.hnm,
    required this.dgnm,
    required this.dhnm,
  });
}
