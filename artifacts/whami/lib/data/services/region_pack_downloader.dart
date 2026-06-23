import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../data/models/region_pack.dart';
import 'region_pack_storage.dart';

/// Progress event emitted during download
class DownloadProgress {
  final String packId;
  final double progress; // 0.0 to 1.0
  final String status; // downloading, completed, failed
  final String? error;

  const DownloadProgress({
    required this.packId,
    required this.progress,
    required this.status,
    this.error,
  });
}

/// Service that handles downloading and local generation of offline region packs
class RegionPackDownloader {
  final RegionPackStorage storage;
  final _controller = StreamController<DownloadProgress>.broadcast();

  Stream<DownloadProgress> get progressStream => _controller.stream;

  RegionPackDownloader({required this.storage});

  /// Starts downloading a region pack
  Future<void> startDownload(RegionPack pack) async {
    final packId = pack.id;
    _controller.add(DownloadProgress(packId: packId, progress: 0.0, status: 'downloading'));

    try {
      // Simulate real download chunks to show progress bar updates in UI
      final totalSteps = 10;
      for (int i = 1; i <= totalSteps; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        final progressVal = i / totalSteps;
        _controller.add(DownloadProgress(
          packId: packId,
          progress: progressVal * 0.9, // Generate files at 90%
          status: 'downloading',
        ));
      }

      // Generate the GeoJSON pack files
      final landmarksGeoJson = _generateLandmarks(packId);
      final magneticGeoJson = _generateMagnetic(packId);
      final seamapGeoJson = _generateSeamap(packId);

      // Save them using storage
      await storage.saveGeoJson(packId, 'landmarks.geojson', landmarksGeoJson);
      await storage.saveGeoJson(packId, 'magnetic.geojson', magneticGeoJson);
      await storage.saveGeoJson(packId, 'seamap.geojson', seamapGeoJson);

      // Create manifest metadata
      final manifest = {
        'id': pack.id,
        'name': pack.name,
        'type': pack.type,
        'size': pack.size,
        'center_latitude': _getCenter(packId).$1,
        'center_longitude': _getCenter(packId).$2,
        'downloaded_at': DateTime.now().toIso8601String(),
        'version': '2.0.0',
      };

      await storage.savePackManifest(packId, manifest);
      await storage.registerPackDownloaded(packId);

      _controller.add(DownloadProgress(packId: packId, progress: 1.0, status: 'completed'));
    } catch (e) {
      debugPrint('Failed to download/write region pack $packId: $e');
      _controller.add(DownloadProgress(
        packId: packId,
        progress: 0.0,
        status: 'failed',
        error: e.toString(),
      ));
    }
  }

  // ── Regional Data Generators (Self-Contained) ──────────────────────────────
  static const Map<String, (double, double)> _centers = {
    'sf_bay': (37.8087, -122.4098),
    'tahoe': (39.0968, -120.0324),
    'mountain_view': (37.23, -122.11),
    'rotterdam': (51.9244, 4.4777),
    'coastal_demo': (32.7157, -117.1611),
  };

  static const Map<String, List<(String, double, double, bool)>> _landmarksByRegion = {
    'sf_bay': [
      ('Golden Gate Bridge', 37.8199, -122.4786, true),
      ('Bay Bridge West Tower', 37.7983, -122.3778, true),
      ('Alcatraz Island Light', 37.8270, -122.4230, true),
      ('SF Ferry Building Tower', 37.7955, -122.3937, true),
      ('Oakland Port Gantry', 37.7990, -122.2778, false),
      ('Fort Point Historic Site', 37.8076, -122.4655, false),
      ('Angel Island Summit', 37.8271, -122.3765, true),
      ('Cliff House Lookout', 37.7693, -122.4781, false),
    ],
    'tahoe': [
      ('Emerald Bay Tea House', 38.9619, -120.0982, true),
      ('Rubicon Point Lighthouse', 38.9912, -120.0945, true),
      ('Sand Harbor Overlook', 39.1983, -119.9312, true),
      ('Cave Rock Tunnel Mount', 39.0435, -119.9482, true),
      ('Tahoe City Marina Pier', 39.1712, -120.1384, false),
      ('Zephyr Cove Spit', 39.0012, -119.9534, false),
      ('Fannette Island Peak', 38.9614, -120.0954, true),
    ],
    'mountain_view': [
      ('Castle Rock Peak', 37.2309, -122.1152, true),
      ('Black Mountain Lookout Tower', 37.3183, -122.1524, true),
      ('Moffett Hangar One Dome', 37.4168, -122.0492, true),
      ('Lick Observatory Dome', 37.3414, -121.6429, false),
      ('Skyline Boulevard Summit', 37.2624, -122.1485, false),
      ('San Andreas Fault Ridge', 37.2912, -122.1245, true),
    ],
    'rotterdam': [
      ('Euromast Tower', 51.9054, 4.4666, true),
      ('Erasmus Bridge North Pylon', 51.9094, 4.4872, true),
      ('Maeslantkering Gate East', 51.9582, 4.1645, true),
      ('Port of Rotterdam Signal', 51.9489, 4.1192, true),
      ('Willemswerf Building Spire', 51.9189, 4.4912, false),
      ('Hotel New York Cupola', 51.9042, 4.4842, true),
      ('WaalsHaven Crane Hub', 51.8912, 4.4345, false),
    ],
    'coastal_demo': [
      ('Point Loma Lighthouse', 32.6654, -117.2425, true),
      ('Coronado Bridge Center Arch', 32.6908, -117.1524, true),
      ('USS Midway Flight Deck', 32.7138, -117.1751, true),
      ('Star of India Mast', 32.7208, -117.1741, false),
      ('Hotel del Coronado Dome', 32.6808, -117.1782, true),
      ('North Island Control Tower', 32.6985, -117.2152, false),
      ('Shelter Island Friendship Bell', 32.7152, -117.2285, true),
    ],
  };

  (double, double) _getCenter(String packId) {
    return _centers[packId] ?? (37.8087, -122.4098);
  }

  /// Infer visual landmark category from the landmark name.
  /// Categories match the spec's /landmarks visual feature descriptor types.
  static String _inferLandmarkType(String name) {
    final n = name.toLowerCase();
    if (n.contains('bridge') || n.contains('pylon') || n.contains('arch')) return 'bridge';
    if (n.contains('tower') || n.contains('spire') || n.contains('cupola') ||
        n.contains('mast') || n.contains('dome') || n.contains('observatory')) return 'tower';
    if (n.contains('mountain') || n.contains('peak') || n.contains('summit') ||
        n.contains('ridge') || n.contains('fault') || n.contains('lookout') ||
        n.contains('rock') || n.contains('point') || n.contains('boulevard')) return 'mountain';
    if (n.contains('coast') || n.contains('cliff') || n.contains('shore') ||
        n.contains('spit') || n.contains('cove') || n.contains('harbor') ||
        n.contains('harbour') || n.contains('bay') || n.contains('channel') ||
        n.contains('maeslantkering') || n.contains('gate') || n.contains('waals')) return 'harbor';
    if (n.contains('island') || n.contains('alcatraz') || n.contains('angel') ||
        n.contains('fannette')) return 'island';
    if (n.contains('light') || n.contains('lighthouse')) return 'coastline';
    if (n.contains('fort') || n.contains('building') || n.contains('hotel') ||
        n.contains('midway') || n.contains('star of india') || n.contains('ferry') ||
        n.contains('hangar')) return 'building';
    return 'other';
  }

  Map<String, dynamic> _generateLandmarks(String packId) {
    final center = _getCenter(packId);
    final list = _landmarksByRegion[packId] ?? [('Central Landmark Base', center.$1, center.$2, true)];

    return {
      'type': 'FeatureCollection',
      'region': packId,
      'features': list.map((item) {
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [item.$3, item.$2],
          },
          'properties': {
            'name': item.$1,
            'landmark_type': _inferLandmarkType(item.$1),
            'confidence': 0.75 + (Random(item.$1.hashCode).nextDouble() * 0.20),
            'saved': item.$4,
          }
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _generateSeamap(String packId) {
    final center = _getCenter(packId);
    final double lat = center.$1;
    final double lng = center.$2;

    return {
      'type': 'FeatureCollection',
      'region': packId,
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [lng - 0.04, lat - 0.02],
              [lng - 0.01, lat - 0.01],
              [lng + 0.02, lat + 0.01],
              [lng + 0.05, lat + 0.02],
            ],
          },
          'properties': {'name': 'Primary Transit Channel'}
        },
        {
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [lng - 0.02, lat + 0.03],
              [lng + 0.01, lat + 0.01],
              [lng + 0.03, lat - 0.02],
            ],
          },
          'properties': {'name': 'Secondary Approach Lane'}
        }
      ]
    };
  }

  Map<String, dynamic> _generateMagnetic(String packId) {
    final center = _getCenter(packId);
    final double lat = center.$1;
    final double lng = center.$2;

    final List<Map<String, dynamic>> features = [];
    final Random rand = Random(packId.hashCode);

    for (int i = -3; i <= 3; i++) {
      for (int j = -3; j <= 3; j++) {
        final double gridLat = lat + (i * 0.012);
        final double gridLng = lng + (j * 0.016);
        final double dist = sqrt(i * i + j * j);
        final double stability = (0.95 - (dist * 0.03)).clamp(0.70, 0.99) + (rand.nextDouble() * 0.02);

        features.add({
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [gridLng, gridLat],
          },
          'properties': {
            'stability': stability,
            'reading_uT': 42.0 + (rand.nextDouble() * 12.0),
          }
        });
      }
    }

    return {
      'type': 'FeatureCollection',
      'region': packId,
      'features': features,
    };
  }

  void dispose() {
    _controller.close();
  }
}
