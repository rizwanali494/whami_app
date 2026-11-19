import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:WHAMI/data/services/geometry_snap_service.dart';
import 'package:WHAMI/data/services/evidence_pack_exporter.dart';
import 'package:WHAMI/data/services/trust_timeline_recorder.dart';
import 'package:WHAMI/data/models/trust_timeline_sample.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('coastline snap near Embarcadero returns lock point', () async {
    final svc = GeometrySnapService();
    final snap = await svc.snapCoastline(37.7955, -122.3937);
    expect(snap, isNotNull);
    expect(snap!.kind, 'coastline');
    expect(snap.label.toLowerCase(), contains('coastline'));
    expect(snap.distanceM, lessThan(2500));
  });

  test('runway snap near SFO returns demo runway', () async {
    final svc = GeometrySnapService();
    final snap = await svc.snapRunway(37.6200, -122.3700);
    expect(snap, isNotNull);
    expect(snap!.kind, 'runway');
    expect(snap.label.toLowerCase(), contains('runway'));
  });

  test('evidence pack builds zip from timeline', () async {
    final temp = await Directory.systemTemp.createTemp('whami_ev_');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final rec = TrustTimelineRecorder();
    rec.add(
      TrustTimelineSample(
        timestamp: DateTime.now(),
        trustScore: 40,
        level: 'unreliable',
        latitude: 37.79,
        longitude: -122.40,
        uncertaintyM: 500,
        gnssSuspicious: true,
        witnessScores: const {'G': 30},
        brokenWitnesses: const ['GPS'],
        gpsClaimLatitude: 37.80,
        gpsClaimLongitude: -122.45,
        trustedLatitude: 37.7955,
        trustedLongitude: -122.3937,
        lieDistanceM: 1200,
      ),
    );
    final exporter = EvidencePackExporter();
    final zip = await exporter.export(
      timeline: rec,
      lockName: 'Ferry Building',
      gnssSuspicious: true,
      lieDistanceM: 1200,
    );
    expect(await zip.exists(), isTrue);
    expect(zip.path.endsWith('.zip'), isTrue);
    expect(await zip.length(), greaterThan(50));
  });
}
