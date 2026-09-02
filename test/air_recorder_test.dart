import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:WHAMI/data/services/air_research_recorder.dart';
import 'package:WHAMI/features/whami_air/air_trust.dart';

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

  late Directory temp;
  late AirResearchRecorder recorder;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('whami_air_rec_');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
    recorder = AirResearchRecorder();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('recorder writes NDJSON and exports zip', () async {
    await recorder.startFlight(meta: {'test': true});
    expect(recorder.isRecording, isTrue);

    const snap = AirTrustSnapshot(
      band: AirTrustBand.green,
      positionTrust: 80,
      confidenceRadiusM: 40,
      gnssSuspicious: false,
      gnssUnavailable: false,
      magneticAgreement: 85,
      baroConsistency: 80,
      celestialAgreement: 70,
      wmmResidualUt: 1.5,
      baroGpsAltDeltaM: 12,
      sourceHierarchy: ['G:90', 'M:85'],
      advisoryMessage: 'ok',
    );
    await recorder.appendFromSensors(air: snap, kpIndex: 3);
    await recorder.appendFromSensors(air: snap, kpIndex: 3);
    expect(recorder.sampleCount, 2);

    final id = await recorder.stopFlight();
    expect(id, isNotNull);
    expect(recorder.isRecording, isFalse);

    final zip = await recorder.exportFlightZip(id!);
    expect(await zip.exists(), isTrue);
    expect(zip.path.endsWith('.zip'), isTrue);
  });
}
