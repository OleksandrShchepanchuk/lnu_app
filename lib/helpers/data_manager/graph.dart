import 'package:lnu_nav_app/types/point.dart';
import 'package:lnu_nav_app/types/structures.dart';

import '../../types/pair.dart';

/// Graph class - Supports both eager-loaded and lazy-loaded edges
/// 
/// BEFORE: Required entire adjacency list in memory
/// AFTER: Can lazy-load edges from SQLite as needed
/// 
/// Two modes of operation:
/// 1. Eager mode: Pass full adjacency list (backward compatible)
/// 2. Lazy mode: Pass edge lookup function for on-demand loading
class Graph {
  // Eager loading: in-memory adjacency list
  final Map<Point, List<Pair<Point, double>>>? _eagerAdjacencyList;
  
  // Lazy loading: function to fetch neighbors on-demand
  final Future<List<Pair<Point, double>>> Function(Point point)? _lazyNeighborLoader;
  
  // Always required
  final Map<String, Point> points;
  final Map<String, BuildingOffset> offsets;
  late List<Point> labeledPoints;
  
  // Cache for lazy-loaded neighbors (optional performance optimization)
  final Map<String, List<Pair<Point, double>>> _neighborCache = {};
  final bool _enableCache;

  /// Backward-compatible constructor (eager loading)
  Graph(
    this.points,
    Map<Point, List<Pair<Point, double>>> adjacencyList,
    this.offsets, {
    bool enableCache = false,
  })  : _eagerAdjacencyList = adjacencyList,
        _lazyNeighborLoader = null,
        _enableCache = enableCache {
    _initializeLabeledPoints();
  }

  /// NEW: Lazy-loading constructor (for SQLite)
  /// Example usage:
  /// ```dart
  /// final graph = Graph.lazy(
  ///   points: allPoints,
  ///   offsets: buildingOffsets,
  ///   edgeLoader: (point) => repository.getEdgesForPoint(point.id),
  ///   enableCache: true, // Cache edges for better performance
  /// );
  /// ```
  Graph.lazy({
    required this.points,
    required this.offsets,
    required Future<List<Pair<Point, double>>> Function(Point point) edgeLoader,
    bool enableCache = true,
  })  : _eagerAdjacencyList = null,
        _lazyNeighborLoader = edgeLoader,
        _enableCache = enableCache {
    _initializeLabeledPoints();
  }

  /// Blank/empty graph for initialization
  static Graph blank() => Graph({}, {}, {});

  void _initializeLabeledPoints() {
    labeledPoints =
        points.values.where((element) => element.label != null).toList();
  }

  /// Get labeled points for a specific floor
  List<Point> labeledPointsForFloor(String id) {
    return labeledPoints.where((element) => element.floorId == id).toList();
  }

  /// Get neighbors for a point - works with both eager and lazy mode
  /// 
  /// In eager mode: Returns from in-memory adjacency list
  /// In lazy mode: Fetches from database via the edge loader function
  Future<List<Pair<Point, double>>> getNeighbors(Point point) async {
    // Eager mode: direct lookup
    if (_eagerAdjacencyList != null) {
      return _eagerAdjacencyList![point] ?? [];
    }

    // Lazy mode: check cache first, then load
    if (_enableCache && _neighborCache.containsKey(point.id)) {
      return _neighborCache[point.id]!;
    }

    if (_lazyNeighborLoader == null) {
      throw Exception('Graph not properly initialized: no adjacency list or loader');
    }

    // Load from database
    final neighbors = await _lazyNeighborLoader!(point);
    
    // Cache if enabled
    if (_enableCache) {
      _neighborCache[point.id] = neighbors;
    }

    return neighbors;
  }

  /// Synchronous version for backward compatibility
  /// Only works in eager mode
  List<Pair<Point, double>> getNeighborsSync(Point point) {
    if (_eagerAdjacencyList == null) {
      throw Exception(
        'getNeighborsSync() only works with eager-loaded graphs. '
        'Use getNeighbors() for lazy-loaded graphs.',
      );
    }
    return _eagerAdjacencyList![point] ?? [];
  }

  /// Get a point by ID
  Point? getPoint(String id) => points[id];

  /// Check if graph is using lazy loading
  bool get isLazy => _lazyNeighborLoader != null;

  /// Check if graph is using eager loading
  bool get isEager => _eagerAdjacencyList != null;

  /// Clear the neighbor cache (for lazy mode)
  void clearCache() {
    _neighborCache.clear();
  }

  /// Preload neighbors for specific points (optimization for lazy mode)
  /// Useful before running pathfinding to avoid repeated queries
  Future<void> preloadNeighbors(List<Point> pointsToPreload) async {
    if (_lazyNeighborLoader == null || !_enableCache) {
      return; // No-op for eager mode or when cache is disabled
    }

    for (final point in pointsToPreload) {
      if (!_neighborCache.containsKey(point.id)) {
        final neighbors = await _lazyNeighborLoader!(point);
        _neighborCache[point.id] = neighbors;
      }
    }
  }
}

