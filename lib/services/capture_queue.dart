import 'dart:async';

import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/capture_record.dart';

class CaptureQueue {
  CaptureQueue._();
  static final CaptureQueue instance = CaptureQueue._();

  static const _dbName = 'capture_queue.db';
  static const _table = 'captures';

  Database? _db;
  bool _ffiInit = false;

  Future<Database> _database() async {
    if (_db != null) return _db!;

    if ((io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS) &&
        !_ffiInit) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInit = true;
    }

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
        CREATE TABLE $_table(
          id TEXT PRIMARY KEY,
          shelfId TEXT,
          localPath TEXT,
          thumbnailPath TEXT,
          width INTEGER,
          height INTEGER,
          capturedAt TEXT,
          objectKey TEXT,
          status TEXT,
          retries INTEGER,
          error TEXT
        )
        ''');
      },
    );
    return _db!;
  }

  Future<void> upsert(CaptureRecord record) async {
    final db = await _database();
    await db.insert(
      _table,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CaptureRecord>> listAll() async {
    final db = await _database();
    final rows = await db.query(_table, orderBy: 'capturedAt DESC');
    return rows.map(CaptureRecord.fromMap).toList();
  }

  Future<List<CaptureRecord>> pending() async {
    final db = await _database();
    final rows = await db.query(
      _table,
      where: 'status IN (?, ?)',
      whereArgs: [CaptureStatus.pending.name, CaptureStatus.failed.name],
      orderBy: 'capturedAt ASC',
    );
    return rows.map(CaptureRecord.fromMap).toList();
  }

  Future<void> updateStatus(
    String id,
    CaptureStatus status, {
    String? objectKey,
    String? error,
    int? retries,
  }) async {
    final db = await _database();
    await db.update(
      _table,
      {
        'status': status.name,
        'objectKey': objectKey,
        'error': error,
        if (retries != null) 'retries': retries,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _database();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }
}

