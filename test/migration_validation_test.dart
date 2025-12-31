import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lnu_nav_app/repositories/map_repository.dart';
import 'package:lnu_nav_app/types/structures.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Integration test to validate that the migrated SQLite database
/// contains the same data as the original JSON files.
/// 
/// This test:
/// 1. Loads the original JSON
/// 2. Queries the migrated SQLite database
/// 3. Compares the data to ensure migration was successful
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Migration Validation - JSON vs SQLite', () {
    late Database database;
    late MapRepository repository;
    late Map<String, dynamic> jsonData;

    setUpAll(() async {
      // Load the original JSON file
      final jsonFile = File('assets/CM.nodes.json');
      if (!jsonFile.existsSync()) {
        fail('JSON file not found: ${jsonFile.path}');
      }
      final jsonString = await jsonFile.readAsString();
      jsonData = json.decode(jsonString) as Map<String, dynamic>;

      // Open the migrated database (use absolute path for sqflite_ffi)
      final dbPath = File('assets/database/lnu_maps.db').absolute.path;
      final dbFile = File(dbPath);
      if (!dbFile.existsSync()) {
        fail('Database not found: $dbPath. Run migration script first.');
      }
      
      database = await openDatabase(dbPath, readOnly: true);
      repository = MapRepository(database);
    });

    tearDownAll(() async {
      await database.close();
    });

    test('Building count matches', () async {
      final jsonBuildings = jsonData['buildings'] as Map<String, dynamic>;
      final dbBuildings = await repository.getAllBuildings();

      expect(dbBuildings.length, equals(jsonBuildings.length),
          reason: 'Number of buildings should match');
    });

    test('Buildings data matches', () async {
      final jsonBuildings = jsonData['buildings'] as Map<String, dynamic>;
      final dbBuildings = await repository.getAllBuildings();

      for (final building in dbBuildings) {
        final jsonBuilding = jsonBuildings[building.id];
        expect(jsonBuilding, isNotNull,
            reason: 'Building ${building.id} should exist in JSON');

        expect(building.name, equals(jsonBuilding['name']),
            reason: 'Building name should match');
        expect(building.defaultFloorId, equals(jsonBuilding['defaultFloor']),
            reason: 'Default floor should match');
        
        final jsonOffset = jsonBuilding['offset'] ?? {};
        expect(building.offset.x, equals(jsonOffset['x'] ?? 0.0),
            reason: 'Building offset X should match');
        expect(building.offset.y, equals(jsonOffset['y'] ?? 0.0),
            reason: 'Building offset Y should match');
      }
    });

    test('Floor count matches', () async {
      final jsonBuildings = jsonData['buildings'] as Map<String, dynamic>;
      
      // Count total floors in JSON (they're nested in buildings)
      int jsonFloorCount = 0;
      for (final building in jsonBuildings.values) {
        final floors = building['floors'] as Map<String, dynamic>?;
        if (floors != null) {
          jsonFloorCount += floors.length;
        }
      }

      final dbFloors = await repository.getAllFloors();
      expect(dbFloors.length, equals(jsonFloorCount),
          reason: 'Number of floors should match');
    });

    test('Floors data matches', () async {
      final jsonBuildings = jsonData['buildings'] as Map<String, dynamic>;
      final dbFloors = await repository.getAllFloors();

      for (final floor in dbFloors) {
        // Find the floor in JSON (nested in buildings)
        Map<String, dynamic>? jsonFloor;
        for (final building in jsonBuildings.values) {
          final floors = building['floors'] as Map<String, dynamic>?;
          if (floors != null && floors.containsKey(floor.id)) {
            jsonFloor = floors[floor.id] as Map<String, dynamic>;
            break;
          }
        }

        expect(jsonFloor, isNotNull,
            reason: 'Floor ${floor.id} should exist in JSON');

        expect(floor.name, equals(jsonFloor!['name']),
            reason: 'Floor name should match');
        expect(floor.z, equals(jsonFloor['z']),
            reason: 'Floor z-level should match');
        expect(floor.background, equals(jsonFloor['background']),
            reason: 'Floor background should match');
      }
    });

    test('Point count matches', () async {
      final jsonPoints = jsonData['points'] as Map<String, dynamic>;
      final dbPoints = await repository.getAllPoints();

      expect(dbPoints.length, equals(jsonPoints.length),
          reason: 'Number of points should match');
    });

    test('Points data matches', () async {
      final jsonPoints = jsonData['points'] as Map<String, dynamic>;
      final dbPoints = await repository.getAllPoints();

      // Test a sample of points (testing all 867 would be slow)
      final sampleSize = 50;
      int tested = 0;
      
      for (final entry in dbPoints.entries) {
        if (tested >= sampleSize) break;
        
        final pointId = entry.key;
        final dbPoint = entry.value;
        final jsonPoint = jsonPoints[pointId];

        expect(jsonPoint, isNotNull,
            reason: 'Point $pointId should exist in JSON');

        expect(dbPoint.x, equals(jsonPoint['x']),
            reason: 'Point X coordinate should match');
        expect(dbPoint.y, equals(jsonPoint['y']),
            reason: 'Point Y coordinate should match');
        expect(dbPoint.buildingId, equals(jsonPoint['buildingId']),
            reason: 'Point buildingId should match');
        expect(dbPoint.floorId, equals(jsonPoint['floorId']),
            reason: 'Point floorId should match');
        expect(dbPoint.label, equals(jsonPoint['label']),
            reason: 'Point label should match');

        tested++;
      }

      print('✓ Validated $tested points');
    });

    test('Edge count matches', () async {
      final jsonNodes = jsonData['nodes'] as Map<String, dynamic>;
      
      // Count total edges in JSON adjacency list
      int jsonEdgeCount = 0;
      for (final neighbors in jsonNodes.values) {
        jsonEdgeCount += (neighbors as Map<String, dynamic>).length;
      }

      // Count edges in database
      final edgeCountResult = await database.rawQuery('SELECT COUNT(*) as count FROM edges');
      final dbEdgeCount = edgeCountResult.first['count'] as int;

      expect(dbEdgeCount, equals(jsonEdgeCount),
          reason: 'Number of edges should match');
    });

    test('Edge data matches (sample)', () async {
      final jsonNodes = jsonData['nodes'] as Map<String, dynamic>;
      
      // Test a sample of edges
      final samplePoints = jsonNodes.keys.take(10).toList();
      
      for (final fromPointId in samplePoints) {
        final jsonNeighbors = jsonNodes[fromPointId] as Map<String, dynamic>;
        final dbEdges = await repository.getEdgesForPoint(fromPointId);

        expect(dbEdges.length, equals(jsonNeighbors.length),
            reason: 'Number of edges for point $fromPointId should match');

        for (final dbEdge in dbEdges) {
          final toPointId = dbEdge.first.id;
          final dbWeight = dbEdge.second;
          final jsonWeight = jsonNeighbors[toPointId];

          expect(jsonWeight, isNotNull,
              reason: 'Edge $fromPointId -> $toPointId should exist in JSON');
          expect(dbWeight, closeTo(jsonWeight as num, 0.001),
              reason: 'Edge weight should match');
        }
      }

      print('✓ Validated edges for ${samplePoints.length} points');
    });

    test('Labeled points match', () async {
      final jsonPoints = jsonData['points'] as Map<String, dynamic>;
      
      // Count labeled points in JSON
      final jsonLabeledPoints = jsonPoints.values
          .where((p) => p['label'] != null && p['label'] != '')
          .length;

      final dbLabeledPoints = await repository.getLabeledPoints();

      expect(dbLabeledPoints.length, equals(jsonLabeledPoints),
          reason: 'Number of labeled points should match');
    });

    test('Search functionality works correctly', () async {
      final jsonPoints = jsonData['points'] as Map<String, dynamic>;
      
      // Pick a known labeled point from JSON
      final knownLabel = jsonPoints.values
          .firstWhere((p) => p['label'] != null && p['label'] != '')['label'] as String;

      final dbResults = await repository.searchPointsByLabel(knownLabel);

      expect(dbResults.isNotEmpty, isTrue,
          reason: 'Search should find the known label');
      expect(dbResults.any((p) => p.label == knownLabel), isTrue,
          reason: 'Search results should contain point with exact label');
    });
  });
}
