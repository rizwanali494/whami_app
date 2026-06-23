class OfflineStyle {
  /// Generate MapLibre Style JSON. It includes both the sleek dark marine base background
  /// and the CartoDB dark tiles as the base. When offline, network failures for tiles
  /// will gracefully fallback to the solid background without needing to reload the style.
  static Map<String, dynamic> generate({required bool isOffline}) {
    return {
      'version': 8,
      'name': 'WHAMI Sleek Dark Marine',
      'sources': {
        'open-tiles': {
          'type': 'raster',
          'tiles': [
            'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
            'https://b.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
            'https://c.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
          ],
          'tileSize': 256,
          'attribution': '© OpenStreetMap, © CartoDB',
        },
      },
      'layers': [
        // Sleek solid background matching WHAMI's premium theme
        {
          'id': 'solid-background',
          'type': 'background',
          'paint': {
            'background-color': '#5D6E96', // Rich dark midnight navy
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
