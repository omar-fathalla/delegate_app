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
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        organizationUID TEXT NOT NULL,
        companyUID TEXT NOT NULL,
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

  Future<void> deletePendingPhoto(int id) async {
    final db = await database;
    await db.delete(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
