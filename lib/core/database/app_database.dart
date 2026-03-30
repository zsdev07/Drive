import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// ── Tables ────────────────────────────────────────────────

class FileItems extends Table {
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get telegramFileId => text()();
  TextColumn get telegramMessageId => text()();
  TextColumn get folderId => text().nullable()();
  TextColumn get fileType => text()(); // image/video/audio/document/archive/other
  DateTimeColumn get uploadedAt => dateTime()();
  DateTimeColumn get lastAccessedAt => dateTime().nullable()();
  TextColumn get thumbnailFileId => text().nullable()();
  BoolColumn get isStarred => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

class FolderItems extends Table {
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  TextColumn get parentFolderId => text().nullable()();
  TextColumn get colorHex => text().nullable()();
  TextColumn get iconName => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

class UserItems extends Table {
  TextColumn get uid => text()();
  TextColumn get name => text()();
  TextColumn get email => text()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get pin => text().nullable()();
  TextColumn get botToken => text()();
  TextColumn get channelId => text()();
  TextColumn get authProvider => text()(); // google / pin
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastLoginAt => dateTime()();
  IntColumn get usedStorageBytes => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {uid};
}

/// Stores MTProto session metadata.
/// Secrets (auth key, server salt) live in flutter_secure_storage —
/// only non-sensitive identifiers live here.
/// Designed for N accounts even though v1 only activates one at a time.
class MtprotoSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get phone => text()();
  TextColumn get dcId => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

// ── Database ──────────────────────────────────────────────

@DriftDatabase(tables: [FileItems, FolderItems, UserItems, MtprotoSessions])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 → v2: add MtprotoSessions table
            await m.createTable(mtprotoSessions);
          }
        },
      );

  // ── MtprotoSessions helpers ───────────────────────────

  Future<MtprotoSession?> getActiveSession() {
    return (select(mtprotoSessions)
          ..where((t) => t.isActive.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> upsertSession({
    required String phone,
    required String dcId,
  }) async {
    // Deactivate any existing active session first
    await (update(mtprotoSessions)
          ..where((t) => t.isActive.equals(true)))
        .write(const MtprotoSessionsCompanion(isActive: Value(false)));

    return into(mtprotoSessions).insert(
      MtprotoSessionsCompanion.insert(
        phone: phone,
        dcId: dcId,
        isActive: const Value(true),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> clearAllSessions() async {
    await delete(mtprotoSessions).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'zx_drive.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
