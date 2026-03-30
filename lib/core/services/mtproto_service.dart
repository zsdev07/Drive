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

// ── Auth state enum ───────────────────────────────────────

enum MtprotoAuthState {
  initial,
  waitingCode,
  waitingPassword,
  authenticated,
  closed,
}

// ── MtprotoService ────────────────────────────────────────

/// Wraps TDLib 1.6.0 (tdjson FFI via the `tdlib` pub package) into clean
/// async Dart methods. Bot API ([TelegramService]) remains the default path —
/// this service is the opt-in upgrade that removes size limits.
///
/// Session lifecycle:
///   init() → sendCode() → signIn() | signInWithPassword() → [authenticated]
class MtprotoService {
  // ── Dependencies ────────────────────────────────────────
  final AppDatabase _db;
  final FlutterSecureStorage _secure;

  // ── TDLib client ────────────────────────────────────────
  // tdlib 1.6.0 removed TdlibParameters as a standalone object.
  // We store the fields individually and pass them flat to SetTdlibParameters.
  String? _databaseDirectory;
  String? _filesDirectory;
  int? _apiId;
  String? _apiHash;

  int? _clientId;
  final _updateController = StreamController<td.TdObject>.broadcast();
  bool _receiveLoopRunning = false;

  // ── State ───────────────────────────────────────────────
  MtprotoAuthState _authState = MtprotoAuthState.initial;
  String? _phoneNumber;

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

  // ── Init ─────────────────────────────────────────────────

  Future<void> init() async {
    if (_clientId != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    _apiId = int.tryParse(dotenv.env['TELEGRAM_API_ID'] ?? '0') ?? 0;
    _apiHash = dotenv.env['TELEGRAM_API_HASH'] ?? '';

    if (_apiId == 0 || (_apiHash?.isEmpty ?? true)) {
      throw MtprotoException(
        'TELEGRAM_API_ID or TELEGRAM_API_HASH missing from .env',
      );
    }

    _databaseDirectory = '${appDir.path}/tdlib';
    _filesDirectory = '${appDir.path}/tdlib_files';

    // tdlib 1.6.0: createClient() replaces tdCreateClientId()
    _clientId = TdPlugin.instance.createClient();
    _startReceiveLoop();
    _send(td.GetAuthorizationState());
  }

  // ── Auth flow ─────────────────────────────────────────────

  Future<void> sendCode(String phone) async {
    await init();
    _phoneNumber = phone;
    _codeCompleter = Completer<void>();

    // tdlib 1.6.0: hasUnknownPhoneNumber removed from PhoneNumberAuthenticationSettings
    _send(td.SetAuthenticationPhoneNumber(
      phoneNumber: phone,
      settings: const td.PhoneNumberAuthenticationSettings(
        allowFlashCall: false,
        allowMissedCall: false,
        isCurrentPhoneNumber: false,
        allowSmsRetrieverApi: false,
        authenticationTokens: [],
      ),
    ));

    await _codeCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw MtprotoAuthException('Timed out waiting for code'),
    );
  }

  Future<void> signIn(String phone, String code) async {
    _signInCompleter = Completer<void>();
    _send(td.CheckAuthenticationCode(code: code));
    await _signInCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw MtprotoAuthException('Timed out verifying code'),
    );
  }

  Future<void> signInWithPassword(String password) async {
    _passwordCompleter = Completer<void>();
    _send(td.CheckAuthenticationPassword(password: password));
    await _passwordCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw MtprotoAuthException('Timed out verifying password'),
    );
  }

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

  Future<TelegramUploadResult> uploadFile({
    required File file,
    required String mimeType,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    _requireAuth();

    final fileSize = await file.length();
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
      // tdlib 1.6.0: UploadFile renamed to PreliminaryUploadFile
      final response = await _sendAsync<td.File>(
        td.PreliminaryUploadFile(
          file: td.InputFileLocal(path: file.path),
          fileType: _fileTypeFromMime(mimeType),
          priority: 1,
        ),
      );
      tdFileId = response.id;

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

  Future<String> downloadFile({
    required String fileId,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    _requireAuth();

    final file = await _sendAsync<td.File>(
      td.GetRemoteFile(
        remoteFileId: fileId,
        fileType: const td.FileTypeDocument(),
      ),
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
            completer.complete(local.path);
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

      await File(cachedPath).copy(savePath);
      return savePath;
    } finally {
      await sub.cancel();
    }
  }

  // ── TDLib internals ───────────────────────────────────────

  void _send(td.TdFunction function) {
    final json = jsonEncode(function.toJson());
    // tdlib 1.6.0: send() replaces tdSend()
    TdPlugin.instance.send(_clientId!, json);
  }

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
    _runIsolatedReceiveLoop();
  }

  void _runIsolatedReceiveLoop() {
    final receivePort = ReceivePort();
    Isolate.spawn(_tdReceiveIsolate, receivePort.sendPort).then((_) {
      receivePort.listen((message) {
        if (message is String) _handleRawUpdate(message);
      });
    });
  }

  static void _tdReceiveIsolate(SendPort sendPort) {
    while (true) {
      // tdlib 1.6.0: receive() replaces tdReceive()
      final result = TdPlugin.instance.receive(2.0);
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
    } catch (_) {}
  }

  void _handleAuthUpdate(td.TdObject obj) {
    if (obj is td.UpdateAuthorizationState) {
      _onAuthState(obj.authorizationState);
    }
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
      // tdlib 1.6.0: SetTdlibParameters now takes flat named params directly —
      // no TdlibParameters wrapper object.
      _send(td.SetTdlibParameters(
        useTestDc: false,
        databaseDirectory: _databaseDirectory!,
        filesDirectory: _filesDirectory!,
        databaseEncryptionKey: '',
        useFileDatabase: false,
        useChatInfoDatabase: false,
        useMessageDatabase: false,
        useSecretChats: false,
        apiId: _apiId!,
        apiHash: _apiHash!,
        systemLanguageCode: 'en',
        deviceModel: Platform.operatingSystem,
        systemVersion: '',
        applicationVersion: AppConstants.appVersion,
      ));
    } else if (state is td.AuthorizationStateWaitPhoneNumber) {
      // Ready — sendCode() drives the next step
    } else if (state is td.AuthorizationStateWaitCode) {
      _authState = MtprotoAuthState.waitingCode;
      _codeCompleter?.complete();
      _codeCompleter = null;
    } else if (state is td.AuthorizationStateWaitPassword) {
      _authState = MtprotoAuthState.waitingPassword;
      final hint = state.passwordHint ?? '';
      final err = MtprotoTwoFactorRequired(hint: hint);
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
    try {
      await _db.upsertSession(phone: _phoneNumber ?? '', dcId: '1');
      await _secure.write(
        key: AppConstants.secureKeyApiId,
        value: dotenv.env['TELEGRAM_API_ID'],
      );
      await _secure.write(
        key: AppConstants.secureKeyApiHash,
        value: dotenv.env['TELEGRAM_API_HASH'],
      );
    } catch (_) {}
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
    if (_clientId != null) _send(td.Close());
  }
}
