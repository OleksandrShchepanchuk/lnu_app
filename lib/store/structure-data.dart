import 'package:flutter/foundation.dart';
import 'package:lnu_nav_app/components/map/controllers/map.dart';
import 'package:lnu_nav_app/helpers/data_manager/graph.dart';
import 'package:lnu_nav_app/repositories/map_repository.dart';
import 'package:lnu_nav_app/types/point.dart';

import '../types/structures.dart';

/// StructureData - Now uses MapRepository via dependency injection
/// 
/// BEFORE: Loaded Structure from JSON in main.dart
/// AFTER: Gets data from SQLite via MapRepository
class StructureData extends ChangeNotifier {
  Structure _structure = Structure.blank;
  MapController? _primaryController;
  MapRepository? _repository;
  
  // Cache for the lazy-loaded graph
  Graph? _lazyGraph;

  MapController? get primaryController => _primaryController;
  Structure get structure => _structure;
  
  /// Setter for backward compatibility with JSON loading
  set structure(Structure structure) {
    _structure = structure;
    _primaryController = MapController(structData: this);
    _lazyGraph = null; // Clear lazy graph when structure changes
    notifyListeners();
  }

  /// Inject repository (called by Provider)
  set repository(MapRepository? repo) {
    _repository = repo;
    if (_repository != null) {
      _initializeFromRepository();
    }
  }

  MapRepository? get repository => _repository;

  /// Initialize structure data from repository
  Future<void> _initializeFromRepository() async {
    if (_repository == null) return;

    try {
      print('🔄 Loading structure from SQLite...');
      
      // Load buildings and points (points are already a Map<String, Point>)
      final buildings = await _repository!.getAllBuildings();
      final pointsMap = await _repository!.getAllPoints();

      // Create structure - offsets are derived from buildings
      final buildingsMap = {for (var b in buildings) b.id: b};
      
      _structure = Structure(
        id: 'lnu', // Default structure ID
        name: 'LNU Campus',
        buildings: buildingsMap,
        defaultBuildingId: buildings.isNotEmpty ? buildings.first.id : '',
        location: StructureLocation.empty, // Can be loaded if needed
        points: pointsMap,
        adjacencyList: {}, // Not used in lazy mode
        subtitle: null,
      );

      _primaryController = MapController(structData: this);
      
      print('✅ Structure loaded: ${buildings.length} buildings, ${pointsMap.length} points');
      notifyListeners();
    } catch (e, stackTrace) {
      print('❌ Failed to load structure from repository: $e');
      print(stackTrace);
    }
  }

  /// Get graph - returns lazy-loaded graph using repository
  /// 
  /// BEFORE: Graph(_structure.points, _structure.adjacencyList, _structure.offsets)
  /// AFTER: Lazy graph that queries SQLite on-demand
  Graph get graph {
    if (_repository == null) {
      // Fallback to old behavior if no repository (backward compatible)
      return Graph(_structure.points, _structure.adjacencyList, _structure.offsets);
    }

    // Create or return cached lazy graph
    if (_lazyGraph == null) {
      _lazyGraph = Graph.lazy(
        points: _structure.points,
        offsets: _structure.offsets,
        edgeLoader: (point) => _repository!.getEdgesForPoint(point.id),
        enableCache: true, // Enable caching for performance
      );
    }

    return _lazyGraph!;
  }

  /// Reload structure from repository
  Future<void> reload() async {
    if (_repository != null) {
      _lazyGraph?.clearCache(); // Clear graph cache
      await _initializeFromRepository();
    }
  }

  /// Search for points by label
  Future<List<Point>> searchPoints(String query) async {
    if (_repository != null) {
      return await _repository!.searchPointsByLabel(query);
    }
    
    // Fallback to in-memory search
    return _structure.points.values
        .where((p) => p.label?.toLowerCase().contains(query.toLowerCase()) ?? false)
        .toList();
  }

  /// Get labeled points for a specific floor
  Future<List<Point>> getLabeledPointsForFloor(String floorId) async {
    if (_repository != null) {
      return await _repository!.getLabeledPointsForFloor(floorId);
    }
    
    // Fallback to in-memory filtering
    return _structure.points.values
        .where((p) => p.floorId == floorId && p.label != null)
        .toList();
  }
}

