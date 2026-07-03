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

  RegionRepository({
    required this.regionEngine,
    required this.downloadEngine,
  }) {
    _initCatalog();
    _subscribeToDownloads();
  }

  /// Initialize region pack list and cross-check filesystem status
  Future<void> _initCatalog() async {
    // 1. Discover and extract bundled assets if this is the first launch
    await regionEngine.storage.discoverBundledPacks();

    // 2. Scan the local documents directory for installed packs
    final discoveredPacks = await regionEngine.storage.scanInstalledPacks();

    _packs.clear();
    _packs.addAll(discoveredPacks);

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
            if (activePackId.isEmpty) {
              activateRegionPack(pack.id);
            }
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
        } else {
          _packs[index] = pack.copyWith(
            status: 'downloading',
            isDownloading: true,
            downloadProgress: progressEvent.progress,
            downloadStage: 'Downloading (${(progressEvent.progress * 100).toStringAsFixed(0)}%)',
          );
          notifyListeners();
        }
      }
    });
  }

  Future<void> startDownload(String packId) async {
    final pack = getRegionPackById(packId);
    if (pack != null && pack.status != 'downloaded') {
      await downloadEngine.startDownload(pack);
    }
  }

  Future<void> deleteRegionPack(String packId) async {
    await regionEngine.storage.deletePackFiles(packId);
    final index = _packs.indexWhere((p) => p.id == packId);
    if (index != -1) {
      _packs[index] = _packs[index].copyWith(status: 'available', metadata: null);
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
