import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/constants/connectivity_status.dart';
import '../models/position_opinion.dart';
import '../models/sensor_status.dart';
import '../models/region_pack.dart';
import '../models/trust_event.dart';
import '../models/landmark.dart';
import '../services/sensor_manager.dart';
import '../services/region_pack_storage.dart';
import '../services/region_pack_downloader.dart';
import '../services/position_matcher.dart';
import '../services/trust_fusion_engine.dart';
import '../services/trust_event_log.dart';

class WhamiRepository extends ChangeNotifier {
  final SensorManager _sensors;
  final RegionPackStorage _storage;
  final RegionPackDownloader _downloader;
  final PositionMatcher _matcher;
  final TrustFusionEngine _fusionEngine;
  final TrustEventLog _eventLog;

  // Live navigation state
  List<PositionOpinion> _opinions = [];
  int _trustScore = 75;
  String _alertMessage = 'Positions aligned. System nominal.';
  String _alertSeverity = 'none';
  bool _isTracking = false;
  final List<Map<String, double>> _trail = [];

  // Active pack state
  String _activePackId = '';
  Map<String, dynamic>? _loadedLandmarks;
  Map<String, dynamic>? _loadedMagnetic;
  Map<String, dynamic>? _loadedSeamap;

  // Connectivity state
  ConnectivityMode _connectivityMode = ConnectivityMode.offline;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Region Packs metadata catalog
  final List<RegionPack> _packs = [];

  // Stream Subscriptions
  StreamSubscription? _sensorSub;
  StreamSubscription<DownloadProgress>? _downloadSub;

  // Map center overrides (optional)
  double? mapCenterLat;
  double? mapCenterLng;

  // Getters
  SensorManager get sensors => _sensors;
  RegionPackStorage get storage => _storage;
  RegionPackDownloader get downloader => _downloader;
  TrustEventLog get eventLog => _eventLog;

  List<PositionOpinion> get positionOpinions => _opinions;
  int get trustScore => _trustScore;
  String get alertMessage => _alertMessage;
  String get alertSeverity => _alertSeverity;
  bool get isTracking => _isTracking;
  List<Map<String, double>> get trail => _trail;
  String get activePackId => _activePackId;
  ConnectivityMode get connectivityMode => _connectivityMode;

  ConnectivityState get connectivityState {
    final activePack = getRegionPackById(_activePackId);
    final packName = activePack?.name ?? 'No Pack';
    final hasPack = activePack != null && activePack.status == 'downloaded';
    final status = hasPack ? 'Active' : 'Not Loaded';

    return ConnectivityState(
      mode: _connectivityMode,
      activePackName: packName,
      packCoverageStatus: status,
    );
  }

  WhamiRepository({
    required SensorManager sensors,
    required RegionPackStorage storage,
    required RegionPackDownloader downloader,
    required PositionMatcher matcher,
    required TrustFusionEngine fusionEngine,
    required TrustEventLog eventLog,
  }) : _sensors = sensors,
       _storage = storage,
       _downloader = downloader,
       _matcher = matcher,
       _fusionEngine = fusionEngine,
       _eventLog = eventLog {
    _initCatalog();
    _initConnectivity();
    _subscribeToDownloads();
  }

  /// Initialize region pack list and cross-check filesystem status
  Future<void> _initCatalog() async {
    // Comprehensive global region catalog
    final defaultPacks = [
      // ── North America ──────────────────────────────────────────────────────
      RegionPack(
        id: 'sf_bay',
        name: 'SF Bay Harbor Pack',
        type: 'Marine',
        size: '142 MB',
        status: 'available',
        location: 'San Francisco Bay, CA, USA',
        lastUpdated: 'Jun 10, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (847)',
          'Magnetic baseline',
          'Celestial tables',
          'Route trust history',
        ],
        trustScore: 94,
        fileSizes: const {
          'maps': '98.4 MB',
          'marine': '17.0 MB',
          'landmarks': '14.2 MB',
          'magnetic': '8.1 MB',
          'celestial': '4.3 MB',
        },
      ),
      RegionPack(
        id: 'chesapeake',
        name: 'Chesapeake Bay Pack',
        type: 'Marine',
        size: '176 MB',
        status: 'available',
        location: 'Chesapeake Bay, MD/VA, USA',
        lastUpdated: 'May 20, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (1,020)',
          'Magnetic baseline',
          'Celestial tables',
          'Route trust history',
        ],
        trustScore: 91,
        fileSizes: const {
          'maps': '112 MB',
          'marine': '28 MB',
          'landmarks': '18 MB',
          'magnetic': '9 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'gulf_mexico',
        name: 'Gulf of Mexico Pack',
        type: 'Marine',
        size: '248 MB',
        status: 'available',
        location: 'Gulf of Mexico, USA/Mexico',
        lastUpdated: 'Jun 5, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (1,580)',
          'Magnetic baseline',
          'Celestial tables',
          'Oil platform data',
        ],
        trustScore: 88,
        fileSizes: const {
          'maps': '148 MB',
          'marine': '42 MB',
          'landmarks': '24 MB',
          'magnetic': '14 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'great_lakes',
        name: 'Great Lakes Pack',
        type: 'Lake',
        size: '195 MB',
        status: 'available',
        location: 'Great Lakes, USA/Canada',
        lastUpdated: 'May 15, 2026',
        includedData: const [
          'Land maps',
          'Lake data',
          'Landmarks (940)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 92,
        fileSizes: const {
          'maps': '118 MB',
          'marine': '32 MB',
          'landmarks': '16 MB',
          'magnetic': '11 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'tahoe',
        name: 'Lake Tahoe Pack',
        type: 'Lake',
        size: '88 MB',
        status: 'available',
        location: 'Lake Tahoe, CA/NV, USA',
        lastUpdated: 'May 28, 2026',
        includedData: const [
          'Land maps',
          'Lake data',
          'Landmarks (312)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 89,
        fileSizes: const {
          'maps': '56.1 MB',
          'marine': '12.4 MB',
          'landmarks': '5.2 MB',
          'magnetic': '9.8 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'mountain_view',
        name: 'Santa Cruz Mountains Hiking Pack',
        type: 'Hiking',
        size: '64 MB',
        status: 'available',
        location: 'Santa Cruz Mountains, CA, USA',
        lastUpdated: 'Mar 15, 2026',
        includedData: const [
          'Land maps',
          'Trail data',
          'Landmarks (198)',
          'Magnetic baseline',
          'Celestial tables',
          'IMU path templates',
        ],
        trustScore: 76,
        fileSizes: const {
          'maps': '38.2 MB',
          'trails': '8.5 MB',
          'landmarks': '3.3 MB',
          'magnetic': '5.4 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'grand_canyon',
        name: 'Grand Canyon Hiking Pack',
        type: 'Hiking',
        size: '112 MB',
        status: 'available',
        location: 'Grand Canyon, AZ, USA',
        lastUpdated: 'Apr 2, 2026',
        includedData: const [
          'Land maps',
          'Trail data',
          'Landmarks (456)',
          'Magnetic baseline',
          'Celestial tables',
          'Elevation data',
        ],
        trustScore: 83,
        fileSizes: const {
          'maps': '68 MB',
          'trails': '16 MB',
          'landmarks': '8 MB',
          'magnetic': '6 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'yellowstone',
        name: 'Yellowstone National Park Pack',
        type: 'Hiking',
        size: '98 MB',
        status: 'available',
        location: 'Yellowstone, WY/MT/ID, USA',
        lastUpdated: 'May 1, 2026',
        includedData: const [
          'Land maps',
          'Trail data',
          'Landmarks (382)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 81,
        fileSizes: const {
          'maps': '58 MB',
          'trails': '14 MB',
          'landmarks': '6 MB',
          'magnetic': '7 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'new_york_harbor',
        name: 'New York Harbor Pack',
        type: 'Marine',
        size: '156 MB',
        status: 'available',
        location: 'New York Harbor, NY, USA',
        lastUpdated: 'Jun 8, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (1,104)',
          'Magnetic baseline',
          'Celestial tables',
          'Route trust history',
        ],
        trustScore: 95,
        fileSizes: const {
          'maps': '94 MB',
          'marine': '24 MB',
          'landmarks': '19 MB',
          'magnetic': '9 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'mississippi_river',
        name: 'Mississippi River Pack',
        type: 'River',
        size: '218 MB',
        status: 'available',
        location: 'Mississippi River, USA',
        lastUpdated: 'May 10, 2026',
        includedData: const [
          'Land maps',
          'River data',
          'Landmarks (720)',
          'Magnetic baseline',
          'Celestial tables',
          'River mile markers',
        ],
        trustScore: 86,
        fileSizes: const {
          'maps': '138 MB',
          'river': '34 MB',
          'landmarks': '12 MB',
          'magnetic': '10 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'vancouver_harbour',
        name: 'Vancouver Harbour Pack',
        type: 'Marine',
        size: '134 MB',
        status: 'available',
        location: 'Vancouver Harbour, BC, Canada',
        lastUpdated: 'Jun 3, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (612)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 93,
        fileSizes: const {
          'maps': '82 MB',
          'marine': '20 MB',
          'landmarks': '12 MB',
          'magnetic': '8 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'caribbean_islands',
        name: 'Caribbean Islands Pack',
        type: 'Island',
        size: '284 MB',
        status: 'available',
        location: 'Caribbean Sea, West Indies',
        lastUpdated: 'Jun 12, 2026',
        includedData: const [
          'Island maps',
          'Marine data',
          'Landmarks (1,820)',
          'Magnetic baseline',
          'Celestial tables',
          'Reef charts',
        ],
        trustScore: 87,
        fileSizes: const {
          'maps': '168 MB',
          'marine': '48 MB',
          'landmarks': '28 MB',
          'magnetic': '16 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'yucatan_coast',
        name: 'Yucatán Coast Pack',
        type: 'Marine',
        size: '122 MB',
        status: 'available',
        location: 'Yucatán Peninsula, Mexico',
        lastUpdated: 'Apr 18, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (512)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 80,
        fileSizes: const {
          'maps': '74 MB',
          'marine': '22 MB',
          'landmarks': '10 MB',
          'magnetic': '8 MB',
          'celestial': '4.5 MB',
        },
      ),

      // ── South America ──────────────────────────────────────────────────────
      RegionPack(
        id: 'amazon_river',
        name: 'Amazon River Basin Pack',
        type: 'River',
        size: '312 MB',
        status: 'available',
        location: 'Amazon River, Brazil/Peru',
        lastUpdated: 'May 22, 2026',
        includedData: const [
          'Land maps',
          'River data',
          'Landmarks (880)',
          'Magnetic baseline',
          'Celestial tables',
          'Canopy elevation',
        ],
        trustScore: 74,
        fileSizes: const {
          'maps': '198 MB',
          'river': '54 MB',
          'landmarks': '18 MB',
          'magnetic': '12 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'patagonia',
        name: 'Patagonia Hiking Pack',
        type: 'Hiking',
        size: '148 MB',
        status: 'available',
        location: 'Patagonia, Argentina/Chile',
        lastUpdated: 'Apr 5, 2026',
        includedData: const [
          'Land maps',
          'Trail data',
          'Landmarks (624)',
          'Magnetic baseline',
          'Celestial tables',
          'Glacier data',
        ],
        trustScore: 79,
        fileSizes: const {
          'maps': '92 MB',
          'trails': '22 MB',
          'landmarks': '12 MB',
          'magnetic': '8 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'rio_de_janeiro',
        name: 'Rio de Janeiro Harbor Pack',
        type: 'Marine',
        size: '108 MB',
        status: 'available',
        location: 'Guanabara Bay, Rio de Janeiro, Brazil',
        lastUpdated: 'May 30, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (478)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 85,
        fileSizes: const {
          'maps': '64 MB',
          'marine': '18 MB',
          'landmarks': '10 MB',
          'magnetic': '7 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'galapagos',
        name: 'Galápagos Islands Pack',
        type: 'Island',
        size: '94 MB',
        status: 'available',
        location: 'Galápagos Islands, Ecuador',
        lastUpdated: 'Mar 28, 2026',
        includedData: const [
          'Island maps',
          'Marine data',
          'Landmarks (304)',
          'Magnetic baseline',
          'Celestial tables',
          'Conservation zones',
        ],
        trustScore: 84,
        fileSizes: const {
          'maps': '56 MB',
          'marine': '16 MB',
          'landmarks': '6 MB',
          'magnetic': '6 MB',
          'celestial': '4.5 MB',
        },
      ),

      // ── Europe ─────────────────────────────────────────────────────────────
      RegionPack(
        id: 'rotterdam',
        name: 'Rotterdam Harbor Pack',
        type: 'Marine',
        size: '210 MB',
        status: 'available',
        location: 'Port of Rotterdam, Netherlands',
        lastUpdated: 'Jun 1, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (1,204)',
          'Magnetic baseline',
          'Celestial tables',
          'Route trust history',
          'Harbor lane data',
        ],
        trustScore: 97,
        fileSizes: const {
          'maps': '124.5 MB',
          'marine': '36.8 MB',
          'landmarks': '22.3 MB',
          'magnetic': '12.2 MB',
          'trust': '9.7 MB',
        },
      ),
      RegionPack(
        id: 'english_channel',
        name: 'English Channel Pack',
        type: 'Marine',
        size: '226 MB',
        status: 'available',
        location: 'English Channel, UK/France',
        lastUpdated: 'Jun 6, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (1,340)',
          'Magnetic baseline',
          'Celestial tables',
          'Traffic separation schemes',
        ],
        trustScore: 96,
        fileSizes: const {
          'maps': '138 MB',
          'marine': '40 MB',
          'landmarks': '24 MB',
          'magnetic': '14 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'north_sea',
        name: 'North Sea Pack',
        type: 'Marine',
        size: '264 MB',
        status: 'available',
        location: 'North Sea, Northern Europe',
        lastUpdated: 'May 28, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (1,560)',
          'Magnetic baseline',
          'Celestial tables',
          'Wind farm data',
        ],
        trustScore: 95,
        fileSizes: const {
          'maps': '164 MB',
          'marine': '46 MB',
          'landmarks': '26 MB',
          'magnetic': '16 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'mediterranean_west',
        name: 'Western Mediterranean Pack',
        type: 'Marine',
        size: '298 MB',
        status: 'available',
        location: 'Western Mediterranean Sea',
        lastUpdated: 'Jun 2, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (1,740)',
          'Magnetic baseline',
          'Celestial tables',
          'Port approach charts',
        ],
        trustScore: 93,
        fileSizes: const {
          'maps': '182 MB',
          'marine': '54 MB',
          'landmarks': '30 MB',
          'magnetic': '16 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'mediterranean_east',
        name: 'Eastern Mediterranean Pack',
        type: 'Marine',
        size: '276 MB',
        status: 'available',
        location: 'Eastern Mediterranean Sea',
        lastUpdated: 'May 25, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (1,620)',
          'Magnetic baseline',
          'Celestial tables',
          'Aegean island charts',
        ],
        trustScore: 91,
        fileSizes: const {
          'maps': '168 MB',
          'marine': '50 MB',
          'landmarks': '28 MB',
          'magnetic': '14 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'thames_estuary',
        name: 'Thames Estuary Pack',
        type: 'River',
        size: '88 MB',
        status: 'available',
        location: 'Thames Estuary, London, UK',
        lastUpdated: 'Jun 11, 2026',
        includedData: const [
          'Land maps',
          'River data',
          'Landmarks (512)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 94,
        fileSizes: const {
          'maps': '52 MB',
          'river': '16 MB',
          'landmarks': '10 MB',
          'magnetic': '6 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'alps_hiking',
        name: 'Alps Hiking Pack',
        type: 'Hiking',
        size: '186 MB',
        status: 'available',
        location: 'Alpine Region, Switzerland/Austria/France',
        lastUpdated: 'Apr 20, 2026',
        includedData: const [
          'Land maps',
          'Trail data',
          'Landmarks (982)',
          'Magnetic baseline',
          'Celestial tables',
          'Avalanche zones',
          'Mountain huts',
        ],
        trustScore: 90,
        fileSizes: const {
          'maps': '112 MB',
          'trails': '32 MB',
          'landmarks': '18 MB',
          'magnetic': '10 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'fjords_norway',
        name: 'Norwegian Fjords Pack',
        type: 'Marine',
        size: '222 MB',
        status: 'available',
        location: 'Norwegian Fjords, Norway',
        lastUpdated: 'May 5, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (1,108)',
          'Magnetic baseline',
          'Celestial tables',
          'Depth soundings',
        ],
        trustScore: 92,
        fileSizes: const {
          'maps': '134 MB',
          'marine': '38 MB',
          'landmarks': '20 MB',
          'magnetic': '12 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'baltic_sea',
        name: 'Baltic Sea Pack',
        type: 'Marine',
        size: '244 MB',
        status: 'available',
        location: 'Baltic Sea, Northern Europe',
        lastUpdated: 'May 18, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (1,450)',
          'Magnetic baseline',
          'Celestial tables',
          'Ice navigation data',
        ],
        trustScore: 90,
        fileSizes: const {
          'maps': '148 MB',
          'marine': '44 MB',
          'landmarks': '24 MB',
          'magnetic': '14 MB',
          'celestial': '4.5 MB',
        },
      ),

      // ── Africa ─────────────────────────────────────────────────────────────
      RegionPack(
        id: 'suez_canal',
        name: 'Suez Canal Pack',
        type: 'Marine',
        size: '118 MB',
        status: 'available',
        location: 'Suez Canal, Egypt',
        lastUpdated: 'Jun 7, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (480)',
          'Magnetic baseline',
          'Celestial tables',
          'Canal lane data',
        ],
        trustScore: 96,
        fileSizes: const {
          'maps': '70 MB',
          'marine': '20 MB',
          'landmarks': '10 MB',
          'magnetic': '8 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'cape_town',
        name: 'Cape Town Harbor Pack',
        type: 'Marine',
        size: '124 MB',
        status: 'available',
        location: 'Table Bay, Cape Town, South Africa',
        lastUpdated: 'May 12, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (540)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 88,
        fileSizes: const {
          'maps': '74 MB',
          'marine': '20 MB',
          'landmarks': '12 MB',
          'magnetic': '8 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'nile_river',
        name: 'Nile River Pack',
        type: 'River',
        size: '186 MB',
        status: 'available',
        location: 'Nile River, Egypt/Sudan',
        lastUpdated: 'Apr 25, 2026',
        includedData: const [
          'Land maps',
          'River data',
          'Landmarks (640)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 82,
        fileSizes: const {
          'maps': '114 MB',
          'river': '30 MB',
          'landmarks': '14 MB',
          'magnetic': '10 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'sahara_desert',
        name: 'Sahara Desert Pack',
        type: 'Desert',
        size: '156 MB',
        status: 'available',
        location: 'Sahara Desert, North Africa',
        lastUpdated: 'Mar 10, 2026',
        includedData: const [
          'Land maps',
          'Landmarks (360)',
          'Magnetic baseline',
          'Celestial tables',
          'Sand dune mapping',
          'Oasis data',
        ],
        trustScore: 77,
        fileSizes: const {
          'maps': '96 MB',
          'landmarks': '8 MB',
          'magnetic': '14 MB',
          'celestial': '4.5 MB',
          'terrain': '18 MB',
        },
      ),
      RegionPack(
        id: 'victoria_lake',
        name: 'Lake Victoria Pack',
        type: 'Lake',
        size: '148 MB',
        status: 'available',
        location: 'Lake Victoria, Kenya/Tanzania/Uganda',
        lastUpdated: 'Apr 14, 2026',
        includedData: const [
          'Lake maps',
          'Marine data',
          'Landmarks (520)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 80,
        fileSizes: const {
          'maps': '88 MB',
          'marine': '26 MB',
          'landmarks': '12 MB',
          'magnetic': '10 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'mombasa_port',
        name: 'Mombasa Port Pack',
        type: 'Marine',
        size: '96 MB',
        status: 'available',
        location: 'Port of Mombasa, Kenya',
        lastUpdated: 'May 6, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (380)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 83,
        fileSizes: const {
          'maps': '56 MB',
          'marine': '16 MB',
          'landmarks': '8 MB',
          'magnetic': '8 MB',
          'celestial': '4.5 MB',
        },
      ),

      // ── Asia ───────────────────────────────────────────────────────────────
      RegionPack(
        id: 'straits_of_malacca',
        name: 'Straits of Malacca Pack',
        type: 'Marine',
        size: '232 MB',
        status: 'available',
        location: 'Strait of Malacca, Malaysia/Singapore/Indonesia',
        lastUpdated: 'Jun 9, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (1,280)',
          'Magnetic baseline',
          'Celestial tables',
          'Traffic separation schemes',
        ],
        trustScore: 95,
        fileSizes: const {
          'maps': '142 MB',
          'marine': '42 MB',
          'landmarks': '24 MB',
          'magnetic': '14 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'shanghai_port',
        name: 'Shanghai Port Pack',
        type: 'Marine',
        size: '196 MB',
        status: 'available',
        location: 'Yangtze River Delta, Shanghai, China',
        lastUpdated: 'Jun 4, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (1,124)',
          'Magnetic baseline',
          'Celestial tables',
          'Channel data',
        ],
        trustScore: 93,
        fileSizes: const {
          'maps': '118 MB',
          'marine': '34 MB',
          'landmarks': '22 MB',
          'magnetic': '12 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'tokyo_bay',
        name: 'Tokyo Bay Pack',
        type: 'Marine',
        size: '178 MB',
        status: 'available',
        location: 'Tokyo Bay, Japan',
        lastUpdated: 'Jun 6, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (960)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 96,
        fileSizes: const {
          'maps': '108 MB',
          'marine': '30 MB',
          'landmarks': '18 MB',
          'magnetic': '12 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'mumbai_port',
        name: 'Mumbai Port Pack',
        type: 'Marine',
        size: '134 MB',
        status: 'available',
        location: 'Mumbai Harbour, India',
        lastUpdated: 'May 24, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (624)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 87,
        fileSizes: const {
          'maps': '80 MB',
          'marine': '24 MB',
          'landmarks': '14 MB',
          'magnetic': '8 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'maldives',
        name: 'Maldives Atoll Pack',
        type: 'Island',
        size: '146 MB',
        status: 'available',
        location: 'Maldive Islands, Indian Ocean',
        lastUpdated: 'Apr 30, 2026',
        includedData: const [
          'Island maps',
          'Marine data',
          'Landmarks (680)',
          'Magnetic baseline',
          'Celestial tables',
          'Reef charts',
        ],
        trustScore: 88,
        fileSizes: const {
          'maps': '88 MB',
          'marine': '28 MB',
          'landmarks': '14 MB',
          'magnetic': '8 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'himalaya_hiking',
        name: 'Himalayan Trekking Pack',
        type: 'Hiking',
        size: '202 MB',
        status: 'available',
        location: 'Himalayas, Nepal/Tibet',
        lastUpdated: 'Apr 8, 2026',
        includedData: const [
          'Land maps',
          'Trail data',
          'Landmarks (840)',
          'Magnetic baseline',
          'Celestial tables',
          'Altitude data',
          'Camp locations',
        ],
        trustScore: 78,
        fileSizes: const {
          'maps': '124 MB',
          'trails': '36 MB',
          'landmarks': '16 MB',
          'magnetic': '10 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'yangtze_river',
        name: 'Yangtze River Pack',
        type: 'River',
        size: '228 MB',
        status: 'available',
        location: 'Yangtze River, China',
        lastUpdated: 'May 16, 2026',
        includedData: const [
          'Land maps',
          'River data',
          'Landmarks (980)',
          'Magnetic baseline',
          'Celestial tables',
          'Dam & lock data',
        ],
        trustScore: 89,
        fileSizes: const {
          'maps': '140 MB',
          'river': '42 MB',
          'landmarks': '18 MB',
          'magnetic': '12 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'gobi_desert',
        name: 'Gobi Desert Pack',
        type: 'Desert',
        size: '138 MB',
        status: 'available',
        location: 'Gobi Desert, Mongolia/China',
        lastUpdated: 'Mar 22, 2026',
        includedData: const [
          'Land maps',
          'Landmarks (310)',
          'Magnetic baseline',
          'Celestial tables',
          'Terrain mapping',
        ],
        trustScore: 73,
        fileSizes: const {
          'maps': '84 MB',
          'landmarks': '6 MB',
          'magnetic': '12 MB',
          'celestial': '4.5 MB',
          'terrain': '16 MB',
        },
      ),
      RegionPack(
        id: 'persian_gulf',
        name: 'Persian Gulf Pack',
        type: 'Marine',
        size: '198 MB',
        status: 'available',
        location: 'Persian Gulf, Middle East',
        lastUpdated: 'Jun 3, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (980)',
          'Magnetic baseline',
          'Celestial tables',
          'Oil terminal data',
        ],
        trustScore: 91,
        fileSizes: const {
          'maps': '122 MB',
          'marine': '36 MB',
          'landmarks': '18 MB',
          'magnetic': '12 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'red_sea',
        name: 'Red Sea Pack',
        type: 'Marine',
        size: '216 MB',
        status: 'available',
        location: 'Red Sea, Middle East/Africa',
        lastUpdated: 'May 28, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (1,060)',
          'Magnetic baseline',
          'Celestial tables',
          'Reef hazard data',
        ],
        trustScore: 90,
        fileSizes: const {
          'maps': '132 MB',
          'marine': '38 MB',
          'landmarks': '20 MB',
          'magnetic': '14 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'bering_sea',
        name: 'Bering Sea Pack',
        type: 'Marine',
        size: '252 MB',
        status: 'available',
        location: 'Bering Sea, Alaska/Russia',
        lastUpdated: 'May 5, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (1,100)',
          'Magnetic baseline',
          'Celestial tables',
          'Ice hazard data',
        ],
        trustScore: 85,
        fileSizes: const {
          'maps': '156 MB',
          'marine': '44 MB',
          'landmarks': '20 MB',
          'magnetic': '14 MB',
          'celestial': '4.5 MB',
        },
      ),

      // ── Oceania ────────────────────────────────────────────────────────────
      RegionPack(
        id: 'great_barrier_reef',
        name: 'Great Barrier Reef Pack',
        type: 'Marine',
        size: '342 MB',
        status: 'available',
        location: 'Great Barrier Reef, Queensland, Australia',
        lastUpdated: 'Jun 10, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (2,140)',
          'Magnetic baseline',
          'Celestial tables',
          'Reef zone charts',
          'Conservation areas',
        ],
        trustScore: 92,
        fileSizes: const {
          'maps': '212 MB',
          'marine': '68 MB',
          'landmarks': '32 MB',
          'magnetic': '16 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'sydney_harbour',
        name: 'Sydney Harbour Pack',
        type: 'Marine',
        size: '118 MB',
        status: 'available',
        location: 'Sydney Harbour, NSW, Australia',
        lastUpdated: 'Jun 5, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (540)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 94,
        fileSizes: const {
          'maps': '72 MB',
          'marine': '20 MB',
          'landmarks': '12 MB',
          'magnetic': '8 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'new_zealand_fiords',
        name: 'New Zealand Fiordland Pack',
        type: 'Hiking',
        size: '158 MB',
        status: 'available',
        location: 'Fiordland, New Zealand',
        lastUpdated: 'Apr 22, 2026',
        includedData: const [
          'Land maps',
          'Trail data',
          'Marine data',
          'Landmarks (712)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 88,
        fileSizes: const {
          'maps': '96 MB',
          'trails': '28 MB',
          'marine': '14 MB',
          'landmarks': '10 MB',
          'magnetic': '6 MB',
        },
      ),
      RegionPack(
        id: 'hawaii_islands',
        name: 'Hawaiian Islands Pack',
        type: 'Island',
        size: '174 MB',
        status: 'available',
        location: 'Hawaiian Islands, USA',
        lastUpdated: 'May 14, 2026',
        includedData: const [
          'Island maps',
          'Marine data',
          'Landmarks (840)',
          'Magnetic baseline',
          'Celestial tables',
          'Lava zone mapping',
        ],
        trustScore: 90,
        fileSizes: const {
          'maps': '106 MB',
          'marine': '32 MB',
          'landmarks': '16 MB',
          'magnetic': '10 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'papua_new_guinea',
        name: 'Papua New Guinea Coast Pack',
        type: 'Marine',
        size: '182 MB',
        status: 'available',
        location: 'Papua New Guinea, Pacific',
        lastUpdated: 'Apr 2, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (780)',
          'Magnetic baseline',
          'Celestial tables',
          'Reef charts',
        ],
        trustScore: 76,
        fileSizes: const {
          'maps': '112 MB',
          'marine': '34 MB',
          'landmarks': '14 MB',
          'magnetic': '12 MB',
          'celestial': '4.5 MB',
        },
      ),

      // ── Polar ─────────────────────────────────────────────────────────────
      RegionPack(
        id: 'arctic_ocean',
        name: 'Arctic Ocean Pack',
        type: 'Arctic',
        size: '312 MB',
        status: 'available',
        location: 'Arctic Ocean, North Pole Region',
        lastUpdated: 'Mar 15, 2026',
        includedData: const [
          'Marine data',
          'Landmarks (820)',
          'Magnetic baseline',
          'Celestial tables',
          'Ice edge tracking',
          'Polar correction data',
        ],
        trustScore: 82,
        fileSizes: const {
          'maps': '194 MB',
          'marine': '52 MB',
          'landmarks': '14 MB',
          'magnetic': '24 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'antarctica',
        name: 'Antarctic Pack',
        type: 'Arctic',
        size: '286 MB',
        status: 'available',
        location: 'Antarctica, South Pole Region',
        lastUpdated: 'Mar 5, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (580)',
          'Magnetic baseline',
          'Celestial tables',
          'Ice shelf data',
          'Polar correction data',
        ],
        trustScore: 85,
        fileSizes: const {
          'maps': '178 MB',
          'marine': '48 MB',
          'landmarks': '10 MB',
          'magnetic': '22 MB',
          'celestial': '4.5 MB',
        },
      ),
      RegionPack(
        id: 'svalbard',
        name: 'Svalbard & Arctic Archipelago Pack',
        type: 'Arctic',
        size: '168 MB',
        status: 'available',
        location: 'Svalbard, Norway / Arctic',
        lastUpdated: 'Apr 10, 2026',
        includedData: const [
          'Land maps',
          'Marine data',
          'Landmarks (480)',
          'Magnetic baseline',
          'Celestial tables',
          'Glacier mapping',
        ],
        trustScore: 83,
        fileSizes: const {
          'maps': '102 MB',
          'marine': '32 MB',
          'landmarks': '10 MB',
          'magnetic': '14 MB',
          'celestial': '4.5 MB',
        },
      ),

      RegionPack(
        id: 'lake_baikal',
        name: 'Lake Baikal Pack',
        type: 'Lake',
        size: '142 MB',
        status: 'available',
        location: 'Lake Baikal, Siberia, Russia',
        lastUpdated: 'Jan 10, 2026',
        includedData: const [
          'Land maps',
          'Lake data',
          'Landmarks (420)',
          'Magnetic baseline',
        ],
        trustScore: 82,
        fileSizes: const {
          'maps': '90 MB',
          'marine': '30 MB',
          'landmarks': '12 MB',
          'magnetic': '10 MB',
        },
      ),
      RegionPack(
        id: 'siberian_tundra',
        name: 'Siberian Tundra Pack',
        type: 'Hiking',
        size: '110 MB',
        status: 'available',
        location: 'Siberia, Russia',
        lastUpdated: 'Feb 15, 2026',
        includedData: const [
          'Land maps',
          'Trail data',
          'Landmarks (210)',
          'Magnetic baseline',
        ],
        trustScore: 78,
        fileSizes: const {
          'maps': '80 MB',
          'trails': '15 MB',
          'landmarks': '8 MB',
          'magnetic': '7 MB',
        },
      ),
      RegionPack(
        id: 'pacific_ocean',
        name: 'Pacific Ocean Open Water Pack',
        type: 'Marine',
        size: '340 MB',
        status: 'available',
        location: 'Pacific Ocean',
        lastUpdated: 'Mar 1, 2026',
        includedData: const [
          'Marine data',
          'Celestial tables',
          'Magnetic baseline',
          'Current data',
        ],
        trustScore: 85,
        fileSizes: const {
          'maps': '50 MB',
          'marine': '200 MB',
          'magnetic': '50 MB',
          'celestial': '40 MB',
        },
      ),
      RegionPack(
        id: 'atlantic_ocean',
        name: 'Atlantic Ocean Open Water Pack',
        type: 'Marine',
        size: '280 MB',
        status: 'available',
        location: 'Atlantic Ocean',
        lastUpdated: 'Apr 11, 2026',
        includedData: const [
          'Marine data',
          'Celestial tables',
          'Magnetic baseline',
        ],
        trustScore: 88,
        fileSizes: const {
          'maps': '40 MB',
          'marine': '180 MB',
          'magnetic': '30 MB',
          'celestial': '30 MB',
        },
      ),
      RegionPack(
        id: 'indian_ocean',
        name: 'Indian Ocean Open Water Pack',
        type: 'Marine',
        size: '220 MB',
        status: 'available',
        location: 'Indian Ocean',
        lastUpdated: 'May 5, 2026',
        includedData: const [
          'Marine data',
          'Celestial tables',
          'Magnetic baseline',
        ],
        trustScore: 84,
        fileSizes: const {
          'maps': '30 MB',
          'marine': '140 MB',
          'magnetic': '25 MB',
          'celestial': '25 MB',
        },
      ),
      RegionPack(
        id: 'southern_ocean',
        name: 'Southern Ocean Pack',
        type: 'Arctic',
        size: '180 MB',
        status: 'available',
        location: 'Southern Ocean',
        lastUpdated: 'Jun 1, 2026',
        includedData: const [
          'Marine data',
          'Ice flow charts',
          'Magnetic baseline',
        ],
        trustScore: 81,
        fileSizes: const {
          'maps': '20 MB',
          'marine': '120 MB',
          'magnetic': '40 MB',
        },
      ),

      // ── Demo ──────────────────────────────────────────────────────────────
      RegionPack(
        id: 'coastal_demo',
        name: 'Coastal Emergency Demo Pack',
        type: 'Urban',
        size: '38 MB',
        status: 'available',
        location: 'Demo — Coastal Area',
        lastUpdated: 'Jun 14, 2026',
        includedData: const [
          'Land maps',
          'Coastal data',
          'Landmarks (56)',
          'Magnetic baseline',
          'Celestial tables',
        ],
        trustScore: 82,
        fileSizes: const {
          'maps': '24.1 MB',
          'marine': '5.2 MB',
          'landmarks': '1.8 MB',
          'magnetic': '2.4 MB',
        },
      ),
    ];

    _packs.clear();
    _packs.addAll(defaultPacks);

    // Sync statuses against local storage
    for (int i = 0; i < _packs.length; i++) {
      final isDownloaded = await _storage.isPackDownloaded(_packs[i].id);
      if (isDownloaded) {
        _packs[i] = _packs[i].copyWith(status: 'downloaded');
      }
    }

    // Default active pack based on user's current location
    await _sensors.gpsService.initialize();
    final loc = await _sensors.gpsService.getCurrentPosition();

    String defaultPackId = _packs.first.id;
    if (loc != null) {
      double minDistance = double.infinity;

      final Map<String, List<double>> coords = {
        'sf_bay': [37.7140, -122.3078],
        'chesapeake': [38.2281, -76.2629],
        'gulf_mexico': [25.0, -90.0],
        'great_lakes': [45.0, -82.0],
        'tahoe': [39.0885, -120.0504],
        'mountain_view': [37.1413, -121.9974],
        'grand_canyon': [36.0980, -112.0963],
        'yellowstone': [44.4, -110.5],
        'new_york_harbor': [40.9076, -73.4652],
        'mississippi_river': [39.5530, -91.1586],
        'vancouver_harbour': [49.2908, -123.1183],
        'caribbean_islands': [15.0, -75.0],
        'yucatan_coast': [18.8017, -89.7427],
        'amazon_river': [-3.0, -60.0],
        'patagonia': [-50.0, -73.0],
        'rio_de_janeiro': [-22.8169, -43.1272],
        'galapagos': [-0.6288, -90.3639],
        'rotterdam': [51.9043, 4.4298],
        'english_channel': [50.0, -2.0],
        'north_sea': [56.0, 3.0],
        'mediterranean_west': [38.0, 5.0],
        'mediterranean_east': [34.0, 25.0],
        'thames_estuary': [51.5, 0.5],
        'alps_hiking': [46.5, 9.0],
        'fjords_norway': [62.1266, 7.1658],
        'baltic_sea': [58.0, 20.0],
        'suez_canal': [30.6053, 32.3331],
        'cape_town': [-33.8917, 18.4597],
        'nile_river': [20.0, 32.0],
        'sahara_desert': [23.0, 10.0],
        'victoria_lake': [-1.0, 33.0],
        'mombasa_port': [-4.0256, 39.6120],
        'straits_of_malacca': [4.0, 100.0],
        'shanghai_port': [31.2, 121.5],
        'tokyo_bay': [35.4700, 139.8477],
        'mumbai_port': [18.9518, 73.0187],
        'maldives': [3.2, 73.0],
        'himalaya_hiking': [28.0, 84.0],
        'yangtze_river': [30.5641, 114.2917],
        'gobi_desert': [43.0, 105.0],
        'persian_gulf': [26.0, 52.0],
        'red_sea': [20.0, 38.0],
        'bering_sea': [58.0, -175.0],
        'great_barrier_reef': [-20.3581, 148.9521],
        'sydney_harbour': [-33.8645, 151.2343],
        'new_zealand_fiords': [-45.2916, 167.4880],
        'hawaii_islands': [19.5896, -155.4487],
        'papua_new_guinea': [-9.4221, 147.0835],
        'arctic_ocean': [85.0, 0.0],
        'antarctica': [-80.0, 0.0],
        'svalbard': [78.0, 15.0],
        'lake_baikal': [53.5, 108.0],
        'siberian_tundra': [66.0, 100.0],
        'pacific_ocean': [0.0, -150.0],
        'atlantic_ocean': [0.0, -30.0],
        'indian_ocean': [-20.0, 80.0],
        'southern_ocean': [-60.0, 0.0],
        'coastal_demo': [37.7, -122.4],
      };

      for (var p in _packs) {
        if (coords.containsKey(p.id)) {
          final lat = coords[p.id]![0];
          final lon = coords[p.id]![1];
          // Haversine Distance
          final dLat = (lat - loc.latitude) * pi / 180.0;
          final dLon = (lon - loc.longitude) * pi / 180.0;
          final a =
              sin(dLat / 2) * sin(dLat / 2) +
              cos(loc.latitude * pi / 180.0) *
                  cos(lat * pi / 180.0) *
                  sin(dLon / 2) *
                  sin(dLon / 2);
          final c = 2 * atan2(sqrt(a), sqrt(1 - a));
          if (c < minDistance) {
            minDistance = c;
            defaultPackId = p.id;
          }
        }
      }
    }

    await activateRegionPack(defaultPackId);

    _eventLog.seedInitialEvents();
    notifyListeners();
  }

  /// Auto detect network connectivity using connectivity_plus
  void _initConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final activePack = getRegionPackById(_activePackId);
      final packName = activePack?.name ?? 'No Pack';
      final hasPack = activePack != null && activePack.status == 'downloaded';
      final status = hasPack ? 'Active' : 'Not Loaded';

      final state = ConnectivityState.fromResults(
        results,
        activePackName: packName,
        packCoverageStatus: status,
      );
      _connectivityMode = state.mode;
      notifyListeners();
    });
  }

  set connectivityMode(ConnectivityMode mode) {
    if (_connectivityMode != mode) {
      _connectivityMode = mode;
      notifyListeners();
    }
  }

  /// Connect downloader streams to repository list updates
  void _subscribeToDownloads() {
    _downloadSub = _downloader.progressStream.listen((progressEvent) {
      final index = _packs.indexWhere((p) => p.id == progressEvent.packId);
      if (index != -1) {
        final pack = _packs[index];
        if (progressEvent.status == 'completed') {
          _packs[index] = pack.copyWith(
            status: 'downloaded',
            isDownloading: false,
            downloadProgress: 1.0,
            downloadStage: 'Complete',
          );
          _eventLog.addEvent(
            title: 'Region Pack Downloaded',
            description: 'Pack ${pack.name} is now available offline.',
            severity: 'info',
            iconName: 'download_done',
          );
          // If no active pack, activate this one
          if (_activePackId.isEmpty) {
            activateRegionPack(pack.id);
          }
        } else if (progressEvent.status == 'failed') {
          _packs[index] = pack.copyWith(
            status: 'available',
            isDownloading: false,
            downloadProgress: 0.0,
            downloadStage: 'Failed: ${progressEvent.error}',
          );
          _eventLog.addEvent(
            title: 'Download Failed',
            description:
                'Failed to download ${pack.name}: ${progressEvent.error}',
            severity: 'warning',
            iconName: 'error',
          );
        } else {
          _packs[index] = pack.copyWith(
            status: 'downloading',
            isDownloading: true,
            downloadProgress: progressEvent.progress,
            downloadStage:
                'Downloading (${(progressEvent.progress * 100).toStringAsFixed(0)}%)',
          );
        }
        notifyListeners();
      }
    });
  }

  /// Start download flow via downloader service
  void startDownload(String packId) {
    final pack = getRegionPackById(packId);
    if (pack != null && pack.status != 'downloaded') {
      _downloader.startDownload(pack);
    }
  }

  void cancelDownload(String packId) {
    //
  }

  /// Delete a region pack from disk and update list status
  Future<void> deleteRegionPack(String packId) async {
    await _storage.deletePackFiles(packId);
    final index = _packs.indexWhere((p) => p.id == packId);
    if (index != -1) {
      _packs[index] = _packs[index].copyWith(status: 'available');
    }
    if (_activePackId == packId) {
      _activePackId = '';
      _loadedLandmarks = null;
      _loadedMagnetic = null;
      _loadedSeamap = null;
    }
    _eventLog.addEvent(
      title: 'Region Pack Removed',
      description: 'Pack files deleted from device storage.',
      severity: 'info',
      iconName: 'delete',
    );
    notifyListeners();
  }

  /// Set the active region pack and load its GeoJSON data from storage
  Future<void> activateRegionPack(String packId) async {
    final index = _packs.indexWhere((p) => p.id == packId);
    if (index == -1 || _packs[index].status != 'downloaded') return;

    _activePackId = packId;

    try {
      _loadedLandmarks = await _storage.loadGeoJson(
        packId,
        'landmarks.geojson',
      );
      _loadedMagnetic = await _storage.loadGeoJson(packId, 'magnetic.geojson');
      _loadedSeamap = await _storage.loadGeoJson(packId, 'seamap.geojson');

      // Get pack center to focus map
      final manifest = await _storage.getPackManifest(packId);
      if (manifest != null) {
        final double centerLat =
            manifest['center_latitude'] as double? ?? 37.8087;
        final double centerLng =
            manifest['center_longitude'] as double? ?? -122.4098;
        centerMapOn(centerLat, centerLng);
      }

      _eventLog.addEvent(
        title: 'Region Activated',
        description: 'Loaded ${packs[index].name} datasets locally.',
        severity: 'info',
        iconName: 'map',
      );
    } catch (e) {
      debugPrint('Error activating region pack $packId: $e');
      _eventLog.addEvent(
        title: 'Activation Failed',
        description: 'Failed to load pack GeoJSON layers.',
        severity: 'critical',
        iconName: 'error_outline',
      );
    }

    notifyListeners();
  }

  /// Enable or disable tracking and start/stop the hardware streams
  void toggleTracking() {
    _isTracking = !_isTracking;
    if (_isTracking) {
      _trail.clear();
      _sensors.imuService.resetDeadReckoning();
      _sensors.startAll();

      _sensorSub = _sensors.snapshotStream.listen((snapshot) {
        _processSnapshot(snapshot);
      });

      _eventLog.addEvent(
        title: 'Tracking Started',
        description: 'All sensor streams opened. Fusing real-time.',
        severity: 'info',
        iconName: 'play_arrow',
      );
    } else {
      _sensorSub?.cancel();
      _sensorSub = null;
      _sensors.stopAll();

      _eventLog.addEvent(
        title: 'Tracking Stopped',
        description: 'Sensor streams closed.',
        severity: 'info',
        iconName: 'stop',
      );
    }
    notifyListeners();
  }

  /// Process live sensor readings through matchers and fusion algorithm
  void _processSnapshot(SensorSnapshot snapshot) {
    final gpsReading = snapshot.gps;
    final magReading = snapshot.magnetometer;

    LandmarkMatch? lMatch;
    MagneticMatch? mMatch;
    SeamapMatch? sMatch;

    if (gpsReading != null) {
      lMatch = _matcher.matchLandmarks(
        latitude: gpsReading.latitude,
        longitude: gpsReading.longitude,
        landmarksGeoJson: _loadedLandmarks,
      );

      if (magReading != null) {
        mMatch = _matcher.matchMagnetic(
          latitude: gpsReading.latitude,
          longitude: gpsReading.longitude,
          liveStrength: magReading.fieldStrength,
          magneticGeoJson: _loadedMagnetic,
        );
      }

      sMatch = _matcher.matchSeamap(
        latitude: gpsReading.latitude,
        longitude: gpsReading.longitude,
        seamapGeoJson: _loadedSeamap,
      );
    }

    double? lastLat = _trail.isNotEmpty ? _trail.last['latitude'] : null;
    double? lastLng = _trail.isNotEmpty ? _trail.last['longitude'] : null;

    final fusion = _fusionEngine.compute(
      gps: gpsReading,
      magnetometer: magReading,
      imu: snapshot.imu,
      barometer: snapshot.barometer,
      sky: snapshot.sky,
      landmarkMatch: lMatch,
      magneticMatch: mMatch,
      seamapMatch: sMatch,
      hasOfflineData: _activePackId.isNotEmpty,
      lastTrustedLat: lastLat,
      lastTrustedLng: lastLng,
    );

    _opinions = fusion.opinions;
    _trustScore = fusion.confidence;

    // Track state change to trigger event log notification
    if (fusion.alertSeverity != _alertSeverity &&
        fusion.alertSeverity != 'none') {
      _eventLog.addEvent(
        title: 'Fusion Status Change',
        description: fusion.alertMessage,
        severity: fusion.alertSeverity,
        iconName: 'warning',
      );
    }

    _alertMessage = fusion.alertMessage;
    _alertSeverity = fusion.alertSeverity;

    // Record trail point
    _trail.add({'latitude': fusion.latitude, 'longitude': fusion.longitude});

    notifyListeners();
  }

  void centerMapOn(double lat, double lng) {
    mapCenterLat = lat;
    mapCenterLng = lng;
    notifyListeners();
  }

  /// Record a successfully matched landmark as a visual anchor in the trust event log.
  /// Called by LandmarkScanScreen when the user taps "Use as Anchor".
  void setLandmarkAnchor(Landmark landmark, int matchPercent) {
    _eventLog.addEvent(
      title: 'Visual Anchor Set',
      description:
          '${landmark.name} matched at $matchPercent% — used as position anchor. '
          'Uncertainty: ±${(100 - matchPercent) ~/ 2}m.',
      severity: 'info',
      iconName: 'anchor',
    );
    notifyListeners();
  }

  /// Record an AR scan visual confirmation result in the trust event log.
  /// Called by ArScanScreen when the user taps "Send to Fusion".
  void recordArScanResult({
    required String poseQuality,
    required int visualMatch,
  }) {
    _eventLog.addEvent(
      title: 'AR Visual Confirmation',
      description:
          'AR Scan completed — pose quality: $poseQuality, '
          'visual match vs. pack geometry: $visualMatch%.',
      severity: visualMatch >= 80 ? 'info' : 'warning',
      iconName: 'view_in_ar',
    );
    notifyListeners();
  }

  List<RegionPack> getRegionPacks() => _packs;

  List<RegionPack> get packs => _packs;

  RegionPack? getRegionPackById(String id) {
    try {
      return _packs.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  void updatePackStatus(String id, String status) {
    final index = _packs.indexWhere((p) => p.id == id);
    if (index != -1) {
      _packs[index] = _packs[index].copyWith(status: status);
      notifyListeners();
    }
  }

  PositionOpinion getTrustedPosition() {
    try {
      return getPositionOpinions().firstWhere((o) => o.sourceType == 'whami');
    } catch (_) {
      // Create a live trusted coordinate point if whami isn't compiled
      final lastLat = _trail.isNotEmpty ? _trail.last['latitude']! : 37.8087;
      final lastLng = _trail.isNotEmpty ? _trail.last['longitude']! : -122.4098;
      return PositionOpinion.whami(
        latitude: lastLat,
        longitude: lastLng,
        confidence: _trustScore,
        uncertaintyRadius: 30,
        description: _alertMessage,
      );
    }
  }

  List<PositionOpinion> getPositionOpinions() {
    if (_opinions.isEmpty) {
      // Build dummy loading opinions before tracking starts
      return [
        PositionOpinion.unavailable(
          id: 'gps',
          name: 'GPS / GNSS',
          shortCode: 'G',
          sourceType: 'gps',
          colorName: 'blue',
        ),
        PositionOpinion.unavailable(
          id: 'landmark',
          name: 'Landmark / Seamap',
          shortCode: 'L',
          sourceType: 'landmark',
          colorName: 'black',
        ),
        PositionOpinion.unavailable(
          id: 'magnetic',
          name: 'Magnetic Field',
          shortCode: 'M',
          sourceType: 'magnetic',
          colorName: 'red',
        ),
      ];
    }
    return _opinions;
  }

  int getTrustScore() => _trustScore;

  String getAlertMessage() => _alertMessage;

  List<SensorStatus> getSensorStatuses() {
    final list = List<SensorStatus>.from(_sensors.getSensorStatuses());
    list.add(
      SensorStatus(
        id: 'fusion',
        name: 'Trust Fusion Engine',
        status: _isTracking ? 'active' : 'available',
        confidence: _trustScore,
        latestValue: _isTracking
            ? 'Consensus confidence: $_trustScore%'
            : 'Ready',
        healthMessage: _alertMessage,
        iconName: 'security',
        lastUpdated: DateTime.now(),
      ),
    );
    return list;
  }

  List<TrustEvent> getTrustEvents() {
    return _eventLog.getEvents();
  }

  Map<String, dynamic> getTrustBreakdown() {
    final ops = getPositionOpinions();
    int landmark = 0;
    int gps = 0;
    int magnetic = 0;
    int imu = 0;
    int sky = 0;

    for (final op in ops) {
      if (op.status == 'active') {
        if (op.sourceType == 'landmark') landmark = op.confidence;
        if (op.sourceType == 'gps') gps = op.confidence;
        if (op.sourceType == 'magnetic') magnetic = op.confidence;
        if (op.sourceType == 'imu') imu = op.confidence;
        if (op.sourceType == 'sextant') sky = op.confidence;
      }
    }

    return {
      'finalScore': _trustScore,
      'landmarkMatch': landmark,
      'gpsConfidence': gps,
      'magneticFit': magnetic,
      'imuPath': imu,
      'skyStability': sky,
    };
  }

  List<Landmark> getLandmarks() {
    if (_loadedLandmarks == null) return [];
    final features = _loadedLandmarks!['features'] as List<dynamic>?;
    if (features == null) return [];

    return features.map((f) {
      final geom = f['geometry'] as Map<String, dynamic>;
      final coords = geom['coordinates'] as List<dynamic>;
      final props = f['properties'] as Map<String, dynamic>;
      return Landmark(
        name: props['name'] as String? ?? 'Unnamed',
        latitude: (coords[1] as num).toDouble(),
        longitude: (coords[0] as num).toDouble(),
        confidence: (props['confidence'] as num?)?.toDouble() ?? 0.8,
        saved: props['saved'] as bool? ?? false,
        type: props['landmark_type'] as String? ?? 'other',
      );
    }).toList();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _sensorSub?.cancel();
    _downloadSub?.cancel();
    super.dispose();
  }
}
