# Database Configuration Best Practices

## ✅ Configuration Centralization

All database-related configuration constants have been moved to a dedicated config file for better maintainability.

### Location

```
lib/config/database_config.dart
```

### Benefits

1. **Easy to Find**: All database settings in one place
2. **Easy to Modify**: No need to search through implementation code
3. **Type-Safe**: Compile-time constants prevent runtime errors
4. **Well-Documented**: Each setting has clear documentation
5. **Environment-Specific**: Can be extended for dev/staging/prod configs

### Available Settings

```dart
DatabaseConfig.databaseName          // 'lnu_maps.db'
DatabaseConfig.databaseVersion       // 1 (increment for migrations)
DatabaseConfig.assetDatabasePath     // 'assets/database/lnu_maps.db'
DatabaseConfig.enableForeignKeys     // true
DatabaseConfig.enableWAL             // true (Write-Ahead Logging)
DatabaseConfig.cacheSize             // -2000 (2MB cache)
DatabaseConfig.enableRepositoryCache // true
DatabaseConfig.enableGraphCache      // true
DatabaseConfig.maxCacheEntries       // 1000
DatabaseConfig.operationTimeout      // 30 seconds
DatabaseConfig.enableDebugLogging    // true
```

### Usage Examples

#### In DatabaseHelper

```dart
import 'package:lnu_nav_app/config/database_config.dart';

// Instead of:
// static const String _databaseName = 'lnu_maps.db';

// Use:
final dbPath = join(documentsDirectory.path, DatabaseConfig.databaseName);
```

#### In Tests

```dart
// Easy to override for testing
class TestDatabaseConfig {
  static const databaseName = 'test_lnu_maps.db';
  static const enableDebugLogging = false;
}
```

#### Feature Flags

```dart
// Enable/disable features quickly
if (DatabaseConfig.enableGraphCache) {
  // Use cached graph
}
```

### Environment-Specific Configs (Future Enhancement)

You can extend this pattern for different environments:

```dart
// lib/config/database_config.dart
class DatabaseConfig {
  static const String databaseName = _getDatabaseName();

  static String _getDatabaseName() {
    const env = String.fromEnvironment('ENV', defaultValue: 'prod');
    switch (env) {
      case 'dev':
        return 'lnu_maps_dev.db';
      case 'staging':
        return 'lnu_maps_staging.db';
      default:
        return 'lnu_maps.db';
    }
  }
}
```

Then build with:

```bash
flutter build apk --dart-define=ENV=dev
```

### Alternative: YAML Config (Not Recommended for Flutter)

While you mentioned YAML, it's not the best practice in Flutter because:

❌ **Cons:**

-   Requires runtime parsing
-   No compile-time type safety
-   Harder to access (need asset loading)
-   Can't use in const contexts
-   Extra dependency

✅ **Dart Config Class Pros:**

-   Compile-time constants
-   Type-safe
-   IDE autocomplete
-   Zero runtime overhead
-   Easy to refactor

### When to Use YAML Config

Use YAML/JSON configs for:

-   User-configurable settings
-   Remote configuration
-   Feature flags fetched from server
-   Large configuration data

Use Dart constants for:

-   **Build-time configuration** ← Your case
-   App-wide constants
-   Performance-critical values
-   Type-safe enums

## Summary

✨ **What Changed:**

1. Created `lib/config/database_config.dart` with all database constants
2. Updated `database_helper.dart` to use `DatabaseConfig`
3. Added SQLite database path to `pubspec.yaml` assets
4. Added performance optimizations (WAL mode, cache size)
5. Made debug logging configurable

🎯 **Result:**

-   All magic strings removed from implementation code
-   Easy to find and modify database settings
-   Production-ready configuration management
-   Follows Flutter best practices
