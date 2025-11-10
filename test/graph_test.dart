import 'package:flutter_test/flutter_test.dart';
import 'package:lnu_nav_app/helpers/data_manager/graph.dart';
import 'package:lnu_nav_app/types/pair.dart';
import 'package:lnu_nav_app/types/point.dart';
import 'package:lnu_nav_app/types/structures.dart';

/// Tests for Graph class with both eager and lazy loading
void main() {
  group('Graph - Eager Loading (Backward Compatible)', () {
    late Graph graph;
    late Map<String, Point> points;
    late Map<Point, List<Pair<Point, double>>> adjacencyList;

    setUp(() {
      // Create test points
      final point1 = Point('p1', 0, 0, 1, 'b1', 'f1', 'Start');
      final point2 = Point('p2', 10, 10, 1, 'b1', 'f1', 'Middle');
      final point3 = Point('p3', 20, 20, 1, 'b1', 'f1', 'End');

      points = {
        'p1': point1,
        'p2': point2,
        'p3': point3,
      };

      // Create adjacency list
      adjacencyList = {
        point1: [
          Pair(point2, 5.0),
          Pair(point3, 15.0),
        ],
        point2: [
          Pair(point3, 5.0),
        ],
        point3: [],
      };

      graph = Graph(
        points,
        adjacencyList,
        {'b1': BuildingOffset.zero},
      );
    });

    test('creates graph with correct points', () {
      expect(graph.points.length, equals(3));
      expect(graph.getPoint('p1'), isNotNull);
      expect(graph.getPoint('p2'), isNotNull);
      expect(graph.getPoint('p3'), isNotNull);
    });

    test('identifies labeled points correctly', () {
      expect(graph.labeledPoints.length, equals(3));
      expect(graph.labeledPoints.every((p) => p.label != null), isTrue);
    });

    test('filters labeled points by floor', () {
      final floorPoints = graph.labeledPointsForFloor('f1');
      expect(floorPoints.length, equals(3));
    });

    test('getNeighborsSync returns correct neighbors', () async {
      final point1 = points['p1']!;
      final neighbors = await graph.getNeighbors(point1);

      expect(neighbors.length, equals(2));
      expect(neighbors[0].first.id, equals('p2'));
      expect(neighbors[0].second, equals(5.0));
    });

    test('isEager returns true for eager-loaded graph', () {
      expect(graph.isEager, isTrue);
      expect(graph.isLazy, isFalse);
    });
  });

  group('Graph - Lazy Loading', () {
    late Graph lazyGraph;
    late Map<String, Point> points;
    late Map<String, List<Pair<Point, double>>> mockEdges;

    setUp(() {
      // Create test points
      final point1 = Point('p1', 0, 0, 1, 'b1', 'f1', 'Start');
      final point2 = Point('p2', 10, 10, 1, 'b1', 'f1', 'Middle');
      final point3 = Point('p3', 20, 20, 1, 'b1', 'f1');

      points = {
        'p1': point1,
        'p2': point2,
        'p3': point3,
      };

      // Mock edge data (simulates repository responses)
      mockEdges = {
        'p1': [
          Pair(point2, 5.0),
          Pair(point3, 15.0),
        ],
        'p2': [
          Pair(point3, 5.0),
        ],
        'p3': [],
      };

      // Create lazy graph with mock edge loader
      lazyGraph = Graph.lazy(
        points: points,
        offsets: {'b1': BuildingOffset.zero},
        edgeLoader: (point) async {
          // Simulate async database query
          await Future.delayed(Duration(milliseconds: 10));
          return mockEdges[point.id] ?? [];
        },
        enableCache: true,
      );
    });

    test('creates lazy graph with correct points', () {
      expect(lazyGraph.points.length, equals(3));
      expect(lazyGraph.getPoint('p1'), isNotNull);
    });

    test('isLazy returns true for lazy-loaded graph', () {
      expect(lazyGraph.isLazy, isTrue);
      expect(lazyGraph.isEager, isFalse);
    });

    test('getNeighbors loads edges asynchronously', () async {
      final point1 = points['p1']!;
      final neighbors = await lazyGraph.getNeighbors(point1);

      expect(neighbors.length, equals(2));
      expect(neighbors[0].first.id, equals('p2'));
      expect(neighbors[0].second, equals(5.0));
    });

    test('cache improves performance on repeated queries', () async {
      final point1 = points['p1']!;

      // First call (loads from mock)
      final stopwatch1 = Stopwatch()..start();
      await lazyGraph.getNeighbors(point1);
      stopwatch1.stop();

      // Second call (should use cache)
      final stopwatch2 = Stopwatch()..start();
      await lazyGraph.getNeighbors(point1);
      stopwatch2.stop();

      // Cached call should be significantly faster
      expect(
        stopwatch2.elapsedMicroseconds,
        lessThan(stopwatch1.elapsedMicroseconds),
      );
    });

    test('clearCache removes cached edges', () async {
      final point1 = points['p1']!;

      // Load and cache
      await lazyGraph.getNeighbors(point1);

      // Clear cache
      lazyGraph.clearCache();

      // Next call should reload (we can't directly test cache state,
      // but we ensure the method works)
      final neighbors = await lazyGraph.getNeighbors(point1);
      expect(neighbors.length, equals(2));
    });

    test('preloadNeighbors caches multiple points', () async {
      final point1 = points['p1']!;
      final point2 = points['p2']!;

      // Preload neighbors
      await lazyGraph.preloadNeighbors([point1, point2]);

      // Subsequent calls should be fast (cached)
      final stopwatch = Stopwatch()..start();
      await lazyGraph.getNeighbors(point1);
      await lazyGraph.getNeighbors(point2);
      stopwatch.stop();

      // Should be very fast since they're cached
      expect(stopwatch.elapsedMicroseconds, lessThan(5000)); // < 5ms
    });

    test('getNeighborsSync throws error on lazy graph', () {
      final point1 = points['p1']!;

      expect(
        () => lazyGraph.getNeighborsSync(point1),
        throwsException,
      );
    });

    test('handles point with no edges', () async {
      final point3 = points['p3']!;
      final neighbors = await lazyGraph.getNeighbors(point3);

      expect(neighbors.isEmpty, isTrue);
    });
  });

  group('Graph - Edge Cases', () {
    test('blank graph is empty', () {
      final blankGraph = Graph.blank();

      expect(blankGraph.points.isEmpty, isTrue);
      expect(blankGraph.labeledPoints.isEmpty, isTrue);
    });

    test('graph handles points without labels', () {
      final pointWithLabel = Point('p1', 0, 0, 1, 'b1', 'f1', 'Labeled');
      final pointWithoutLabel = Point('p2', 10, 10, 1, 'b1', 'f1', null);

      final graph = Graph(
        {'p1': pointWithLabel, 'p2': pointWithoutLabel},
        {},
        {},
      );

      expect(graph.points.length, equals(2));
      expect(graph.labeledPoints.length, equals(1));
      expect(graph.labeledPoints.first.id, equals('p1'));
    });

    test('getPoint returns null for non-existent point', () {
      final graph = Graph({}, {}, {});

      expect(graph.getPoint('non_existent'), isNull);
    });
  });
}
