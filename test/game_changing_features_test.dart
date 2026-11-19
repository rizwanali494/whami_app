import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:WHAMI/core/trust/trust_summary.dart';
import 'package:WHAMI/data/models/position_opinion.dart';
import 'package:WHAMI/data/models/trust_timeline_sample.dart';
import 'package:WHAMI/data/services/evidence_pack_exporter.dart';
import 'package:WHAMI/data/services/geometry_snap_service.dart';
import 'package:WHAMI/data/services/spoof_heatmap_service.dart';
import 'package:WHAMI/data/services/truth_mode_service.dart';
import 'package:WHAMI/data/services/trust_copilot.dart';
import 'package:WHAMI/data/services/trust_timeline_recorder.dart';
import 'package:WHAMI/data/services/witness_mesh_service.dart';

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

  group('TruthModeService', () {
    test('records dual trails and lie episodes', () {
      final tm = TruthModeService();
      tm.record(
        gnssSuspicious: true,
        trustedLat: -35.81,
        trustedLng: 145.60,
        claimLat: -35.82,
        claimLng: 145.70,
        lieDistanceM: 9000,
      );
      expect(tm.trustedTrail, isNotEmpty);
      expect(tm.claimedTrail, isNotEmpty);
      expect(tm.episodes, isNotEmpty);
      expect(tm.episodes.first.isOngoing, isTrue);

      tm.record(
        gnssSuspicious: false,
        trustedLat: -35.81,
        trustedLng: 145.60,
      );
      expect(tm.episodes.first.isOngoing, isFalse);
    });
  });

  group('WitnessMeshService', () {
    test('export/import compares peers', () {
      final mesh = WitnessMeshService();
      final peerJson = mesh.exportLocal(
        deviceId: 'peer-b',
        deviceLabel: 'Bravo',
        latitude: -35.81,
        longitude: 145.60,
        trustScore: 90,
        gnssSuspicious: false,
      );
      final result = mesh.importPeer(
        peerJson,
        localLat: -35.81,
        localLng: 145.60,
        localSuspicious: false,
      );
      expect(result, isNotNull);
      expect(result!.verdict, 'agree');
    });
  });

  group('SpoofHeatmapService', () {
    test('builds cells from suspicious samples', () {
      final svc = SpoofHeatmapService();
      final cells = svc.build(
        samples: [
          TrustTimelineSample(
            timestamp: DateTime.utc(2026, 1, 1),
            trustScore: 40,
            level: 'unreliable',
            latitude: -35.81,
            longitude: 145.60,
            uncertaintyM: 50,
            gnssSuspicious: true,
            witnessScores: const {},
            brokenWitnesses: const [],
            lieDistanceM: 1200,
            gpsClaimLatitude: -35.82,
            gpsClaimLongitude: 145.61,
          ),
        ],
        includeDemo: false,
      );
      expect(cells, isNotEmpty);
      expect(cells.first.hitCount, 1);
    });
  });

  group('TrustCopilot', () {
    test('advises verify on spoof', () {
      final adv = TrustCopilot().advise(
        summary: const TrustSummary(
          level: TrustLevel.caution,
          score: 60,
          agreeingSources: 2,
          totalSources: 5,
          uncertaintyMeters: 40,
          headline: 'Verify',
          subtitle: 'x',
          explanation: 'y',
          action: 'z',
        ),
        opinions: const [
          PositionOpinion(
            id: 'gps',
            name: 'GPS',
            shortCode: 'G',
            sourceType: 'gps',
            latitude: 0,
            longitude: 0,
            confidence: 40,
            uncertaintyRadius: 40,
            colorName: 'red',
            status: 'unstable',
            description: 'jump',
          ),
        ],
        isTracking: true,
        gpsEnabled: true,
        hasGpsFix: true,
        gnssSuspicious: true,
        hasLock: false,
        hasActivePack: true,
        lieDistanceM: 800,
      );
      expect(adv?.code, 'SPOOF');
      expect(adv?.actionRoute, '/verify');
    });
  });

  group('GeometrySnapService expansion', () {
    test('road and nearest snap return demo geometry near Bayshore', () async {
      final snap = GeometrySnapService();
      final road = await snap.snap('road', 37.64, -122.39);
      expect(road, isNotNull);
      expect(road!.kind, 'road');
      final nearest = await snap.snapNearest(37.62, -122.37);
      expect(nearest, isNotNull);
    });
  });

  group('Evidence vault hash tip', () {
    test('export includes hash_chain zip', () async {
      final temp = await Directory.systemTemp.createTemp('whami_vault_');
      PathProviderPlatform.instance = _FakePathProvider(temp.path);
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final timeline = TrustTimelineRecorder();
      timeline.add(
        TrustTimelineSample(
          timestamp: DateTime.utc(2026, 1, 1, 12),
          trustScore: 80,
          level: 'reliable',
          latitude: 37.6,
          longitude: -122.4,
          uncertaintyM: 8,
          gnssSuspicious: false,
          witnessScores: const {'GPS': 90},
          brokenWitnesses: const [],
        ),
      );
      final file = await EvidencePackExporter().export(timeline: timeline);
      expect(await file.exists(), isTrue);
      expect(file.path.contains('whami-evidence-'), isTrue);
      expect(await file.length(), greaterThan(50));
    });
  });
}
