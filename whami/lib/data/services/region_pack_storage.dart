import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/region_pack.dart';
import '../models/region_metadata.dart';

/// Service responsible for managing offline region pack files and directories on the local filesystem
class RegionPackStorage {
  static const String _packsSubDir = 'WHAMI/packs';

  /// Get absolute path to app documents directory
  Future<String> get _appDocPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  /// Get directory reference for stored region packs (root: WHAMI/packs/)
  Future<Directory> get _packsDirectory async {
    final path = await _appDocPath;
    final dir = Directory('$path/$_packsSubDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Resolve pack folder path
  Future<Directory> getPackDirectory(
    String packId, {
    String? country,
    String? regionName,
  }) async {
    final rootDir = await _packsDirectory;
    return Directory('${rootDir.path}/$packId');
  }

  /// Get temporary staging directory for unpack operations
  Future<Directory> getTempDirectory() async {
    final rootDir = await _packsDirectory;
    final dir = Directory('${rootDir.path}/temp_unpack');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Load pack metadata/manifest from disk
  Future<RegionMetadata?> getPackMetadata(String packId) async {
    try {
      final packDir = await getPackDirectory(packId);
      final metadataFile = File('${packDir.path}/metadata.json');
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        return RegionMetadata.fromJson(
          jsonDecode(content) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint(
        '[RegionPackStorage] Failed to read metadata.json for $packId: $e',
      );
    }
    return null;
  }

  /// Save pack metadata/manifest to disk
  Future<void> savePackMetadata(String packId, RegionMetadata metadata) async {
    final packDir = await getPackDirectory(
      packId,
      country: metadata.country,
      regionName: metadata.name,
    );
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }
    final metadataFile = File('${packDir.path}/metadata.json');
    await metadataFile.writeAsString(metadata.toJsonString());
  }

  /// Checks if a region pack's files exist locally (metadata + landmarks.sqlite + map.mbtiles must exist)
  Future<bool> isPackDownloaded(String packId) async {
    try {
      final packDir = await getPackDirectory(packId);
      final metadataFile = File('${packDir.path}/metadata.json');
      final dbFile = File('${packDir.path}/landmarks.sqlite');
      final mapFile = File('${packDir.path}/map.mbtiles');
      return await metadataFile.exists() &&
          await dbFile.exists() &&
          await mapFile.exists();
    } catch (_) {
      return false;
    }
  }

  /// Get MBTiles filepath for active map engine
  Future<String?> getMBTilesPath(String packId) async {
    final packDir = await getPackDirectory(packId);
    final file = File('${packDir.path}/map.mbtiles');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  /// Get SQLite landmarks database filepath
  Future<String?> getLandmarksDbPath(String packId) async {
    final packDir = await getPackDirectory(packId);
    final file = File('${packDir.path}/landmarks.sqlite');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  /// Copy bundled region packs into the application's documents directory.
  /// This runs on every startup, but only copies packs that don't already exist.
  Future<void> discoverBundledPacks() async {
    final packsDir = await _packsDirectory;

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);

      final bundledAssets = manifest
          .listAssets()
          .where((asset) => asset.startsWith('region_packs/'))
          .toList();

      debugPrint(
        '[RegionPackStorage] Found ${bundledAssets.length} bundled assets.',
      );

      for (final asset in bundledAssets) {
        debugPrint('[RegionPackStorage] Asset: $asset');
      }

      if (bundledAssets.isEmpty) {
        debugPrint('[RegionPackStorage] No bundled region packs found.');
        return;
      }

      /// Collect unique pack folders
      final packFolders = <String>{};

      for (final asset in bundledAssets) {
        final parts = asset.split('/');

        if (parts.length >= 3) {
          packFolders.add('${parts[0]}/${parts[1]}');
        }
      }

      debugPrint(
        '[RegionPackStorage] Found ${packFolders.length} bundled packs.',
      );

      for (final folder in packFolders) {
        final packName = folder.split('/').last;

        final destination = Directory('${packsDir.path}/$packName');

        /// Skip already installed packs
        if (await destination.exists()) {
          debugPrint('[RegionPackStorage] Pack already installed: $packName');
          continue;
        }

        await destination.create(recursive: true);

        final files = bundledAssets.where(
          (asset) => asset.startsWith('$folder/'),
        );

        for (final assetPath in files) {
          final fileName = assetPath.split('/').last;

          final byteData = await rootBundle.load(assetPath);

          final outputFile = File('${destination.path}/$fileName');

          await outputFile.writeAsBytes(
            byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ),
          );

          debugPrint('[RegionPackStorage] Copied: $fileName -> $packName');
        }

        debugPrint('[RegionPackStorage] Installed bundled pack: $packName');
      }
    } catch (e, stackTrace) {
      debugPrint('[RegionPackStorage] Failed to discover bundled packs:\n$e');
      debugPrint(stackTrace.toString());
    }
  }

  /// Scans local folder and returns metadata list of downloaded packs (Filesystem as Registry)
  Future<List<RegionPack>> scanInstalledPacks() async {
    final packsList = <RegionPack>[];
    try {
      final rootDir = await _packsDirectory;
      if (!await rootDir.exists()) return packsList;

      final entities = rootDir.listSync(recursive: false);
      for (final entity in entities) {
        if (entity is Directory) {
          final packId = entity.path.split('/').last;
          if (packId == 'temp_unpack') continue; // Skip staging folder

          if (await isPackDownloaded(packId)) {
            final meta = await getPackMetadata(packId);
            debugPrint("Scanning folder: ${entity.path}");

            if (meta != null) {
              debugPrint("Found pack: ${meta.id} (${meta.name})");
              packsList.add(RegionPack.fromMetadata(meta, entity.path));
            } else {
              debugPrint("Invalid pack: $packId");
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[RegionPackStorage] Failed to scan installed packs: $e');
    }
    return packsList;
  }

  /// Deletes all files and folder of a region pack
  Future<void> deletePackFiles(String packId) async {
    try {
      final packDir = await getPackDirectory(packId);
      if (await packDir.exists()) {
        await packDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[RegionPackStorage] Error deleting pack files: $e');
    }
  }

  /// Register pack downloaded is a no-op now, filesystem is registry
  Future<void> registerPackDownloaded(
    String packId, {
    required String country,
    required String regionName,
  }) async {
    // No-op, folder existence is the registry
  }
}
