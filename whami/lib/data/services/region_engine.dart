import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'region_pack_storage.dart';
import '../models/region_pack.dart';
import '../models/region_metadata.dart';
import 'landmark_database.dart';
import 'mbtiles_tile_server.dart';

class RegionEngine {
  final RegionPackStorage storage;
  final LandmarkDatabase landmarkDatabase;
  final MBTilesTileServer tileServer = MBTilesTileServer();

  RegionPack? _activeRegionPack;

  String? get activePackId => _activeRegionPack?.id;
  RegionPack? get activeRegionPack => _activeRegionPack;

  RegionEngine({required this.storage, required this.landmarkDatabase}) {
    tileServer.start();
  }

  /// Safely installs a local `.whami` ZIP file.
  /// Extracts to temp, verifies contents, moves to production, registers, and auto-activates.
  Future<void> installLocalPack(String zipFilePath) async {
    final zipFile = File(zipFilePath);
    if (!await zipFile.exists()) {
      throw FileSystemException('Pack file not found', zipFilePath);
    }

    final tempDir = await storage.getTempDirectory();

    for (final entity in tempDir.listSync()) {
      debugPrint("Found: ${entity.path}");
    }

    // Clean temp dir before starting
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    await tempDir.create(recursive: true);

    try {
      debugPrint(
        '[RegionEngine] Extracting $zipFilePath to ${tempDir.path}...',
      );
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File('${tempDir.path}/$filename');
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          await Directory('${tempDir.path}/$filename').create(recursive: true);
        }
      }

      // Verify metadata
      final metaFile = File('${tempDir.path}/metadata.json');
      if (!await metaFile.exists()) {
        throw const FormatException(
          'metadata.json is missing from pack archive.',
        );
      }

      final metaContent = await metaFile.readAsString();
      final metaJson = jsonDecode(metaContent) as Map<String, dynamic>;
      final meta = RegionMetadata.fromJson(metaJson);

      // Verify essential files
      final dbFile = File('${tempDir.path}/landmarks.sqlite');
      if (!await dbFile.exists()) {
        throw const FormatException(
          'landmarks.sqlite is missing from pack archive.',
        );
      }

      final mapFile = File('${tempDir.path}/map.mbtiles');
      if (!await mapFile.exists()) {
        throw const FormatException(
          'map.mbtiles is missing from pack archive.',
        );
      }

      // Everything verified. Move to final directory.
      final finalDir = await storage.getPackDirectory(
        meta.id,
        country: meta.country,
        regionName: meta.name,
      );

      // // If an old version exists, delete it first
      // if (await finalDir.exists()) {
      //   await finalDir.delete(recursive: true);
      // }

      // If this pack is currently active, release all resources first.
      if (isPackActive(meta.id)) {
        await deactivatePack();
      }

      // Remove previous installation if it exists.
      if (await finalDir.exists()) {
        await finalDir.delete(recursive: true);
      }

      // Ensure parent exists
      await finalDir.parent.create(recursive: true);

      // Rename temp to final (this is an atomic move on the same filesystem)
      await tempDir.rename(finalDir.path);

      debugPrint(
        '[RegionEngine] Successfully installed ${meta.name} (${meta.id})',
      );

      // Auto-activate
      await activatePack(meta.id);
    } catch (e) {
      debugPrint('[RegionEngine] Installation failed: $e');
      // Clean up temp dir on failure
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  /// Activate a pack: Load its SQLite database connection and read metadata.
  Future<void> activatePack(String packId) async {
    if (_activeRegionPack?.id == packId) return; // Already active

    // 1. Deactivate current pack first to clean up memory
    await deactivatePack();

    // 2. Read metadata
    final meta = await storage.getPackMetadata(packId);
    if (meta == null) {
      throw StateError(
        'Cannot activate pack $packId: Metadata missing on disk.',
      );
    }

    // 3. Open landmarks.sqlite connection
    final dbPath = await storage.getLandmarksDbPath(packId);
    if (dbPath == null) {
      throw StateError(
        'Cannot activate pack $packId: landmarks.sqlite missing on disk.',
      );
    }

    await landmarkDatabase.open(dbPath);

    // // 4. Open map.mbtiles connection on the local tile server
    // final mapPath = await storage.getMBTilesPath(packId);
    // await tileServer.setActiveMBTiles(mapPath);

    // 4. Open map.mbtiles connection on the local tile server
    final mapPath = await storage.getMBTilesPath(packId);

    if (mapPath == null) {
      throw StateError(
        'Cannot activate pack $packId: map.mbtiles missing on disk.',
      );
    }

    debugPrint('[RegionEngine] Loading MBTiles: $mapPath');

    await tileServer.setActiveMBTiles(mapPath);

    final packDir = await storage.getPackDirectory(packId);
    _activeRegionPack = RegionPack.fromMetadata(meta, packDir.path);

    debugPrint('[RegionEngine] Activated pack: $packId (${meta.name})');
  }

  /// Deactivate currently active pack: Close SQLite and release metadata
  Future<void> deactivatePack() async {
    if (_activeRegionPack == null) return;

    debugPrint('[RegionEngine] Deactivating pack: ${_activeRegionPack!.id}');

    // Close SQLite db connection
    await landmarkDatabase.close();

    // Close map.mbtiles connection on local tile server
    await tileServer.setActiveMBTiles(null);

    _activeRegionPack = null;
  }

  /// Verify integrity of a pack on disk
  Future<bool> verifyPack(String packId) async {
    final downloaded = await storage.isPackDownloaded(packId);
    if (!downloaded) return false;

    final meta = await storage.getPackMetadata(packId);
    if (meta == null) return false;

    final dbPath = await storage.getLandmarksDbPath(packId);
    return dbPath != null;
  }

  bool isPackActive(String packId) => _activeRegionPack?.id == packId;
}
