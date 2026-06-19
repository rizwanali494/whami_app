import 'dart:math';

class RegionPackCdn {
  // Center coordinates for each region pack
  static const Map<String, (double, double)> centers = {
    'sf_bay': (37.8087, -122.4098),
    'tahoe': (39.0968, -120.0324),
    'mountain_view': (37.23, -122.11),
    'rotterdam': (51.9244, 4.4777),
    'coastal_demo': (32.7157, -117.1611),
  };

  // Landmark names specific to each region to make the database feel completely realistic
  static const Map<String, List<(String, double, double, bool)>> landmarksByRegion = {
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

  /// Generates a realistic Landmarks GeoJSON structure based on coordinates
  static Map<String, dynamic> generateLandmarks(String packId) {
    final center = centers[packId] ?? (37.8087, -122.4098);
    final landmarkList = landmarksByRegion[packId] ?? [
      ('Central Landmark Base', center.$1, center.$2, true),
    ];

    return {
      'type': 'FeatureCollection',
      'region': packId,
      'features': landmarkList.map((item) {
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [item.$3, item.$2],
          },
          'properties': {
            'name': item.$1,
            'type': 'landmark',
            'confidence': 0.75 + (Random(item.$1.hashCode).nextDouble() * 0.20),
            'saved': item.$4,
          }
        };
      }).toList(),
    };
  }

  /// Generates dynamic realistic Seamap/Chart lines
  static Map<String, dynamic> generateSeamap(String packId) {
    final center = centers[packId] ?? (37.8087, -122.4098);
    final double lat = center.$1;
    final double lng = center.$2;

    // Draw some mock sea boundaries or channel routes
    return {
      'type': 'FeatureCollection',
      'region': packId,
      'features': [
        // Channel Lane 1
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
        // Shipping Lane 2
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

  /// Generates a realistic local magnetic anomaly grid
  static Map<String, dynamic> generateMagnetic(String packId) {
    final center = centers[packId] ?? (37.8087, -122.4098);
    final double lat = center.$1;
    final double lng = center.$2;

    final List<Map<String, dynamic>> features = [];
    final Random rand = Random(packId.hashCode);

    // Create a 6x6 coordinate anomaly reading grid surrounding the center
    for (int i = -3; i <= 3; i++) {
      for (int j = -3; j <= 3; j++) {
        final double gridLat = lat + (i * 0.012);
        final double gridLng = lng + (j * 0.016);
        // Vary stability: closer to center is highly stable, edges have variations
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
}
