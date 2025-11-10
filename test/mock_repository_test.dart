import 'package:flutter_test/flutter_test.dart';
import 'package:lnu_nav_app/repositories/map_repository.dart';
import 'package:lnu_nav_app/types/pair.dart';
import 'package:lnu_nav_app/types/point.dart';
import 'package:lnu_nav_app/types/structures.dart';

/// Mock implementation of MapRepository for testing
/// 
/// This shows how to create a mock without using external mocking libraries.
/// It's simple, testable, and easy to understand.
class MockMapRepository implements MapRepository {
  final Map<String, Building> _buildings = {};
  final Map<String, Point> _points = {};
  final Map<String, List<Pair<Point, double>>> _edges = {};

  /// Add test data to the mock
  void addBuilding(Building building) {
    _buildings[building.id] = building;
  }

  void addPoint(Point point) {
    _points[point.id] = point;
  }

  void addEdge(String fromPointId, Point toPoint, double weight) {
    _edges.putIfAbsent(fromPointId, () => []).add(Pair(toPoint, weight));
  }

  @override
  Future<Building?> getBuildingById(String buildingId) async {
    return _buildings[buildingId];
  }

  @override
  Future<List<Building>> getAllBuildings() async {
    return _buildings.values.toList();
  }

  @override
  Future<Point?> getPointById(String pointId) async {
    return _points[pointId];
  }

  @override
  Future<Map<String, Point>> getAllPoints() async {
    return Map.from(_points);
  }

  @override
  Future<List<Point>> getPointsForBuilding(String buildingId) async {
    return _points.values
        .where((p) => p.buildingId == buildingId)
        .toList();
  }

  @override
  Future<List<Point>> getLabeledPoints() async {
    return _points.values
        .where((p) => p.label != null && p.label!.isNotEmpty)
        .toList();
  }

  @override
  Future<List<Point>> getLabeledPointsForFloor(String floorId) async {
    return _points.values
        .where((p) => p.floorId == floorId && p.label != null)
        .toList();
  }

  @override
  Future<List<Point>> searchPointsByLabel(String searchTerm) async {
    final lowerSearch = searchTerm.toLowerCase();
    return _points.values
        .where((p) =>
            p.label?.toLowerCase().contains(lowerSearch) ?? false)
        .toList();
  }

  @override
  Future<List<Pair<Point, double>>> getEdgesForPoint(String pointId) async {
    return _edges[pointId] ?? [];
  }

  @override
  Future<Map<String, List<Pair<Point, double>>>> getEdgesForPoints(
    List<String> pointIds,
  ) async {
    final result = <String, List<Pair<Point, double>>>{};
    for (final id in pointIds) {
      result[id] = _edges[id] ?? [];
    }
    return result;
  }

  @override
  Future<Map<Point, List<Pair<Point, double>>>> getAllEdges() async {
    final result = <Point, List<Pair<Point, double>>>{};
    for (final entry in _edges.entries) {
      final point = _points[entry.key];
      if (point != null) {
        result[point] = entry.value;
      }
    }
    return result;
  }

  @override
  Future<Map<String, BuildingOffset>> getBuildingOffsets() async {
    final offsets = <String, BuildingOffset>{};
    for (final building in _buildings.values) {
      offsets[building.id] = building.offset;
    }
    return offsets;
  }

  @override
  Future<void> warmupCache() async {
    // No-op for mock
  }

  @override
  void clearCache() {
    // No-op for mock
  }

  // These are not part of the interface but exist in the real implementation
  // We don't need to implement them for the mock
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MockMapRepository Tests', () {
    late MockMapRepository mockRepo;

    setUp(() {
      mockRepo = MockMapRepository();

      // Add test data
      final building = Building(
        id: 'b1',
        name: 'Test Building',
        subtitle: 'Test',
        defaultFloorId: 'f1',
        offset: BuildingOffset(x: 10, y: 20),
        floors: {
          'f1': Floor(
            id: 'f1',
            name: 'Floor 1',
            z: 0,
            background: 'bg.svg',
          ),
        },
      );

      final point1 = Point(
        'p1',  // id
        0,     // x
        0,     // y
        1,     // z
        'b1',  // buildingId
        'f1',  // floorId
        'Room A', // label
      );

      final point2 = Point(
        'p2',  // id
        10,    // x
        10,    // y
        1,     // z
        'b1',  // buildingId
        'f1',  // floorId
        'Room B', // label
      );

      mockRepo.addBuilding(building);
      mockRepo.addPoint(point1);
      mockRepo.addPoint(point2);
      mockRepo.addEdge('p1', point2, 5.0);
    });

    test('mock returns added buildings', () async {
      final building = await mockRepo.getBuildingById('b1');

      expect(building, isNotNull);
      expect(building!.name, equals('Test Building'));
    });

    test('mock returns added points', () async {
      final points = await mockRepo.getAllPoints();

      expect(points.length, equals(2));
      expect(points.containsKey('p1'), isTrue);
      expect(points.containsKey('p2'), isTrue);
    });

    test('mock returns edges', () async {
      final edges = await mockRepo.getEdgesForPoint('p1');

      expect(edges.length, equals(1));
      expect(edges.first.first.id, equals('p2'));
      expect(edges.first.second, equals(5.0));
    });

    test('mock filters points by building', () async {
      final points = await mockRepo.getPointsForBuilding('b1');

      expect(points.length, equals(2));
      expect(points.every((p) => p.buildingId == 'b1'), isTrue);
    });

    test('mock search works', () async {
      final results = await mockRepo.searchPointsByLabel('Room');

      expect(results.length, equals(2));
    });
  });

  group('Using Mock in Tests', () {
    test('example: test graph with mocked repository', () async {
      final mockRepo = MockMapRepository();

      // Setup test data
      final point1 = Point(
        'p1', 0, 0, 1, 'b1', 'f1', 'Start',
      );

      final point2 = Point(
        'p2', 10, 10, 1, 'b1', 'f1', 'End',
      );

      mockRepo.addPoint(point1);
      mockRepo.addPoint(point2);
      mockRepo.addEdge('p1', point2, 5.0);

      // Test edge loading
      final edges = await mockRepo.getEdgesForPoint('p1');

      expect(edges.length, equals(1));
      expect(edges.first.first.label, equals('End'));
    });

    test('example: test search functionality', () async {
      final mockRepo = MockMapRepository();

      // Add various points
      mockRepo.addPoint(Point(
        'p1', 0, 0, 1, 'b1', 'f1', 'Computer Lab',
      ));

      mockRepo.addPoint(Point(
        'p2', 10, 10, 1, 'b1', 'f1', 'Chemistry Lab',
      ));

      mockRepo.addPoint(Point(
        'p3', 20, 20, 1, 'b1', 'f1', 'Library',
      ));

      // Test search
      final labResults = await mockRepo.searchPointsByLabel('Lab');
      final libraryResults = await mockRepo.searchPointsByLabel('Library');

      expect(labResults.length, equals(2));
      expect(libraryResults.length, equals(1));
      expect(libraryResults.first.label, equals('Library'));
    });
  });
}
