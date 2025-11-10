import 'package:flutter/material.dart';
import 'package:lnu_nav_app/database/database_helper.dart';
import 'package:lnu_nav_app/helpers/ui.dart';
import 'package:lnu_nav_app/repositories/map_repository.dart';
import 'package:lnu_nav_app/store/permanent/config-storage.dart';
import 'package:lnu_nav_app/store/structure-data.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

/// Providers widget - Sets up dependency injection hierarchy
/// 
/// DEPENDENCY CHAIN:
/// 1. DatabaseHelper (no deps) -> Provides Database
/// 2. MapRepository (depends on DatabaseHelper) -> Provides data access
/// 3. StructureData (depends on MapRepository) -> Provides business logic
/// 
/// This order ensures proper initialization and allows child widgets
/// to access any provider they need.
class Providers extends StatelessWidget {
  final Widget child;

  const Providers({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ==================== EXISTING PROVIDERS ====================
        ChangeNotifierProvider<UiModel>(
          create: (_) => UiModel(),
        ),
        ChangeNotifierProvider<ConfigStorage>(
          create: (_) => ConfigStorage(),
        ),

        // ==================== DATABASE PROVIDERS ====================
        
        // 1. DatabaseHelper Provider (base layer)
        // Creates a DatabaseHelper instance and initializes the database
        Provider<DatabaseHelper>(
          create: (_) => DatabaseHelper(),
          dispose: (_, helper) => helper.close(), // Clean up on app close
        ),

        // 2. Database Provider (depends on DatabaseHelper)
        // This provides the actual Database instance to other providers
        FutureProvider<Database?>(
          create: (context) async {
            final helper = context.read<DatabaseHelper>();
            try {
              return await helper.getDatabase();
            } catch (e) {
              print('❌ Failed to initialize database: $e');
              return null;
            }
          },
          initialData: null,
        ),

        // 3. MapRepository Provider (depends on Database)
        // Provides data access layer to widgets
        ProxyProvider<Database?, MapRepository?>(
          update: (context, database, previous) {
            if (database == null) {
              print('⚠️ Database not ready yet');
              return null;
            }
            
            // Create new repository when database becomes available
            if (previous == null) {
              print('✅ Creating MapRepository');
              return MapRepository(database);
            }
            
            // Reuse existing repository if database hasn't changed
            return previous;
          },
        ),

        // 4. StructureData Provider (depends on MapRepository)
        // Updated to use MapRepository instead of JSON loading
        ChangeNotifierProxyProvider<MapRepository?, StructureData>(
          create: (_) => StructureData(),
          update: (context, repository, previous) {
            // Update the repository reference when it becomes available
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

/// Alternative: If you prefer async initialization with loading screen
/// This example shows how to handle async database initialization gracefully
class ProvidersWithAsyncInit extends StatelessWidget {
  final Widget child;
  final Widget loadingWidget;

  const ProvidersWithAsyncInit({
    Key? key,
    required this.child,
    this.loadingWidget = const Center(child: CircularProgressIndicator()),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DatabaseHelper>(
      future: _initializeDatabase(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Failed to initialize app: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData) {
          return loadingWidget;
        }

        final databaseHelper = snapshot.data!;

        return FutureBuilder<Database>(
          future: databaseHelper.getDatabase(),
          builder: (context, dbSnapshot) {
            if (dbSnapshot.hasError) {
              return Center(
                child: Text('Failed to load database: ${dbSnapshot.error}'),
              );
            }

            if (!dbSnapshot.hasData) {
              return loadingWidget;
            }

            final database = dbSnapshot.data!;
            final repository = MapRepository(database);

            return MultiProvider(
              providers: [
                ChangeNotifierProvider<UiModel>(create: (_) => UiModel()),
                ChangeNotifierProvider<ConfigStorage>(create: (_) => ConfigStorage()),
                Provider<DatabaseHelper>.value(value: databaseHelper),
                Provider<Database>.value(value: database),
                Provider<MapRepository>.value(value: repository),
                ChangeNotifierProvider<StructureData>(
                  create: (_) => StructureData()..repository = repository,
                ),
              ],
              child: child,
            );
          },
        );
      },
    );
  }

  Future<DatabaseHelper> _initializeDatabase() async {
    final helper = DatabaseHelper();
    await helper.getDatabase(); // Ensure database is copied and ready
    return helper;
  }
}
