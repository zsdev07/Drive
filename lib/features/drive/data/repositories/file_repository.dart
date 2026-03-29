import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/telegram_service.dart';
import '../../domain/models/zx_file.dart';

class FileRepository {
  final AppDatabase _db;
  final TelegramService _telegram;

  FileRepository(this._db, this._telegram);

  // ── Upload ────────────────────────────────────────────

  Future<FileItem> uploadFile({
    required File file,
    String? folderId,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final fileName = file.path.split('/').last;
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final uploadId = const Uuid().v4();

    final result = await _telegram.uploadFileResumable(
      file: file,
      mimeType: mimeType,
      fileName: fileName,
      uploadId: uploadId,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    final fileType = ZXFileTypeX.fromMime(mimeType);

    final companion = FileItemsCompanion.insert(
      uuid: uploadId,
      name: fileName,
      mimeType: mimeType,
      sizeBytes: result.fileSize,
      telegramFileId: result.fileId,
      telegramMessageId: result.messageId,
      folderId: Value(folderId),
      fileType: fileType.label,
      uploadedAt: DateTime.now(),
    );

    await _db.into(_db.fileItems).insert(companion);

    return await (_db.select(_db.fileItems)
          ..where((t) => t.uuid.equals(uploadId)))
        .getSingle();
  }

  // ── Download ──────────────────────────────────────────

  Future<String> downloadFile({
    required FileItem file,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/downloads/${file.name}';
    await Directory('${dir.path}/downloads').create(recursive: true);

    await _telegram.downloadFile(
      fileId: file.telegramFileId,
      savePath: savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    // Update last accessed
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(FileItemsCompanion(lastAccessedAt: Value(DateTime.now())));

    return savePath;
  }

  // ── Delete ────────────────────────────────────────────

  Future<void> deleteFile(FileItem file) async {
    // Soft delete in DB
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(const FileItemsCompanion(isDeleted: Value(true)));

    // Delete from Telegram
    try {
      await _telegram.deleteMessage(file.telegramMessageId);
    } catch (_) {
      // Ignore Telegram errors — DB soft delete is the source of truth
    }
  }

  Future<void> permanentlyDelete(FileItem file) async {
    await (_db.delete(_db.fileItems)
          ..where((t) => t.uuid.equals(file.uuid)))
        .go();
    try {
      await _telegram.deleteMessage(file.telegramMessageId);
    } catch (_) {}
  }

  // ── Queries ───────────────────────────────────────────

  Stream<List<FileItem>> watchFiles({String? folderId}) {
    return (_db.select(_db.fileItems)
          ..where((t) =>
              t.isDeleted.equals(false) &
              (folderId != null
                  ? t.folderId.equals(folderId)
                  : t.folderId.isNull())))
        .watch();
  }

  Stream<List<FileItem>> watchStarredFiles() {
    return (_db.select(_db.fileItems)
          ..where((t) => t.isStarred.equals(true) & t.isDeleted.equals(false)))
        .watch();
  }

  Stream<List<FileItem>> watchTrash() {
    return (_db.select(_db.fileItems)
          ..where((t) => t.isDeleted.equals(true)))
        .watch();
  }

  Future<List<FileItem>> searchFiles(String query) {
    return (_db.select(_db.fileItems)
          ..where((t) =>
              t.name.like('%$query%') & t.isDeleted.equals(false)))
        .get();
  }

  Future<void> toggleStar(FileItem file) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(FileItemsCompanion(isStarred: Value(!file.isStarred)));
  }

  Future<void> renameFile(FileItem file, String newName) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(FileItemsCompanion(name: Value(newName)));
  }

  Future<void> moveFile(FileItem file, String? newFolderId) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(FileItemsCompanion(folderId: Value(newFolderId)));
  }

  // ── Storage Stats ─────────────────────────────────────

  Future<int> getTotalUsedBytes() async {
    final files = await (_db.select(_db.fileItems)
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    return files.fold(0, (sum, f) => sum + f.sizeBytes);
  }
}

// ── Folder Repository ─────────────────────────────────────

class FolderRepository {
  final AppDatabase _db;

  FolderRepository(this._db);

  Stream<List<FolderItem>> watchFolders({String? parentId}) {
    return (_db.select(_db.folderItems)
          ..where((t) =>
              t.isDeleted.equals(false) &
              (parentId != null
                  ? t.parentFolderId.equals(parentId)
                  : t.parentFolderId.isNull())))
        .watch();
  }

  Future<void> createFolder({
    required String name,
    String? parentFolderId,
    String? colorHex,
  }) async {
    await _db.into(_db.folderItems).insert(FolderItemsCompanion.insert(
          uuid: const Uuid().v4(),
          name: name,
          parentFolderId: Value(parentFolderId),
          colorHex: Value(colorHex ?? '#4F6FFF'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
  }

  Future<void> renameFolder(FolderItem folder, String newName) async {
    await (_db.update(_db.folderItems)
          ..where((t) => t.uuid.equals(folder.uuid)))
        .write(FolderItemsCompanion(name: Value(newName), updatedAt: Value(DateTime.now())));
  }

  Future<void> deleteFolder(FolderItem folder) async {
    await (_db.update(_db.folderItems)
          ..where((t) => t.uuid.equals(folder.uuid)))
        .write(const FolderItemsCompanion(isDeleted: Value(true)));
  }
}
