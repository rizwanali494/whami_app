import '../models/trust_timeline_sample.dart';

/// One confrontation episode: GPS claim diverged from trusted position.
class LieEpisode {
  final DateTime startedAt;
  final DateTime? endedAt;
  final double maxLieDistanceM;
  final double claimLat;
  final double claimLng;
  final double trustedLat;
  final double trustedLng;
  final int sampleCount;

  const LieEpisode({
    required this.startedAt,
    required this.maxLieDistanceM,
    required this.claimLat,
    required this.claimLng,
    required this.trustedLat,
    required this.trustedLng,
    this.endedAt,
    this.sampleCount = 1,
  });

  bool get isOngoing => endedAt == null;

  String get distanceLabel {
    if (maxLieDistanceM >= 1000) {
      return '${(maxLieDistanceM / 1000).toStringAsFixed(1)} km';
    }
    return '${maxLieDistanceM.round()} m';
  }
}

/// Truth Mode: dual trails (GPS claim vs trusted) + lie episode timeline.
class TruthModeService {
  bool enabled = false;

  final List<Map<String, double>> claimedTrail = [];
  final List<Map<String, double>> trustedTrail = [];
  final List<LieEpisode> episodes = [];

  LieEpisode? _open;

  void clear() {
    claimedTrail.clear();
    trustedTrail.clear();
    episodes.clear();
    _open = null;
  }

  void setEnabled(bool value) {
    enabled = value;
    if (!value) {
      // Keep history for export; only stop recording new dual trails.
    }
  }

  /// Record one fusion tick. Safe to call even when Truth Mode UI is off —
  /// samples still feed lie episodes when GNSS is suspicious.
  void record({
    required bool gnssSuspicious,
    required double trustedLat,
    required double trustedLng,
    double? claimLat,
    double? claimLng,
    double? lieDistanceM,
  }) {
    trustedTrail.add({'latitude': trustedLat, 'longitude': trustedLng});
    if (trustedTrail.length > 2000) {
      trustedTrail.removeRange(0, trustedTrail.length - 2000);
    }

    if (gnssSuspicious && claimLat != null && claimLng != null) {
      claimedTrail.add({'latitude': claimLat, 'longitude': claimLng});
      if (claimedTrail.length > 2000) {
        claimedTrail.removeRange(0, claimedTrail.length - 2000);
      }
      final lie = lieDistanceM ?? 0;
      if (_open == null) {
        _open = LieEpisode(
          startedAt: DateTime.now(),
          maxLieDistanceM: lie,
          claimLat: claimLat,
          claimLng: claimLng,
          trustedLat: trustedLat,
          trustedLng: trustedLng,
        );
        episodes.insert(0, _open!);
      } else {
        final prev = _open!;
        _open = LieEpisode(
          startedAt: prev.startedAt,
          maxLieDistanceM: lie > prev.maxLieDistanceM ? lie : prev.maxLieDistanceM,
          claimLat: claimLat,
          claimLng: claimLng,
          trustedLat: trustedLat,
          trustedLng: trustedLng,
          sampleCount: prev.sampleCount + 1,
        );
        episodes[0] = _open!;
      }
      if (episodes.length > 40) {
        episodes.removeRange(40, episodes.length);
      }
    } else if (_open != null) {
      final prev = _open!;
      episodes[0] = LieEpisode(
        startedAt: prev.startedAt,
        endedAt: DateTime.now(),
        maxLieDistanceM: prev.maxLieDistanceM,
        claimLat: prev.claimLat,
        claimLng: prev.claimLng,
        trustedLat: prev.trustedLat,
        trustedLng: prev.trustedLng,
        sampleCount: prev.sampleCount,
      );
      _open = null;
    }
  }

  /// Rebuild trails/episodes from an existing trust timeline (replay/export).
  void hydrateFromTimeline(List<TrustTimelineSample> samples) {
    clear();
    for (final s in samples) {
      record(
        gnssSuspicious: s.gnssSuspicious,
        trustedLat: s.trustedLatitude ?? s.latitude,
        trustedLng: s.trustedLongitude ?? s.longitude,
        claimLat: s.gpsClaimLatitude,
        claimLng: s.gpsClaimLongitude,
        lieDistanceM: s.lieDistanceM,
      );
    }
  }
}
