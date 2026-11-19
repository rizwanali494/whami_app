import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'trust_timeline_recorder.dart';

/// Court-ready evidence pack: NDJSON + hash chain + HTML report + zip.
class EvidencePackExporter {
  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/WHAMI/evidence');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Build and write a zip under Documents/WHAMI/evidence/.
  Future<File> export({
    required TrustTimelineRecorder timeline,
    String? lockName,
    bool gnssSuspicious = false,
    double? lieDistanceM,
    List<String> brokenWitnesses = const [],
    List<Map<String, dynamic>> meshPeers = const [],
    List<Map<String, dynamic>> lieEpisodes = const [],
  }) async {
    final samples = timeline.samples;
    if (samples.isEmpty) {
      throw StateError('No timeline samples to export. Start tracking first.');
    }

    final id = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final root = await _root();
    final packDir = Directory('${root.path}/$id');
    await packDir.create(recursive: true);

    final ndjson = StringBuffer();
    var maxLie = 0.0;
    final broken = <String>{...brokenWitnesses};
    final chain = <Map<String, dynamic>>[];
    String prevHash = 'GENESIS';

    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final payload = s.toJson();
      ndjson.writeln(jsonEncode(payload));
      if (s.lieDistanceM != null && s.lieDistanceM! > maxLie) {
        maxLie = s.lieDistanceM!;
      }
      broken.addAll(s.brokenWitnesses);

      final body = jsonEncode(payload);
      final hash = sha256.convert(utf8.encode('$prevHash|$body')).toString();
      chain.add({
        'index': i,
        'prev': prevHash,
        'hash': hash,
        'ts': s.timestamp.toUtc().toIso8601String(),
      });
      prevHash = hash;
    }
    await File('${packDir.path}/samples.ndjson').writeAsString(ndjson.toString());
    await File('${packDir.path}/hash_chain.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'algorithm': 'SHA-256',
        'linking': 'prev|sampleJson',
        'tip': prevHash,
        'entries': chain,
      }),
    );

    final first = samples.first;
    final last = samples.last;
    final summary = {
      'packId': id,
      'product': 'WHAMI Evidence Vault',
      'version': 2,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'sessionStart': first.timestamp.toUtc().toIso8601String(),
      'sessionEnd': last.timestamp.toUtc().toIso8601String(),
      'sampleCount': samples.length,
      'lockName': lockName,
      'gnssSuspiciousAtExport': gnssSuspicious,
      'lieDistanceMAtExport': lieDistanceM,
      'maxLieDistanceM': math.max(maxLie, lieDistanceM ?? 0),
      'brokenWitnesses': broken.toList(),
      'finalTrustScore': last.trustScore,
      'finalLevel': last.level,
      'integrityTip': prevHash,
      'meshPeers': meshPeers,
      'lieEpisodes': lieEpisodes,
      'verify': {
        'instruction':
            'Recompute SHA-256 chain over samples.ndjson; tip must match integrityTip.',
        'qrPayload': 'whami-evidence:$id:$prevHash',
      },
      'note':
          'Tamper-evident location evidence — verified by the real world. Not a legal certification of position.',
    };
    await File('${packDir.path}/summary.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary),
    );

    final report = _htmlReport(summary, chain.length, prevHash);
    await File('${packDir.path}/report.html').writeAsString(report);

    final archive = Archive();
    await for (final entity in packDir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }
    final zipBytes = ZipEncoder().encode(archive);
    final out = File('${root.path}/whami-evidence-$id.zip');
    await out.writeAsBytes(zipBytes, flush: true);
    return out;
  }

  String _htmlReport(
    Map<String, dynamic> summary,
    int chainLen,
    String tip,
  ) {
    final created = summary['createdAt'];
    final score = summary['finalTrustScore'];
    final level = summary['finalLevel'];
    final samples = summary['sampleCount'];
    final maxLie = summary['maxLieDistanceM'];
    final lock = summary['lockName'] ?? '—';
    return '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>WHAMI Evidence Vault</title>
<style>
body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#0A1628;color:#F5F7FA;padding:32px;max-width:720px;margin:auto}
h1{color:#4FC3F7;letter-spacing:1px;font-size:22px}
.card{background:#122033;border:1px solid #ffffff22;border-radius:14px;padding:18px;margin:14px 0}
.k{color:#78909C;font-size:11px;font-weight:700;letter-spacing:1px}
.v{font-size:18px;font-weight:800;margin-top:4px}
code{word-break:break-all;color:#4FC3F7;font-size:12px}
.note{color:#B0BEC5;font-size:13px;line-height:1.45}
</style></head><body>
<h1>WHAMI EVIDENCE VAULT</h1>
<p class="note">Tamper-evident session report. Hash tip must match recomputed chain.</p>
<div class="card"><div class="k">CREATED</div><div class="v">$created</div></div>
<div class="card"><div class="k">TRUST</div><div class="v">$score / 100 · $level</div></div>
<div class="card"><div class="k">SAMPLES · CHAIN</div><div class="v">$samples samples · $chainLen links</div></div>
<div class="card"><div class="k">MAX LIE LINE</div><div class="v">${(maxLie as num).toStringAsFixed(1)} m</div></div>
<div class="card"><div class="k">REAL-WORLD LOCK</div><div class="v">$lock</div></div>
<div class="card"><div class="k">INTEGRITY TIP (SHA-256)</div><div class="v"><code>$tip</code></div></div>
<p class="note">QR payload: <code>${summary['verify']['qrPayload']}</code></p>
</body></html>''';
  }
}
