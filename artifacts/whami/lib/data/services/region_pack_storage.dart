import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../data/models/region_pack.dart';

/// Service responsible for managing offline region pack files and directories on the local filesystem
class RegionPackStorage {
  static const String _packsSubDir = 'region_packs';
  static const String _registryFilename = 'registry.json';

  /// Get absolute path to app documents directory
  Future<String> get _appDocPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  /// Get directory reference for stored region packs
  Future<Directory> get _packsDirectory async {
    final path = await _appDocPath;
    final dir = Directory('$path/$_packsSubDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Get registry file reference
  Future<File> get _registryFile async {
    final dir = await _packsDirectory;
    final file = File('${dir.path}/$_registryFilename');
    if (!await file.exists()) {
      // Write initial empty registry
      await file.writeAsString(jsonEncode(<String, dynamic>{}));
    }
    return file;
  }

  /// Load pack manifest from disk
  Future<Map<String, dynamic>?> getPackManifest(String packId) async {
    final dir = await _packsDirectory;
    final manifestFile = File('${dir.path}/$packId/manifest.json');
    if (await manifestFile.exists()) {
      try {
        final content = await manifestFile.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  /// Save pack manifest to disk
  Future<void> savePackManifest(String packId, Map<String, dynamic> manifest) async {
    final dir = await _packsDirectory;
    final packDir = Directory('${dir.path}/$packId');
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }
    final manifestFile = File('${packDir.path}/manifest.json');
    await manifestFile.writeAsString(jsonEncode(manifest));
  }

  /// Checks if a region pack's files exist locally
  Future<bool> isPackDownloaded(String packId) async {
    final manifest = await getPackManifest(packId);
    if (manifest == null) return false;

    // Check if the actual geojson files exist too
    final dir = await _packsDirectory;
    final landmarks = File('${dir.path}/$packId/landmarks.geojson');
    final magnetic = File('${dir.path}/$packId/magnetic.geojson');
    final seamap = File('${dir.path}/$packId/seamap.geojson');

    return await landmarks.exists() && await magnetic.exists() && await seamap.exists();
  }

  /// Scans local folder and returns metadata list of downloaded packs
  Future<List<RegionPack>> listDownloadedPacks() async {
    final packsList = <RegionPack>[];
    final dir = await _packsDirectory;

    try {
      final registryFile = await _registryFile;
      final registryContent = await registryFile.readAsString();
      final registryJson = jsonDecode(registryContent) as Map<String, dynamic>;
      final packIds = (registryJson['packs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      // List directories, filter by registry entries
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is Directory) {
          final packId = entity.path.split('/').last;
          if (packIds.isNotEmpty && !packIds.contains(packId)) continue;
          final manifest = await getPackManifest(packId);
          if (manifest != null) {
            final isDownloaded = await isPackDownloaded(packId);
            if (isDownloaded) {
              packsList.add(RegionPack.fromManifest(manifest, entity.path));
            }
          }
        }
      }
    } catch (e) {
      // Fallback/log
    }
    return packsList;
  }

  /// Reads and parses a local GeoJSON file
  Future<Map<String, dynamic>> loadGeoJson(String packId, String filename) async {
    final dir = await _packsDirectory;
    final file = File('${dir.path}/$packId/$filename');
    if (!await file.exists()) {
      throw FileSystemException('GeoJSON pack file $filename not found for $packId');
    }
    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  /// Writes a parsed GeoJSON map structure to disk
  Future<void> saveGeoJson(String packId, String filename, Map<String, dynamic> data) async {
    final dir = await _packsDirectory;
    final packDir = Directory('${dir.path}/$packId');
    if (!await packDir.exists()) {
      await packDir.create(recursive: true);
    }
    final file = File('${packDir.path}/$filename');
    await file.writeAsString(jsonEncode(data));
  }

  /// Deletes all files and folder of a region pack
  Future<void> deletePackFiles(String packId) async {
    final dir = await _packsDirectory;
    final packDir = Directory('${dir.path}/$packId');
    if (await packDir.exists()) {
      await packDir.delete(recursive: true);
    }

    // Remove from registry file
    try {
      final registryFile = await _registryFile;
      final registryContent = await registryFile.readAsString();
      final registryJson = jsonDecode(registryContent) as Map<String, dynamic>;
      registryJson.remove(packId);
      await registryFile.writeAsString(jsonEncode(registryJson));
    } catch (e) {
      //
    }
  }

  /// Updates status in local registry
  Future<void> registerPackDownloaded(String packId) async {
    try {
      final registryFile = await _registryFile;
      final registryContent = await registryFile.readAsString();
      final registryJson = jsonDecode(registryContent) as Map<String, dynamic>;
      registryJson[packId] = 'downloaded';
      await registryFile.writeAsString(jsonEncode(registryJson));
    } catch (e) {
      //
    }
  }
}
