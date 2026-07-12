import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/region_pack.dart';
import '../services/region_engine.dart';
import '../services/download_engine.dart';

class RegionRepository extends ChangeNotifier {
  final RegionEngine regionEngine;
  final DownloadEngine downloadEngine;

  final List<RegionPack> _packs = [];
  StreamSubscription<DownloadProgress>? _downloadSub;

  List<RegionPack> get packs => _packs;
  String get activePackId => regionEngine.activePackId ?? '';

  RegionRepository({required this.regionEngine, required this.downloadEngine}) {
    _init();
    _subscribeToDownloads();
  }

  Future<void> _init() async {
    await _initCatalog();
    await _restoreActivePack();
  }

  /// Re-activate whichever pack was active when the app was last closed, so
  /// activation survives a relaunch. Falls back to clearing the persisted
  /// id if that pack is no longer downloaded (e.g. deleted while offline).
  Future<void> _restoreActivePack() async {
    final savedId = await regionEngine.storage.getActivePackId();
    if (savedId == null) return;

    final downloaded = await regionEngine.storage.isPackDownloaded(savedId);
    if (downloaded) {
      await activateRegionPack(savedId);
    } else {
      await regionEngine.storage.setActivePackId(null);
    }
  }

  /// Initialize region pack list and cross-check filesystem status
  Future<void> _initCatalog() async {
    // 1. Discover and extract bundled assets if this is the first launch
    await regionEngine.storage.discoverBundledPacks();

    // 2. Scan the local documents directory for installed packs
    final discoveredPacks = await regionEngine.storage.scanInstalledPacks();

    // 3. Load the pack catalog (includes packs that aren't downloaded yet)
    final catalogEntries = await regionEngine.storage.loadCatalog();

    _packs.clear();
    for (final entry in catalogEntries) {
      final id = entry['id'] as String;
      RegionPack? installedPack;
      for (final p in discoveredPacks) {
        if (p.id == id) {
          installedPack = p;
          break;
        }
      }
      _packs.add(installedPack ?? RegionPack.fromCatalogEntry(entry));
    }

    // Any installed pack not present in the catalog (e.g. sideloaded .whami)
    // is still shown.
    for (final p in discoveredPacks) {
      if (!_packs.any((x) => x.id == p.id)) {
        _packs.add(p);
      }
    }

    notifyListeners();
  }

  void _subscribeToDownloads() {
    _downloadSub = downloadEngine.progressStream.listen((progressEvent) {
      final index = _packs.indexWhere((p) => p.id == progressEvent.packId);
      if (index != -1) {
        final pack = _packs[index];
        if (progressEvent.status == 'completed') {
          // Sync metadata
          regionEngine.storage.getPackMetadata(pack.id).then((meta) {
            _packs[index] = pack.copyWith(
              status: 'downloaded',
              isDownloading: false,
              downloadProgress: 1.0,
              downloadStage: 'Complete',
              metadata: meta,
            );
            // If no active pack, activate this one
            // if (activePackId.isEmpty) {
            //   activateRegionPack(pack.id);
            // }
            notifyListeners();
          });
        } else if (progressEvent.status == 'failed') {
          _packs[index] = pack.copyWith(
            status: 'available',
            isDownloading: false,
            downloadProgress: 0.0,
            downloadStage: 'Failed: ${progressEvent.error}',
          );
          notifyListeners();
        } else if (progressEvent.status == 'installing') {
          _packs[index] = pack.copyWith(
            status: 'downloading',
            isDownloading: true,
            downloadProgress: 1.0,
            downloadStage: 'Installing...',
          );
          notifyListeners();
        } else {
          _packs[index] = pack.copyWith(
            status: 'downloading',
            isDownloading: true,
            downloadProgress: progressEvent.progress,
            downloadStage: _formatDownloadStage(progressEvent),
          );
          notifyListeners();
        }
      }
    });
  }

  /// Formats a stage string like "12.3 MB / 45.6 MB · 2.1 MB/s · 27%".
  String _formatDownloadStage(DownloadProgress event) {
    final percent = (event.progress * 100).clamp(0, 100).toStringAsFixed(0);
    if (event.totalBytes <= 0) {
      return 'Downloading ($percent%)';
    }
    final received = _formatBytes(event.bytesReceived);
    final total = _formatBytes(event.totalBytes);
    final speed = _formatBytes(event.bytesPerSecond.round());
    return '$received / $total · $speed/s · $percent%';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final decimals = unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }

  Future<void> startDownload(String packId) async {
    final pack = getRegionPackById(packId);
    if (pack != null &&
        (pack.status == 'available' ||
            pack.downloadStage.startsWith('Failed:'))) {
      await downloadEngine.startDownload(pack);
    }
  }

  Future<void> cancelDownload(String packId) async {
    await downloadEngine.cancelDownload(packId);
  }

  Future<void> deleteRegionPack(String packId) async {
    await regionEngine.storage.deletePackFiles(packId);
    final index = _packs.indexWhere((p) => p.id == packId);
    if (index != -1) {
      _packs[index] = _packs[index].copyWith(
        status: 'available',
        metadata: null,
      );
    }
    if (activePackId == packId) {
      await regionEngine.deactivatePack();
    }
    notifyListeners();
  }

  Future<void> activateRegionPack(String packId) async {
    await regionEngine.activatePack(packId);
    notifyListeners();
  }

  Future<void> deactivateRegionPack() async {
    await regionEngine.deactivatePack();
    notifyListeners();
  }

  RegionPack? getRegionPackById(String id) {
    try {
      return _packs.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }
}
