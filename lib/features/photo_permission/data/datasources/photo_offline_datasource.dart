import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class PhotoOfflineDataSource {
  static Database? _database;
  static const String tableName = 'pending_photos';

  /// TAS-369: v3 adds the capture time, the watermark flag and the retry
  /// bookkeeping. Existing rows keep their data (columns are nullable or
  /// have defaults).
  static const int schemaVersion = 3;

  /// SQL run by [_onUpgrade] from [oldVersion] (pure, unit-tested).
  static List<String> upgradeStatements(int oldVersion) => [
        if (oldVersion < 2) ...[
          'ALTER TABLE $tableName ADD COLUMN companyName TEXT',
          'ALTER TABLE $tableName ADD COLUMN companyCode INTEGER',
        ],
        if (oldVersion < 3) ...[
          'ALTER TABLE $tableName ADD COLUMN capturedAtMs INTEGER',
          'ALTER TABLE $tableName ADD COLUMN watermarkFailed INTEGER NOT NULL DEFAULT 0',
          'ALTER TABLE $tableName ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0',
          'ALTER TABLE $tableName ADD COLUMN lastError TEXT',
        ],
      ];

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
      version: schemaVersion,
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
        timestamp INTEGER NOT NULL,
        capturedAtMs INTEGER,
        watermarkFailed INTEGER NOT NULL DEFAULT 0,
        attempts INTEGER NOT NULL DEFAULT 0,
        lastError TEXT
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (final sql in upgradeStatements(oldVersion)) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column already there (a half-applied earlier upgrade).
      }
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

  /// TAS-369: the rows of the signed-in delegate only (any of its ids), so a
  /// second account on the same phone never uploads someone else's photos.
  Future<List<Map<String, dynamic>>> getPendingPhotosForDelegates(Set<String> ids) async {
    if (ids.isEmpty) return const [];
    final db = await database;
    final marks = List.filled(ids.length, '?').join(',');
    return db.query(
      tableName,
      where: 'delegateUID IN ($marks)',
      whereArgs: ids.toList(),
      orderBy: 'timestamp ASC',
    );
  }

  /// Records a failed attempt. [countAttempt] is false for network errors
  /// (they retry freely) and true for errors a retry will not fix.
  Future<void> recordFailure(int id, String error, {required bool countAttempt}) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE $tableName SET lastError = ?, attempts = attempts + ? WHERE id = ?',
      [error.length > 300 ? error.substring(0, 300) : error, countAttempt ? 1 : 0, id],
    );
  }

  /// «فشلت، اضغط لإعادة المحاولة»: the delegate retries the stuck rows.
  Future<void> resetAttempts(Set<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final marks = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE $tableName SET attempts = 0 WHERE delegateUID IN ($marks)',
      ids.toList(),
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
