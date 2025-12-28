import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../services/update_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await MapUpdateService().getDatabasePath();
    
    return await openDatabase(
      dbPath,
      version: 1,
      readOnly: false, 
    );
  }


  Future<Database> getDatabase() async {
    return await database;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null; 
    }
  }
}