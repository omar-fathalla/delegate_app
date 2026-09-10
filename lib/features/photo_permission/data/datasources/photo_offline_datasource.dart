import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class PhotoOfflineDataSource {
  static Database? _database;
  static const String tableName = 'pending_photos';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('photo_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        organizationUID TEXT NOT NULL,
        companyUID TEXT NOT NULL,
        companyName TEXT,
        companyCode INTEGER,
        permissionId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        branchName TEXT NOT NULL,
        delegateUID TEXT NOT NULL,
        delegateName TEXT NOT NULL,
        imagePath TEXT NOT NULL,
        comment TEXT,
        latitude REAL,
        longitude REAL,
        timestamp INTEGER NOT NULL
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE $tableName ADD COLUMN companyName TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $tableName ADD COLUMN companyCode INTEGER');
      } catch (_) {}
    }
  }

  /// Copies temporary image file to persistent App Documents Directory
  /// so that it will never be deleted by Android/iOS cache clear or temporary cleanup.
  Future<String> saveImageToPersistentDirectory(File imageFile) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${appDir.path}/offline_captured_photos');
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }
      final fileName = 'offline_${DateTime.now().millisecondsSinceEpoch}_${basename(imageFile.path)}';
      final savedFile = await imageFile.copy('${photosDir.path}/$fileName');
      return savedFile.path;
    } catch (_) {
      return imageFile.path;
    }
  }

  Future<void> savePendingPhoto(Map<String, dynamic> photoData) async {
    final db = await database;
    await db.insert(
      tableName,
      photoData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingPhotos() async {
    final db = await database;
    return await db.query(tableName, orderBy: 'timestamp ASC');
  }

  Future<List<Map<String, dynamic>>> getPendingPhotosForDelegate(String delegateUID) async {
    final db = await database;
    return await db.query(
      tableName,
      where: 'delegateUID = ?',
      whereArgs: [delegateUID],
      orderBy: 'timestamp DESC',
    );
  }

  Future<void> deletePendingPhoto(int id) async {
    final db = await database;
    await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
