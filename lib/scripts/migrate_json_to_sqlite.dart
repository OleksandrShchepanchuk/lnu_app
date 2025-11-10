import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// JSON to SQLite Migration Script
/// 
/// This script converts your existing JSON map data to SQLite database.
/// 
/// Usage:
/// ```bash
/// dart run lib/scripts/migrate_json_to_sqlite.dart
/// ```
/// 
/// Input: Your JSON files (e.g., assets/CM.nodes.json)
/// Output: assets/database/lnu_maps.db

void main() async {
  print('🚀 Starting JSON to SQLite migration...\n');

  // Initialize SQLite for desktop
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final migrator = JsonToSqliteMigrator();
  await migrator.migrate();

  print('\n✅ Migration completed successfully!');
  print('📁 Database created at: ${await migrator.getDatabasePath()}');
}

class JsonToSqliteMigrator {
  static const String outputDbPath = 'assets/database/lnu_maps.db';
  
  // Configure your JSON file paths here
  static const List<String> jsonFilePaths = [
    'assets/CM.nodes.json',
    // Add more JSON files if you have multiple buildings
  ];

  Database? _db;

  Future<String> getDatabasePath() async {
    final currentDir = Directory.current.path;
    return join(currentDir, outputDbPath);
  }

  Future<void> migrate() async {
    try {
      // 1. Create database
      print('📦 Creating database...');
      _db = await _createDatabase();
      
      // 2. Read and parse JSON files
      print('📖 Reading JSON files...');
      final jsonData = await _readJsonFiles();
      
      // 3. Insert data into database
      print('💾 Inserting data into database...');
      await _insertData(jsonData);
      
      // 4. Create indexes for performance
      print('⚡ Creating indexes...');
      await _createIndexes();
      
      // 5. Verify data
      print('🔍 Verifying data...');
      await _verifyData();
      
      // 6. Close database
      await _db?.close();
      
    } catch (e, stackTrace) {
      print('❌ Migration failed: $e');
      print(stackTrace);
      await _db?.close();
      rethrow;
    }
  }

  Future<Database> _createDatabase() async {
    // Ensure directory exists
    final dbPath = await getDatabasePath();
    final dbDir = Directory(dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    // Delete existing database
    if (await File(dbPath).exists()) {
      await File(dbPath).delete();
      print('   Deleted existing database');
    }

    // Create new database
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
    );

    print('   ✓ Database created');
    return db;
  }

  Future<void> _createSchema(Database db) async {
    // Buildings table
    await db.execute('''
      CREATE TABLE buildings (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        subtitle TEXT,
        default_floor_id TEXT NOT NULL,
        offset_x REAL DEFAULT 0,
        offset_y REAL DEFAULT 0
      )
    ''');

    // Floors table
    await db.execute('''
      CREATE TABLE floors (
        id TEXT PRIMARY KEY,
        building_id TEXT NOT NULL,
        name TEXT NOT NULL,
        z REAL NOT NULL,
        background TEXT NOT NULL,
        subtitle TEXT,
        FOREIGN KEY (building_id) REFERENCES buildings(id)
      )
    ''');

    // Points table
    await db.execute('''
      CREATE TABLE points (
        id TEXT PRIMARY KEY,
        x REAL NOT NULL,
        y REAL NOT NULL,
        building_id TEXT NOT NULL,
        floor_id TEXT NOT NULL,
        label TEXT,
        type TEXT,
        FOREIGN KEY (building_id) REFERENCES buildings(id),
        FOREIGN KEY (floor_id) REFERENCES floors(id)
      )
    ''');

    // Edges table
    await db.execute('''
      CREATE TABLE edges (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_point_id TEXT NOT NULL,
        to_point_id TEXT NOT NULL,
        weight REAL NOT NULL,
        FOREIGN KEY (from_point_id) REFERENCES points(id),
        FOREIGN KEY (to_point_id) REFERENCES points(id)
      )
    ''');

    print('   ✓ Schema created');
  }

  Future<Map<String, dynamic>> _readJsonFiles() async {
    final allData = <String, dynamic>{
      'buildings': [],
      'floors': [],
      'points': [],
      'edges': [],
    };

    for (final jsonPath in jsonFilePaths) {
      final file = File(jsonPath);
      if (!await file.exists()) {
        print('   ⚠️  File not found: $jsonPath (skipping)');
        continue;
      }

      print('   Reading: $jsonPath');
      final jsonString = await file.readAsString();
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      // Parse JSON structure (adjust this based on your JSON format)
      _parseJsonStructure(jsonData, allData);
    }

    print('   ✓ Parsed ${allData['buildings'].length} buildings');
    print('   ✓ Parsed ${allData['floors'].length} floors');
    print('   ✓ Parsed ${allData['points'].length} points');
    print('   ✓ Parsed ${allData['edges'].length} edges');

    return allData;
  }

  void _parseJsonStructure(
    Map<String, dynamic> jsonData,
    Map<String, dynamic> allData,
  ) {
    // Parse buildings
    if (jsonData.containsKey('buildings')) {
      final buildings = jsonData['buildings'];
      if (buildings is Map) {
        buildings.forEach((key, value) {
          allData['buildings'].add(_normalizeBuilding(key, value));
        });
      }
    }

    // Parse floors
    if (jsonData.containsKey('floors')) {
      final floors = jsonData['floors'];
      if (floors is Map) {
        floors.forEach((key, value) {
          allData['floors'].add(_normalizeFloor(key, value));
        });
      }
    }

    // Parse points
    if (jsonData.containsKey('points')) {
      final points = jsonData['points'];
      if (points is Map) {
        points.forEach((key, value) {
          allData['points'].add(_normalizePoint(key, value));
        });
      }
    }

    // Parse adjacency list (edges)
    if (jsonData.containsKey('adjacencyList')) {
      final adjacencyList = jsonData['adjacencyList'];
      if (adjacencyList is Map) {
        adjacencyList.forEach((fromPointId, neighbors) {
          if (neighbors is List) {
            for (final neighbor in neighbors) {
              allData['edges'].add({
                'from_point_id': fromPointId,
                'to_point_id': neighbor['pointId'] ?? neighbor['id'],
                'weight': (neighbor['weight'] ?? neighbor['distance'] ?? 1.0).toDouble(),
              });
            }
          }
        });
      }
    }

    // Parse offsets
    if (jsonData.containsKey('offsets')) {
      final offsets = jsonData['offsets'];
      if (offsets is Map) {
        offsets.forEach((buildingId, offset) {
          // Find and update building offset
          final buildingIndex = (allData['buildings'] as List)
              .indexWhere((b) => b['id'] == buildingId);
          if (buildingIndex != -1) {
            allData['buildings'][buildingIndex]['offset_x'] = 
                (offset['x'] ?? 0.0).toDouble();
            allData['buildings'][buildingIndex]['offset_y'] = 
                (offset['y'] ?? 0.0).toDouble();
          }
        });
      }
    }
  }

  Map<String, dynamic> _normalizeBuilding(String id, dynamic data) {
    return {
      'id': id,
      'name': data['name'] ?? 'Unknown Building',
      'subtitle': data['subtitle'],
      'default_floor_id': data['defaultFloor'] ?? data['default_floor_id'] ?? '',
      'offset_x': 0.0,
      'offset_y': 0.0,
    };
  }

  Map<String, dynamic> _normalizeFloor(String id, dynamic data) {
    return {
      'id': id,
      'building_id': data['buildingId'] ?? data['building_id'] ?? '',
      'name': data['name'] ?? 'Unknown Floor',
      'z': (data['z'] ?? 0.0).toDouble(),
      'background': data['background'] ?? '',
      'subtitle': data['subtitle'],
    };
  }

  Map<String, dynamic> _normalizePoint(String id, dynamic data) {
    return {
      'id': id,
      'x': (data['x'] ?? 0.0).toDouble(),
      'y': (data['y'] ?? 0.0).toDouble(),
      'building_id': data['buildingId'] ?? data['building_id'] ?? '',
      'floor_id': data['floorId'] ?? data['floor_id'] ?? '',
      'label': data['label'],
      'type': data['type'],
    };
  }

  Future<void> _insertData(Map<String, dynamic> data) async {
    if (_db == null) throw Exception('Database not initialized');

    // Use transaction for better performance
    await _db!.transaction((txn) async {
      // Insert buildings
      for (final building in data['buildings']) {
        await txn.insert('buildings', building);
      }
      print('   ✓ Inserted ${data['buildings'].length} buildings');

      // Insert floors
      for (final floor in data['floors']) {
        await txn.insert('floors', floor);
      }
      print('   ✓ Inserted ${data['floors'].length} floors');

      // Insert points
      for (final point in data['points']) {
        await txn.insert('points', point);
      }
      print('   ✓ Inserted ${data['points'].length} points');

      // Insert edges
      for (final edge in data['edges']) {
        await txn.insert('edges', edge);
      }
      print('   ✓ Inserted ${data['edges'].length} edges');
    });
  }

  Future<void> _createIndexes() async {
    if (_db == null) throw Exception('Database not initialized');

    await _db!.execute('CREATE INDEX idx_points_label ON points(label)');
    await _db!.execute('CREATE INDEX idx_points_floor ON points(floor_id)');
    await _db!.execute('CREATE INDEX idx_points_building ON points(building_id)');
    await _db!.execute('CREATE INDEX idx_edges_from ON edges(from_point_id)');
    await _db!.execute('CREATE INDEX idx_floors_building ON floors(building_id)');

    print('   ✓ Created 5 indexes');
  }

  Future<void> _verifyData() async {
    if (_db == null) throw Exception('Database not initialized');

    final buildingCount = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM buildings'),
    );
    final floorCount = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM floors'),
    );
    final pointCount = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM points'),
    );
    final edgeCount = Sqflite.firstIntValue(
      await _db!.rawQuery('SELECT COUNT(*) FROM edges'),
    );

    print('   ✓ Buildings: $buildingCount');
    print('   ✓ Floors: $floorCount');
    print('   ✓ Points: $pointCount');
    print('   ✓ Edges: $edgeCount');

    // Check for orphaned data
    final orphanedPoints = Sqflite.firstIntValue(
      await _db!.rawQuery('''
        SELECT COUNT(*) FROM points 
        WHERE building_id NOT IN (SELECT id FROM buildings)
      '''),
    );

    if (orphanedPoints! > 0) {
      print('   ⚠️  Warning: $orphanedPoints orphaned points found');
    }
  }
}
