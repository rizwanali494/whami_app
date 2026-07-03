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
    // 50+ Global regions catalog (copied from WhamiRepository baseline for legacy UI rendering)
    final defaultPacks = [
      RegionPack(
        id: 'sf_bay',
        name: 'SF Bay Harbor Pack',
        type: 'Marine',
        size: '142 MB',
        status: 'available',
        location: 'San Francisco Bay, CA, USA',
        lastUpdated: 'Jun 10, 2026',
        includedData: const ['Land maps', 'Marine data', 'Landmarks (847)', 'Magnetic baseline'],
        trustScore: 94,
      ),
      RegionPack(
        id: 'tahoe',
        name: 'Lake Tahoe Pack',
        type: 'Lake',
        size: '88 MB',
        status: 'available',
        location: 'Lake Tahoe, CA/NV, USA',
        lastUpdated: 'May 28, 2026',
        includedData: const ['Land maps', 'Lake data', 'Landmarks (312)', 'Magnetic baseline'],
        trustScore: 89,
      ),
      RegionPack(
        id: 'mountain_view',
        name: 'Santa Cruz Mountains Hiking Pack',
        type: 'Hiking',
        size: '64 MB',
        status: 'available',
        location: 'Santa Cruz Mountains, CA, USA',
        lastUpdated: 'Mar 15, 2026',
        includedData: const ['Land maps', 'Trail data', 'Landmarks (198)', 'Magnetic baseline'],
        trustScore: 76,
      ),
      RegionPack(
        id: 'rotterdam',
        name: 'Rotterdam Harbor Pack',
        type: 'Marine',
        size: '210 MB',
        status: 'available',
        location: 'Port of Rotterdam, Netherlands',
        lastUpdated: 'Jun 1, 2026',
        includedData: const ['Land maps', 'Marine data', 'Landmarks (1204)', 'Magnetic baseline'],
        trustScore: 97,
      ),
      RegionPack(
        id: 'coastal_demo',
        name: 'Coastal Emergency Demo Pack',
        type: 'Urban',
        size: '38 MB',
        status: 'available',
        location: 'Demo — Coastal Area',
        lastUpdated: 'Jun 14, 2026',
        includedData: const ['Land maps', 'Coastal data', 'Landmarks (56)', 'Magnetic baseline'],
        trustScore: 82,
      ),
    ];

    _packs.clear();
    _packs.addAll(defaultPacks);

    // Sync downloaded statuses on load
    for (int i = 0; i < _packs.length; i++) {
      final isDownloaded = await regionEngine.storage.isPackDownloaded(_packs[i].id);
      if (isDownloaded) {
        final meta = await regionEngine.storage.getPackMetadata(_packs[i].id);
        _packs[i] = _packs[i].copyWith(
          status: 'downloaded',
          metadata: meta,
        );
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
