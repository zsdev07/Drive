import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/telegram_service.dart';
import '../../data/repositories/file_repository.dart';
import '../../domain/models/zx_file.dart';

// ── Services ──────────────────────────────────────────────

final telegramServiceProvider = Provider<TelegramService>((ref) {
  return TelegramService();
});

// ── Repositories ──────────────────────────────────────────

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  return FileRepository(
    ref.watch(databaseProvider),
    ref.watch(telegramServiceProvider),
  );
});

final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  return FolderRepository(ref.watch(databaseProvider));
});

// ── File Streams ──────────────────────────────────────────

final filesProvider = StreamProvider.family<List<FileItem>, String?>(
  (ref, folderId) =>
      ref.watch(fileRepositoryProvider).watchFiles(folderId: folderId),
);

final starredFilesProvider = StreamProvider<List<FileItem>>(
  (ref) => ref.watch(fileRepositoryProvider).watchStarredFiles(),
);

final trashProvider = StreamProvider<List<FileItem>>(
  (ref) => ref.watch(fileRepositoryProvider).watchTrash(),
);

final foldersProvider = StreamProvider.family<List<FolderItem>, String?>(
  (ref, parentId) =>
      ref.watch(folderRepositoryProvider).watchFolders(parentId: parentId),
);

// ── Storage Stats ─────────────────────────────────────────

final usedStorageProvider = FutureProvider<int>((ref) {
  return ref.watch(fileRepositoryProvider).getTotalUsedBytes();
});

// ── Search ────────────────────────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<FileItem>>((ref) {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return Future.value([]);
  return ref.watch(fileRepositoryProvider).searchFiles(query);
});

// ── Upload Manager ────────────────────────────────────────

class UploadNotifier extends StateNotifier<List<UploadTask>> {
  final FileRepository _repo;

  UploadNotifier(this._repo) : super([]);

  Future<void> addUpload({
    required File file,
    String? folderId,
  }) async {
    final fileName = file.path.split('/').last;
    final fileSize = await file.length();
    final task = UploadTask(
      uploadId: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: fileName,
      totalBytes: fileSize,
      status: UploadStatus.uploading,
    );

    state = [...state, task];

    final cancelToken = CancelToken();

    try {
      await _repo.uploadFile(
        file: file,
        folderId: folderId,
        onProgress: (sent, total) {
          state = [
            for (final t in state)
              if (t.uploadId == task.uploadId)
                UploadTask(
                  uploadId: t.uploadId,
                  fileName: t.fileName,
                  totalBytes: t.totalBytes,
                  sentBytes: sent,
                  status: UploadStatus.uploading,
                )
              else
                t,
          ];
        },
        cancelToken: cancelToken,
      );

      // Mark done
      state = [
        for (final t in state)
          if (t.uploadId == task.uploadId)
            UploadTask(
              uploadId: t.uploadId,
              fileName: t.fileName,
              totalBytes: t.totalBytes,
              sentBytes: t.totalBytes,
              status: UploadStatus.done,
            )
          else
            t,
      ];

      // Auto-remove after 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      state = state.where((t) => t.uploadId != task.uploadId).toList();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _updateTaskStatus(task.uploadId, UploadStatus.paused);
      } else {
        _updateTaskStatus(task.uploadId, UploadStatus.failed,
            error: e.message);
      }
    } catch (e) {
      _updateTaskStatus(task.uploadId, UploadStatus.failed,
          error: e.toString());
    }
  }

  void _updateTaskStatus(String uploadId, UploadStatus status,
      {String? error}) {
    state = [
      for (final t in state)
        if (t.uploadId == uploadId)
          UploadTask(
            uploadId: t.uploadId,
            fileName: t.fileName,
            totalBytes: t.totalBytes,
            sentBytes: t.sentBytes,
            status: status,
            errorMessage: error,
          )
        else
          t,
    ];
  }

  void dismissTask(String uploadId) {
    state = state.where((t) => t.uploadId != uploadId).toList();
  }
}

final uploadNotifierProvider =
    StateNotifierProvider<UploadNotifier, List<UploadTask>>((ref) {
  return UploadNotifier(ref.watch(fileRepositoryProvider));
});
