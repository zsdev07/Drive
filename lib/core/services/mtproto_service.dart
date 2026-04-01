// lib/core/services/mtproto_service.dart
//
// MtprotoService is now a thin orchestration layer:
//   • Credential storage  (API ID / Hash in FlutterSecureStorage)
//   • Session persistence (auth key in secure storage)
//   • File upload/download (delegated to TdlibService)
//   • Auth state + stream (re-exported from TdlibService)
//
// All authentication flows (QR, phone OTP, 2FA) have moved to TdlibService.
// The old api.telegram.org HTTP calls have been REMOVED — they caused the
// MtprotoException [404]: Not Found because api.telegram.org is the Bot API
// gateway and does NOT serve auth.exportLoginToken or any user-auth methods.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../database/app_database.dart';
import 'tdlib_service.dart';
import 'telegram_service.dart';

// ═══════════════════════════════════════════════════════════
// Re-export TdlibService types so existing call-sites compile
// ═══════════════════════════════════════════════════════════

// Map old MtprotoAuthState values → TdlibAuthState so pages don't break
typedef MtprotoAuthState = TdlibAuthState;
typedef MtprotoQrToken   = TdlibQrToken;

// ═══════════════════════════════════════════════════════════
// Exceptions (kept for existing catch-sites)
// ═══════════════════════════════════════════════════════════

class MtprotoException implements Exception {
  final String message;
  final String? code;
  MtprotoException(this.message, {this.code});

  @override
  String toString() => code != null
      ? 'MtprotoException [$code]: $message'
      : 'MtprotoException: $message';
}

class MtprotoAuthException extends MtprotoException {
  MtprotoAuthException(super.message, {super.code});
}

class MtprotoTwoFactorRequired extends MtprotoException {
  final String hint;
  MtprotoTwoFactorRequired({required this.hint})
      : super('Two-factor authentication required');
}

class MtprotoFloodWaitException extends MtprotoException {
  final int waitSeconds;
  MtprotoFloodWaitException(this.waitSeconds)
      : super('Please wait $waitSeconds seconds before trying again.',
            code: 'FLOOD_WAIT');
}

// ═══════════════════════════════════════════════════════════
// MtprotoService
// ═══════════════════════════════════════════════════════════

class MtprotoService {
  final AppDatabase _db;
  final FlutterSecureStorage _secure;

  // TdlibService is created once credentials are available
  TdlibService? _tdlib;
  String? _tdlibChannelId;

  MtprotoService({
    required AppDatabase db,
    FlutterSecureStorage? secureStorage,
  })  : _db = db,
        _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.first_unlock),
            );

  // ── Internal stream controller for auth state ─────────────
  // This allows callers to subscribe before _tdlib is initialised.
  final _authStateCtrl = StreamController<TdlibAuthState>.broadcast();

  // ── Public state ──────────────────────────────────────────

  TdlibAuthState get authState =>
      _tdlib?.authState ?? TdlibAuthState.initial;

  Stream<TdlibAuthState> get authStateStream => _authStateCtrl.stream;

  bool get isAuthenticated =>
      _tdlib?.isAuthenticated ?? false;

  TdlibQrToken? get currentQrToken => _tdlib?.currentQrToken;

  // ── Init ──────────────────────────────────────────────────

  Future<void> init() async {
    final raw = await _secure.read(key: AppConstants.secureKeyAuthKey);
    if (raw == null || raw.isEmpty) return;

    try {
      jsonDecode(raw); // validate stored JSON
      // Session exists → spin up TDLib so it can restore auth
      await _ensureTdlib();
    } catch (_) {
      await _clearSession();
    }
  }

  // ── TDLib init ────────────────────────────────────────────

  /// Ensures TdlibService is created and initialised.
  /// Call this before any auth or file operation.
  Future<TdlibService> _ensureTdlib() async {
    if (_tdlib != null) return _tdlib!;

    final id   = await _secure.read(key: AppConstants.secureKeyApiId);
    final hash = await _secure.read(key: AppConstants.secureKeyApiHash);

    if (id == null || id.isEmpty || hash == null || hash.isEmpty) {
      throw MtprotoException(
          'API credentials not set. Enter them on the credentials page.',
          code: 'MISSING_CREDENTIALS');
    }

    final apiId = int.tryParse(id);
    if (apiId == null || apiId == 0) {
      throw MtprotoException('Invalid API ID: "$id"');
    }

    _tdlib = TdlibService();
    await _tdlib!.init(apiId: apiId, apiHash: hash);

    // Forward all TDLib auth state changes through our broadcast controller
    // so callers who subscribed before _tdlib existed still get updates.
    _tdlib!.authStateStream.listen((state) async {
      // Broadcast to our own controller first
      if (!_authStateCtrl.isClosed) _authStateCtrl.add(state);

      if (state == TdlibAuthState.authenticated) {
        // Persist session key when authenticated
        await _secure.write(
          key: AppConstants.secureKeyAuthKey,
          value: jsonEncode({
            'ts': DateTime.now().millisecondsSinceEpoch,
          }),
        );
        try {
          await _db.upsertSession(phone: 'tdlib', dcId: '2');
        } catch (_) {}
      } else if (state == TdlibAuthState.closed) {
        await _clearSession();
      }
    });

    return _tdlib!;
  }

  /// Public: call once the user is authenticated and channelId is known.
  Future<void> initTdlib({required String channelId}) async {
    if (_tdlibChannelId == channelId && _tdlib != null) return;
    await _ensureTdlib();
    _tdlibChannelId = channelId;
  }

  // ── Credentials ───────────────────────────────────────────

  Future<bool> hasCredentials() async {
    final id   = await _secure.read(key: AppConstants.secureKeyApiId);
    final hash = await _secure.read(key: AppConstants.secureKeyApiHash);
    return (id?.isNotEmpty ?? false) && (hash?.isNotEmpty ?? false);
  }

  Future<void> saveCredentials({
    required String apiId,
    required String apiHash,
  }) async {
    await _secure.write(key: AppConstants.secureKeyApiId,   value: apiId.trim());
    await _secure.write(key: AppConstants.secureKeyApiHash, value: apiHash.trim());
  }

  Future<void> clearCredentials() async {
    await _secure.delete(key: AppConstants.secureKeyApiId);
    await _secure.delete(key: AppConstants.secureKeyApiHash);
  }

  // ══════════════════════════════════════════════════════════
  // QR LOGIN  (delegates entirely to TdlibService)
  // ══════════════════════════════════════════════════════════

  /// Initialises TDLib (if not yet done) and requests a QR login token.
  /// TDLib fires [TdlibAuthState.waitingQrScan] with [currentQrToken] set.
  Future<TdlibQrToken> startQrLogin() async {
    final tdlib = await _ensureTdlib();

    // Set up the stream listener BEFORE requesting QR login to avoid missing
    // the state update that arrives immediately after the request.
    // Use the TdlibService stream directly — _tdlib is guaranteed non-null here.
    final stateStream = tdlib.authStateStream.asBroadcastStream();

    // If TDLib is already in waitingQrScan state (e.g. after a refresh),
    // return the cached token immediately without sending another request.
    if (tdlib.authState == TdlibAuthState.waitingQrScan &&
        tdlib.currentQrToken != null) {
      return tdlib.currentQrToken!;
    }

    // Subscribe first, then send the request — eliminates the race window.
    final stateFuture = stateStream
        .where((s) => s == TdlibAuthState.waitingQrScan)
        .timeout(const Duration(seconds: 20))
        .first;

    await tdlib.requestQrLogin();

    // Wait for TDLib to emit the QR link
    await stateFuture;

    final token = tdlib.currentQrToken;
    if (token == null) {
      throw MtprotoException('Failed to obtain QR token from TDLib.',
          code: 'QR_TOKEN_NULL');
    }
    return token;
  }

  // ══════════════════════════════════════════════════════════
  // PHONE LOGIN  (delegates entirely to TdlibService)
  // ══════════════════════════════════════════════════════════

  Future<void> sendCode(String phone) async {
    final tdlib = await _ensureTdlib();
    try {
      await tdlib.setPhoneNumber(phone);
    } on TdlibAuthException catch (e) {
      throw MtprotoAuthException(e.message, code: e.code);
    }
  }

  Future<void> signIn(String phone, String code) async {
    if (_tdlib == null) {
      throw MtprotoAuthException('Call sendCode() first.', code: 'NOT_READY');
    }
    try {
      await _tdlib!.checkCode(code);
    } on TdlibTwoFactorRequired catch (e) {
      throw MtprotoTwoFactorRequired(hint: e.hint);
    } on TdlibAuthException catch (e) {
      throw MtprotoAuthException(e.message, code: e.code);
    }
  }

  Future<void> signInWithPassword(String password) async {
    if (_tdlib == null) {
      throw MtprotoAuthException('Not in auth flow.', code: 'NOT_READY');
    }
    try {
      await _tdlib!.checkPassword(password);
    } on TdlibAuthException catch (e) {
      throw MtprotoAuthException(e.message, code: e.code);
    }
  }

  // ══════════════════════════════════════════════════════════
  // SIGN OUT
  // ══════════════════════════════════════════════════════════

  Future<void> signOut() async {
    try { await _tdlib?.signOut(); } catch (_) {}
    await _tdlib?.dispose();
    _tdlib          = null;
    _tdlibChannelId = null;
    await _clearSession();
    await _db.clearAllSessions();
    // Emit closed state so listeners know the session ended
    if (!_authStateCtrl.isClosed) _authStateCtrl.add(TdlibAuthState.closed);
  }

  // ══════════════════════════════════════════════════════════
  // FILE OPS — delegated to TdlibService
  // ══════════════════════════════════════════════════════════

  Future<TelegramUploadResult> uploadFile({
    required io.File file,
    required String mimeType,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (!isAuthenticated) {
      throw MtprotoException('Not authenticated.', code: 'NOT_AUTHENTICATED');
    }
    if (_tdlib == null || _tdlibChannelId == null) {
      throw MtprotoException(
        'TdlibService not initialised. Call initTdlib() first.',
        code: 'TDLIB_NOT_READY',
      );
    }

    final result = await _tdlib!.uploadFile(
      file: file,
      mimeType: mimeType,
      fileName: fileName,
      channelId: _tdlibChannelId!,
      onProgress: onProgress,
    );

    return TelegramUploadResult(
      fileId: result.fileId,
      messageId: result.messageId,
      fileSize: result.fileSize,
    );
  }

  Future<String> downloadFile({
    required String fileId,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    if (!isAuthenticated) {
      throw MtprotoException('Not authenticated.', code: 'NOT_AUTHENTICATED');
    }
    if (_tdlib == null) {
      throw MtprotoException(
        'TdlibService not initialised. Call initTdlib() first.',
        code: 'TDLIB_NOT_READY',
      );
    }

    return _tdlib!.downloadFile(
      fileId: fileId,
      savePath: savePath,
      onProgress: onProgress,
    );
  }

  // ══════════════════════════════════════════════════════════
  // Dispose
  // ══════════════════════════════════════════════════════════

  Future<void> dispose() async {
    await _tdlib?.dispose();
    if (!_authStateCtrl.isClosed) await _authStateCtrl.close();
  }

  // ── Internal ──────────────────────────────────────────────

  Future<void> _clearSession() async {
    await _secure.delete(key: AppConstants.secureKeyAuthKey);
    await _secure.delete(key: AppConstants.secureKeyDcId);
    await _secure.delete(key: AppConstants.secureKeyServerSalt);
  }
}
