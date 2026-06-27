class OfflineStyle {
  /// Generate MapLibre Style JSON using light CartoDB tiles.
  /// When offline, network failures for tiles will gracefully
  /// fallback to the solid background without reloading the style.
  static Map<String, dynamic> generate({required bool isOffline}) {
    return {
      'version': 8,
      'name': 'WHAMI Light',
      'sources': {
        'open-tiles': {
          'type': 'raster',
          'tiles': [
            'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
            'https://b.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
            'https://c.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
          ],
          'tileSize': 256,
          'attribution': '© OpenStreetMap, © CartoDB',
        },
      },
      'layers': [
        // Fallback background for offline mode
        {
          'id': 'solid-background',
          'type': 'background',
          'paint': {
            'background-color': '#E8EDF2', // Light bluish-grey
          },
        },
        {
          'id': 'base-tiles',
          'type': 'raster',
          'source': 'open-tiles',
          'minzoom': 0,
          'maxzoom': 18,
        },
      ],
    };
  }
}
