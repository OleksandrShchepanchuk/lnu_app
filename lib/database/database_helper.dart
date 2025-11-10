import 'dart:io';
import 'package:flutter/services.dart';
import 'package:lnu_nav_app/config/database_config.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// DatabaseHelper - NOT a singleton, designed for dependency injection
/// 
/// This class handles:
/// 1. Copying the bundled SQLite database from assets to app documents
/// 2. Opening and returning a Database instance
/// 3. Managing database initialization and version control
/// 
/// KEY DESIGN: This is NOT a singleton to enable:
/// - Easy mocking in tests
/// - Multiple database instances if needed
/// - Proper dependency injection via Provider
/// 
/// Configuration is centralized in DatabaseConfig class for easy access.
class DatabaseHelper {
  
  Database? _database;
  bool _isInitialized = false;

  /// Returns the database instance, initializing it if necessary
  /// This method is idempotent - safe to call multiple times
  Future<Database> getDatabase() async {
    if (_database != null && _isInitialized) {
      return _database!;
    }
    
    _database = await _initDatabase();
    _isInitialized = true;
    return _database!;
  }

  /// Initialize the database by copying from assets if needed
  Future<Database> _initDatabase() async {
    // Get the application documents directory
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDirectory.path, DatabaseConfig.databaseName);

    // Check if database already exists
    final exists = await databaseExists(dbPath);

    if (!exists) {
      if (DatabaseConfig.enableDebugLogging) {
        print('📦 Database not found, copying from assets...');
      }
      
      // Make sure the parent directory exists
      try {
        await Directory(dirname(dbPath)).create(recursive: true);
      } catch (_) {
        // Directory might already exist
      }

      // Copy from assets
      await _copyDatabaseFromAssets(dbPath);
      if (DatabaseConfig.enableDebugLogging) {
        print('✅ Database copied successfully to: $dbPath');
      }
    } else {
      if (DatabaseConfig.enableDebugLogging) {
        print('✅ Database already exists at: $dbPath');
      }
    }

    // Open the database
    return await openDatabase(
      dbPath,
      version: DatabaseConfig.databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Copy database file from assets to target path
  Future<void> _copyDatabaseFromAssets(String targetPath) async {
    // Read the database file from assets
    final ByteData data = await rootBundle.load(DatabaseConfig.assetDatabasePath);
    final List<int> bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    // Write to file
    await File(targetPath).writeAsBytes(bytes, flush: true);
  }

  /// Configure database settings
  Future<void> _onConfigure(Database db) async {
    // Enable foreign keys
    if (DatabaseConfig.enableForeignKeys) {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    // Enable Write-Ahead Logging for better performance
    // Note: On Android, WAL mode might not work with execute() in onConfigure
    // Use rawQuery instead, or skip it (WAL is optional optimization)
    if (DatabaseConfig.enableWAL) {
      try {
        await db.rawQuery('PRAGMA journal_mode = WAL');
      } catch (e) {
        // WAL mode not critical, continue without it
        if (DatabaseConfig.enableDebugLogging) {
          print('⚠️ Could not enable WAL mode: $e');
        }
      }
    }

    // Set cache size
    try {
      await db.rawQuery('PRAGMA cache_size = ${DatabaseConfig.cacheSize}');
    } catch (e) {
      // Cache size not critical
      if (DatabaseConfig.enableDebugLogging) {
        print('⚠️ Could not set cache size: $e');
      }
    }
  }

  /// Called when database is created for the first time
  /// If you're bundling a pre-populated database, this might not be needed
  Future<void> _onCreate(Database db, int version) async {
    if (DatabaseConfig.enableDebugLogging) {
      print('🔨 Database onCreate called - version $version');
    }
    // If you need to create tables programmatically, do it here
    // For bundled databases, this is usually empty
  }

  /// Called when database needs to be upgraded
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (DatabaseConfig.enableDebugLogging) {
      print('⬆️ Database upgrade from $oldVersion to $newVersion');
    }
    // Handle database migrations here
    // Example:
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE points ADD COLUMN new_field TEXT');
    // }
  }

  /// Close the database connection
  /// Call this when the app is shutting down or when testing
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _isInitialized = false;
      if (DatabaseConfig.enableDebugLogging) {
        print('🔒 Database closed');
      }
    }
  }

  /// For testing: delete the database file
  /// WARNING: This will permanently delete all local data
  Future<void> deleteDatabase() async {
    if (_database != null) {
      await close();
    }
    
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = join(documentsDirectory.path, DatabaseConfig.databaseName);
    
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
      if (DatabaseConfig.enableDebugLogging) {
        print('🗑️ Database deleted');
      }
    }
  }

  /// Get database path (useful for debugging)
  Future<String> getDatabasePath() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, DatabaseConfig.databaseName);
  }
}
