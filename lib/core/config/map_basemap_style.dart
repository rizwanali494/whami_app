/// Selectable WHAMI basemap styles (real tile sources only).
enum MapBasemapStyle {
  /// Dark Carto Matter — low-light cockpit feel.
  aviationDark,

  /// Bright Carto Voyager — daytime navigation.
  aviationLight,

  /// Esri World Imagery.
  satellite,

  /// OpenTopoMap elevation shading.
  terrain,

  /// OSM France streets (default ground reference).
  street,

  /// Esri imagery + place/boundary labels.
  hybrid,
}

extension MapBasemapStyleX on MapBasemapStyle {
  String get id {
    switch (this) {
      case MapBasemapStyle.aviationDark:
        return 'aviation_dark';
      case MapBasemapStyle.aviationLight:
        return 'aviation_light';
      case MapBasemapStyle.satellite:
        return 'satellite';
      case MapBasemapStyle.terrain:
        return 'terrain';
      case MapBasemapStyle.street:
        return 'street';
      case MapBasemapStyle.hybrid:
        return 'hybrid';
    }
  }

  String get label {
    switch (this) {
      case MapBasemapStyle.aviationDark:
        return 'Aviation Dark';
      case MapBasemapStyle.aviationLight:
        return 'Aviation Light';
      case MapBasemapStyle.satellite:
        return 'Satellite';
      case MapBasemapStyle.terrain:
        return 'Terrain';
      case MapBasemapStyle.street:
        return 'Street';
      case MapBasemapStyle.hybrid:
        return 'Hybrid';
    }
  }

  String get shortLabel {
    switch (this) {
      case MapBasemapStyle.aviationDark:
        return 'Dark';
      case MapBasemapStyle.aviationLight:
        return 'Light';
      case MapBasemapStyle.satellite:
        return 'Sat';
      case MapBasemapStyle.terrain:
        return 'Topo';
      case MapBasemapStyle.street:
        return 'Street';
      case MapBasemapStyle.hybrid:
        return 'Hybrid';
    }
  }

  String get description {
    switch (this) {
      case MapBasemapStyle.aviationDark:
        return 'Navy cockpit basemap · best at night';
      case MapBasemapStyle.aviationLight:
        return 'Clean daytime navigation map';
      case MapBasemapStyle.satellite:
        return 'Esri World Imagery';
      case MapBasemapStyle.terrain:
        return 'OpenTopoMap elevation shading';
      case MapBasemapStyle.street:
        return 'OSM France streets & places';
      case MapBasemapStyle.hybrid:
        return 'Satellite + place labels';
    }
  }

  /// Cached tiles still work offline once fetched; none are bundled atlases.
  String get offlineNote => 'Uses cached tiles when offline';

  bool get isImagery =>
      this == MapBasemapStyle.satellite || this == MapBasemapStyle.hybrid;

  static MapBasemapStyle fromId(String? id) {
    for (final s in MapBasemapStyle.values) {
      if (s.id == id) return s;
    }
    // Legacy satellite toggle.
    if (id == 'satellite_legacy' || id == 'true') {
      return MapBasemapStyle.satellite;
    }
    return MapBasemapStyle.street;
  }
}
