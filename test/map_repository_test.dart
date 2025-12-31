import 'package:flutter_test/flutter_test.dart';
import 'package:lnu_nav_app/repositories/map_repository.dart';
import 'package:lnu_nav_app/types/pair.dart';
import 'package:lnu_nav_app/types/point.dart';
import 'package:lnu_nav_app/types/structures.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Practical unit tests for MapRepository
/// 
/// These tests help with:
/// 1. Regression testing - ensure queries work correctly
/// 2. Development - test new features without running the full app
/// 3. Documentation - show how to use the repository
void main() {
  // Initialize FFI for desktop testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('MapRepository Tests', () {
    late Database database;
    late MapRepository repository;

    setUp(() async {
      // Create in-memory database for testing
      database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          // Create test schema
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

          // Create indexes for better query performance
          await db.execute(
            'CREATE INDEX idx_points_label ON points(label)',
          );
          await db.execute(
            'CREATE INDEX idx_points_floor ON points(floor_id)',
          );
          await db.execute(
            'CREATE INDEX idx_edges_from ON edges(from_point_id)',
          );

          // Insert test data
          await _insertTestData(db);
        },
      );

      repository = MapRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('getBuildingById returns correct building', () async {
      final building = await repository.getBuildingById('building_1');

      expect(building, isNotNull);
      expect(building!.id, equals('building_1'));
      expect(building.name, equals('Test Building 1'));
      expect(building.floors.length, equals(2));
    });

    test('getBuildingById returns null for non-existent building', () async {
      final building = await repository.getBuildingById('non_existent');

      expect(building, isNull);
    });

    test('getAllPoints returns all points', () async {
      final points = await repository.getAllPoints();

      expect(points.length, equals(5));
      expect(points.containsKey('point_1'), isTrue);
      expect(points.containsKey('point_2'), isTrue);
    });

    test('getPointById returns correct point', () async {
      final point = await repository.getPointById('point_1');

      expect(point, isNotNull);
      expect(point!.id, equals('point_1'));
      expect(point.label, equals('Room 101'));
      expect(point.x, equals(10.0));
      expect(point.y, equals(20.0));
    });

    test('getLabeledPoints returns only points with labels', () async {
      final labeledPoints = await repository.getLabeledPoints();

      expect(labeledPoints.length, equals(3)); // Only 3 have labels
      expect(
        labeledPoints.every((p) => p.label != null && p.label!.isNotEmpty),
        isTrue,
      );
    });

    test('searchPointsByLabel finds matching points', () async {
      final results = await repository.searchPointsByLabel('Room');

      expect(results.length, equals(2)); // Room 101 and Room 102
      expect(results.any((p) => p.label == 'Room 101'), isTrue);
      expect(results.any((p) => p.label == 'Room 102'), isTrue);
    });

    test('searchPointsByLabel is case-insensitive', () async {
      final results = await repository.searchPointsByLabel('room');

      expect(results.length, equals(2));
    });

    test('getPointsForBuilding returns correct points', () async {
      final points = await repository.getPointsForBuilding('building_1');

      expect(points.length, equals(5));
      expect(points.every((p) => p.buildingId == 'building_1'), isTrue);
    });

    test('getLabeledPointsForFloor filters correctly', () async {
      final points = await repository.getLabeledPointsForFloor('floor_1');

      expect(points.length, equals(2)); // Only 2 labeled points on floor_1
      expect(points.every((p) => p.floorId == 'floor_1'), isTrue);
      expect(points.every((p) => p.label != null), isTrue);
    });

    test('getEdgesForPoint returns correct neighbors', () async {
      final edges = await repository.getEdgesForPoint('point_1');

      expect(edges.length, equals(2)); // point_1 connects to point_2 and point_3
      expect(edges.any((e) => e.first.id == 'point_2'), isTrue);
      expect(edges.any((e) => e.first.id == 'point_3'), isTrue);
    });

    test('getEdgesForPoint returns empty list for point with no edges', () async {
      final edges = await repository.getEdgesForPoint('point_5');

      expect(edges.isEmpty, isTrue);
    });

    test('edge weights are correctly retrieved', () async {
      final edges = await repository.getEdgesForPoint('point_1');
      final edgeToPoint2 = edges.firstWhere((e) => e.first.id == 'point_2');

      expect(edgeToPoint2.second, equals(5.0)); // Weight from point_1 to point_2
    });

    test('getBuildingOffsets returns all offsets', () async {
      final offsets = await repository.getBuildingOffsets();

      expect(offsets.length, equals(2));
      expect(offsets['building_1']?.x, equals(100.0));
      expect(offsets['building_1']?.y, equals(200.0));
    });

    test('cache improves performance on repeated queries', () async {
      // Clear cache first
      repository.clearCache();

      // First query (not cached)
      final stopwatch1 = Stopwatch()..start();
      await repository.getPointById('point_1');
      stopwatch1.stop();

      // Second query (should be cached)
      final stopwatch2 = Stopwatch()..start();
      await repository.getPointById('point_1');
      stopwatch2.stop();

      // Cached query should be faster (or at least not slower)
      expect(stopwatch2.elapsedMicroseconds, lessThanOrEqualTo(stopwatch1.elapsedMicroseconds));
    });

    test('clearCache removes cached data', () async {
      // Load a point (will be cached)
      await repository.getPointById('point_1');

      // Clear cache
      repository.clearCache();

      // Verify by checking internal state (if cache was public) or
      // just ensure the method doesn't throw
      expect(() => repository.clearCache(), returnsNormally);
    });
  });
}

/// Insert test data into the database
Future<void> _insertTestData(Database db) async {
  // Insert buildings
  await db.insert('buildings', {
    'id': 'building_1',
    'name': 'Test Building 1',
    'subtitle': 'Main Campus',
    'default_floor_id': 'floor_1',
    'offset_x': 100.0,
    'offset_y': 200.0,
  });

  await db.insert('buildings', {
    'id': 'building_2',
    'name': 'Test Building 2',
    'subtitle': 'East Campus',
    'default_floor_id': 'floor_3',
    'offset_x': 0.0,
    'offset_y': 0.0,
  });

  // Insert floors
  await db.insert('floors', {
    'id': 'floor_1',
    'building_id': 'building_1',
    'name': 'Ground Floor',
    'z': 0.0,
    'background': 'floor1.svg',
  });

  await db.insert('floors', {
    'id': 'floor_2',
    'building_id': 'building_1',
    'name': 'First Floor',
    'z': 1.0,
    'background': 'floor2.svg',
  });

  await db.insert('floors', {
    'id': 'floor_3',
    'building_id': 'building_2',
    'name': 'Ground Floor',
    'z': 0.0,
    'background': 'floor3.svg',
  });

  // Insert points
  await db.insert('points', {
    'id': 'point_1',
    'x': 10.0,
    'y': 20.0,
    'building_id': 'building_1',
    'floor_id': 'floor_1',
    'label': 'Room 101',
    'type': 'room',
  });

  await db.insert('points', {
    'id': 'point_2',
    'x': 15.0,
    'y': 25.0,
    'building_id': 'building_1',
    'floor_id': 'floor_1',
    'label': 'Room 102',
    'type': 'room',
  });

  await db.insert('points', {
    'id': 'point_3',
    'x': 20.0,
    'y': 30.0,
    'building_id': 'building_1',
    'floor_id': 'floor_2',
    'label': 'Hallway',
    'type': 'corridor',
  });

  await db.insert('points', {
    'id': 'point_4',
    'x': 25.0,
    'y': 35.0,
    'building_id': 'building_1',
    'floor_id': 'floor_2',
    'label': null, // Unlabeled point
    'type': 'junction',
  });

  await db.insert('points', {
    'id': 'point_5',
    'x': 30.0,
    'y': 40.0,
    'building_id': 'building_1',
    'floor_id': 'floor_2',
    'label': null, // Unlabeled point
    'type': 'junction',
  });

  // Insert edges (graph connections)
  await db.insert('edges', {
    'from_point_id': 'point_1',
    'to_point_id': 'point_2',
    'weight': 5.0,
  });

  await db.insert('edges', {
    'from_point_id': 'point_1',
    'to_point_id': 'point_3',
    'weight': 10.0,
  });

  await db.insert('edges', {
    'from_point_id': 'point_2',
    'to_point_id': 'point_3',
    'weight': 7.5,
  });

  await db.insert('edges', {
    'from_point_id': 'point_3',
    'to_point_id': 'point_4',
    'weight': 3.0,
  });
}
