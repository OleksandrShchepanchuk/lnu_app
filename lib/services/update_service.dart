import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class MapUpdateService {
  static const String _remoteDbUrl = 'https://raw.githubusercontent.com/OleksandrShchepanchuk/lnu_maps_data/main/lnu_maps.db';
  static const String _dbFileName = 'lnu_maps.db';
  
  final Dio _dio = Dio();

  Future<void> downloadMapIfNeeded() async {
    try {
      final String localDbPath = await getDatabasePath();
      final File localFile = File(localDbPath);

      if (await localFile.exists()) {
        return; 
      }

      final Directory tempDir = await getTemporaryDirectory();
      final String tempDbPath = p.join(tempDir.path, 'temp_map_update.db');

      await _dio.download(_remoteDbUrl, tempDbPath);

      if (!await _verifyDatabase(tempDbPath)) {
        return;
      }

      final File tempFile = File(tempDbPath);
      
      if (await localFile.exists()) {
        await localFile.delete();
      }
      
      await tempFile.copy(localDbPath);
      await tempFile.delete();

    } catch (e) {
      if (kDebugMode) {
        print('MapUpdateService error: $e');
      }
    }
  }

  Future<String> getDatabasePath() async {
    final String databasesPath = await getDatabasesPath();
    return p.join(databasesPath, _dbFileName);
  }

  Future<bool> _verifyDatabase(String path) async {
    try {
      final Database db = await openDatabase(path, readOnly: true);
      final List<Map> result = await db.rawQuery('SELECT count(*) FROM points');
      await db.close();
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}