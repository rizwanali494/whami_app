import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/whami_air/air_trust.dart';

/// One research-recorder sample (NDJSON line).
class FlightSample {
  final DateTime timestamp;
  final Map<String, dynamic> payload;

  const FlightSample({required this.timestamp, required this.payload});

  String toNdjson() => jsonEncode({
        'ts': timestamp.toUtc().toIso8601String(),
        ...payload,
      });
}

/// Durable WHAMI-Air research recorder.
/// Writes NDJSON under Documents/WHAMI/air/flights/{id}/samples.ndjson
class AirResearchRecorder {
  String? _flightId;
  IOSink? _sink;
  File? _samplesFile;
  File? _metaFile;
  int _sampleCount = 0;
  bool _active = false;

  bool get isRecording => _active;
  String? get flightId => _flightId;
  int get sampleCount => _sampleCount;

  Future<Directory> _flightsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/WHAMI/air/flights');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> startFlight({Map<String, dynamic>? meta}) async {
    if (_active) await stopFlight();
    final root = await _flightsRoot();
    final id =
        DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final flightDir = Directory('${root.path}/$id');
    await flightDir.create(recursive: true);
    _flightId = id;
    _samplesFile = File('${flightDir.path}/samples.ndjson');
    _metaFile = File('${flightDir.path}/meta.json');
    _sink = _samplesFile!.openWrite(mode: FileMode.append);
    _sampleCount = 0;
    _active = true;
    await _metaFile!.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'flightId': id,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'product': 'WHAMI-Air Research Recorder',
        'advisoryOnly': true,
        'disclaimer':
            'Research / advisory only. Do not use to navigate the aircraft.',
        ...?meta,
      }),
    );
  }

  Future<void> appendSample(Map<String, dynamic> payload) async {
    if (!_active || _sink == null) return;
    final sample = FlightSample(
      timestamp: DateTime.now().toUtc(),
      payload: payload,
    );
    _sink!.writeln(sample.toNdjson());
    _sampleCount++;
    // Flush periodically for crash resilience.
    if (_sampleCount % 10 == 0) {
      await _sink!.flush();
    }
  }

  Future<void> appendFromSensors({
    required AirTrustSnapshot air,
    Map<String, dynamic>? gnss,
    Map<String, dynamic>? mag,
    Map<String, dynamic>? imu,
    Map<String, dynamic>? baro,
    Map<String, dynamic>? sky,
    Map<String, dynamic>? wmm,
    double? kpIndex,
  }) {
    return appendSample({
      'air': air.toJson(),
      'gnss': gnss,
      'mag': mag,
      'imu': imu,
      'baro': baro,
      'sky': sky,
      'wmm': wmm,
      'kp': kpIndex,
    });
  }

  Future<String?> stopFlight() async {
    if (!_active) return null;
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    final id = _flightId;
    if (_metaFile != null && await _metaFile!.exists()) {
      try {
        final existing =
            jsonDecode(await _metaFile!.readAsString()) as Map<String, dynamic>;
        existing['endedAt'] = DateTime.now().toUtc().toIso8601String();
        existing['sampleCount'] = _sampleCount;
        await _metaFile!.writeAsString(
          const JsonEncoder.withIndent('  ').convert(existing),
        );
      } catch (_) {}
    }
    _active = false;
    _flightId = null;
    _sampleCount = 0;
    return id;
  }

  Future<List<Directory>> listFlights() async {
    final root = await _flightsRoot();
    final kids = await root.list().where((e) => e is Directory).toList();
    kids.sort((a, b) => b.path.compareTo(a.path));
    return kids.cast<Directory>();
  }

  /// Zip a flight folder for share/export. Returns zip path.
  Future<File> exportFlightZip(String flightId) async {
    final root = await _flightsRoot();
    final dir = Directory('${root.path}/$flightId');
    if (!await dir.exists()) {
      throw StateError('Flight not found: $flightId');
    }
    final archive = Archive();
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final name = entity.path.substring(dir.path.length + 1);
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    final zipBytes = ZipEncoder().encode(archive);
    final out = File('${root.path}/$flightId.zip');
    await out.writeAsBytes(zipBytes, flush: true);
    return out;
  }

  /// Latest completed or current flight id for quick export.
  Future<String?> latestFlightId() async {
    if (_flightId != null) return _flightId;
    final flights = await listFlights();
    if (flights.isEmpty) return null;
    return flights.first.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last;
  }
}
