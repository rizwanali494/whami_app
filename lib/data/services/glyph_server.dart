import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serves the bundled Noto Sans glyph PBF files locally, matching the
/// `{fontstack}/{range}.pbf` URL pattern MapLibre GL's style `glyphs` field
/// expects. Runs independently of any region pack — map labels need glyphs
/// regardless of connectivity or pack activation state, so this starts once
/// at app boot and stays up for the app's lifetime.
class GlyphServer {
  HttpServer? _server;

  String get baseUrl =>
      _server != null ? 'http://127.0.0.1:${_server!.port}' : '';

  Future<void> start() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('[GlyphServer] Running on $baseUrl');

      _server!.listen((HttpRequest request) async {
        try {
          await _handleRequest(request);
        } catch (e) {
          debugPrint('[GlyphServer] Error handling request: $e');
          request.response.statusCode = HttpStatus.internalServerError;
          try {
            await request.response.close();
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('[GlyphServer] Failed to start server: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    // Request path looks like /Noto Sans Regular/0-255.pbf (URL-decoded);
    // bundled assets live at assets/glyphs/Noto Sans Regular/0-255.pbf.
    final decodedPath = Uri.decodeComponent(request.uri.path);
    final assetPath = 'assets/glyphs$decodedPath';

    try {
      final data = await rootBundle.load(assetPath);
      response.headers.contentType = ContentType.parse(
        'application/x-protobuf',
      );
      response.headers.set('Cache-Control', 'max-age=86400');
      response.headers.set('Access-Control-Allow-Origin', '*');
      response.add(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      await response.close();
    } catch (e) {
      debugPrint('[GlyphServer] Not found: $assetPath ($e)');
      response.statusCode = HttpStatus.notFound;
      await response.close();
    }
  }

  Future<void> stop() async {
    if (_server != null) {
      try {
        await _server!.close(force: true);
      } catch (_) {}
      _server = null;
    }
  }
}
