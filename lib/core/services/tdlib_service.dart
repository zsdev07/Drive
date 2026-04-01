// lib/core/services/tdlib_service.dart
//
// TDLib now owns ALL authentication:
//   • QR login  → RequestQrCodeAuthentication + UpdateAuthorizationState
//   • Phone OTP → SetAuthenticationPhoneNumber + CheckAuthenticationCode
//   • 2FA       → CheckAuthenticationPassword
//   • Auth state changes are broadcast via authStateStream
//
// File upload / download unchanged — still uses SendMessage + DownloadFile.

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io' as io;
import 'package:handy_tdlib/api.dart' as td;
import 'package:handy_tdlib/handy_tdlib.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';

// ═══════════════════════════════════════════════════════════
// Data / result classes
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

// ═══════════════════════════════════════════════════════════
// Auth state — mirrors what TDLib reports
// ═══════════════════════════════════════════════════════════

enum TdlibAuthState {
  initial,
  waitingTdlibParams,  // SetTdlibParameters needed
  waitingPhoneNumber,  // Phone login path
  waitingCode,         // OTP entry
  waitingPassword,     // 2FA password
  waitingQrScan,       // QR login path — waiting for user to scan
  authenticated,
  closed,
  unknown,
}

// ═══════════════════════════════════════════════════════════
// QR token
// ═══════════════════════════════════════════════════════════

class TdlibQrToken {
  final String link; // tg://login?token=…
  TdlibQrToken({required this.link});
}

// ═══════════════════════════════════════════════════════════
// Exceptions
// ═══════════════════════════════════════════════════════════

class TdlibException implements Exception {
  final String message;
  final String? code;
  TdlibException(this.message, {this.code});

  @override
  String toString() =>
      code != null ? 'TdlibException [$code]: $message' : 'TdlibException: $message';
}

class TdlibAuthException extends TdlibException {
  TdlibAuthException(super.message, {super.code});
}

class TdlibTwoFactorRequired extends TdlibException {
  final String hint;
  TdlibTwoFactorRequired({required this.hint})
      : super('Two-factor authentication required');
}

// ═══════════════════════════════════════════════════════════
// Isolate message types (must be top-level / simple)
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
  // ── Streams ───────────────────────────────────────────────
  final _updateCtrl = StreamController<td.TdObject>.broadcast();
  Stream<td.TdObject> get updates => _updateCtrl.stream;

  final _authStateCtrl = StreamController<TdlibAuthState>.broadcast();
  Stream<TdlibAuthState> get authStateStream => _authStateCtrl.stream;

  // ── State ─────────────────────────────────────────────────
  TdlibAuthState _authState = TdlibAuthState.initial;
  TdlibAuthState get authState => _authState;
  bool get isAuthenticated => _authState == TdlibAuthState.authenticated;

  TdlibQrToken? _currentQrToken;
  TdlibQrToken? get currentQrToken => _currentQrToken;

  // ── Isolate infra ─────────────────────────────────────────
  final _pending = <int, Completer<td.TdObject>>{};
  int _nextExtra = 1;
  Isolate? _updatesIsolate;
  SendPort? _invokesSendPort;
  bool _ready = false;
  int? _clientId;

  // ── Stored credentials (needed for SetTdlibParameters) ───
  int? _apiId;
  String? _apiHash;

  // ─────────────────────────────────────────────────────────
  // Init
  // ─────────────────────────────────────────────────────────

  Future<void> init({
    required int apiId,
    required String apiHash,
  }) async {
    if (_ready) return;

    _apiId   = apiId;
    _apiHash = apiHash;

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath  = '${docsDir.path}/${AppConstants.tdlibDbName}';
    await io.Directory(dbPath).create(recursive: true);

    // 1. Set up updates ReceivePort on main isolate
    final updatesReceivePort = ReceivePort();

    // 2. Spawn updates isolate
    _updatesIsolate = await Isolate.spawn(
      _updatesLoop,
      updatesReceivePort.sendPort,
    );

    // 3. Get clientId + invokesSendPort back from isolate
    final firstMsg = await updatesReceivePort.first as Map<String, dynamic>;
    _clientId = firstMsg['clientId'] as int;
    _invokesSendPort = firstMsg['invokesSendPort'] as SendPort;

    // 4. Completer that resolves once TDLib emits a meaningful auth state
    //    (anything past WaitTdlibParameters), proving the native layer is live.
    final tdlibBootCompleter = Completer<void>();

    // 4. Listen for updates and invoke results
    updatesReceivePort.listen((msg) {
      if (msg is! _UpdateMsg) return;
      final obj = msg.object;

      // Route invoke results by @extra
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

      // Handle auth state updates
      if (obj is td.UpdateAuthorizationState) {
        _handleAuthUpdate(obj.authorizationState);

        // Signal that TDLib has bootstrapped past the parameters step.
        // WaitTdlibParameters means we still need to send params; any state
        // after that means TDLib is alive and ready for commands.
        if (!tdlibBootCompleter.isCompleted &&
            obj.authorizationState is! td.AuthorizationStateWaitTdlibParameters) {
          tdlibBootCompleter.complete();
        }
      }

      // Broadcast everything else
      _updateCtrl.add(obj);
    });

    // 5. Bootstrap TDLib parameters
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

    // 6. Wait until TDLib confirms it has moved past the params stage.
    //    Without this wait, calls like setPhoneNumber / requestQrLogin arrive
    //    before TDLib is ready, causing NOT_READY / QR_TOKEN_NULL errors.
    await tdlibBootCompleter.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TdlibException(
          'TDLib did not become ready within 30 seconds. '
          'Check your API ID / Hash and internet connection.',
          code: 'BOOT_TIMEOUT',
        );
      },
    );

    _ready = true;
  }

  // ─────────────────────────────────────────────────────────
  // Auth state handler
  // ─────────────────────────────────────────────────────────

  void _handleAuthUpdate(td.AuthorizationState state) {
    if (state is td.AuthorizationStateWaitTdlibParameters) {
      _setAuthState(TdlibAuthState.waitingTdlibParams);

    } else if (state is td.AuthorizationStateWaitPhoneNumber) {
      _setAuthState(TdlibAuthState.waitingPhoneNumber);

    } else if (state is td.AuthorizationStateWaitCode) {
      _setAuthState(TdlibAuthState.waitingCode);

    } else if (state is td.AuthorizationStateWaitPassword) {
      _setAuthState(TdlibAuthState.waitingPassword);

    } else if (state is td.AuthorizationStateWaitOtherDeviceConfirmation) {
      // This is the QR login state — state.link is the tg:// URI
      _currentQrToken = TdlibQrToken(link: state.link);
      _setAuthState(TdlibAuthState.waitingQrScan);

    } else if (state is td.AuthorizationStateReady) {
      _setAuthState(TdlibAuthState.authenticated);

    } else if (state is td.AuthorizationStateClosed) {
      _setAuthState(TdlibAuthState.closed);

    } else {
      _setAuthState(TdlibAuthState.unknown);
    }
  }

  void _setAuthState(TdlibAuthState s) {
    _authState = s;
    if (!_authStateCtrl.isClosed) _authStateCtrl.add(s);
  }

  // ─────────────────────────────────────────────────────────
  // QR Login
  // ─────────────────────────────────────────────────────────

  /// Starts QR login flow. TDLib will emit
  /// AuthorizationStateWaitOtherDeviceConfirmation with the tg:// link.
  /// Listen to [authStateStream] for [TdlibAuthState.waitingQrScan] and
  /// read [currentQrToken] to get the link.
  Future<void> requestQrLogin() async {
    _assertReady();
    try {
      await _send(td.RequestQrCodeAuthentication(otherUserIds: []));
    } on TdlibException catch (e) {
      // If already in QR wait state TDLib returns an error — ignore it
      if (e.message.contains('ANOTHER_LOGIN')) return;
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────
  // Phone Login
  // ─────────────────────────────────────────────────────────

  /// Step 1: send phone number — triggers OTP
  Future<void> setPhoneNumber(String phoneE164) async {
    _assertReady();
    try {
      await _send(td.SetAuthenticationPhoneNumber(
        phoneNumber: phoneE164,
        settings: td.PhoneNumberAuthenticationSettings(
          allowFlashCall: false,
          allowMissedCall: false,
          isCurrentPhoneNumber: false,
          hasUnknownPhoneNumber: false,
          allowSmsRetrieverApi: false,
          firebaseAuthenticationSettings: null,
          authenticationTokens: [],
        ),
      ));
    } on TdlibException catch (e) {
      throw TdlibAuthException(e.message, code: e.code);
    }
  }

  /// Step 2: verify OTP code
  Future<void> checkCode(String code) async {
    _assertReady();
    try {
      await _send(td.CheckAuthenticationCode(code: code));
    } on TdlibException catch (e) {
      if (e.message.contains('PASSWORD_NEEDED') ||
          e.code == '401') {
        throw TdlibTwoFactorRequired(hint: '');
      }
      throw TdlibAuthException(e.message, code: e.code);
    }
  }

  /// Step 3 (optional): verify 2FA password
  Future<void> checkPassword(String password) async {
    _assertReady();
    try {
      await _send(td.CheckAuthenticationPassword(password: password));
    } on TdlibException catch (e) {
      throw TdlibAuthException(e.message, code: e.code);
    }
  }

  // ─────────────────────────────────────────────────────────
  // Sign out
  // ─────────────────────────────────────────────────────────

  Future<void> signOut() async {
    if (!_ready) return;
    try {
      await _send(td.LogOut());
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────
  // File ops
  // ─────────────────────────────────────────────────────────

  Future<TdlibUploadResult> uploadFile({
    required io.File file,
    required String mimeType,
    required String fileName,
    required String channelId,
    void Function(int sent, int total)? onProgress,
  }) async {
    _assertReady();

    final fileSize = await file.length();

    // 1. Preliminary upload
    final uploadedFile = await _send(td.PreliminaryUploadFile(
      file: td.InputFileLocal(path: file.path),
      fileType: _fileTypeFromMime(mimeType),
      priority: 1,
    )) as td.File;

    final fileId = uploadedFile.id;
    await _waitForFileUpload(fileId, fileSize, onProgress);

    // 2. Send as message to channel
    final chatId = _normaliseChatId(channelId);

    final message = await _send(td.SendMessage(
      chatId: chatId,
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
      synchronous: true,
    )) as td.File;

    if (downloaded.local.isDownloadingCompleted) {
      await io.File(downloaded.local.path).copy(savePath);
      return savePath;
    }

    await for (final update in updates) {
      if (update is td.UpdateFile) {
        final f = update.file;
        if (f.id == id) {
          onProgress?.call(f.local.downloadedSize, f.expectedSize ?? 0);
          if (f.local.isDownloadingCompleted) {
            await io.File(f.local.path).copy(savePath);
            return savePath;
          }
        }
      }
    }
    throw TdlibException('Download failed', code: 'DOWNLOAD_FAILED');
  }

  // ─────────────────────────────────────────────────────────
  // Dispose
  // ─────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _updatesIsolate?.kill(priority: Isolate.immediate);
    await _updateCtrl.close();
    await _authStateCtrl.close();
    _pending.clear();
    _ready = false;
  }

  // ─────────────────────────────────────────────────────────
  // Internal helpers
  // ─────────────────────────────────────────────────────────

  void _assertReady() {
    if (!_ready) {
      throw TdlibException('TdlibService not initialised.', code: 'NOT_READY');
    }
  }

  Future<td.TdObject> _send(td.TdFunction fn) {
    final extra = _nextExtra++;
    final json  = fn.toJson()..['@extra'] = extra;
    final c     = Completer<td.TdObject>();
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
    if (mime.startsWith('image/')) return td.FileTypePhoto();
    if (mime.startsWith('video/')) return td.FileTypeVideo();
    if (mime.startsWith('audio/')) return td.FileTypeAudio();
    return td.FileTypeDocument();
  }

  /// Converts a channel ID string like "-1001234567890" or "1234567890"
  /// into the int64 chat ID TDLib expects.
  int _normaliseChatId(String channelId) {
    final raw = channelId.trim();
    if (raw.startsWith('-')) return int.parse(raw);
    // bare numeric → supergroup/channel format
    final n = int.parse(raw.replaceAll(RegExp(r'^-?100'), ''));
    return -1000000000000 - n; // -100<id>
  }
}

// ═══════════════════════════════════════════════════════════
// Updates isolate entry point (must be top-level)
// ═══════════════════════════════════════════════════════════

void _updatesLoop(SendPort mainSendPort) {
  final clientId = TdPlugin.instance.tdCreateClientId();

  final invokesReceivePort = ReceivePort();

  mainSendPort.send({
    'clientId': clientId,
    'invokesSendPort': invokesReceivePort.sendPort,
  });

  invokesReceivePort.listen((msg) {
    if (msg is _InvokeMsg) {
      TdPlugin.instance.tdSend(clientId, jsonEncode(msg.json));
    }
  });

  while (true) {
    final response = TdPlugin.instance.tdReceive(clientId.toDouble());
    if (response != null) {
      try {
        final obj = convertJsonToObject(response);
        if (obj != null) mainSendPort.send(_UpdateMsg(obj));
      } catch (_) {}
    }
  }
}
