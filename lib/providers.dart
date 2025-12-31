import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

// Internal App Imports
import 'package:lnu_nav_app/database/database_helper.dart';
import 'package:lnu_nav_app/repositories/map_repository.dart';
import 'package:lnu_nav_app/store/structure-data.dart';
import 'package:lnu_nav_app/store/permanent/config-storage.dart';
import 'package:lnu_nav_app/helpers/ui.dart';

/// Root Dependency Injection Container
///
/// This widget initializes the dependency graph for the application.
/// It uses a hierarchical flow:
/// 1. [DatabaseHelper] (Singleton)
/// 2. [Database] (Async Future)
/// 3. [MapRepository] (Data Access Layer)
/// 4. [StructureData] (Business Logic Layer)
class Providers extends StatelessWidget {
  final Widget child;

  const Providers({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ---------------------------------------------------------------------
        // 1. Independent Services
        // ---------------------------------------------------------------------
        ChangeNotifierProvider<UiModel>(
          create: (_) => UiModel(),
        ),
        ChangeNotifierProvider<ConfigStorage>(
          create: (_) => ConfigStorage(),
        ),

        // ---------------------------------------------------------------------
        // 2. Database Infrastructure
        // ---------------------------------------------------------------------
        
        // Provides the raw DatabaseHelper Singleton
        Provider<DatabaseHelper>(
          create: (_) => DatabaseHelper.instance,
          dispose: (_, helper) => helper.close(),
        ),

        // Asynchronously initializes the SQLite Database
        // Returns null initially, then the Database instance once loaded
        FutureProvider<Database?>(
          create: (context) async {
            try {
              final helper = context.read<DatabaseHelper>();
              return await helper.getDatabase();
            } catch (e) {
              debugPrint('Critical Error: Failed to initialize database: $e');
              return null;
            }
          },
          initialData: null,
          catchError: (_, error) {
            debugPrint('Database Provider Error: $error');
            return null;
          },
        ),

        // ---------------------------------------------------------------------
        // 3. Data Access Layer (Repositories)
        // ---------------------------------------------------------------------
        
        // Creates the MapRepository only when the Database is ready
        ProxyProvider<Database?, MapRepository?>(
          update: (context, database, previous) {
            // Case 1: Database is still loading or failed
            if (database == null) {
              return null; 
            }

            // Case 2: Repository already exists for this database instance
            if (previous != null) {
              return previous;
            }

            // Case 3: Create new Repository
            debugPrint('✅ Database connected. Initializing MapRepository.');
            return MapRepository(database);
          },
        ),

        // ---------------------------------------------------------------------
        // 4. Business Logic / State Management
        // ---------------------------------------------------------------------
        
        // The main store for map structures.
        // It listens to MapRepository changes and updates accordingly.
        ChangeNotifierProxyProvider<MapRepository?, StructureData>(
          create: (_) => StructureData(),
          update: (context, repository, previous) {
            final structureData = previous ?? StructureData();
            
            // Inject the repository once it is available
            if (repository != null) {
              structureData.repository = repository;
              
              // Optional: Trigger an initial load if data is empty
              // if (structureData.structures.isEmpty) {
              //   structureData.loadInitialData(); 
              // }
            }
            
            return structureData;
          },
        ),
      ],
      child: child,
    );
  }
}