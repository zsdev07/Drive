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
    // Bot API only allows getFile on files ≤ 20 MB
    if (file.sizeBytes > 20 * 1024 * 1024) {
      throw Exception(
        'File is ${(file.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB — '
        'Bot API download limit is 20 MB. MTProto support coming soon.',
      );
    }

    // On Android: save to /storage/emulated/0/Download — the real shared
    // Downloads folder visible to every file manager. No permissions needed
    // on Android 10+ because we write only to this public directory.
    // On iOS / fallback: use app documents (iOS has no shared Downloads).
    Directory saveDir;
    if (Platform.isAndroid) {
      // Walk up from getExternalStorageDirectory() (e.g. /storage/emulated/0/Android/data/…)
      // to find /storage/emulated/0, then append Download.
      try {
        final extDir = await getExternalStorageDirectory();
        // extDir.path is like /storage/emulated/0/Android/data/<pkg>/files
        // Split on '/Android/' to get the root: /storage/emulated/0
        final root = extDir!.path.split('/Android/').first;
        saveDir = Directory('$root/Download');
      } catch (_) {
        // Fallback: app documents (won't appear in file manager, but won't crash)
        final appDir = await getApplicationDocumentsDirectory();
        saveDir = Directory('${appDir.path}/ZX Drive Downloads');
      }
    } else {
      // iOS — app documents directory is the only writable option
      final appDir = await getApplicationDocumentsDirectory();
      saveDir = Directory('${appDir.path}/ZX Drive Downloads');
    }
    await saveDir.create(recursive: true);

    // Avoid silently overwriting an existing file with the same name
    String savePath = '${saveDir.path}/${file.name}';
    if (File(savePath).existsSync()) {
      final dotIndex = file.name.lastIndexOf('.');
      final ext = dotIndex != -1 ? file.name.substring(dotIndex) : '';
      final base = dotIndex != -1 ? file.name.substring(0, dotIndex) : file.name;
      savePath = '${saveDir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
    }

    await _telegram.downloadFile(
      fileId: file.telegramFileId,
      savePath: savePath,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    // Update last accessed timestamp
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(FileItemsCompanion(lastAccessedAt: Value(DateTime.now())));

    return savePath;
  }

  // ── Delete / Restore ──────────────────────────────────

  /// Soft-delete: moves to trash in DB only.
  /// Does NOT touch Telegram so the file can be restored later.
  Future<void> deleteFile(FileItem file) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(const FileItemsCompanion(isDeleted: Value(true)));
  }

  /// Restores a trashed file back to its original location.
  Future<void> restoreFile(FileItem file) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(const FileItemsCompanion(isDeleted: Value(false)));
  }

  /// Permanent delete: removes from DB AND deletes from Telegram channel.
  /// Only called from the Trash screen — never from the main drive.
  Future<void> permanentlyDelete(FileItem file) async {
    await (_db.delete(_db.fileItems)
          ..where((t) => t.uuid.equals(file.uuid)))
        .go();
    try {
      await _telegram.deleteMessage(file.telegramMessageId);
    } catch (_) {}
  }

  // ── Bulk Operations ───────────────────────────────────

  Future<void> bulkDelete(List<String> uuids) async {
    // Soft-delete only — no Telegram calls
    await (_db.update(_db.fileItems)
          ..where((t) => t.uuid.isIn(uuids)))
        .write(const FileItemsCompanion(isDeleted: Value(true)));
  }

  Future<void> bulkRestore(List<String> uuids) async {
    await (_db.update(_db.fileItems)
          ..where((t) => t.uuid.isIn(uuids)))
        .write(const FileItemsCompanion(isDeleted: Value(false)));
  }

  Future<void> bulkPermanentDelete(List<String> uuids) async {
    final files = await getFilesByUuids(uuids);
    await (_db.delete(_db.fileItems)
          ..where((t) => t.uuid.isIn(uuids)))
        .go();
    for (final file in files) {
      try {
        await _telegram.deleteMessage(file.telegramMessageId);
      } catch (_) {}
    }
  }

  Future<void> bulkMove(List<String> uuids, String? targetFolderId) async {
    await (_db.update(_db.fileItems)
          ..where((t) => t.uuid.isIn(uuids)))
        .write(FileItemsCompanion(folderId: Value(targetFolderId)));
  }

  Future<void> bulkStar(List<String> uuids, {required bool star}) async {
    await (_db.update(_db.fileItems)
          ..where((t) => t.uuid.isIn(uuids)))
        .write(FileItemsCompanion(isStarred: Value(star)));
  }

  Future<List<FileItem>> getFilesByUuids(List<String> uuids) async {
    return (_db.select(_db.fileItems)
          ..where((t) => t.uuid.isIn(uuids)))
        .get();
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
    return files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
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

  Future<List<FolderItem>> getAllFolders() async {
    return (_db.select(_db.folderItems)
          ..where((t) => t.isDeleted.equals(false)))
        .get();
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
        .write(FolderItemsCompanion(
            name: Value(newName), updatedAt: Value(DateTime.now())));
  }

  Future<void> deleteFolder(FolderItem folder) async {
    await (_db.update(_db.folderItems)
          ..where((t) => t.uuid.equals(folder.uuid)))
        .write(const FolderItemsCompanion(isDeleted: Value(true)));
  }
}
