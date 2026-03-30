import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/telegram_service.dart';
import '../../../../core/services/mtproto_service.dart';
import '../../domain/models/zx_file.dart';

class FileRepository {
  final AppDatabase _db;
  final TelegramService _telegram;
  final MtprotoService? _mtproto;

  FileRepository(this._db, this._telegram, this._mtproto);

  // ── Auth mode helper ──────────────────────────────────

  Future<bool> _isMtprotoActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppConstants.keyMtprotoConnected) ?? false;
  }

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

    late final TelegramUploadResult result;

    if (await _isMtprotoActive() && (_mtproto?.isAuthenticated ?? false)) {
      // MTProto path — no 50 MB limit, parallel 512 KB chunks
      final mtResult = await _mtproto!.uploadFile(
        file: file,
        mimeType: mimeType,
        fileName: fileName,
        onProgress: onProgress,
      );
      result = TelegramUploadResult(
        fileId: mtResult.fileId,
        messageId: mtResult.messageId,
        fileSize: mtResult.fileSize,
      );
    } else {
      // Bot API path — existing chunked resumable upload
      result = await _telegram.uploadFileResumable(
        file: file,
        mimeType: mimeType,
        fileName: fileName,
        uploadId: uploadId,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }

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
    // Build the save path regardless of protocol
    Directory saveDir;
    if (Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        final root = extDir!.path.split('/Android/').first;
        saveDir = Directory('$root/Download');
      } catch (_) {
        final appDir = await getApplicationDocumentsDirectory();
        saveDir = Directory('${appDir.path}/ZX Drive Downloads');
      }
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      saveDir = Directory('${appDir.path}/ZX Drive Downloads');
    }
    await saveDir.create(recursive: true);

    String savePath = '${saveDir.path}/${file.name}';
    if (File(savePath).existsSync()) {
      final dotIndex = file.name.lastIndexOf('.');
      final ext = dotIndex != -1 ? file.name.substring(dotIndex) : '';
      final base =
          dotIndex != -1 ? file.name.substring(0, dotIndex) : file.name;
      savePath =
          '${saveDir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
    }

    if (await _isMtprotoActive() && (_mtproto?.isAuthenticated ?? false)) {
      // MTProto path — no 20 MB limit
      await _mtproto!.downloadFile(
        fileId: file.telegramFileId,
        savePath: savePath,
        onProgress: onProgress,
      );
    } else {
      // Bot API path — 20 MB hard limit
      if (file.sizeBytes > AppConstants.botApiMaxDownloadBytes) {
        throw Exception(
          'File is ${(file.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB — '
          'Bot API download limit is 20 MB. '
          'Connect your Telegram account in the Account tab to unlock unlimited downloads.',
        );
      }
      await _telegram.downloadFile(
        fileId: file.telegramFileId,
        savePath: savePath,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }

    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(FileItemsCompanion(lastAccessedAt: Value(DateTime.now())));

    return savePath;
  }

  // ── Delete / Restore ──────────────────────────────────

  Future<void> deleteFile(FileItem file) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(const FileItemsCompanion(isDeleted: Value(true)));
  }

  Future<void> restoreFile(FileItem file) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .write(const FileItemsCompanion(isDeleted: Value(false)));
  }

  Future<void> permanentlyDelete(FileItem file) async {
    await (_db.delete(_db.fileItems)..where((t) => t.uuid.equals(file.uuid)))
        .go();
    try {
      await _telegram.deleteMessage(file.telegramMessageId);
    } catch (_) {}
  }

  // ── Bulk Operations ───────────────────────────────────

  Future<void> bulkDelete(List<String> uuids) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.isIn(uuids)))
        .write(const FileItemsCompanion(isDeleted: Value(true)));
  }

  Future<void> bulkRestore(List<String> uuids) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.isIn(uuids)))
        .write(const FileItemsCompanion(isDeleted: Value(false)));
  }

  Future<void> bulkPermanentDelete(List<String> uuids) async {
    final files = await getFilesByUuids(uuids);
    await (_db.delete(_db.fileItems)..where((t) => t.uuid.isIn(uuids))).go();
    for (final file in files) {
      try {
        await _telegram.deleteMessage(file.telegramMessageId);
      } catch (_) {}
    }
  }

  Future<void> bulkMove(List<String> uuids, String? targetFolderId) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.isIn(uuids)))
        .write(FileItemsCompanion(folderId: Value(targetFolderId)));
  }

  Future<void> bulkStar(List<String> uuids, {required bool star}) async {
    await (_db.update(_db.fileItems)..where((t) => t.uuid.isIn(uuids)))
        .write(FileItemsCompanion(isStarred: Value(star)));
  }

  Future<List<FileItem>> getFilesByUuids(List<String> uuids) async {
    return (_db.select(_db.fileItems)..where((t) => t.uuid.isIn(uuids))).get();
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
    return (_db.select(_db.fileItems)..where((t) => t.isDeleted.equals(true)))
        .watch();
  }

  Future<List<FileItem>> searchFiles(String query) {
    return (_db.select(_db.fileItems)
          ..where(
              (t) => t.name.like('%$query%') & t.isDeleted.equals(false)))
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
