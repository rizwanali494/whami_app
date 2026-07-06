import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import '../models/region_pack.dart';
import '../models/region_metadata.dart';
import '../models/landmark.dart';
import 'region_pack_storage.dart';
import 'landmark_database.dart';

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

class DownloadEngine {
  final RegionPackStorage storage;
  final _controller = StreamController<DownloadProgress>.broadcast();

  Stream<DownloadProgress> get progressStream => _controller.stream;

  DownloadEngine({required this.storage});

  /// Starts downloading/generating a region pack
  Future<void> startDownload(RegionPack pack) async {
    final packId = pack.id;
    _controller.add(DownloadProgress(packId: packId, progress: 0.0, status: 'downloading'));

    try {
      // 1. Check if the pack is a real CDN URL or a catalog demo.
      // For this refactor, we simulate the network download but write
      // real SQLite databases and metadata.json to disk under packs/
      // so the offline maps and RTree spatial indexes work locally.
      
      final totalSteps = 10;
      for (int i = 1; i <= totalSteps; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        _controller.add(DownloadProgress(
          packId: packId,
          progress: (i / totalSteps) * 0.7, // 70% for download phase
          status: 'downloading',
        ));
      }

      // 2. Simulating checksum validation phase
      _controller.add(DownloadProgress(packId: packId, progress: 0.75, status: 'downloading'));
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Calculate a dummy SHA-256 for integrity verification check
      final bytes = utf8.encode(packId);
      final sha = sha256.convert(bytes).toString();

      // 3. Simulating unpacking and structure validation phase
      _controller.add(DownloadProgress(packId: packId, progress: 0.85, status: 'downloading'));

      // Create directories
      final packDir = await storage.getPackDirectory(packId, country: pack.location, regionName: pack.name);
      if (!await packDir.exists()) {
        await packDir.create(recursive: true);
      }

      // Generate rich metadata object
      final now = DateTime.now();
      final meta = RegionMetadata(
        id: pack.id,
        name: pack.name,
        country: pack.location,
        versions: RegionVersions(
          engine: '2.0.0',
          schema: '1.4.0',
          data: now.toIso8601String().substring(0, 10).replaceAll('-', '.'),
          map: '1.0.0',
          landmarks: '1.1.0',
          magnetic: '1.0.0',
        ),
        bounds: _getBounds(packId),
        checksum: sha,
        sizeBytes: 15 * 1024 * 1024, // arbitrary 15MB representation
        packType: pack.type,
        trustScore: pack.trustScore,
      );

      // Write metadata.json
      await storage.savePackMetadata(packId, meta);

      // Create landmarks.sqlite and populate with RTree virtual index
      final dbPath = '${packDir.path}/landmarks.sqlite';
      final ldb = LandmarkDatabase();
      await ldb.open(dbPath);

      // Insert pre-baked landmarks for this region to test unified searches
      final demoLandmarks = _getDemoLandmarks(packId, pack.location, pack.name);
      for (final l in demoLandmarks) {
        await ldb.insertLandmark(l);
      }
      await ldb.close();

      // Save registry entry pointing to relative subfolder path
      await storage.registerPackDownloaded(
        packId, 
        country: pack.location, 
        regionName: pack.name
      );

      _controller.add(DownloadProgress(packId: packId, progress: 1.0, status: 'completed'));
    } catch (e) {
      debugPrint('[DownloadEngine] Download/verification failed for $packId: $e');
      _controller.add(DownloadProgress(
        packId: packId,
        progress: 0.0,
        status: 'failed',
        error: e.toString(),
      ));
    }
  }

  /// Real Archive Download/Integrity Flow (Architected for production hookup)
  Future<void> downloadRealPack(String url, String expectedChecksum) async {
    // 1. Download bytes via HTTP
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw HttpException('Failed to fetch pack. HTTP: ${response.statusCode}');
    }

    // 2. Validate Checksum
    final bytes = response.bodyBytes;
    final fileHash = sha256.convert(bytes).toString();
    if (fileHash != expectedChecksum) {
      throw const OSError('Checksum verification failed. File corrupt or tampered.');
    }

    // 3. Extract Zip archive using archive package
    final archive = ZipDecoder().decodeBytes(bytes);
    final docDir = await storage.getPackDirectory('temp_unpack');
    
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File('${docDir.path}/$filename');
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(data);
      } else {
        await Directory('${docDir.path}/$filename').create(recursive: true);
      }
    }
  }

  List<double> _getBounds(String packId) {
    // Return approximate bounding box coordinates [minLat, minLng, maxLat, maxLng]
    switch (packId) {
      case 'sf_bay':
        return [37.6, -122.6, 38.0, -122.2];
      case 'tahoe':
        return [38.8, -120.2, 39.3, -119.8];
      case 'mountain_view':
        return [37.0, -122.3, 37.5, -121.8];
      case 'rotterdam':
        return [51.8, 4.0, 52.1, 4.8];
      case 'coastal_demo':
        return [32.5, -117.4, 32.9, -117.0];
      default:
        // Default small square bounds around center
        return [37.7, -122.5, 37.9, -122.3];
    }
  }

  List<Landmark> _getDemoLandmarks(String packId, String country, String regionName) {
    // Pre-seed some dummy landmarks matching the legacy ones but with new full schemas
    final now = DateTime.now();
    final list = <Landmark>[];
    
    // Core landmark lists mapped from original list
    final List<(String, double, double, String)> points;
    if (packId == 'sf_bay') {
      points = [
        ('Golden Gate Bridge', 37.8199, -122.4786, 'bridge'),
        ('Bay Bridge West Tower', 37.7983, -122.3778, 'bridge'),
        ('Alcatraz Island Light', 37.8270, -122.4230, 'coastline'),
        ('SF Ferry Building Tower', 37.7955, -122.3937, 'building'),
        ('Oakland Port Gantry', 37.7990, -122.2778, 'harbor'),
        ('Fort Point Historic Site', 37.8076, -122.4655, 'building'),
        ('Angel Island Summit', 37.8271, -122.3765, 'island'),
        ('Cliff House Lookout', 37.7693, -122.4781, 'harbor'),
      ];
    } else if (packId == 'tahoe') {
      points = [
        ('Emerald Bay Tea House', 38.9619, -120.0982, 'harbor'),
        ('Rubicon Point Lighthouse', 38.9912, -120.0945, 'coastline'),
        ('Sand Harbor Overlook', 39.1983, -119.9312, 'mountain'),
        ('Cave Rock Tunnel Mount', 39.0435, -119.9482, 'mountain'),
        ('Tahoe City Marina Pier', 39.1712, -120.1384, 'harbor'),
        ('Zephyr Cove Spit', 39.0012, -119.9534, 'harbor'),
        ('Fannette Island Peak', 38.9614, -120.0954, 'island'),
      ];
    } else if (packId == 'mountain_view') {
      points = [
        ('Castle Rock Peak', 37.2309, -122.1152, 'mountain'),
        ('Black Mountain Lookout Tower', 37.3183, -122.1524, 'tower'),
        ('Moffett Hangar One Dome', 37.4168, -122.0492, 'tower'),
        ('Lick Observatory Dome', 37.3414, -121.6429, 'tower'),
        ('Skyline Boulevard Summit', 37.2624, -122.1485, 'mountain'),
        ('San Andreas Fault Ridge', 37.2912, -122.1245, 'mountain'),
      ];
    } else if (packId == 'rotterdam') {
      points = [
        ('Euromast Tower', 51.9054, 4.4666, 'tower'),
        ('Erasmus Bridge North Pylon', 51.9094, 4.4872, 'bridge'),
        ('Maeslantkering Gate East', 51.9582, 4.1645, 'harbor'),
        ('Port of Rotterdam Signal', 51.9489, 4.1192, 'coastline'),
        ('Willemswerf Building Spire', 51.9189, 4.4912, 'building'),
        ('Hotel New York Cupola', 51.9042, 4.4842, 'building'),
        ('WaalsHaven Crane Hub', 51.8912, 4.4345, 'harbor'),
      ];
    } else if (packId == 'coastal_demo') {
      points = [
        ('Point Loma Lighthouse', 32.6654, -117.2425, 'coastline'),
        ('Coronado Bridge Center Arch', 32.6908, -117.1524, 'bridge'),
        ('USS Midway Flight Deck', 32.7138, -117.1751, 'building'),
        ('Star of India Mast', 32.7208, -117.1741, 'tower'),
        ('Hotel del Coronado Dome', 32.6808, -117.1782, 'building'),
        ('North Island Control Tower', 32.6985, -117.2152, 'tower'),
        ('Shelter Island Friendship Bell', 32.7152, -117.2285, 'harbor'),
      ];
    } else {
      // Default fallback landmark for the 45+ other region packs
      points = [
        ('Regional Baseline Beacon', 37.8, -122.4, 'tower'),
      ];
    }

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      list.add(Landmark(
        id: '${packId}_l_$i',
        name: p.$1,
        category: p.$4,
        latitude: p.$2,
        longitude: p.$3,
        altitude: 15.0 + (i * 5),
        description: 'Physical navigational baseline for ${p.$1} located in $regionName, $country.',
        verified: true,
        confidence: 0.85 + (i * 0.02).clamp(0.0, 0.14),
        imagePath: null,
        source: LandmarkSource.system,
        isFavorite: false,
        createdAt: now,
        updatedAt: now,
      ));
    }

    return list;
  }

  void dispose() {
    _controller.close();
  }
}
