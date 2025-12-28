import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static const String _dbName = 'lnu_maps.db';

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(_dbName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    if (!await databaseExists(path)) {
      try {
        await Directory(dirname(path)).create(recursive: true);
        
        final ByteData data = await rootBundle.load(join('assets', 'database', filePath));
        final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        
        await File(path).writeAsBytes(bytes, flush: true);
      } catch (e) {
        throw Exception("Failed to initialize database from assets: $e");
      }
    }

    return await openDatabase(path);
  }
}