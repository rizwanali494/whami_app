import 'dart:convert';
import 'dart:math' as math;

/// A peer device's signed-ish witness snapshot for local mesh compare.
class MeshPeerSnapshot {
  final String deviceId;
  final String deviceLabel;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int trustScore;
  final bool gnssSuspicious;
  final String? lockName;

  const MeshPeerSnapshot({
    required this.deviceId,
    required this.deviceLabel,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.trustScore,
    required this.gnssSuspicious,
    this.accuracyM,
    this.lockName,
  });

  Map<String, dynamic> toJson() => {
        'v': 1,
        'kind': 'whami_mesh_peer',
        'deviceId': deviceId,
        'deviceLabel': deviceLabel,
        'ts': timestamp.toUtc().toIso8601String(),
        'lat': latitude,
        'lng': longitude,
        'accuracyM': accuracyM,
        'trustScore': trustScore,
        'gnssSuspicious': gnssSuspicious,
        'lockName': lockName,
      };

  static MeshPeerSnapshot? tryParse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['kind'] != 'whami_mesh_peer') return null;
      return MeshPeerSnapshot(
        deviceId: map['deviceId'] as String? ?? 'peer',
        deviceLabel: map['deviceLabel'] as String? ?? 'Peer device',
        timestamp: DateTime.tryParse(map['ts'] as String? ?? '') ??
            DateTime.now().toUtc(),
        latitude: (map['lat'] as num).toDouble(),
        longitude: (map['lng'] as num).toDouble(),
        accuracyM: (map['accuracyM'] as num?)?.toDouble(),
        trustScore: (map['trustScore'] as num?)?.toInt() ?? 0,
        gnssSuspicious: map['gnssSuspicious'] as bool? ?? false,
        lockName: map['lockName'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class MeshCompareResult {
  final MeshPeerSnapshot peer;
  final double separationM;
  final String verdict; // agree | diverge | peer_suspicious | local_suspicious
  final String headline;

  const MeshCompareResult({
    required this.peer,
    required this.separationM,
    required this.verdict,
    required this.headline,
  });
}

/// Multi-device Witness Mesh — share/import peer snapshots (no cloud required).
class WitnessMeshService {
  final List<MeshPeerSnapshot> peers = [];
  MeshCompareResult? lastCompare;

  String exportLocal({
    required String deviceId,
    required String deviceLabel,
    required double latitude,
    required double longitude,
    double? accuracyM,
    required int trustScore,
    required bool gnssSuspicious,
    String? lockName,
  }) {
    final snap = MeshPeerSnapshot(
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      timestamp: DateTime.now().toUtc(),
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      trustScore: trustScore,
      gnssSuspicious: gnssSuspicious,
      lockName: lockName,
    );
    return const JsonEncoder.withIndent('  ').convert(snap.toJson());
  }

  MeshCompareResult? importPeer(
    String raw, {
    required double localLat,
    required double localLng,
    required bool localSuspicious,
  }) {
    final peer = MeshPeerSnapshot.tryParse(raw);
    if (peer == null) return null;

    peers.removeWhere((p) => p.deviceId == peer.deviceId);
    peers.insert(0, peer);
    if (peers.length > 12) peers.removeRange(12, peers.length);

    final sep = _haversineM(localLat, localLng, peer.latitude, peer.longitude);
    final String verdict;
    final String headline;
    if (peer.gnssSuspicious && !localSuspicious) {
      verdict = 'peer_suspicious';
      headline = 'Peer GPS looks spoofed · you look solid';
    } else if (!peer.gnssSuspicious && localSuspicious) {
      verdict = 'local_suspicious';
      headline = 'Your GPS looks spoofed · peer looks solid';
    } else if (sep > 250) {
      verdict = 'diverge';
      headline =
          'Devices disagree by ${sep >= 1000 ? '${(sep / 1000).toStringAsFixed(1)} km' : '${sep.round()} m'}';
    } else {
      verdict = 'agree';
      headline =
          'Devices agree within ${sep < 10 ? sep.toStringAsFixed(1) : sep.round()} m';
    }

    lastCompare = MeshCompareResult(
      peer: peer,
      separationM: sep,
      verdict: verdict,
      headline: headline,
    );
    return lastCompare;
  }

  void clear() {
    peers.clear();
    lastCompare = null;
  }

  static double _haversineM(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static double _rad(double d) => d * math.pi / 180;
}
