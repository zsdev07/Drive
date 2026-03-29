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

// ── Database ──────────────────────────────────────────────

@DriftDatabase(tables: [FileItems, FolderItems, UserItems])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'zx_drive.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
