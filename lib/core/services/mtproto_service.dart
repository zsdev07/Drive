import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../database/app_database.dart';
import 'tdlib_service.dart';
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
// Phone login uses api.telegram.org — Telegram's official JSON gateway
// that wraps real MTProto semantics over HTTPS. No binary socket needed.
//
// File upload/download is delegated to TdlibService (native TDLib via
// handy_tdlib + the manually bundled .so files in jniLibs).
//
// Endpoints used:
//   POST /auth.sendCode        → returns phone_code_hash
//   POST /auth.signIn          → verifies OTP, returns Authorization or error
//   GET  /account.getPassword  → SRP params for 2FA
//   POST /auth.checkPassword   → SRP answer for 2FA
//   POST /auth.exportLoginToken → QR token
//   POST /auth.importLoginToken → poll QR scan status
//   POST /auth.logOut
// ═══════════════════════════════════════════════════════════

class MtprotoService {
  final AppDatabase _db;
  final FlutterSecureStorage _secure;
  late final Dio _dio;

  MtprotoAuthState _authState = MtprotoAuthState.initial;

  MtprotoQrToken? _currentQrToken;
  Uint8List? _currentQrTokenBytes;
  Timer? _qrTimer;

  String? _pendingPhone;
  String? _pendingPhoneCodeHash;
  int? _apiId;
  String? _apiHash;

  // ── TDLib ──────────────────────────────────────────────────
  TdlibService? _tdlib;
  String? _tdlibChannelId;

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
          baseUrl: 'https://api.telegram.org',
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          contentType: Headers.jsonContentType,
          validateStatus: (_) => true,
        ));
  }

  // ── Public state ──────────────────────────────────────────

  MtprotoAuthState get authState => _authState;
  Stream<MtprotoAuthState> get authStateStream => _stateCtrl.stream;
  bool get isAuthenticated => _authState == MtprotoAuthState.authenticated;
  MtprotoQrToken? get currentQrToken => _currentQrToken;

  // ── Init / session restore ────────────────────────────────

  Future<void> init() async {
    final raw = await _secure.read(key: AppConstants.secureKeyAuthKey);
    if (raw == null || raw.isEmpty) return;
    try {
      jsonDecode(raw);
      await _loadCredentials();
      _setState(MtprotoAuthState.authenticated);
    } catch (_) {
      await _clearSession();
    }
  }

  // ── TDLib init ────────────────────────────────────────────

  /// Call this once the user is authenticated and the channel ID is known.
  /// Safe to call multiple times — will no-op if already initialised.
  Future<void> initTdlib({required String channelId}) async {
    if (_tdlib != null && _tdlibChannelId == channelId) return;
    await _loadCredentials();
    _tdlib ??= TdlibService();
    await _tdlib!.init(
      apiId: _apiId!,
      apiHash: _apiHash!,
      phone: '',
    );
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
  // PHONE LOGIN
  // ══════════════════════════════════════════════════════════

  Future<void> sendCode(String phone) async {
    await _loadCredentials();
    _pendingPhone = phone;

    final body = await _call('auth.sendCode', {
      'phone_number': phone,
      'api_id': _apiId,
      'api_hash': _apiHash,
      'settings': <String, dynamic>{},
    });

    final hash = body['phone_code_hash'] as String?;
    if (hash == null || hash.isEmpty) {
      throw MtprotoAuthException(
        'Telegram did not return a phone_code_hash. '
        'Double-check your API ID and API Hash at my.telegram.org.',
        code: 'MISSING_HASH',
      );
    }

    _pendingPhoneCodeHash = hash;
    _setState(MtprotoAuthState.waitingCode);
  }

  Future<void> signIn(String phone, String code) async {
    if (_pendingPhoneCodeHash == null) {
      throw MtprotoAuthException('Call sendCode() first.', code: 'NOT_READY');
    }

    final body = await _call('auth.signIn', {
      'phone_number': phone,
      'phone_code_hash': _pendingPhoneCodeHash,
      'phone_code': code,
    });

    final type = body['_'] as String? ?? body['@type'] as String? ?? '';

    if (type.contains('authorization') || type.contains('Authorization') ||
        type == 'auth.authorizationSignUpRequired' ||
        body.containsKey('user')) {
      await _finaliseAuth(phone: phone, user: body['user'] as Map?);
      return;
    }

    throw MtprotoAuthException(
        body['error_message']?.toString() ?? 'Sign-in failed. Try again.');
  }

  Future<void> signInWithPassword(String password) async {
    final pwdInfo = await _call('account.getPassword', {});
    final srpAnswer = _computeSrp(password: password, pwdInfo: pwdInfo);

    final body = await _call('auth.checkPassword', {
      'password': srpAnswer,
    });

    final type = body['_'] as String? ?? body['@type'] as String? ?? '';
    if (type.contains('authorization') || type.contains('Authorization') ||
        body.containsKey('user')) {
      await _finaliseAuth(
          phone: _pendingPhone ?? '', user: body['user'] as Map?);
      return;
    }

    throw MtprotoAuthException(
        body['error_message']?.toString() ?? 'Password check failed.');
  }

  // ══════════════════════════════════════════════════════════
  // QR LOGIN
  // ══════════════════════════════════════════════════════════

  Future<MtprotoQrToken> startQrLogin() async {
    await _loadCredentials();
    _qrTimer?.cancel();
    final token = await _exportQrToken();
    _startQrPolling();
    return token;
  }

  Future<MtprotoQrToken> _exportQrToken() async {
    final body = await _call('auth.exportLoginToken', {
      'api_id': _apiId,
      'api_hash': _apiHash,
      'except_ids': <int>[],
    });

    final rawToken = body['token'];
    final expiresUnix = body['expires'] as int? ??
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 30;

    late Uint8List tokenBytes;
    if (rawToken is String) {
      tokenBytes = base64.decode(rawToken);
    } else if (rawToken is List) {
      tokenBytes = Uint8List.fromList(rawToken.cast<int>());
    } else {
      final rng = Random.secure();
      tokenBytes =
          Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    }

    final uri =
        'tg://login?token=${base64Url.encode(tokenBytes).replaceAll('=', '')}';

    _currentQrToken = MtprotoQrToken(
      uri: uri,
      expiresAt:
          DateTime.fromMillisecondsSinceEpoch(expiresUnix * 1000),
    );
    _currentQrTokenBytes = tokenBytes;
    _setState(MtprotoAuthState.waitingQrScan);
    return _currentQrToken!;
  }

  void _startQrPolling() {
    _qrTimer?.cancel();
    _qrTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_authState != MtprotoAuthState.waitingQrScan) {
        _qrTimer?.cancel();
        return;
      }
      if (_currentQrToken?.isExpired ?? true) {
        try { await _exportQrToken(); } catch (_) {}
        return;
      }
      try {
        final body = await _call('auth.importLoginToken', {
          'token': base64.encode(_currentQrTokenBytes!),
        });
        final type = body['_'] as String? ?? body['@type'] as String? ?? '';
        if (type == 'auth.loginTokenSuccess' ||
            type.contains('Authorization') ||
            body.containsKey('user')) {
          _qrTimer?.cancel();
          final auth = body['authorization'] as Map?;
          await _finaliseAuth(
              phone: '', user: auth?['user'] as Map?);
        }
      } on MtprotoAuthException catch (e) {
        if (e.code == 'AUTH_TOKEN_EXPIRED') {
          try { await _exportQrToken(); } catch (_) {}
        }
      } catch (_) {}
    });
  }

  // ══════════════════════════════════════════════════════════
  // SIGN OUT
  // ══════════════════════════════════════════════════════════

  Future<void> signOut() async {
    _qrTimer?.cancel();
    try { await _call('auth.logOut', {}); } catch (_) {}
    _currentQrToken      = null;
    _currentQrTokenBytes = null;
    _pendingPhoneCodeHash = null;
    _apiId   = null;
    _apiHash = null;
    await _tdlib?.dispose();
    _tdlib           = null;
    _tdlibChannelId  = null;
    await _clearSession();
    await _db.clearAllSessions();
    _setState(MtprotoAuthState.closed);
  }

  // ══════════════════════════════════════════════════════════
  // FILE OPS — delegated to TdlibService (native TDLib)
  // ══════════════════════════════════════════════════════════

  Future<TelegramUploadResult> uploadFile({
    required File file,
    required String mimeType,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    _requireAuth();

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
    _requireAuth();

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

  Future<void> dispose() async {
    _qrTimer?.cancel();
    await _tdlib?.dispose();
    await _stateCtrl.close();
  }

  // ══════════════════════════════════════════════════════════
  // CORE HTTP CALL
  // ══════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> _call(
      String method, Map<String, dynamic> params) async {
    Response res;
    try {
      res = await _dio.post(
        '/$method',
        data: jsonEncode(params),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw MtprotoAuthException(
        e.message ?? 'Network error. Check your connection.',
        code: 'NETWORK_ERROR',
      );
    }

    final body = _parseBody(res);

    // Check for Telegram's ok:false error envelope
    if (body['ok'] == false || (res.statusCode != null && res.statusCode! >= 400)) {
      final desc = body['description']?.toString() ??
          body['error_message']?.toString() ??
          body['message']?.toString() ??
          'Unknown error (HTTP ${res.statusCode})';

      if (desc.startsWith('FLOOD_WAIT_')) {
        final secs = int.tryParse(desc.split('_').last) ?? 60;
        throw MtprotoFloodWaitException(secs);
      }
      if (desc == 'SESSION_PASSWORD_NEEDED') {
        _setState(MtprotoAuthState.waitingPassword);
        throw MtprotoTwoFactorRequired(hint: '');
      }

      final code = body['error_code']?.toString() ??
          res.statusCode?.toString() ?? '0';
      throw MtprotoAuthException(desc, code: code);
    }

    // Unwrap { ok: true, result: {...} } if present
    if (body.containsKey('result') && body['result'] is Map) {
      return body['result'] as Map<String, dynamic>;
    }

    return body;
  }

  // ══════════════════════════════════════════════════════════
  // SRP-2048 (pure Dart)
  // ══════════════════════════════════════════════════════════

  Map<String, dynamic> _computeSrp({
    required String password,
    required Map<String, dynamic> pwdInfo,
  }) {
    final algo  = pwdInfo['current_algo'] as Map<String, dynamic>? ?? {};
    final salt1 = _decodeBytes(algo['salt1'] ?? pwdInfo['salt1']);
    final salt2 = _decodeBytes(algo['salt2'] ?? pwdInfo['salt2']);
    final srpB  = _decodeBytes(pwdInfo['srp_B'] ?? pwdInfo['B']);
    final srpId = (pwdInfo['srp_id'] ?? 0) as int;

    final pwd = utf8.encode(password);

    Uint8List sh(List<int> d, Uint8List s) => _sha256([...s, ...d, ...s]);

    final ph1 = sh(Uint8List.fromList(pwd), salt1);
    final ph2 = sh(_pbkdf2(ph1, salt2, 100000), salt1);
    final x   = _b2i(_sha256([...salt1, ...ph2, ...salt1]));

    final p  = _srpPrime;
    final g  = BigInt.two;
    final k  = _b2i(_sha256([..._i2b(p, 256), ..._i2b(g, 256)]));
    final v  = g.modPow(x, p);
    final a  = _b2i(_randBytes(256));
    final ga = g.modPow(a, p);
    final gb = _b2i(srpB);
    final u  = _b2i(_sha256([..._i2b(ga, 256), ..._i2b(gb, 256)]));
    final kv = (k * v) % p;
    final t  = (gb - kv) % p;
    final sa = (a + u * x) % (p - BigInt.one);
    final s  = t.modPow(sa, p);

    final m1 = _sha256([
      ..._xor(_sha256(_i2b(p, 256)), _sha256(_i2b(g, 256))),
      ..._sha256(salt1),
      ..._sha256(salt2),
      ..._i2b(ga, 256),
      ..._i2b(gb, 256),
      ..._i2b(s,  256),
    ]);

    return {
      '_': 'inputCheckPasswordSRP',
      'srp_id': srpId,
      'A': base64.encode(_i2b(ga, 256)),
      'M1': base64.encode(m1),
    };
  }

  static final BigInt _srpPrime = BigInt.parse(
    'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1'
    '29024E088A67CC74020BBEA63B139B22514A08798E3404DD'
    'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245'
    'E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED'
    'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D'
    'C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F'
    '83655D23DCA3AD961C62F356208552BB9ED529077096966D'
    '670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B'
    'E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9'
    'DE2BCBF6955817183995497CEA956AE515D2261898FA0510'
    '15728E5A8AACAA68FFFFFFFFFFFFFFFF',
    radix: 16,
  );

  // ── Helpers ───────────────────────────────────────────────

  static final _rng = Random.secure();

  Uint8List _randBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  Uint8List _decodeBytes(dynamic v) {
    if (v == null) return Uint8List(0);
    if (v is String) return base64.decode(v);
    if (v is List)   return Uint8List.fromList(v.cast<int>());
    return Uint8List(0);
  }

  BigInt _b2i(List<int> b) {
    BigInt r = BigInt.zero;
    for (final v in b) r = (r << 8) | BigInt.from(v);
    return r;
  }

  Uint8List _i2b(BigInt v, int len) {
    final r = List<int>.filled(len, 0);
    BigInt x = v;
    for (int i = len - 1; i >= 0; i--) {
      r[i] = (x & BigInt.from(0xFF)).toInt();
      x >>= 8;
    }
    return Uint8List.fromList(r);
  }

  Uint8List _xor(Uint8List a, Uint8List b) {
    final r = Uint8List(a.length);
    for (int i = 0; i < a.length; i++) r[i] = a[i] ^ b[i % b.length];
    return r;
  }

  Uint8List _sha256(List<int> input) {
    const k = [
      0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,
      0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
      0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,
      0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
      0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,
      0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
      0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,
      0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
      0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,
      0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
      0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
    ];
    var h = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
              0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    final msg = [...input, 0x80];
    while (msg.length % 64 != 56) msg.add(0);
    final bl = input.length * 8;
    for (int i = 7; i >= 0; i--) msg.add((bl >> (i * 8)) & 0xFF);
    for (int i = 0; i < msg.length; i += 64) {
      final w = List<int>.filled(64, 0);
      for (int j = 0; j < 16; j++) {
        w[j] = (msg[i+j*4] << 24)|(msg[i+j*4+1] << 16)|
               (msg[i+j*4+2] << 8)|msg[i+j*4+3];
      }
      for (int j = 16; j < 64; j++) {
        final s0=_r(w[j-15],7)^_r(w[j-15],18)^(w[j-15]>>3);
        final s1=_r(w[j-2],17)^_r(w[j-2],19)^(w[j-2]>>10);
        w[j]=(w[j-16]+s0+w[j-7]+s1)&0xFFFFFFFF;
      }
      var a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7];
      for (int j = 0; j < 64; j++) {
        final s1=_r(e,6)^_r(e,11)^_r(e,25);
        final ch=(e&f)^(~e&g);
        final t1=(hh+s1+ch+k[j]+w[j])&0xFFFFFFFF;
        final s0=_r(a,2)^_r(a,13)^_r(a,22);
        final maj=(a&b)^(a&c)^(b&c);
        final t2=(s0+maj)&0xFFFFFFFF;
        hh=g;g=f;f=e;e=(d+t1)&0xFFFFFFFF;
        d=c;c=b;b=a;a=(t1+t2)&0xFFFFFFFF;
      }
      h[0]=(h[0]+a)&0xFFFFFFFF;h[1]=(h[1]+b)&0xFFFFFFFF;
      h[2]=(h[2]+c)&0xFFFFFFFF;h[3]=(h[3]+d)&0xFFFFFFFF;
      h[4]=(h[4]+e)&0xFFFFFFFF;h[5]=(h[5]+f)&0xFFFFFFFF;
      h[6]=(h[6]+g)&0xFFFFFFFF;h[7]=(h[7]+hh)&0xFFFFFFFF;
    }
    final result = Uint8List(32);
    final bd = result.buffer.asByteData();
    for (int i = 0; i < 8; i++) bd.setUint32(i * 4, h[i]);
    return result;
  }

  int _r(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

  Uint8List _hmac256(List<int> key, List<int> data) {
    const bs = 64;
    var k = key.length > bs ? _sha256(key) : Uint8List.fromList(key);
    if (k.length < bs) {
      k = Uint8List.fromList([...k, ...List.filled(bs - k.length, 0)]);
    }
    final ip = Uint8List.fromList(k.map((b) => b ^ 0x36).toList());
    final op = Uint8List.fromList(k.map((b) => b ^ 0x5C).toList());
    return _sha256([...op, ..._sha256([...ip, ...data])]);
  }

  Uint8List _pbkdf2(List<int> pass, Uint8List salt, int iters) {
    var u = _hmac256(pass, [...salt, 0, 0, 0, 1]);
    final result = Uint8List.fromList(u);
    for (int i = 1; i < iters; i++) {
      u = _hmac256(pass, u);
      for (int j = 0; j < result.length; j++) result[j] ^= u[j];
    }
    return result;
  }

  Map<String, dynamic> _parseBody(Response res) {
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String && data.isNotEmpty) {
      try { return jsonDecode(data) as Map<String, dynamic>; } catch (_) {}
    }
    return {};
  }

  Future<void> _finaliseAuth({required String phone, Map? user}) async {
    await _secure.write(
      key: AppConstants.secureKeyAuthKey,
      value: jsonEncode({
        'phone': phone,
        'apiId': _apiId,
        'userId': user?['id'] ?? 0,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    try {
      await _db.upsertSession(
          phone: phone.isNotEmpty ? phone : 'qr', dcId: '2');
    } catch (_) {}
    _setState(MtprotoAuthState.authenticated);
  }

  Future<void> _clearSession() async {
    await _secure.delete(key: AppConstants.secureKeyAuthKey);
    await _secure.delete(key: AppConstants.secureKeyDcId);
    await _secure.delete(key: AppConstants.secureKeyServerSalt);
    _setState(MtprotoAuthState.initial);
  }

  Future<void> _loadCredentials() async {
    final rawId   = await _secure.read(key: AppConstants.secureKeyApiId);
    final rawHash = await _secure.read(key: AppConstants.secureKeyApiHash);
    if (rawId == null || rawId.isEmpty || rawHash == null || rawHash.isEmpty) {
      throw MtprotoException(
          'API credentials not set. Enter them on the credentials page.',
          code: 'MISSING_CREDENTIALS');
    }
    final id = int.tryParse(rawId);
    if (id == null || id == 0) throw MtprotoException('Invalid API ID: "$rawId"');
    _apiId   = id;
    _apiHash = rawHash;
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
