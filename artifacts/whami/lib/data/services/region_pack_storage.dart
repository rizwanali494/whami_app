import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/region_pack.dart';
import '../models/region_metadata.dart';

/// Service responsible for managing offline region pack files and directories on the local filesystem
class RegionPackStorage {
  static const String _packsSubDir = 'WHAMI/packs';
  static const String _registryFilename = 'registry.json';

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

  /// Get registry file reference (located in WHAMI/packs/registry.json)
  Future<File> get _registryFile async {
    final dir = await _packsDirectory;
    final file = File('${dir.path}/$_registryFilename');
    if (!await file.exists()) {
      // Write initial empty registry
      await file.writeAsString(jsonEncode(<String, dynamic>{}));
    }
    return file;
  }

  /// Resolve pack folder path by querying the registry
  Future<Directory> getPackDirectory(String packId, {String? country, String? regionName}) async {
    final rootDir = await _packsDirectory;
    
    // Check registry first
    try {
      final registryFile = await _registryFile;
      final content = await registryFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      if (json.containsKey(packId)) {
        final val = json[packId];
        if (val is String && val != 'downloaded' && val.contains('/')) {
          return Directory('${rootDir.path}/$val');
        }
      }
    } catch (_) {}

    // Fallback/derive from arguments or default
    final c = country?.replaceAll(' ', '_') ?? 'default';
    final r = regionName?.replaceAll(' ', '_') ?? packId;
    return Directory('${rootDir.path}/$c/$r');
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
      // Resolve path
      final packDir = await getPackDirectory(packId);
      final metadataFile = File('${packDir.path}/metadata.json');
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        return RegionMetadata.fromJson(jsonDecode(content) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[RegionPackStorage] Failed to read metadata.json for $packId: $e');
    }
    return null;
  }

  /// Save pack metadata/manifest to disk
  Future<void> savePackMetadata(String packId, RegionMetadata metadata) async {
    final packDir = await getPackDirectory(
      packId, 
      country: metadata.country, 
      regionName: metadata.name
    );
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }
    final metadataFile = File('${packDir.path}/metadata.json');
    await metadataFile.writeAsString(metadata.toJsonString());
  }

  /// Checks if a region pack's files exist locally (metadata + landmarks.sqlite must exist)
  Future<bool> isPackDownloaded(String packId) async {
    try {
      final packDir = await getPackDirectory(packId);
      final metadataFile = File('${packDir.path}/metadata.json');
      final dbFile = File('${packDir.path}/landmarks.sqlite');
      return await metadataFile.exists() && await dbFile.exists();
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

  /// Scans local folder and returns metadata list of downloaded packs
  Future<List<RegionPack>> listDownloadedPacks() async {
    final packsList = <RegionPack>[];

    try {
      final registryFile = await _registryFile;
      final registryContent = await registryFile.readAsString();
      final registryJson = jsonDecode(registryContent) as Map<String, dynamic>;

      for (final packId in registryJson.keys) {
        final val = registryJson[packId];
        if (val is String) {
          final isDownloaded = await isPackDownloaded(packId);
          if (isDownloaded) {
            final meta = await getPackMetadata(packId);
            final packDir = await getPackDirectory(packId);
            if (meta != null) {
              packsList.add(RegionPack.fromMetadata(meta, packDir.path));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[RegionPackStorage] Failed to list downloaded packs: $e');
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

      // Remove from registry file
      final registryFile = await _registryFile;
      final registryContent = await registryFile.readAsString();
      final registryJson = jsonDecode(registryContent) as Map<String, dynamic>;
      registryJson.remove(packId);
      await registryFile.writeAsString(jsonEncode(registryJson));
    } catch (e) {
      debugPrint('[RegionPackStorage] Error deleting pack files: $e');
    }
  }

  /// Updates status in local registry to map packId to relative folder path
  Future<void> registerPackDownloaded(
    String packId, {
    required String country,
    required String regionName,
  }) async {
    try {
      final registryFile = await _registryFile;
      final registryContent = await registryFile.readAsString();
      final registryJson = jsonDecode(registryContent) as Map<String, dynamic>;
      
      final relativePath = '${country.replaceAll(' ', '_')}/${regionName.replaceAll(' ', '_')}';
      registryJson[packId] = relativePath;
      
      await registryFile.writeAsString(jsonEncode(registryJson));
    } catch (e) {
      debugPrint('[RegionPackStorage] Failed to register pack downloaded: $e');
    }
  }
}
