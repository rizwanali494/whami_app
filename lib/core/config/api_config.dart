class ApiConfig {
  /// Base URL for the production Region Pack catalog
  static const String productionCatalog = 'https://api.whami.com/v1/catalog.json';

  /// Base URL for the staging Region Pack catalog
  static const String stagingCatalog = 'https://staging.api.whami.com/v1/catalog.json';

  /// Base URL for local development and testing
  static const String developmentCatalog = 'http://localhost:8080/catalog.json';

  /// Get the active catalog URL based on the current environment
  static String get activeCatalog {
    // In the future, this can be driven by a Build Environment flag
    // For now, default to development
    return developmentCatalog;
  }
}
