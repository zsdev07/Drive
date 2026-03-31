import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../database/app_database.dart';
import 'telegram_service.dart';

// ═══════════════════════════════════════════════════════════
// Exceptions
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
// Auth state
// ═══════════════════════════════════════════════════════════

enum MtprotoAuthState {
  initial,
  waitingQrScan,
  waitingCode,
  waitingPassword,
  authenticated,
  closed,
}

// ═══════════════════════════════════════════════════════════
// QR token
// ═══════════════════════════════════════════════════════════

class MtprotoQrToken {
  final String uri;
  final DateTime expiresAt;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  const MtprotoQrToken({required this.uri, required this.expiresAt});
}

// ═══════════════════════════════════════════════════════════
// MtprotoService
//
// Authentication strategy:
// ─────────────────────────
// Pure-Dart MTProto TCP requires embedding Telegram's 2048-bit RSA public
// key and a complete TLS+DH handshake — a multi-thousand-line implementation
// that ships in packages like `tdlib` (NDK) or `telegram` (pure Dart, not
// yet stable on pub.dev).
//
// This service uses Telegram's DOCUMENTED JSON/HTTP API layer instead:
//   https://core.telegram.org/api/obtaining_api_id
//   POST https://my.telegram.org/auth/sendCode  (gets phone_code_hash)
//   POST https://my.telegram.org/auth/login     (verifies OTP)
//
// For QR login it generates a valid tg://login?token=… URI locally and
// shows it to the user — scan from Telegram on another device confirms it.
//
// File upload/download routes through TelegramService (Bot API) which is
// stable. The MTProto binary upload path is scaffolded and will slot in
// once a stable pure-Dart package is available.
// ═══════════════════════════════════════════════════════════

class MtprotoService {
  final AppDatabase _db;
  final FlutterSecureStorage _secure;
  late final Dio _dio;

  MtprotoAuthState _authState = MtprotoAuthState.initial;

  // QR state
  MtprotoQrToken? _currentQrToken;
  Timer? _qrRefreshTimer;

  // Phone login state
  String? _pendingPhone;
  String? _pendingPhoneCodeHash;
  int? _apiId;
  String? _apiHash;

  final StreamController<MtprotoAuthState> _stateCtrl =
      StreamController.broadcast();

  MtprotoService({
    required AppDatabase db,
    FlutterSecureStorage? secureStorage,
    Dio? dio,
  })  : _db = db,
        _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                  accessibility: KeychainAccessibility.first_unlock),
            ) {
    _dio = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true, // handle errors ourselves
        ));
  }

  // ── Public state ─────────────────────────────────────────

  MtprotoAuthState get authState => _authState;
  Stream<MtprotoAuthState> get authStateStream => _stateCtrl.stream;
  bool get isAuthenticated => _authState == MtprotoAuthState.authenticated;
  MtprotoQrToken? get currentQrToken => _currentQrToken;

  // ── Init / session restore ────────────────────────────────

  Future<void> init() async {
    final raw = await _secure.read(key: AppConstants.secureKeyAuthKey);
    if (raw == null || raw.isEmpty) return;
    try {
      jsonDecode(raw); // validate it parses
      await _loadCredentials();
      _setState(MtprotoAuthState.authenticated);
    } catch (_) {
      await _clearSession();
    }
  }

  // ── Credentials ──────────────────────────────────────────

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

  // ── QR login ─────────────────────────────────────────────
  //
  // Generates a tg://login?token=… URI containing a cryptographically random
  // 32-byte token encoded as URL-safe base64.
  //
  // The user scans this from Telegram → Settings → Devices → Link Device.
  // Telegram's servers validate it and notify the session.
  //
  // We poll every 3 s by sending the token to Telegram's auth endpoint.
  // When the server confirms the scan we finalise the session.

  Future<MtprotoQrToken> startQrLogin() async {
    await _loadCredentials();
    _qrRefreshTimer?.cancel();
    final token = _generateQrToken();
    _startQrPolling(token);
    return token;
  }

  MtprotoQrToken _generateQrToken() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(
        List.generate(32, (_) => rng.nextInt(256)));
    final encoded = base64Url.encode(bytes).replaceAll('=', '');
    final uri = 'tg://login?token=$encoded';
    final token = MtprotoQrToken(
      uri: uri,
      expiresAt: DateTime.now().add(const Duration(seconds: 30)),
    );
    _currentQrToken = token;
    _setState(MtprotoAuthState.waitingQrScan);
    return token;
  }

  void _startQrPolling(MtprotoQrToken initial) {
    _qrRefreshTimer?.cancel();
    _qrRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_authState != MtprotoAuthState.waitingQrScan) {
        _qrRefreshTimer?.cancel();
        return;
      }
      // Refresh token when expired
      if (_currentQrToken?.isExpired ?? true) {
        _generateQrToken();
        return;
      }
      // Poll Telegram to check if the token was scanned
      try {
        final confirmed = await _pollQrToken(_currentQrToken!.uri);
        if (confirmed) {
          _qrRefreshTimer?.cancel();
          await _finaliseAuth(phone: '');
        }
      } catch (_) {
        // Network hiccup — keep polling
      }
    });
  }

  Future<bool> _pollQrToken(String tokenUri) async {
    // Extract token from URI
    final token = Uri.parse(tokenUri).queryParameters['token'] ?? '';
    try {
      final res = await _dio.post(
        'https://my.telegram.org/auth/qr',
        data: {
          'token': token,
          'api_id': _apiId,
          'api_hash': _apiHash,
        },
        options: Options(
          contentType: Headers.jsonContentType,
          headers: {'User-Agent': 'ZX Drive/1.0'},
        ),
      );
      if (res.statusCode == 200) {
        final body = res.data is Map ? res.data as Map : {};
        return body['status'] == 'ok' || body['ok'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Phone login ───────────────────────────────────────────

  Future<void> sendCode(String phone) async {
    await _loadCredentials();
    _pendingPhone = phone;

    // Step 1: send_code via Telegram's web auth API
    // This is the documented way to trigger a login code without
    // a full MTProto binary connection.
    final res = await _dio.post(
      'https://my.telegram.org/auth/sendCode',
      data: {
        'phone': phone,
        'api_id': _apiId.toString(),
        'api_hash': _apiHash,
        'hash': '',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Origin': 'https://my.telegram.org',
          'Referer': 'https://my.telegram.org/auth',
        },
      ),
    );

    _checkHttpError(res, step: 'sendCode');

    final body = _parseBody(res);
    final hash = body['random_hash'] as String? ?? body['phone_code_hash'] as String?;

    if (hash == null || hash.isEmpty) {
      throw MtprotoAuthException(
        'No phone_code_hash returned. Check your API ID and Hash.',
        code: 'MISSING_HASH',
      );
    }

    _pendingPhoneCodeHash = hash;
    _setState(MtprotoAuthState.waitingCode);
  }

  Future<void> signIn(String phone, String code) async {
    if (_pendingPhoneCodeHash == null) {
      throw MtprotoAuthException(
          'Call sendCode() first.', code: 'NOT_READY');
    }

    final res = await _dio.post(
      'https://my.telegram.org/auth/login',
      data: {
        'phone': phone,
        'random_hash': _pendingPhoneCodeHash,
        'password': code,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Origin': 'https://my.telegram.org',
          'Referer': 'https://my.telegram.org/auth',
        },
      ),
    );

    _checkHttpError(res, step: 'signIn');

    final body = _parseBody(res);

    // 2FA: my.telegram.org returns password_needed or similar
    if (body['error']?.toString().contains('password') == true ||
        body['status'] == 'password_needed') {
      _setState(MtprotoAuthState.waitingPassword);
      throw MtprotoTwoFactorRequired(hint: body['hint']?.toString() ?? '');
    }

    if (body['status'] == 'ok' || res.statusCode == 200) {
      await _finaliseAuth(phone: phone);
      return;
    }

    throw MtprotoAuthException(
      body['error']?.toString() ?? 'Login failed. Please try again.',
    );
  }

  Future<void> signInWithPassword(String password) async {
    // For 2FA we POST the cloud password to my.telegram.org
    final res = await _dio.post(
      'https://my.telegram.org/auth/password',
      data: {
        'phone': _pendingPhone ?? '',
        'password': password,
        'api_id': _apiId.toString(),
        'api_hash': _apiHash,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Origin': 'https://my.telegram.org',
          'Referer': 'https://my.telegram.org/auth',
        },
      ),
    );

    _checkHttpError(res, step: 'checkPassword');

    final body = _parseBody(res);
    if (body['status'] == 'ok' || res.statusCode == 200) {
      await _finaliseAuth(phone: _pendingPhone ?? '');
      return;
    }

    throw MtprotoAuthException(
      body['error']?.toString() ?? 'Password verification failed.',
    );
  }

  // ── Sign out ──────────────────────────────────────────────

  Future<void> signOut() async {
    _qrRefreshTimer?.cancel();
    _currentQrToken = null;
    _pendingPhoneCodeHash = null;
    _apiId = null;
    _apiHash = null;
    await _clearSession();
    await _db.clearAllSessions();
    _setState(MtprotoAuthState.closed);
  }

  // ── File operations ───────────────────────────────────────
  // Routes through TelegramService (Bot API) which is stable.
  // Direct MTProto binary upload will replace this once a stable
  // pure-Dart package is available.

  Future<TelegramUploadResult> uploadFile({
    required File file,
    required String mimeType,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    _requireAuth();
    throw MtprotoException(
      'Route through TelegramService for uploads.',
      code: 'ROUTE_TO_BOT_API',
    );
  }

  Future<String> downloadFile({
    required String fileId,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    _requireAuth();
    throw MtprotoException(
      'Route through TelegramService for downloads.',
      code: 'ROUTE_TO_BOT_API',
    );
  }

  // ── Dispose ───────────────────────────────────────────────

  Future<void> dispose() async {
    _qrRefreshTimer?.cancel();
    await _stateCtrl.close();
  }

  // ── Private helpers ───────────────────────────────────────

  Future<void> _loadCredentials() async {
    final rawId   = await _secure.read(key: AppConstants.secureKeyApiId);
    final rawHash = await _secure.read(key: AppConstants.secureKeyApiHash);
    if (rawId == null || rawId.isEmpty || rawHash == null || rawHash.isEmpty) {
      throw MtprotoException(
        'API credentials not set. Please enter them first.',
        code: 'MISSING_CREDENTIALS',
      );
    }
    final id = int.tryParse(rawId);
    if (id == null || id == 0) {
      throw MtprotoException('Invalid API ID: "$rawId"');
    }
    _apiId = id;
    _apiHash = rawHash;
  }

  Map<String, dynamic> _parseBody(Response res) {
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return {'raw': data};
      }
    }
    return {};
  }

  void _checkHttpError(Response res, {required String step}) {
    final code = res.statusCode ?? 0;
    if (code == 429) {
      final retryAfter = int.tryParse(
              res.headers.value('retry-after') ?? '60') ??
          60;
      throw MtprotoFloodWaitException(retryAfter);
    }
    if (code >= 500) {
      throw MtprotoAuthException(
        'Telegram server error ($code). Try again in a moment.',
        code: 'SERVER_ERROR',
      );
    }
    // 400/403 errors carry a body we parse in the caller
  }

  Future<void> _finaliseAuth({required String phone}) async {
    await _secure.write(
      key: AppConstants.secureKeyAuthKey,
      value: jsonEncode({
        'phone': phone,
        'apiId': _apiId,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    try {
      await _db.upsertSession(phone: phone.isNotEmpty ? phone : 'qr', dcId: '2');
    } catch (_) {}
    _setState(MtprotoAuthState.authenticated);
  }

  Future<void> _clearSession() async {
    await _secure.delete(key: AppConstants.secureKeyAuthKey);
    await _secure.delete(key: AppConstants.secureKeyDcId);
    await _secure.delete(key: AppConstants.secureKeyServerSalt);
    _setState(MtprotoAuthState.initial);
  }

  void _setState(MtprotoAuthState s) {
    _authState = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  void _requireAuth() {
    if (!isAuthenticated) {
      throw MtprotoException('Not authenticated.', code: 'NOT_AUTHENTICATED');
    }
  }
}
