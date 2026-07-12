import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../models/region_pack.dart';
import 'region_pack_storage.dart';
import 'region_engine.dart';

class DownloadProgress {
  final String packId;
  final double progress; // 0.0 to 1.0
  final String status; // downloading, installing, completed, failed
  final String? error;
  final int bytesReceived;
  final int totalBytes;
  final double bytesPerSecond;

  const DownloadProgress({
    required this.packId,
    required this.progress,
    required this.status,
    this.error,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0.0,
  });
}

class _CancelledException implements Exception {}

class DownloadEngine {
  final RegionPackStorage storage;
  final _controller = StreamController<DownloadProgress>.broadcast();

  // Lets cancelDownload() interrupt an in-flight download instantly rather
  // than waiting for the current network chunk/stream to finish on its own.
  final Map<String, void Function()> _activeCancellers = {};

  Stream<DownloadProgress> get progressStream => _controller.stream;

  DownloadEngine({required this.storage});

  Future<File> _partFile(String packId) async {
    final stagingDir = await storage.getDownloadStagingDirectory();
    return File('${stagingDir.path}/$packId.whami.part');
  }

  /// Downloads a region pack from [pack.downloadUrl], resuming a previous
  /// partial download if one exists, verifies its checksum, then extracts
  /// and installs it via [RegionEngine.extractAndInstall].
  Future<void> startDownload(RegionPack pack) async {
    final packId = pack.id;
    final url = pack.downloadUrl;
    final expectedChecksum = pack.checksum;

    if (url == null || url.isEmpty || expectedChecksum == null || expectedChecksum.isEmpty) {
      _controller.add(DownloadProgress(
        packId: packId,
        progress: 0.0,
        status: 'failed',
        error: 'No download source configured for this pack.',
      ));
      return;
    }

    final partFile = await _partFile(packId);
    final client = http.Client();
    StreamSubscription<List<int>>? subscription;
    final completer = Completer<void>();
    IOSink? sink;

    _activeCancellers[packId] = () {
      subscription?.cancel();
      if (!completer.isCompleted) completer.completeError(_CancelledException());
    };

    try {
      int downloaded = await partFile.exists() ? await partFile.length() : 0;

      final request = http.Request('GET', Uri.parse(url));
      if (downloaded > 0) {
        request.headers['Range'] = 'bytes=$downloaded-';
      }

      final response = await client.send(request);

      // If the server doesn't honor Range (200 instead of 206), restart clean.
      final resuming = downloaded > 0 && response.statusCode == 206;
      if (!resuming) {
        downloaded = 0;
        if (await partFile.exists()) {
          await partFile.delete();
        }
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException('Failed to fetch pack. HTTP: ${response.statusCode}');
      }

      final total = (response.contentLength ?? 0) + downloaded;
      sink = partFile.openWrite(mode: resuming ? FileMode.append : FileMode.write);

      final stopwatch = Stopwatch()..start();
      var lastEmitMs = 0;
      var bytesAtLastEmit = downloaded;

      subscription = response.stream.listen(
        (chunk) {
          sink!.add(chunk);
          downloaded += chunk.length;

          // Throttle progress/speed emission so fast connections don't
          // flood the UI with an event per chunk.
          final nowMs = stopwatch.elapsedMilliseconds;
          final elapsedMs = nowMs - lastEmitMs;
          if (elapsedMs >= 200) {
            final speed = elapsedMs > 0
                ? (downloaded - bytesAtLastEmit) * 1000 / elapsedMs
                : 0.0;
            _controller.add(DownloadProgress(
              packId: packId,
              progress: total > 0 ? (downloaded / total).clamp(0.0, 1.0) : 0.0,
              status: 'downloading',
              bytesReceived: downloaded,
              totalBytes: total,
              bytesPerSecond: speed,
            ));
            lastEmitMs = nowMs;
            bytesAtLastEmit = downloaded;
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
        cancelOnError: true,
      );

      await completer.future;
      await sink.close();
      sink = null;

      // Verify checksum
      final bytes = await partFile.readAsBytes();
      final actualHash = sha256.convert(bytes).toString();
      if (actualHash != expectedChecksum) {
        // Corrupt/tampered file: delete so a retry starts fresh rather than
        // resuming from bad data.
        await partFile.delete();
        throw const FormatException('Checksum verification failed. File corrupt or tampered.');
      }

      _controller.add(DownloadProgress(
        packId: packId,
        progress: 1.0,
        status: 'installing',
        bytesReceived: downloaded,
        totalBytes: total,
      ));

      await RegionEngine.extractAndInstall(storage, bytes);
      await partFile.delete();

      _controller.add(DownloadProgress(
        packId: packId,
        progress: 1.0,
        status: 'completed',
        bytesReceived: downloaded,
        totalBytes: total,
      ));
    } catch (e) {
      // Always flush/close so bytes received before an error are persisted
      // to disk — the .part file must reflect what was actually written for
      // a subsequent resume to work correctly.
      await sink?.close();

      if (e is _CancelledException) {
        // cancelDownload() already emitted the user-facing "Cancelled"
        // event and owns deleting the partial file — nothing more to do.
        return;
      }

      // Network hiccups otherwise leave the .part file in place so a retry
      // can resume; only checksum failures delete it (handled above).
      debugPrint('[DownloadEngine] Download failed for $packId: $e');
      _controller.add(DownloadProgress(
        packId: packId,
        progress: 0.0,
        status: 'failed',
        error: e.toString(),
      ));
    } finally {
      client.close();
      _activeCancellers.remove(packId);
    }
  }

  /// Cancels an in-progress download instantly (interrupts the network
  /// stream rather than waiting for it to finish) and discards any partial
  /// data.
  Future<void> cancelDownload(String packId) async {
    _activeCancellers[packId]?.call();

    final partFile = await _partFile(packId);
    if (await partFile.exists()) {
      await partFile.delete();
    }
    _controller.add(DownloadProgress(
      packId: packId,
      progress: 0.0,
      status: 'failed',
      error: 'Cancelled',
    ));
  }

  void dispose() {
    _controller.close();
  }
}
