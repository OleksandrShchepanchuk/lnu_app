/// Database Configuration
/// 
/// Centralized configuration for SQLite database settings.
/// This makes it easy to find and modify database-related constants
/// without digging through implementation code.
class DatabaseConfig {
  // Prevent instantiation
  DatabaseConfig._();

  /// Database file name (stored in app documents directory)
  static const String databaseName = 'lnu_maps.db';

  /// Database schema version
  /// Increment this when you need to run migrations
  static const int databaseVersion = 1;

  /// Path to bundled database in assets folder
  static const String assetDatabasePath = 'assets/database/$databaseName';

  /// Enable foreign key constraints
  static const bool enableForeignKeys = true;

  /// Enable Write-Ahead Logging for better performance
  /// https://www.sqlite.org/wal.html
  static const bool enableWAL = true;

  /// Cache size in pages (negative = KB, positive = pages)
  /// -2000 = 2MB cache
  static const int cacheSize = -2000;

  /// Enable query result caching in repository
  static const bool enableRepositoryCache = true;

  /// Enable graph edge caching
  static const bool enableGraphCache = true;

  /// Maximum cache entries (for LRU cache implementations)
  static const int maxCacheEntries = 1000;

  /// Database operation timeout in seconds
  static const int operationTimeout = 30;

  /// Enable debug logging for database operations
  static const bool enableDebugLogging = true;
}
