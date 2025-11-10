import 'package:lnu_nav_app/types/pair.dart';
import 'package:lnu_nav_app/types/point.dart';
import 'package:lnu_nav_app/types/structures.dart';
import 'package:sqflite/sqflite.dart';

/// MapRepository - Injectable repository for map data queries
/// 
/// This class provides a clean abstraction over SQLite database queries.
/// It accepts a Database instance via constructor (dependency injection).
/// 
/// KEY BENEFITS:
/// - Easy to mock in tests
/// - Clear separation of concerns
/// - Type-safe domain models (not raw Map<String, dynamic>)
/// - Single responsibility: data access only
class MapRepository {
  final Database _database;
  
  // Optional: in-memory cache for frequently accessed data
  final Map<String, Building> _buildingCache = {};
  final Map<String, Point> _pointCache = {};
  bool _cacheInitialized = false;

  /// Constructor accepts Database instance (dependency injection)
  MapRepository(this._database);

  // ==================== BUILDING QUERIES ====================

  /// Get a building by its ID
  /// Returns null if not found
  Future<Building?> getBuildingById(String buildingId) async {
    // Check cache first
    if (_buildingCache.containsKey(buildingId)) {
      return _buildingCache[buildingId];
    }

    final List<Map<String, dynamic>> results = await _database.query(
      'buildings',
      where: 'id = ?',
      whereArgs: [buildingId],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final building = _buildingFromMap(results.first);
    
    // Load floors for this building
    final floors = await _getFloorsForBuilding(buildingId);
    final buildingWithFloors = Building(
      id: building.id,
      name: building.name,
      subtitle: building.subtitle,
      defaultFloorId: building.defaultFloorId,
      offset: building.offset,
      floors: floors,
    );

    // Cache it
    _buildingCache[buildingId] = buildingWithFloors;
    return buildingWithFloors;
  }

  /// Get all buildings
  Future<List<Building>> getAllBuildings() async {
    final List<Map<String, dynamic>> results = await _database.query('buildings');
    
    final buildings = <Building>[];
    for (final row in results) {
      final building = _buildingFromMap(row);
      final floors = await _getFloorsForBuilding(building.id);
      
      buildings.add(Building(
        id: building.id,
        name: building.name,
        subtitle: building.subtitle,
        defaultFloorId: building.defaultFloorId,
        offset: building.offset,
        floors: floors,
      ));
    }
    
    return buildings;
  }

  /// Get floors for a specific building
  Future<Map<String, Floor>> _getFloorsForBuilding(String buildingId) async {
    final List<Map<String, dynamic>> results = await _database.query(
      'floors',
      where: 'building_id = ?',
      whereArgs: [buildingId],
    );

    final Map<String, Floor> floors = {};
    for (final row in results) {
      final floor = _floorFromMap(row);
      floors[floor.id] = floor;
    }
    
    return floors;
  }

  /// Get all floors
  Future<List<Floor>> getAllFloors() async {
    final List<Map<String, dynamic>> results = await _database.query('floors');
    return results.map((row) => _floorFromMap(row)).toList();
  }

  // ==================== POINT QUERIES ====================

  /// Get a single point by ID
  Future<Point?> getPointById(String pointId) async {
    // Check cache first
    if (_pointCache.containsKey(pointId)) {
      return _pointCache[pointId];
    }

    final List<Map<String, dynamic>> results = await _database.rawQuery('''
      SELECT p.*, f.z as floor_z
      FROM points p
      INNER JOIN floors f ON p.floor_id = f.id
      WHERE p.id = ?
    ''', [pointId]);

    if (results.isEmpty) return null;

    final point = _pointFromMap(results.first);
    _pointCache[pointId] = point;
    return point;
  }

  /// Get all points (use with caution on large datasets)
  Future<Map<String, Point>> getAllPoints() async {
    final List<Map<String, dynamic>> results = await _database.rawQuery('''
      SELECT p.*, f.z as floor_z
      FROM points p
      INNER JOIN floors f ON p.floor_id = f.id
    ''');
    
    final Map<String, Point> points = {};
    for (final row in results) {
      final point = _pointFromMap(row);
      points[point.id] = point;
      _pointCache[point.id] = point;
    }
    
    return points;
  }

  /// Get points for a specific building
  Future<List<Point>> getPointsForBuilding(String buildingId) async {
    final List<Map<String, dynamic>> results = await _database.rawQuery('''
      SELECT p.*, f.z as floor_z
      FROM points p
      INNER JOIN floors f ON p.floor_id = f.id
      WHERE p.building_id = ?
    ''', [buildingId]);

    return results.map((row) => _pointFromMap(row)).toList();
  }

  /// Get labeled points (points with labels)
  Future<List<Point>> getLabeledPoints() async {
    final List<Map<String, dynamic>> results = await _database.rawQuery('''
      SELECT p.*, f.z as floor_z
      FROM points p
      INNER JOIN floors f ON p.floor_id = f.id
      WHERE p.label IS NOT NULL AND p.label != ?
    ''', ['']);

    return results.map((row) => _pointFromMap(row)).toList();
  }

  /// Get labeled points for a specific floor
  Future<List<Point>> getLabeledPointsForFloor(String floorId) async {
    final List<Map<String, dynamic>> results = await _database.rawQuery('''
      SELECT p.*, f.z as floor_z
      FROM points p
      INNER JOIN floors f ON p.floor_id = f.id
      WHERE p.floor_id = ? AND p.label IS NOT NULL AND p.label != ?
    ''', [floorId, '']);

    return results.map((row) => _pointFromMap(row)).toList();
  }

  /// Search points by label (case-insensitive)
  Future<List<Point>> searchPointsByLabel(String searchTerm) async {
    final List<Map<String, dynamic>> results = await _database.rawQuery('''
      SELECT p.*, f.z as floor_z
      FROM points p
      INNER JOIN floors f ON p.floor_id = f.id
      WHERE p.label LIKE ? COLLATE NOCASE
    ''', ['%$searchTerm%']);

    return results.map((row) => _pointFromMap(row)).toList();
  }

  // ==================== EDGE QUERIES (for A* pathfinding) ====================

  /// Get edges for a specific point (its neighbors with weights)
  /// This is the KEY method for lazy-loading graph edges
  Future<List<Pair<Point, double>>> getEdgesForPoint(String pointId) async {
    // Query the edges table
    final List<Map<String, dynamic>> results = await _database.query(
      'edges',
      where: 'from_point_id = ?',
      whereArgs: [pointId],
    );

    final edges = <Pair<Point, double>>[];
    
    for (final row in results) {
      final toPointId = row['to_point_id'] as String;
      final weight = (row['weight'] as num).toDouble();
      
      // Get the target point
      final point = await getPointById(toPointId);
      if (point != null) {
        edges.add(Pair(point, weight));
      }
    }

    return edges;
  }

  /// Get edges for multiple points at once (batch query for performance)
  /// Returns Map<pointId, List<Pair<Point, weight>>>
  Future<Map<String, List<Pair<Point, double>>>> getEdgesForPoints(
    List<String> pointIds,
  ) async {
    if (pointIds.isEmpty) return {};

    // Create placeholders for IN clause
    final placeholders = List.filled(pointIds.length, '?').join(',');
    
    final List<Map<String, dynamic>> results = await _database.query(
      'edges',
      where: 'from_point_id IN ($placeholders)',
      whereArgs: pointIds,
    );

    // Group edges by from_point_id
    final Map<String, List<Map<String, dynamic>>> edgesByPoint = {};
    for (final row in results) {
      final fromPointId = row['from_point_id'] as String;
      edgesByPoint.putIfAbsent(fromPointId, () => []).add(row);
    }

    // Convert to Pair<Point, double>
    final Map<String, List<Pair<Point, double>>> result = {};
    
    for (final entry in edgesByPoint.entries) {
      final edges = <Pair<Point, double>>[];
      
      for (final row in entry.value) {
        final toPointId = row['to_point_id'] as String;
        final weight = (row['weight'] as num).toDouble();
        
        final point = await getPointById(toPointId);
        if (point != null) {
          edges.add(Pair(point, weight));
        }
      }
      
      result[entry.key] = edges;
    }

    return result;
  }

  /// Get all edges (for pre-loading the entire graph)
  /// Use this if you want to load all data at startup like before
  Future<Map<Point, List<Pair<Point, double>>>> getAllEdges() async {
    // First get all points
    final allPoints = await getAllPoints();
    
    // Then get all edges
    final List<Map<String, dynamic>> results = await _database.query('edges');
    
    // Build adjacency list
    final Map<String, List<Pair<String, double>>> edgesByPointId = {};
    for (final row in results) {
      final fromPointId = row['from_point_id'] as String;
      final toPointId = row['to_point_id'] as String;
      final weight = (row['weight'] as num).toDouble();
      
      edgesByPointId
          .putIfAbsent(fromPointId, () => [])
          .add(Pair(toPointId, weight));
    }

    // Convert to Point objects
    final Map<Point, List<Pair<Point, double>>> adjacencyList = {};
    
    for (final entry in edgesByPointId.entries) {
      final fromPoint = allPoints[entry.key];
      if (fromPoint == null) continue;
      
      final neighbors = <Pair<Point, double>>[];
      for (final edge in entry.value) {
        final toPoint = allPoints[edge.first];
        if (toPoint != null) {
          neighbors.add(Pair(toPoint, edge.second));
        }
      }
      
      adjacencyList[fromPoint] = neighbors;
    }

    return adjacencyList;
  }

  // ==================== OFFSET QUERIES ====================

  /// Get building offsets
  Future<Map<String, BuildingOffset>> getBuildingOffsets() async {
    final List<Map<String, dynamic>> results = await _database.query('buildings');
    
    final Map<String, BuildingOffset> offsets = {};
    for (final row in results) {
      final id = row['id'] as String;
      final offsetX = (row['offset_x'] as num?)?.toDouble() ?? 0.0;
      final offsetY = (row['offset_y'] as num?)?.toDouble() ?? 0.0;
      
      offsets[id] = BuildingOffset(x: offsetX, y: offsetY);
    }
    
    return offsets;
  }

  // ==================== CACHE MANAGEMENT ====================

  /// Pre-load all data into cache (optional, for faster subsequent queries)
  Future<void> warmupCache() async {
    if (_cacheInitialized) return;
    
    print('🔥 Warming up cache...');
    await getAllPoints();
    await getAllBuildings();
    _cacheInitialized = true;
    print('✅ Cache warmed up');
  }

  /// Clear in-memory cache
  void clearCache() {
    _buildingCache.clear();
    _pointCache.clear();
    _cacheInitialized = false;
  }

  // ==================== HELPER METHODS ====================

  /// Convert database row to Building object
  Building _buildingFromMap(Map<String, dynamic> map) {
    return Building(
      id: map['id'] as String,
      name: map['name'] as String,
      subtitle: map['subtitle'] as String?,
      defaultFloorId: map['default_floor_id'] as String,
      offset: BuildingOffset(
        x: (map['offset_x'] as num?)?.toDouble() ?? 0.0,
        y: (map['offset_y'] as num?)?.toDouble() ?? 0.0,
      ),
      floors: {}, // Will be populated separately
    );
  }

  /// Convert database row to Floor object
  Floor _floorFromMap(Map<String, dynamic> map) {
    return Floor(
      id: map['id'] as String,
      name: map['name'] as String,
      z: (map['z'] as num).toDouble(),
      background: map['background'] as String,
      subtitle: map['subtitle'] as String?,
    );
  }

  /// Convert database row to Point object
  Point _pointFromMap(Map<String, dynamic> map) {
    return Point(
      map['id'] as String,
      (map['x'] as num).toDouble(),
      (map['y'] as num).toDouble(),
      (map['floor_z'] as num).toDouble(), // Get z from joined floor table
      map['building_id'] as String,
      map['floor_id'] as String,
      map['label'] as String?,
      map['type'] as String?, // kind
      null, // color - not stored in DB
    );
  }
}
