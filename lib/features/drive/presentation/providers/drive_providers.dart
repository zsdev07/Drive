import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/services/telegram_service.dart';
import '../../../../core/services/mtproto_service.dart';
import '../../data/repositories/file_repository.dart';
import '../../domain/models/zx_file.dart';

// ── Auth mode ─────────────────────────────────────────────

enum AuthMode { bot, mtproto }

final authModeProvider = FutureProvider<AuthMode>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final connected = prefs.getBool(AppConstants.keyMtprotoConnected) ?? false;
  return connected ? AuthMode.mtproto : AuthMode.bot;
});

// ── Services ──────────────────────────────────────────────

final telegramServiceProvider = Provider<TelegramService>((ref) {
  return TelegramService();
});

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
});

/// MtprotoService is now a FutureProvider because init() restores the session
/// asynchronously on startup. Widgets should use .when() or .valueOrNull.
final mtprotoServiceProvider = FutureProvider<MtprotoService>((ref) async {
  final db     = ref.watch(databaseProvider);
  final secure = ref.watch(secureStorageProvider);
  final service = MtprotoService(db: db, secureStorage: secure);
  await service.init();
  ref.onDispose(service.dispose);
  return service;
});

/// Convenience: stream of auth state changes. Widgets can watch this directly.
final mtprotoAuthStateProvider = StreamProvider<MtprotoAuthState>((ref) async* {
  final service = await ref.watch(mtprotoServiceProvider.future);
  yield service.authState;
  yield* service.authStateStream;
});

/// Current QR token — non-null only while in waitingQrScan state.
final mtprotoQrTokenProvider = StreamProvider<MtprotoQrToken?>((ref) async* {
  final service = await ref.watch(mtprotoServiceProvider.future);
  yield service.currentQrToken;
  await for (final state in service.authStateStream) {
    yield state == MtprotoAuthState.waitingQrScan ? service.currentQrToken : null;
  }
});

// ── Repositories ──────────────────────────────────────────

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  // MtprotoService may still be loading; pass null-safe fallback.
  final mtproto = ref.watch(mtprotoServiceProvider).valueOrNull;
  return FileRepository(
    ref.watch(databaseProvider),
    ref.watch(telegramServiceProvider),
    mtproto,
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

// ── Selection ─────────────────────────────────────────────

class SelectionNotifier extends StateNotifier<Set<String>> {
  SelectionNotifier() : super({});

  bool get isActive => state.isNotEmpty;

  void toggle(String uuid) {
    if (state.contains(uuid)) {
      state = {...state}..remove(uuid);
    } else {
      state = {...state, uuid};
    }
  }

  void selectAll(List<String> uuids) => state = uuids.toSet();
  void clear() => state = {};
}

final selectionProvider =
    StateNotifierProvider<SelectionNotifier, Set<String>>((ref) {
  return SelectionNotifier();
});

// ── Upload Manager ────────────────────────────────────────

class UploadNotifier extends StateNotifier<List<UploadTask>> {
  final FileRepository _repo;

  UploadNotifier(this._repo) : super([]);

  int get _activeCount =>
      state.where((t) => t.status == UploadStatus.uploading).length;

  Future<int> _concurrentLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final isMtproto = prefs.getBool(AppConstants.keyMtprotoConnected) ?? false;
    return isMtproto
        ? AppConstants.maxConcurrentUploadsAccount
        : AppConstants.maxConcurrentUploads;
  }

  Future<void> addUpload({required File file, String? folderId}) async {
    final limit = await _concurrentLimit();
    if (_activeCount >= limit) {
      throw UploadLimitException(
          'You can only upload $limit files at a time. Wait for current uploads to finish.');
    }

    final fileName = file.path.split('/').last;
    final fileSize = await file.length();

    if (fileSize > AppConstants.maxUploadBytes) {
      throw UploadLimitException('$fileName exceeds the 2 GB file limit.');
    }

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
                  uploadId: t.uploadId, fileName: t.fileName,
                  totalBytes: t.totalBytes, sentBytes: sent,
                  status: UploadStatus.uploading,
                )
              else t,
          ];
        },
        cancelToken: cancelToken,
      );

      state = [
        for (final t in state)
          if (t.uploadId == task.uploadId)
            UploadTask(
              uploadId: t.uploadId, fileName: t.fileName,
              totalBytes: t.totalBytes, sentBytes: t.totalBytes,
              status: UploadStatus.done,
            )
          else t,
      ];

      await Future.delayed(const Duration(seconds: 3));
      state = state.where((t) => t.uploadId != task.uploadId).toList();
    } on TelegramApiException catch (e) {
      _updateStatus(task.uploadId, UploadStatus.failed,
          error: 'Telegram ${e.errorCode}: ${e.description}');
    } on MtprotoException catch (e) {
      _updateStatus(task.uploadId, UploadStatus.failed, error: e.toString());
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _updateStatus(task.uploadId, UploadStatus.paused);
      } else {
        _updateStatus(task.uploadId, UploadStatus.failed,
            error: e.message ?? 'Network error');
      }
    } catch (e) {
      _updateStatus(task.uploadId, UploadStatus.failed, error: e.toString());
    }
  }

  void _updateStatus(String uploadId, UploadStatus status, {String? error}) {
    state = [
      for (final t in state)
        if (t.uploadId == uploadId)
          UploadTask(
            uploadId: t.uploadId, fileName: t.fileName,
            totalBytes: t.totalBytes, sentBytes: t.sentBytes,
            status: status, errorMessage: error,
          )
        else t,
    ];
  }

  void dismissTask(String uploadId) {
    state = state.where((t) => t.uploadId != uploadId).toList();
  }
}

class UploadLimitException implements Exception {
  final String message;
  UploadLimitException(this.message);
  @override
  String toString() => message;
}

final uploadNotifierProvider =
    StateNotifierProvider<UploadNotifier, List<UploadTask>>((ref) {
  return UploadNotifier(ref.watch(fileRepositoryProvider));
});
