# Before/After Migration Examples

## 1. Main App Initialization

### ❌ BEFORE (JSON Loading)

```dart
// main.dart
void main() {
  runApp(
    Providers(
      child: MyApp(),
    ),
  );
}

// Providers widget
class Providers extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<UiModel>(create: (_) => UiModel()),
        ChangeNotifierProvider<StructureData>(create: (_) => StructureData()),
        ChangeNotifierProvider<ConfigStorage>(create: (_) => ConfigStorage()),
      ],
      child: child,
    );
  }
}
```

### ✅ AFTER (SQLite with DI)

```dart
// main.dart
void main() {
  runApp(
    Providers(  // Now includes database providers
      child: MyApp(),
    ),
  );
}

// Providers widget with dependency injection chain
class Providers extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Existing providers
        ChangeNotifierProvider<UiModel>(create: (_) => UiModel()),
        ChangeNotifierProvider<ConfigStorage>(create: (_) => ConfigStorage()),

        // 1. DatabaseHelper (base layer)
        Provider<DatabaseHelper>(
          create: (_) => DatabaseHelper(),
          dispose: (_, helper) => helper.close(),
        ),

        // 2. Database instance (async initialization)
        FutureProvider<Database?>(
          create: (context) async {
            final helper = context.read<DatabaseHelper>();
            return await helper.getDatabase();
          },
          initialData: null,
        ),

        // 3. MapRepository (depends on Database)
        ProxyProvider<Database?, MapRepository?>(
          update: (context, database, previous) {
            if (database == null) return null;
            return previous ?? MapRepository(database);
          },
        ),

        // 4. StructureData (depends on MapRepository)
        ChangeNotifierProxyProvider<MapRepository?, StructureData>(
          create: (_) => StructureData(),
          update: (context, repository, previous) {
            if (previous != null && repository != null) {
              previous.repository = repository;
            }
            return previous ?? StructureData();
          },
        ),
      ],
      child: child,
    );
  }
}
```

---

## 2. Loading Structure Data

### ❌ BEFORE (Preloading from JSON)

```dart
// main.dart
class Preloading {
  static Structure? cache;

  Future<Structure?> start() async {
    final structurePath = ConfigStorage().structurePath;

    try {
      final structureStr = await rootBundle.loadString(structurePath);
      final result = await compute(_start, structureStr);
      return result;
    } catch (e) {
      print('Failed to preload data | $e');
      throw Exception('Failed to preload data');
    }
  }

  Future<Structure> _start(String structureData) async {
    final structure = JsonReader.readStr(structureData, Structure.blank);
    // Build entire graph in memory
    final graph = Graph(structure.points, structure.adjacencyList, structure.offsets);
    return structure;
  }
}

// In a widget
class MyHomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Structure?>(
      future: Preloading().start(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return CircularProgressIndicator();
        }

        // Manually set structure
        Provider.of<StructureData>(context, listen: false)
            .structure = snapshot.data!;

        return MapView();
      },
    );
  }
}
```

### ✅ AFTER (Automatic Loading from SQLite)

```dart
// No more Preloading class needed!
// StructureData automatically loads from repository

// In a widget - just use the data
class MyHomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final structureData = Provider.of<StructureData>(context);
    final repository = Provider.of<MapRepository?>(context);

    // Check if repository is ready
    if (repository == null) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Data is automatically loaded by StructureData
    return MapView();
  }
}

// Or use Consumer for better rebuilds
class MyHomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<MapRepository?>(
      builder: (context, repository, child) {
        if (repository == null) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return MapView();
      },
    );
  }
}
```

---

## 3. Using Graph for Pathfinding

### ❌ BEFORE (Synchronous with in-memory graph)

```dart
class MapWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final structureData = Provider.of<StructureData>(context);
    final graph = structureData.graph;

    // Find path synchronously
    void findPath(Point start, Point end) {
      final astar = AStar(graph);
      final path = astar.findPath(start, end);  // Synchronous

      if (path != null) {
        print('Path found: ${path.length} points');
      }
    }

    return YourMapUI(onFindPath: findPath);
  }
}
```

### ✅ AFTER (Async with lazy-loaded edges)

```dart
class MapWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final structureData = Provider.of<StructureData>(context);
    final graph = structureData.graph;  // Now returns lazy Graph

    // Find path asynchronously (lazy loads edges from SQLite)
    Future<void> findPath(Point start, Point end) async {
      final astar = AStar(graph);
      final path = await astar.findPath(start, end);  // Now async

      if (path != null) {
        print('Path found: ${path.length} points');
      }
    }

    return YourMapUI(onFindPath: findPath);
  }
}

// Or use FutureBuilder
class PathFinder extends StatelessWidget {
  final Point start;
  final Point end;

  @override
  Widget build(BuildContext context) {
    final structureData = Provider.of<StructureData>(context);
    final graph = structureData.graph;

    return FutureBuilder<List<Point>?>(
      future: AStar(graph).findPath(start, end),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        }

        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }

        final path = snapshot.data;
        if (path == null) {
          return Text('No path found');
        }

        return PathVisualization(path: path);
      },
    );
  }
}
```

---

## 4. Searching Points

### ❌ BEFORE (In-memory search)

```dart
class SearchWidget extends StatefulWidget {
  @override
  _SearchWidgetState createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  List<Point> searchResults = [];

  void search(String query) {
    final structureData = Provider.of<StructureData>(context, listen: false);

    // Search through in-memory points
    setState(() {
      searchResults = structureData.structure.points.values
          .where((p) => p.label?.toLowerCase().contains(query.toLowerCase()) ?? false)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      onSearch: search,
      results: searchResults,
    );
  }
}
```

### ✅ AFTER (Database query with indexes)

```dart
class SearchWidget extends StatefulWidget {
  @override
  _SearchWidgetState createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  Future<List<Point>>? searchFuture;

  void search(String query) async {
    final structureData = Provider.of<StructureData>(context, listen: false);

    // Use optimized database search
    setState(() {
      searchFuture = structureData.searchPoints(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SearchBar(onSearch: search),

        // Display results with FutureBuilder
        Expanded(
          child: FutureBuilder<List<Point>>(
            future: searchFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return CircularProgressIndicator();
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Text('No results');
              }

              return ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) {
                  final point = snapshot.data![index];
                  return PointListTile(point: point);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
```

---

## 5. Accessing Repository Directly

### ✅ NEW CAPABILITY (Direct database queries)

```dart
// You can now query specific data without loading everything

class BuildingDetailsPage extends StatelessWidget {
  final String buildingId;

  @override
  Widget build(BuildContext context) {
    final repository = Provider.of<MapRepository?>(context);

    if (repository == null) {
      return CircularProgressIndicator();
    }

    return FutureBuilder<Building?>(
      future: repository.getBuildingById(buildingId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return CircularProgressIndicator();
        }

        final building = snapshot.data!;
        return BuildingDetailsView(building: building);
      },
    );
  }
}

// Get points for a specific floor
class FloorView extends StatelessWidget {
  final String floorId;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<MapRepository?>();

    return FutureBuilder<List<Point>>(
      future: repository?.getLabeledPointsForFloor(floorId) ?? Future.value([]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();

        return FloorMapWithPoints(points: snapshot.data!);
      },
    );
  }
}
```

---

## Key Benefits Summary

| Aspect            | Before (JSON)                  | After (SQLite + DI)       |
| ----------------- | ------------------------------ | ------------------------- |
| **Data Loading**  | Manual preloading in main.dart | Automatic via Provider    |
| **Memory Usage**  | Load everything upfront        | Lazy load on demand       |
| **Search**        | In-memory filter               | Indexed database query    |
| **Pathfinding**   | Synchronous                    | Async (non-blocking)      |
| **Testing**       | Hard to mock                   | Easy to inject mocks      |
| **Flexibility**   | Load all or nothing            | Query specific data       |
| **Startup Time**  | Slower (parse JSON)            | Faster (direct DB access) |
| **Code Coupling** | Tight (manual setup)           | Loose (DI pattern)        |

---

## Migration Checklist

-   [x] Add SQLite dependencies to pubspec.yaml
-   [x] Create DatabaseHelper class
-   [x] Create MapRepository class
-   [x] Update providers.dart with DB providers
-   [x] Update widgets to use async/await for pathfinding
-   [x] Replace in-memory searches with repository queries
-   [x] Test with actual SQLite database
-   [ ] Remove old JSON loading code
-   [ ] Remove Preloading class
-   [ ] Update tests to use mocked repositories
