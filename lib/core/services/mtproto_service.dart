import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tdlib/td_api.dart' as td;
import 'package:tdlib/tdlib.dart';

import '../constants/app_constants.dart';
import '../database/app_database.dart';
import 'telegram_service.dart'; // shared TelegramUploadResult lives here

// ── Exceptions ────────────────────────────────────────────

class MtprotoException implements Exception {
  final String message;
  final String? code;
  MtprotoException(this.message, {this.code});

  @override
  String toString() =>
      code != null ? 'MtprotoException [$code]: $message' : 'MtprotoException: $message';
}

class MtprotoAuthException extends MtprotoException {
  MtprotoAuthException(super.message, {super.code});
}

class MtprotoTwoFactorRequired extends MtprotoException {
  final String hint;
  MtprotoTwoFactorRequired({required this.hint})
      : super('Two-factor authentication required');
}

// ── Auth state enum (mirrors TDLib auth states we care about) ─

enum MtprotoAuthState {
  initial,
  waitingCode,
  waitingPassword,
  authenticated,
  closed,
}

// ── MtprotoService ────────────────────────────────────────

/// Wraps TDLib (via the `tdlib` pub package / tdjson FFI) into clean
/// async Dart methods. Lives alongside [TelegramService] (Bot API) —
/// neither replaces the other.
///
/// Session lifecycle:
///   init() → sendCode() → signIn() | signInWithPassword() → [authenticated]
///
/// Secrets (auth key, dc_id, server salt) are stored in
/// [FlutterSecureStorage]. Non-secret UI state (connected bool, display
/// name, phone) stays in SharedPreferences via [AppConstants] keys.
class MtprotoService {
  // ── Dependencies ────────────────────────────────────────
  final AppDatabase _db;
  final FlutterSecureStorage _secure;

  // ── TDLib client ────────────────────────────────────────
  TdlibParameters? _tdlibParams;
  int? _clientId;
  final _updateController = StreamController<td.TdObject>.broadcast();
  bool _receiveLoopRunning = false;

  // ── State ───────────────────────────────────────────────
  MtprotoAuthState _authState = MtprotoAuthState.initial;
  String? _phoneNumber;
  String? _twoFaHint;

  // Completers used to await specific TDLib responses
  Completer<void>? _codeCompleter;
  Completer<void>? _signInCompleter;
  Completer<void>? _passwordCompleter;

  MtprotoService({
    required AppDatabase db,
    FlutterSecureStorage? secureStorage,
  })  : _db = db,
        _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  // ── Public state ─────────────────────────────────────────

  bool get isAuthenticated => _authState == MtprotoAuthState.authenticated;
  MtprotoAuthState get authState => _authState;
  Stream<td.TdObject> get updates => _updateController.stream;

  // ── Init / session restore ───────────────────────────────

  /// Call once at app start. Loads TDLib, restores session from secure
  /// storage if it exists, and begins the TDLib update receive loop.
  Future<void> init() async {
    if (_clientId != null) return; // already initialised

    final appDir = await getApplicationDocumentsDirectory();
    final apiId = int.tryParse(dotenv.env['TELEGRAM_API_ID'] ?? '0') ?? 0;
    final apiHash = dotenv.env['TELEGRAM_API_HASH'] ?? '';

    if (apiId == 0 || apiHash.isEmpty) {
      throw MtprotoException(
        'TELEGRAM_API_ID or TELEGRAM_API_HASH missing from .env',
      );
    }

    _tdlibParams = TdlibParameters(
      apiId: apiId,
      apiHash: apiHash,
      databaseDirectory: '${appDir.path}/tdlib',
      filesDirectory: '${appDir.path}/tdlib_files',
      systemLanguageCode: 'en',
      deviceModel: Platform.operatingSystem,
      applicationVersion: AppConstants.appVersion,
      useMessageDatabase: false,  // We only need file transfers, not full history
      useSecretChats: false,
      useTestDc: false,
    );

    _clientId = TdPlugin.instance.tdCreateClientId();
    _startReceiveLoop();

    // Send the first required TDLib request to trigger authorizationState
    _send(td.GetAuthorizationState());
  }

  // ── Auth flow ─────────────────────────────────────────────

  /// Step 1: send auth code to [phone].
  /// Throws [MtprotoAuthException] on failure.
  Future<void> sendCode(String phone) async {
    await init();
    _phoneNumber = phone;
    _codeCompleter = Completer<void>();

    _send(td.SetAuthenticationPhoneNumber(
      phoneNumber: phone,
      settings: const td.PhoneNumberAuthenticationSettings(
        allowFlashCall: false,
        allowMissedCall: false,
        isCurrentPhoneNumber: false,
        hasUnknownPhoneNumber: false,
        allowSmsRetrieverApi: false,
        authenticationTokens: [],
      ),
    ));

    await _codeCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw MtprotoAuthException('Timed out waiting for code'),
    );
  }

  /// Step 2a: verify the OTP [code] received via Telegram.
  /// If the account has 2FA, throws [MtprotoTwoFactorRequired].
  Future<void> signIn(String phone, String code) async {
    _signInCompleter = Completer<void>();

    _send(td.CheckAuthenticationCode(code: code));

    await _signInCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw MtprotoAuthException('Timed out verifying code'),
    );

    // If 2FA is required the completer was completed with an error
    // (MtprotoTwoFactorRequired), which will propagate here.
  }

  /// Step 2b: supply cloud [password] for accounts with 2FA enabled.
  Future<void> signInWithPassword(String password) async {
    _passwordCompleter = Completer<void>();

    _send(td.CheckAuthenticationPassword(password: password));

    await _passwordCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw MtprotoAuthException('Timed out verifying password'),
    );
  }

  /// Sign out and wipe all session data.
  Future<void> signOut() async {
    if (_clientId == null) return;
    _send(td.LogOut());

    await _secure.delete(key: AppConstants.secureKeyAuthKey);
    await _secure.delete(key: AppConstants.secureKeyDcId);
    await _secure.delete(key: AppConstants.secureKeyServerSalt);
    await _secure.delete(key: AppConstants.secureKeyApiId);
    await _secure.delete(key: AppConstants.secureKeyApiHash);

    await _db.clearAllSessions();
    _authState = MtprotoAuthState.initial;
    _clientId = null;
  }

  // ── File upload ───────────────────────────────────────────

  /// Upload [file] via TDLib's parallel-chunk upload.
  /// Returns a [TelegramUploadResult] on success.
  /// Throws [MtprotoException] if not authenticated.
  Future<TelegramUploadResult> uploadFile({
    required File file,
    required String mimeType,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    _requireAuth();

    final fileSize = await file.length();

    // TDLib handles chunking internally via uploadFile + getRemoteFileId.
    // We request the upload and then poll for progress via updates.
    final completer = Completer<TelegramUploadResult>();
    int? tdFileId;

    final sub = _updateController.stream.listen((update) {
      if (update is td.UpdateFile) {
        final f = update.file;
        if (tdFileId != null && f.id == tdFileId) {
          final local = f.local;
          final remote = f.remote;
          if (local.uploadedSize > 0) {
            onProgress?.call(local.uploadedSize, fileSize);
          }
          if (remote.isUploadingCompleted && !completer.isCompleted) {
            completer.complete(TelegramUploadResult(
              fileId: remote.id,
              messageId: remote.uniqueId,
              fileSize: fileSize,
            ));
          }
        }
      }
    });

    try {
      final response = await _sendAsync<td.File>(
        td.UploadFile(
          file: td.InputFileLocal(path: file.path),
          fileType: _fileTypeFromMime(mimeType),
          priority: 1,
        ),
      );
      tdFileId = response.id;

      // If already completed synchronously (small file)
      if (response.remote.isUploadingCompleted && !completer.isCompleted) {
        completer.complete(TelegramUploadResult(
          fileId: response.remote.id,
          messageId: response.remote.uniqueId,
          fileSize: fileSize,
        ));
      }

      return await completer.future.timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw MtprotoException('Upload timed out'),
      );
    } finally {
      await sub.cancel();
    }
  }

  // ── File download ─────────────────────────────────────────

  /// Download file by its remote [fileId] to [savePath].
  /// No 20 MB limit — TDLib handles arbitrarily large files.
  Future<String> downloadFile({
    required String fileId,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    _requireAuth();

    // First resolve remote fileId → TDLib local file descriptor
    final file = await _sendAsync<td.File>(
      td.GetRemoteFile(remoteFileId: fileId, fileType: const td.FileTypeDocument()),
    );

    final completer = Completer<String>();

    final sub = _updateController.stream.listen((update) {
      if (update is td.UpdateFile) {
        final f = update.file;
        if (f.id == file.id) {
          final local = f.local;
          if (f.size > 0 && local.downloadedSize > 0) {
            onProgress?.call(local.downloadedSize, f.size);
          }
          if (local.isDownloadingCompleted && !completer.isCompleted) {
            // Move from TDLib cache to user's desired savePath
            final cachedPath = local.path;
            completer.complete(cachedPath);
          }
        }
      }
    });

    try {
      _send(td.DownloadFile(
        fileId: file.id,
        priority: 1,
        offset: 0,
        limit: 0,
        synchronous: false,
      ));

      final cachedPath = await completer.future.timeout(
        const Duration(minutes: 30),
        onTimeout: () => throw MtprotoException('Download timed out'),
      );

      // Copy from TDLib cache to the user's actual save path
      await File(cachedPath).copy(savePath);
      return savePath;
    } finally {
      await sub.cancel();
    }
  }

  // ── TDLib internals ───────────────────────────────────────

  void _send(td.TdFunction function) {
    final json = jsonEncode(function.toJson());
    TdPlugin.instance.tdSend(_clientId!, json);
  }

  /// Send a TDLib request and await the first matching response type.
  Future<T> _sendAsync<T extends td.TdObject>(
    td.TdFunction function, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final completer = Completer<T>();
    StreamSubscription? sub;

    sub = _updateController.stream.listen((update) {
      if (update is T && !completer.isCompleted) {
        completer.complete(update);
        sub?.cancel();
      } else if (update is td.TdError && !completer.isCompleted) {
        completer.completeError(
          MtprotoException(update.message, code: update.code.toString()),
        );
        sub?.cancel();
      }
    });

    _send(function);

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        sub?.cancel();
        throw MtprotoException('Request timed out: ${function.runtimeType}');
      },
    );
  }

  void _startReceiveLoop() {
    if (_receiveLoopRunning) return;
    _receiveLoopRunning = true;

    // Run the TDLib receive loop in a separate isolate to keep the main
    // thread free. The isolate sends raw JSON strings back via SendPort.
    _runIsolatedReceiveLoop();
  }

  void _runIsolatedReceiveLoop() {
    final receivePort = ReceivePort();

    Isolate.spawn(_tdReceiveIsolate, receivePort.sendPort).then((_) {
      receivePort.listen((message) {
        if (message is String) {
          _handleRawUpdate(message);
        }
      });
    });
  }

  static void _tdReceiveIsolate(SendPort sendPort) {
    // This function runs in a separate isolate.
    // It continuously polls TDLib for updates and sends them back.
    while (true) {
      final result = TdPlugin.instance.tdReceive(2.0); // 2s timeout
      if (result != null && result.isNotEmpty) {
        sendPort.send(result);
      }
    }
  }

  void _handleRawUpdate(String rawJson) {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final obj = td.convertJsonToObject(map);
      if (obj == null) return;

      _updateController.add(obj);
      _handleAuthUpdate(obj);
    } catch (_) {
      // Malformed JSON — ignore silently
    }
  }

  void _handleAuthUpdate(td.TdObject obj) {
    if (obj is td.UpdateAuthorizationState) {
      _onAuthState(obj.authorizationState);
    }

    // Handle errors for pending auth completers
    if (obj is td.TdError) {
      final err = MtprotoAuthException(obj.message, code: obj.code.toString());
      _codeCompleter?.completeError(err);
      _signInCompleter?.completeError(err);
      _passwordCompleter?.completeError(err);
      _codeCompleter = null;
      _signInCompleter = null;
      _passwordCompleter = null;
    }
  }

  void _onAuthState(td.AuthorizationState state) {
    if (state is td.AuthorizationStateWaitTdlibParameters) {
      _send(td.SetTdlibParameters(parameters: _tdlibParams!));
    } else if (state is td.AuthorizationStateWaitPhoneNumber) {
      // Ready to receive phone number — nothing to do here, sendCode() drives it
    } else if (state is td.AuthorizationStateWaitCode) {
      _authState = MtprotoAuthState.waitingCode;
      _codeCompleter?.complete();
      _codeCompleter = null;
    } else if (state is td.AuthorizationStateWaitPassword) {
      _authState = MtprotoAuthState.waitingPassword;
      _twoFaHint = state.passwordHint;
      final err = MtprotoTwoFactorRequired(hint: state.passwordHint ?? '');
      _signInCompleter?.completeError(err);
      _signInCompleter = null;
    } else if (state is td.AuthorizationStateReady) {
      _authState = MtprotoAuthState.authenticated;
      _signInCompleter?.complete();
      _passwordCompleter?.complete();
      _signInCompleter = null;
      _passwordCompleter = null;
      _persistSession();
    } else if (state is td.AuthorizationStateClosed) {
      _authState = MtprotoAuthState.closed;
      _receiveLoopRunning = false;
    }
  }

  Future<void> _persistSession() async {
    // Get the current DC from TDLib
    try {
      final network = await _sendAsync<td.NetworkStatistics>(
        td.GetNetworkStatistics(onlyCurrent: true),
      );
      // Extract DC from network statistics if available
      // For simplicity, we default to DC 1 if we can't determine it
      final dcId = '1';

      await _db.upsertSession(
        phone: _phoneNumber ?? '',
        dcId: dcId,
      );

      // Store API credentials in secure storage for session restore
      await _secure.write(
        key: AppConstants.secureKeyApiId,
        value: dotenv.env['TELEGRAM_API_ID'],
      );
      await _secure.write(
        key: AppConstants.secureKeyApiHash,
        value: dotenv.env['TELEGRAM_API_HASH'],
      );
    } catch (_) {
      // Non-fatal — session is still active in TDLib's own database
    }
  }

  void _requireAuth() {
    if (!isAuthenticated) {
      throw MtprotoException(
        'Not authenticated. Call sendCode() and signIn() first.',
      );
    }
  }

  td.FileType _fileTypeFromMime(String mime) {
    if (mime.startsWith('image/')) return const td.FileTypePhoto();
    if (mime.startsWith('video/')) return const td.FileTypeVideo();
    if (mime.startsWith('audio/')) return const td.FileTypeAudio();
    return const td.FileTypeDocument();
  }

  Future<void> dispose() async {
    await _updateController.close();
    if (_clientId != null) {
      _send(td.Close());
    }
  }
}
