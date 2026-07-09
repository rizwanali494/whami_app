import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:whami/data/models/region_pack.dart';
import 'package:whami/data/services/download_engine.dart';
import 'package:whami/data/services/region_pack_storage.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

Uint8List _buildFixtureZip(String packId, {int mapBytesLength = 20000}) {
  final archive = Archive();

  final metadata = utf8.encode(jsonEncode({
    'id': packId,
    'name': 'Test Pack',
    'country': 'Testland',
    'packType': 'Urban',
    'trustScore': 50,
    'size': mapBytesLength,
    'bounds': {'minLat': 0.0, 'minLon': 0.0, 'maxLat': 1.0, 'maxLon': 1.0},
  }));
  archive.addFile(ArchiveFile('metadata.json', metadata.length, metadata));

  final landmarks = utf8.encode('fake sqlite bytes');
  archive.addFile(
      ArchiveFile('landmarks.sqlite', landmarks.length, landmarks));

  final map = List<int>.generate(mapBytesLength, (i) => i % 256);
  archive.addFile(ArchiveFile('map.mbtiles', map.length, map));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

RegionPack _catalogPack({
  required String id,
  required String downloadUrl,
  required String checksum,
}) {
  return RegionPack(
    id: id,
    name: 'Test Pack',
    type: 'Urban',
    size: '0 MB',
    status: 'available',
    location: 'Testland',
    lastUpdated: '',
    includedData: const [],
    trustScore: 50,
    downloadUrl: downloadUrl,
    checksum: checksum,
  );
}

/// Serves [bytes], honoring Range requests. If [abortFirstRequest] is set,
/// the first request is cut off halfway through by destroying the raw
/// socket (simulating a dropped connection), so callers can verify partial
/// downloads survive and are resumed by a subsequent request.
Future<HttpServer> _serveRangeAware(
  Uint8List bytes, {
  bool abortFirstRequest = false,
}) async {
  var firstRequest = true;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    if (rangeHeader != null) {
      final match = RegExp(r'bytes=(\d+)-').firstMatch(rangeHeader);
      if (match != null) start = int.parse(match.group(1)!);
    }
    final slice = bytes.sublist(start);

    request.response.statusCode =
        rangeHeader != null ? HttpStatus.partialContent : HttpStatus.ok;
    if (rangeHeader != null) {
      request.response.headers.set(
        'Content-Range',
        'bytes $start-${bytes.length - 1}/${bytes.length}',
      );
    }
    request.response.headers.contentLength = slice.length;

    if (abortFirstRequest && firstRequest) {
      firstRequest = false;
      final half = slice.length ~/ 2;
      // Detach the raw socket (after the headers, which declare the full
      // Content-Length, are written), write only half the body, then kill
      // the connection. Going through the raw socket bypasses dart:io's
      // HttpResponse content-length bookkeeping, which would otherwise
      // throw synchronously on the server side for an intentionally short
      // write — we want the client to observe a genuinely dropped
      // connection instead.
      final socket = await request.response.detachSocket();
      socket.add(slice.sublist(0, half));
      await socket.flush();
      socket.destroy();
      return;
    }

    request.response.add(slice);
    await request.response.close();
  });
  return server;
}

/// Subscribes before starting the download so no event is missed, and
/// returns the first terminal (completed/failed) progress event. Waiting
/// on the broadcast stream directly (instead of just inspecting the last
/// item collected via a plain listener) avoids a race where the final
/// event's delivery microtask hasn't run yet by the time the outer
/// `await startDownload(...)` in the test resumes.
Future<DownloadProgress> _runToCompletion(
  DownloadEngine engine,
  RegionPack pack,
) async {
  final terminal = engine.progressStream.firstWhere(
    (e) => e.status == 'completed' || e.status == 'failed',
  );
  await engine.startDownload(pack);
  return terminal;
}

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('whami_download_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('downloads, verifies checksum, and installs a pack', () async {
    final fixture = _buildFixtureZip('dl_test_happy');
    final checksum = sha256.convert(fixture).toString();
    final server = await _serveRangeAware(fixture);
    addTearDown(server.close);

    final storage = RegionPackStorage();
    final engine = DownloadEngine(storage: storage);
    addTearDown(engine.dispose);

    final pack = _catalogPack(
      id: 'dl_test_happy',
      downloadUrl: 'http://${server.address.address}:${server.port}/pack.whami',
      checksum: checksum,
    );

    final result = await _runToCompletion(engine, pack);

    expect(result.status, 'completed');
    expect(await storage.isPackDownloaded('dl_test_happy'), isTrue);
  });

  test('resumes an interrupted download using a Range request', () async {
    final fixture = _buildFixtureZip('dl_test_resume', mapBytesLength: 200000);
    final checksum = sha256.convert(fixture).toString();
    final server = await _serveRangeAware(fixture, abortFirstRequest: true);
    addTearDown(server.close);

    final storage = RegionPackStorage();
    final engine = DownloadEngine(storage: storage);
    addTearDown(engine.dispose);

    final pack = _catalogPack(
      id: 'dl_test_resume',
      downloadUrl: 'http://${server.address.address}:${server.port}/pack.whami',
      checksum: checksum,
    );

    // First attempt: connection dies mid-stream -> should fail but leave
    // the partial bytes on disk rather than discarding them.
    final result1 = await _runToCompletion(engine, pack);
    expect(result1.status, 'failed');

    final stagingDir = await storage.getDownloadStagingDirectory();
    final partFile = File('${stagingDir.path}/dl_test_resume.whami.part');
    expect(await partFile.exists(), isTrue);
    final partialLength = await partFile.length();
    expect(partialLength, greaterThan(0));
    expect(partialLength, lessThan(fixture.length));

    // Second attempt: should resume from partialLength (server receives a
    // Range header) and complete successfully.
    final result2 = await _runToCompletion(engine, pack);

    expect(result2.status, 'completed');
    expect(await storage.isPackDownloaded('dl_test_resume'), isTrue);
  });

  test('rejects a bad checksum and deletes the partial file', () async {
    final fixture = _buildFixtureZip('dl_test_badsum');
    final server = await _serveRangeAware(fixture);
    addTearDown(server.close);

    final storage = RegionPackStorage();
    final engine = DownloadEngine(storage: storage);
    addTearDown(engine.dispose);

    final pack = _catalogPack(
      id: 'dl_test_badsum',
      downloadUrl: 'http://${server.address.address}:${server.port}/pack.whami',
      checksum: '0' * 64,
    );

    final result = await _runToCompletion(engine, pack);

    expect(result.status, 'failed');
    expect(await storage.isPackDownloaded('dl_test_badsum'), isFalse);

    final stagingDir = await storage.getDownloadStagingDirectory();
    final partFile = File('${stagingDir.path}/dl_test_badsum.whami.part');
    expect(await partFile.exists(), isFalse);
  });
}
