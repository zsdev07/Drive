// lib/core/services/tdlib_service.dart
//
// Wraps handy_tdlib in a two-isolate architecture as recommended by the README:
//   • "invokes" isolate  — sends TDLib requests (tdSend)
//   • "updates" isolate  — receives TDLib updates (tdReceive loop)
//
// Usage (injected via Riverpod in drive_providers.dart):
//   final tdlib = ref.watch(tdlibServiceProvider);
//   await tdlib.init(apiId: id, apiHash: hash);
//   final update = await tdlib.send(SetTdlibParameters(...));

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:handy_tdlib/api.dart' as td;
import 'package:handy_tdlib/handy_tdlib.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';

// ═══════════════════════════════════════════════════════════
// Data classes
// ═══════════════════════════════════════════════════════════

class TdlibUploadResult {
  final String fileId;
  final String messageId;
  final int fileSize;
  const TdlibUploadResult({
    required this.fileId,
    required this.messageId,
    required this.fileSize,
  });
}

class TdlibException implements Exception {
  final String message;
  final String? code;
  TdlibException(this.message, {this.code});
  @override
  String toString() =>
      code != null ? 'TdlibException [$code]: $message' : 'TdlibException: $message';
}

// ═══════════════════════════════════════════════════════════
// Isolate message types
// ═══════════════════════════════════════════════════════════

class _InvokeMsg {
  final int extra;
  final Map<String, dynamic> json;
  const _InvokeMsg(this.extra, this.json);
}

class _UpdateMsg {
  final td.TdObject object;
  const _UpdateMsg(this.object);
}

// ═══════════════════════════════════════════════════════════
// TdlibService
// ═══════════════════════════════════════════════════════════

class TdlibService {
  // Public update stream — widgets/repos can listen for auth updates, etc.
  final _updateCtrl = StreamController<td.TdObject>.broadcast();
  Stream<td.TdObject> get updates => _updateCtrl.stream;

  // Pending invoke completers keyed by extra id
  final _pending = <int, Completer<td.TdObject>>{};
  int _nextExtra = 1;

  // Isolate infrastructure
  Isolate? _updatesIsolate;
  SendPort? _invokesSendPort;
  bool _ready = false;

  int? _clientId;

  // ── Init ─────────────────────────────────────────────────

  Future<void> init({
    required int apiId,
    required String apiHash,
    required String phone, // pass '' if using QR / already authed
  }) async {
    if (_ready) return;

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath  = '${docsDir.path}/${AppConstants.tdlibDbName}';
    await Directory(dbPath).create(recursive: true);

    // ── 1. Set up the updates ReceivePort on the main isolate ──
    final updatesReceivePort = ReceivePort();

    // ── 2. Spawn the updates isolate ──────────────────────────
    _updatesIsolate = await Isolate.spawn(
      _updatesLoop,
      updatesReceivePort.sendPort,
    );

    // ── 3. Get client ID from updates isolate ─────────────────
    final firstMsg = await updatesReceivePort.first as Map<String, dynamic>;
    _clientId = firstMsg['clientId'] as int;
    final updatesSendPort = firstMsg['invokesSendPort'] as SendPort;
    _invokesSendPort = updatesSendPort;

    // ── 4. Listen for updates / invoke results ────────────────
    updatesReceivePort.listen((msg) {
      if (msg is! _UpdateMsg) return;
      final obj = msg.object;

      // Route invoke results by extra
      // ignore: avoid_dynamic_calls
      final extra = (obj as dynamic).extra as int?;
      if (extra != null && _pending.containsKey(extra)) {
        final c = _pending.remove(extra)!;
        if (obj is td.TdError) {
          c.completeError(TdlibException(obj.message, code: '${obj.code}'));
        } else {
          c.complete(obj);
        }
        return;
      }

      // Broadcast real updates
      _updateCtrl.add(obj);
    });

    // ── 5. Bootstrap TDLib parameters ────────────────────────
    await _send(td.SetTdlibParameters(
      useTestDc: false,
      databaseDirectory: dbPath,
      filesDirectory: '$dbPath/files',
      databaseEncryptionKey: '',
      useFileDatabase: true,
      useChatInfoDatabase: true,
      useMessageDatabase: true,
      useSecretChats: false,
      apiId: apiId,
      apiHash: apiHash,
      systemLanguageCode: 'en',
      deviceModel: 'Android',
      systemVersion: 'Android',
      applicationVersion: AppConstants.appVersion,
    ));

    _ready = true;
  }

  // ── Send a TDLib function ─────────────────────────────────

  Future<td.TdObject> _send(td.TdFunction fn) {
    final extra  = _nextExtra++;
    final json   = fn.toJson()..['@extra'] = extra;
    final c      = Completer<td.TdObject>();
    _pending[extra] = c;
    _invokesSendPort!.send(_InvokeMsg(extra, json));
    return c.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(extra);
        throw TdlibException('Request timed out.', code: 'TIMEOUT');
      },
    );
  }

  // ── Upload a file to a Telegram channel via MTProto ──────

  Future<TdlibUploadResult> uploadFile({
    required File file,
    required String mimeType,
    required String fileName,
    required String channelId,   // numeric, without -100
    void Function(int sent, int total)? onProgress,
  }) async {
    _assertReady();

    final fileSize = await file.length();

    // 1. Tell TDLib to upload the file
    final uploadedFile = await _send(td.UploadFile(
      file: td.InputFileLocal(path: file.path),
      fileType: _fileTypeFromMime(mimeType),
      priority: 1,
    )) as td.File;

    // 2. Wait for upload completion, streaming progress
    final fileId = uploadedFile.id;
    await _waitForFileUpload(fileId, fileSize, onProgress);

    // 3. Send as message to the channel
    final chatId = int.parse(channelId.replaceAll(RegExp(r'^-100'), ''));
    // Prepend -100 for supergroups/channels
    final tgChatId = -1 * (100 * 1000000000 + chatId);

    final message = await _send(td.SendMessage(
      chatId: tgChatId,
      messageThreadId: 0,
      replyTo: null,
      options: null,
      replyMarkup: null,
      inputMessageContent: td.InputMessageDocument(
        document: td.InputFileId(id: fileId),
        thumbnail: null,
        disableContentTypeDetection: true,
        caption: td.FormattedText(text: 'ZX Drive | $fileName', entities: []),
      ),
    )) as td.Message;

    return TdlibUploadResult(
      fileId: fileId.toString(),
      messageId: message.id.toString(),
      fileSize: fileSize,
    );
  }

  // ── Download a file ───────────────────────────────────────

  Future<String> downloadFile({
    required String fileId,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    _assertReady();

    final id = int.parse(fileId);

    final downloaded = await _send(td.DownloadFile(
      fileId: id,
      priority: 1,
      offset: 0,
      limit: 0,
      synchronous: true, // wait until complete
    )) as td.File;

    if (downloaded.local.isDownloadingCompleted) {
      // Copy from TDLib cache to desired save path
      await File(downloaded.local.path).copy(savePath);
      return savePath;
    }

    // Await via update stream if not yet done
    await for (final update in updates) {
      if (update is td.UpdateFile) {
        final f = update.file;
        if (f.id == id) {
          onProgress?.call(f.local.downloadedSize, f.expectedSize);
          if (f.local.isDownloadingCompleted) {
            await File(f.local.path).copy(savePath);
            return savePath;
          }
        }
      }
    }

    throw TdlibException('Download did not complete.', code: 'DOWNLOAD_FAILED');
  }

  // ── Dispose ───────────────────────────────────────────────

  Future<void> dispose() async {
    _updatesIsolate?.kill(priority: Isolate.immediate);
    await _updateCtrl.close();
    _pending.clear();
    _ready = false;
  }

  // ── Helpers ───────────────────────────────────────────────

  void _assertReady() {
    if (!_ready) throw TdlibException('TdlibService not initialised.', code: 'NOT_READY');
  }

  Future<void> _waitForFileUpload(
    int fileId,
    int totalSize,
    void Function(int, int)? onProgress,
  ) async {
    await for (final update in updates) {
      if (update is td.UpdateFile) {
        final f = update.file;
        if (f.id == fileId) {
          onProgress?.call(f.remote.uploadedSize, totalSize);
          if (f.remote.isUploadingCompleted) return;
        }
      }
    }
  }

  td.FileType _fileTypeFromMime(String mime) {
    if (mime.startsWith('image/')) return const td.FileTypePhoto();
    if (mime.startsWith('video/')) return const td.FileTypeVideo();
    if (mime.startsWith('audio/')) return const td.FileTypeAudio();
    return const td.FileTypeDocument();
  }
}

// ═══════════════════════════════════════════════════════════
// Updates isolate entry point (top-level function required)
// ═══════════════════════════════════════════════════════════

void _updatesLoop(SendPort mainSendPort) {
  // Create the TDLib client
  final clientId = TdPlugin.instance.tdCreateClientId();

  // Set up a ReceivePort so main isolate can send invokes to us
  final invokesReceivePort = ReceivePort();

  // Send back the client ID and our SendPort
  mainSendPort.send({
    'clientId': clientId,
    'invokesSendPort': invokesReceivePort.sendPort,
  });

  // Handle incoming invoke requests
  invokesReceivePort.listen((msg) {
    if (msg is _InvokeMsg) {
      TdPlugin.instance.tdSend(clientId, jsonEncode(msg.json));
    }
  });

  // Receive loop — this runs forever on this isolate
  while (true) {
    final response = TdPlugin.instance.tdReceive(clientId);
    if (response != null) {
      try {
        final obj = convertJsonToObject(response);
        if (obj != null) {
          mainSendPort.send(_UpdateMsg(obj));
        }
      } catch (_) {
        // Ignore parse errors for unknown TDLib object types
      }
    }
  }
}
