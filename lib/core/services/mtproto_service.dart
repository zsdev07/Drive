import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
// DC addresses
// ═══════════════════════════════════════════════════════════

const Map<int, ({String host, int port})> _kDcs = {
  1: (host: '149.154.175.53',  port: 443),
  2: (host: '149.154.167.51',  port: 443),
  3: (host: '149.154.175.100', port: 443),
  4: (host: '149.154.167.91',  port: 443),
  5: (host: '91.108.56.130',   port: 443),
};

// ═══════════════════════════════════════════════════════════
// Pure-Dart TCP transport (MTProto intermediate mode)
// ═══════════════════════════════════════════════════════════

class _Transport {
  final String host;
  final int port;
  Socket? _socket;
  final _controller = StreamController<Uint8List>.broadcast();
  StreamSubscription? _sub;

  _Transport(this.host, this.port);

  Future<void> connect() async {
    _socket = await Socket.connect(host, port,
        timeout: const Duration(seconds: 15));
    // Intermediate transport header
    _socket!.add(const [0xee, 0xee, 0xee, 0xee]);
    _sub = _socket!.listen(
      (d) => _controller.add(Uint8List.fromList(d)),
      onError: _controller.addError,
      onDone: _controller.close,
    );
  }

  void send(Uint8List payload) {
    final frame = Uint8List(4 + payload.length);
    frame.buffer.asByteData().setUint32(0, payload.length, Endian.little);
    frame.setAll(4, payload);
    _socket!.add(frame);
  }

  Future<Uint8List> recv({int timeoutSec = 30}) =>
      _controller.stream.first.timeout(
        Duration(seconds: timeoutSec),
        onTimeout: () => throw MtprotoException('Response timed out'),
      );

  Future<void> close() async {
    await _sub?.cancel();
    await _socket?.close();
  }
}

// ═══════════════════════════════════════════════════════════
// Pure-Dart crypto helpers
// ═══════════════════════════════════════════════════════════

class _C {
  static final _rng = Random.secure();
  static Uint8List rand(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  // SHA-1
  static Uint8List sha1(List<int> input) {
    var h0 = 0x67452301, h1 = 0xEFCDAB89;
    var h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
    final msg = [...input, 0x80];
    while (msg.length % 64 != 56) msg.add(0);
    final bl = input.length * 8;
    for (int i = 7; i >= 0; i--) msg.add((bl >> (i * 8)) & 0xFF);
    for (int i = 0; i < msg.length; i += 64) {
      final w = List<int>.filled(80, 0);
      for (int j = 0; j < 16; j++) {
        w[j] = (msg[i+j*4]<<24)|(msg[i+j*4+1]<<16)|(msg[i+j*4+2]<<8)|msg[i+j*4+3];
      }
      for (int j = 16; j < 80; j++) {
        final v = w[j-3]^w[j-8]^w[j-14]^w[j-16];
        w[j] = ((v<<1)|(v>>31)) & 0xFFFFFFFF;
      }
      int a=h0,b=h1,c=h2,d=h3,e=h4;
      for (int j = 0; j < 80; j++) {
        int f,k;
        if(j<20){f=(b&c)|(~b&d);k=0x5A827999;}
        else if(j<40){f=b^c^d;k=0x6ED9EBA1;}
        else if(j<60){f=(b&c)|(b&d)|(c&d);k=0x8F1BBCDC;}
        else{f=b^c^d;k=0xCA62C1D6;}
        final t=(((a<<5)|(a>>27))+f+e+k+w[j])&0xFFFFFFFF;
        e=d;d=c;c=((b<<30)|(b>>2))&0xFFFFFFFF;b=a;a=t;
      }
      h0=(h0+a)&0xFFFFFFFF;h1=(h1+b)&0xFFFFFFFF;
      h2=(h2+c)&0xFFFFFFFF;h3=(h3+d)&0xFFFFFFFF;h4=(h4+e)&0xFFFFFFFF;
    }
    final r = Uint8List(20);
    final bd = r.buffer.asByteData();
    bd.setUint32(0,h0);bd.setUint32(4,h1);bd.setUint32(8,h2);
    bd.setUint32(12,h3);bd.setUint32(16,h4);
    return r;
  }

  // SHA-256
  static Uint8List sha256(List<int> input) {
    const k=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    var h=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    final msg=[...input,0x80];
    while(msg.length%64!=56)msg.add(0);
    final bl=input.length*8;
    for(int i=7;i>=0;i--)msg.add((bl>>(i*8))&0xFF);
    for(int i=0;i<msg.length;i+=64){
      final w=List<int>.filled(64,0);
      for(int j=0;j<16;j++)w[j]=(msg[i+j*4]<<24)|(msg[i+j*4+1]<<16)|(msg[i+j*4+2]<<8)|msg[i+j*4+3];
      for(int j=16;j<64;j++){
        final s0=_r(w[j-15],7)^_r(w[j-15],18)^(w[j-15]>>3);
        final s1=_r(w[j-2],17)^_r(w[j-2],19)^(w[j-2]>>10);
        w[j]=(w[j-16]+s0+w[j-7]+s1)&0xFFFFFFFF;
      }
      var a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7];
      for(int j=0;j<64;j++){
        final s1=_r(e,6)^_r(e,11)^_r(e,25);
        final ch=(e&f)^(~e&g);
        final t1=(hh+s1+ch+k[j]+w[j])&0xFFFFFFFF;
        final s0=_r(a,2)^_r(a,13)^_r(a,22);
        final maj=(a&b)^(a&c)^(b&c);
        final t2=(s0+maj)&0xFFFFFFFF;
        hh=g;g=f;f=e;e=(d+t1)&0xFFFFFFFF;d=c;c=b;b=a;a=(t1+t2)&0xFFFFFFFF;
      }
      h[0]=(h[0]+a)&0xFFFFFFFF;h[1]=(h[1]+b)&0xFFFFFFFF;
      h[2]=(h[2]+c)&0xFFFFFFFF;h[3]=(h[3]+d)&0xFFFFFFFF;
      h[4]=(h[4]+e)&0xFFFFFFFF;h[5]=(h[5]+f)&0xFFFFFFFF;
      h[6]=(h[6]+g)&0xFFFFFFFF;h[7]=(h[7]+hh)&0xFFFFFFFF;
    }
    final r=Uint8List(32);final bd=r.buffer.asByteData();
    for(int i=0;i<8;i++)bd.setUint32(i*4,h[i]);
    return r;
  }
  static int _r(int x,int n)=>((x>>n)|(x<<(32-n)))&0xFFFFFFFF;

  // HMAC-SHA256
  static Uint8List hmac256(List<int> key, List<int> data) {
    const bs = 64;
    var k = key.length > bs ? sha256(key) : Uint8List.fromList(key);
    if (k.length < bs) k = Uint8List.fromList([...k, ...List.filled(bs-k.length, 0)]);
    final ipad = Uint8List.fromList(k.map((b) => b^0x36).toList());
    final opad = Uint8List.fromList(k.map((b) => b^0x5C).toList());
    return sha256([...opad, ...sha256([...ipad, ...data])]);
  }

  // PBKDF2-HMAC-SHA256 (used for SRP)
  static Uint8List pbkdf2(List<int> pass, List<int> salt, int iters) {
    var u = hmac256(pass, [...salt, 0,0,0,1]);
    final result = Uint8List.fromList(u);
    for (int i = 1; i < iters; i++) {
      u = hmac256(pass, u);
      for (int j = 0; j < result.length; j++) result[j] ^= u[j];
    }
    return result;
  }

  // AES-IGE (requires pointycastle — add to pubspec: pointycastle: ^3.9.1)
  // import 'package:pointycastle/export.dart';
  static Uint8List aesIge(Uint8List data, Uint8List key, Uint8List iv, bool encrypt) {
    // final cipher = IGEBlockCipher(AESEngine())
    //   ..init(encrypt, ParametersWithIV(KeyParameter(key), iv));
    // return cipher.process(data);
    //
    // Until pointycastle is added this returns data as-is so the rest compiles.
    // Add pointycastle: ^3.9.1 and uncomment the lines above.
    return data;
  }

  // BigInt ↔ bytes
  static BigInt b2i(List<int> b) {
    BigInt r = BigInt.zero;
    for (final v in b) r = (r << 8) | BigInt.from(v);
    return r;
  }
  static Uint8List i2b(BigInt v, int len) {
    final r = List<int>.filled(len, 0);
    BigInt x = v;
    for (int i = len-1; i >= 0; i--) {
      r[i] = (x & BigInt.from(0xFF)).toInt();
      x >>= 8;
    }
    return Uint8List.fromList(r);
  }

  // Pollard rho factorisation (for DH pq step)
  static (BigInt, BigInt) factorise(BigInt n) {
    if (n % BigInt.two == BigInt.zero) return (BigInt.two, n ~/ BigInt.two);
    BigInt x = BigInt.two, y = BigInt.two, c = BigInt.one, d = BigInt.one;
    while (d == BigInt.one) {
      x = (x*x+c) % n; y = (y*y+c) % n; y = (y*y+c) % n;
      d = _gcd((x-y).abs(), n);
    }
    if (d == n) {
      BigInt i = BigInt.two;
      while (i*i <= n) { if (n%i==BigInt.zero) return (i,n~/i); i+=BigInt.one; }
      return (n, BigInt.one);
    }
    final o = n ~/ d;
    return d < o ? (d, o) : (o, d);
  }
  static BigInt _gcd(BigInt a, BigInt b) { while(b!=BigInt.zero){final t=b;b=a%b;a=t;} return a; }

  static Uint8List xor(Uint8List a, Uint8List b) {
    final r = Uint8List(a.length);
    for (int i = 0; i < a.length; i++) r[i] = a[i] ^ b[i % b.length];
    return r;
  }
}

// ═══════════════════════════════════════════════════════════
// MTProto client — DH key exchange + encrypted calls
// ═══════════════════════════════════════════════════════════

class _Client {
  final int apiId;
  final String apiHash;
  int dcId;

  _Transport? _t;
  Uint8List? _authKey;
  late Uint8List _authKeyId;
  int _salt = 0;
  int _sessionId = 0;
  int _seqNo = 0;
  int _lastMsgId = 0;

  _Client({required this.apiId, required this.apiHash, this.dcId = 2});

  // ── Connect ─────────────────────────────────────────────

  Future<void> connect({int? dc}) async {
    if (dc != null) dcId = dc;
    final addr = _kDcs[dcId]!;
    _t = _Transport(addr.host, addr.port);
    await _t!.connect();
    _sessionId = _C.rand(8).buffer.asByteData().getInt64(0, Endian.little);
    await _doHandshake();
  }

  // ── DH handshake ────────────────────────────────────────

  Future<void> _doHandshake() async {
    // 1. req_pq_multi
    final nonce = _C.rand(16);
    _sendPlain(_ser(0xbe7e8ef1, nonce));
    final resPq = await _recvPlain();

    final serverNonce = resPq.sublist(20, 36);
    final pqLen = resPq[36];
    final pqBytes = resPq.sublist(37, 37 + pqLen);
    final pq = _C.b2i(pqBytes);
    final factors = _C.factorise(pq);
    final p = _C.i2b(factors.$1, 4);
    final q = _C.i2b(factors.$2, 4);

    // 2. req_DH_params
    final newNonce = _C.rand(32);
    final inner = _serPQInner(
        nonce: nonce, serverNonce: serverNonce,
        pq: pqBytes, p: p, q: q, newNonce: newNonce);
    final innerHash = _C.sha1(inner);
    final innerPadded = Uint8List.fromList([...innerHash, ...inner,
      ..._C.rand(255 - (innerHash.length + inner.length) % 255)]);

    _sendPlain(_serReqDH(
        nonce: nonce, serverNonce: serverNonce,
        p: p, q: q, encryptedData: innerPadded));
    final serverDH = await _recvPlain();

    // 3. parse server DH params and generate our DH half
    final encAnswerLen = serverDH.buffer.asByteData().getUint32(40, Endian.little);
    final encAnswer = serverDH.sublist(44, 44 + encAnswerLen);
    final tmpAesKey = Uint8List.fromList([
      ..._C.sha1([...newNonce, ...serverNonce]),
      ..._C.sha1([...serverNonce, ...newNonce]).sublist(0, 12),
    ]);
    final tmpAesIv = Uint8List.fromList([
      ..._C.sha1([...serverNonce, ...newNonce]).sublist(12),
      ..._C.sha1([...newNonce, ...newNonce]),
      ...newNonce.sublist(0, 4),
    ]);
    final answer = _C.aesIge(encAnswer, tmpAesKey, tmpAesIv, false);

    int off = 20; // skip hash
    off += 4; // constructor id (server_DH_inner_data)
    off += 16 + 16; // nonces
    final gVal = answer.buffer.asByteData().getUint32(off, Endian.little);
    off += 4;
    final dhPrimeLen = answer.buffer.asByteData().getUint32(off, Endian.little);
    off += 4;
    final dhPrime = _C.b2i(answer.sublist(off, off + dhPrimeLen));
    off += dhPrimeLen;
    final gaLen = answer.buffer.asByteData().getUint32(off, Endian.little);
    off += 4;
    final ga = _C.b2i(answer.sublist(off, off + gaLen));

    final b = _C.b2i(_C.rand(256));
    final g = BigInt.from(gVal);
    final gb = g.modPow(b, dhPrime);
    final authKeyBig = ga.modPow(b, dhPrime);
    _authKey = _C.i2b(authKeyBig, 256);
    _authKeyId = _C.sha1(_authKey!).sublist(12, 20);
    _salt = serverNonce.buffer.asByteData().getInt64(0, Endian.little) ^
        newNonce.buffer.asByteData().getInt64(0, Endian.little);

    // 4. set_client_DH_params
    final gbBytes = _C.i2b(gb, 256);
    final clientDHInner = _serClientDHInner(
        nonce: nonce, serverNonce: serverNonce, retryId: 0, gb: gbBytes);
    final ciHash = _C.sha1(clientDHInner);
    final ciPadded = Uint8List.fromList([...ciHash, ...clientDHInner,
      ..._C.rand((16 - (ciHash.length + clientDHInner.length) % 16) % 16)]);
    final encClientDH = _C.aesIge(ciPadded, tmpAesKey, tmpAesIv, true);

    _sendPlain(_serSetClientDH(
        nonce: nonce, serverNonce: serverNonce, encData: encClientDH));
    await _recvPlain(); // dh_gen_ok
  }

  // ── Serialisers for handshake messages ─────────────────

  Uint8List _ser(int id, Uint8List payload) {
    final buf = Uint8List(4 + payload.length);
    buf.buffer.asByteData().setUint32(0, id, Endian.little);
    buf.setAll(4, payload);
    return buf;
  }

  Uint8List _serPQInner({
    required Uint8List nonce, required Uint8List serverNonce,
    required Uint8List pq, required Uint8List p, required Uint8List q,
    required Uint8List newNonce,
  }) {
    final b = BytesBuilder();
    void u32le(int v) => b.add([v&0xFF,(v>>8)&0xFF,(v>>16)&0xFF,(v>>24)&0xFF]);
    void bytes(Uint8List d) {
      if (d.length<=253) { b.addByte(d.length); }
      else { b.addByte(254); b.add([d.length&0xFF,(d.length>>8)&0xFF,(d.length>>16)&0xFF]); }
      b.add(d);
      final pad=(4-(b.length%4))%4;
      if(pad>0) b.add(List.filled(pad,0));
    }
    u32le(0x83c95aec); // p_q_inner_data
    bytes(pq); bytes(p); bytes(q);
    b.add(nonce); b.add(serverNonce); b.add(newNonce);
    return b.toBytes();
  }

  Uint8List _serReqDH({
    required Uint8List nonce, required Uint8List serverNonce,
    required Uint8List p, required Uint8List q,
    required Uint8List encryptedData,
  }) {
    final b = BytesBuilder();
    void u32le(int v) => b.add([v&0xFF,(v>>8)&0xFF,(v>>16)&0xFF,(v>>24)&0xFF]);
    void u64le(int v) {
      final bd = ByteData(8); bd.setInt64(0, v, Endian.little);
      b.add(bd.buffer.asUint8List());
    }
    void bytes(Uint8List d) {
      if (d.length<=253) b.addByte(d.length);
      else { b.addByte(254); b.add([d.length&0xFF,(d.length>>8)&0xFF,(d.length>>16)&0xFF]); }
      b.add(d);
      final pad=(4-(b.length%4))%4;
      if(pad>0) b.add(List.filled(pad,0));
    }
    u32le(0xd712e4be); // req_DH_params
    b.add(nonce); b.add(serverNonce);
    bytes(p); bytes(q);
    u64le(0); // public key fingerprint placeholder
    bytes(encryptedData);
    return b.toBytes();
  }

  Uint8List _serClientDHInner({
    required Uint8List nonce, required Uint8List serverNonce,
    required int retryId, required Uint8List gb,
  }) {
    final b = BytesBuilder();
    void u32le(int v) => b.add([v&0xFF,(v>>8)&0xFF,(v>>16)&0xFF,(v>>24)&0xFF]);
    void u64le(int v) {
      final bd = ByteData(8); bd.setInt64(0, v, Endian.little);
      b.add(bd.buffer.asUint8List());
    }
    void bytes(Uint8List d) {
      if (d.length<=253) b.addByte(d.length);
      else { b.addByte(254); b.add([d.length&0xFF,(d.length>>8)&0xFF,(d.length>>16)&0xFF]); }
      b.add(d);
      final pad=(4-(b.length%4))%4;
      if(pad>0) b.add(List.filled(pad,0));
    }
    u32le(0x6643b654); // client_DH_inner_data
    b.add(nonce); b.add(serverNonce);
    u64le(retryId);
    bytes(gb);
    return b.toBytes();
  }

  Uint8List _serSetClientDH({
    required Uint8List nonce, required Uint8List serverNonce,
    required Uint8List encData,
  }) {
    final b = BytesBuilder();
    void u32le(int v) => b.add([v&0xFF,(v>>8)&0xFF,(v>>16)&0xFF,(v>>24)&0xFF]);
    void bytes(Uint8List d) {
      if (d.length<=253) b.addByte(d.length);
      else { b.addByte(254); b.add([d.length&0xFF,(d.length>>8)&0xFF,(d.length>>16)&0xFF]); }
      b.add(d);
      final pad=(4-(b.length%4))%4;
      if(pad>0) b.add(List.filled(pad,0));
    }
    u32le(0xf5045f1f); // set_client_DH_params
    b.add(nonce); b.add(serverNonce);
    bytes(encData);
    return b.toBytes();
  }

  // ── Encrypted message send/recv ─────────────────────────

  int _nextMsgId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    var id = (ms ~/ 1000) << 32 | ((ms % 1000) * 4294967) & 0xFFFFFFFF;
    if (id <= _lastMsgId) id = _lastMsgId + 4;
    _lastMsgId = id;
    return id;
  }

  Uint8List _buildMsg(Uint8List body) {
    final msgId = _nextMsgId();
    final seqNo = (_seqNo++ * 2 + 1); // content-related

    final b = BytesBuilder();
    final salt = ByteData(8)..setInt64(0, _salt, Endian.little);
    b.add(salt.buffer.asUint8List());
    final sess = ByteData(8)..setInt64(0, _sessionId, Endian.little);
    b.add(sess.buffer.asUint8List());
    final mid = ByteData(8)..setInt64(0, msgId, Endian.little);
    b.add(mid.buffer.asUint8List());
    final seq = ByteData(4)..setUint32(0, seqNo, Endian.little);
    b.add(seq.buffer.asUint8List());
    final blen = ByteData(4)..setUint32(0, body.length, Endian.little);
    b.add(blen.buffer.asUint8List());
    b.add(body);
    // padding
    final pad = (16 - (b.length % 16)) % 16;
    b.add(_C.rand(pad + 12));
    return b.toBytes();
  }

  Uint8List _encrypt(Uint8List plaintext) {
    final msgKey = _C.sha256([..._authKey!.sublist(88, 120), ...plaintext]).sublist(8, 24);
    final k = _deriveKeys(msgKey, true);
    final enc = _C.aesIge(plaintext, k.$1, k.$2, true);
    final out = Uint8List(8 + 16 + enc.length);
    out.setAll(0, _authKeyId);
    out.setAll(8, msgKey);
    out.setAll(24, enc);
    return out;
  }

  Uint8List _decrypt(Uint8List data) {
    final msgKey = data.sublist(8, 24);
    final k = _deriveKeys(msgKey, false);
    return _C.aesIge(data.sublist(24), k.$1, k.$2, false);
  }

  (Uint8List, Uint8List) _deriveKeys(Uint8List msgKey, bool fromClient) {
    final x = fromClient ? 0 : 8;
    final ak = _authKey!;
    final a = _C.sha256([...msgKey, ...ak.sublist(x, x+36)]);
    final b2 = _C.sha256([...ak.sublist(x+40, x+76), ...msgKey, ...ak.sublist(x+76, x+108)]);
    final key = Uint8List.fromList([...a.sublist(0,8), ...b2.sublist(8,24), ...a.sublist(24,32)]);
    final iv  = Uint8List.fromList([...b2.sublist(0,8), ...a.sublist(8,24), ...b2.sublist(24,32)]);
    return (key, iv);
  }

  void _sendPlain(Uint8List payload) {
    final msgId = _nextMsgId();
    final header = ByteData(20);
    header.setInt64(0, 0);       // auth_key_id = 0 (unencrypted)
    header.setInt64(8, msgId);
    header.setUint32(16, payload.length, Endian.little);
    final out = Uint8List(20 + payload.length);
    out.setAll(0, header.buffer.asUint8List());
    out.setAll(20, payload);
    _t!.send(out);
  }

  Future<Uint8List> _recvPlain() async {
    final raw = await _t!.recv(timeoutSec: 15);
    return raw.sublist(20); // skip header
  }

  // ── RPC call ─────────────────────────────────────────────

  Future<_TLObject> call(Uint8List body) async {
    if (_authKey == null) throw MtprotoException('Not connected');
    final plain = _buildMsg(body);
    _t!.send(_encrypt(plain));
    final raw = await _t!.recv();
    final dec = _decrypt(raw);
    // The actual message content starts at offset 32 (skip salt+session+msgid+seqno+len)
    final inner = dec.sublist(32);
    return _TLObject.parse(inner);
  }

  // ── Public auth methods ─────────────────────────────────

  Future<({Uint8List token, DateTime expires})> exportLoginToken() async {
    // auth.exportLoginToken#b7d0f392 flags:# api_id:int api_hash:string except_ids:Vector<long>
    final body = _TLWriter()
      ..u32(0xb7d0f392)
      ..u32(0) // flags
      ..u32(apiId)
      ..str(apiHash)
      ..vectorLong([]) // except_ids
      ..build();
    final res = await call(body.build());

    // loginToken#629f1980 expires:int token:bytes
    final token = res.bytes('token');
    final exp = res.int32('expires');
    return (
      token: token,
      expires: DateTime.fromMillisecondsSinceEpoch(exp * 1000),
    );
  }

  Future<Map<String, dynamic>?> importLoginToken(Uint8List token) async {
    // auth.importLoginToken#95ac5ce4 token:bytes
    final body = _TLWriter()
      ..u32(0x95ac5ce4)
      ..bytes(token)
      ..build();
    try {
      final res = await call(body.build());
      if (res.constructorId == 0x390d5c5e) {
        // loginToken.success#390d5c5e
        return {'id': res.int32('user.id'), 'first_name': res.str('user.first_name')};
      }
      return null; // still waiting
    } on MtprotoAuthException catch (e) {
      if (e.code == 'AUTH_TOKEN_EXPIRED' || e.code == 'AUTH_TOKEN_INVALID') rethrow;
      return null;
    }
  }

  Future<String> sendCode(String phone) async {
    // auth.sendCode#a677244f phone_number:string api_id:int api_hash:string settings:CodeSettings
    final body = _TLWriter()
      ..u32(0xa677244f)
      ..str(phone)
      ..u32(apiId)
      ..str(apiHash)
      ..u32(0x8faee98e) // codeSettings constructor
      ..u32(0)          // flags
      ..build();
    final res = await call(body.build());
    return res.str('phone_code_hash');
  }

  Future<Map<String, dynamic>> signIn({
    required String phone,
    required String phoneCodeHash,
    required String code,
  }) async {
    // auth.signIn#8d52a951
    final body = _TLWriter()
      ..u32(0x8d52a951)
      ..str(phone)
      ..str(phoneCodeHash)
      ..str(code)
      ..build();
    try {
      final res = await call(body.build());
      return {'id': res.int32('user.id'), 'first_name': res.str('user.first_name')};
    } on MtprotoAuthException catch (e) {
      if (e.code == 'SESSION_PASSWORD_NEEDED') throw MtprotoTwoFactorRequired(hint: '');
      if (e.message.startsWith('FLOOD_WAIT_')) {
        throw MtprotoFloodWaitException(int.tryParse(e.message.split('_').last) ?? 60);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> checkPassword(String password) async {
    // account.getPassword#548a30f5
    final pwdRes = await call((_TLWriter()..u32(0x548a30f5)..build()).build());

    final salt1 = pwdRes.bytes('current_algo.salt1');
    final salt2 = pwdRes.bytes('current_algo.salt2');
    final srpB  = pwdRes.bytes('srp_B');
    final srpId = pwdRes.int64('srp_id');

    final srpAnswer = _srpAnswer(
        password: password, salt1: salt1, salt2: salt2, srpB: srpB, srpId: srpId);

    // auth.checkPassword#d18b4d16
    final body = _TLWriter()
      ..u32(0xd18b4d16)
      ..rawMap(srpAnswer)
      ..build();
    final res = await call(body.build());
    return {'id': res.int32('user.id'), 'first_name': res.str('user.first_name')};
  }

  Future<void> logOut() async {
    await call((_TLWriter()..u32(0x5717da40)..build()).build());
  }

  Future<void> close() async => _t?.close();

  // ── SRP-2048 ─────────────────────────────────────────────

  static final BigInt _P = BigInt.parse(
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

  Map<String, dynamic> _srpAnswer({
    required String password,
    required Uint8List salt1,
    required Uint8List salt2,
    required Uint8List srpB,
    required int srpId,
  }) {
    final pwd = utf8.encode(password);

    Uint8List sh(List<int> data, Uint8List salt) =>
        _C.sha256([...salt, ...data, ...salt]);

    final ph1 = sh(Uint8List.fromList(pwd), salt1);
    final ph2 = sh(_C.pbkdf2(ph1, salt2, 100000), salt1);
    final x   = _C.b2i(_C.sha256([...salt1, ...ph2, ...salt1]));
    final g   = BigInt.two;
    final p   = _P;
    final k   = _C.b2i(_C.sha256([..._C.i2b(p, 256), ..._C.i2b(g, 256)]));
    final v   = g.modPow(x, p);
    final a   = _C.b2i(_C.rand(256));
    final ga  = g.modPow(a, p);
    final gb  = _C.b2i(srpB);
    final u   = _C.b2i(_C.sha256([..._C.i2b(ga, 256), ..._C.i2b(gb, 256)]));
    final kv  = (k * v) % p;
    final t   = (gb - kv) % p;
    final sa  = (a + u * x) % (p - BigInt.one);
    final s   = t.modPow(sa, p);

    final m1 = _C.sha256([
      ..._C.xor(_C.sha256(_C.i2b(p, 256)), _C.sha256(_C.i2b(g, 256))),
      ..._C.sha256(salt1), ..._C.sha256(salt2),
      ..._C.i2b(ga, 256), ..._C.i2b(gb, 256), ..._C.i2b(s, 256),
    ]);

    return {
      '_': 'inputCheckPasswordSRP',
      'srp_id': srpId,
      'A': _C.i2b(ga, 256),
      'M1': m1,
    };
  }
}

// ═══════════════════════════════════════════════════════════
// Minimal TL writer / reader
// ═══════════════════════════════════════════════════════════

class _TLWriter {
  final _b = BytesBuilder();

  _TLWriter u32(int v) {
    _b.add([v&0xFF,(v>>8)&0xFF,(v>>16)&0xFF,(v>>24)&0xFF]);
    return this;
  }

  _TLWriter u64(int v) {
    final bd = ByteData(8)..setInt64(0, v, Endian.little);
    _b.add(bd.buffer.asUint8List());
    return this;
  }

  _TLWriter str(String s) => bytes(Uint8List.fromList(utf8.encode(s)));

  _TLWriter bytes(Uint8List d) {
    if (d.length <= 253) {
      _b.addByte(d.length);
    } else {
      _b.addByte(254);
      _b.add([d.length&0xFF,(d.length>>8)&0xFF,(d.length>>16)&0xFF]);
    }
    _b.add(d);
    final pad = (4 - (_b.length % 4)) % 4;
    if (pad > 0) _b.add(List.filled(pad, 0));
    return this;
  }

  _TLWriter vectorLong(List<int> v) {
    u32(0x1cb5c415); // vector id
    u32(v.length);
    for (final x in v) u64(x);
    return this;
  }

  _TLWriter rawMap(Map<String, dynamic> m) {
    // Serialise inputCheckPasswordSRP
    u32(0xd27ff082); // inputCheckPasswordSRP#d27ff082
    final bd = ByteData(8)..setInt64(0, m['srp_id'] as int, Endian.little);
    _b.add(bd.buffer.asUint8List());
    bytes(m['A'] as Uint8List);
    bytes(m['M1'] as Uint8List);
    return this;
  }

  Uint8List build() => _b.toBytes();

  // Alias so the fluent chain works
  _TLWriter get _self => this;
}

// A very thin TL response wrapper — enough to extract the fields used above.
class _TLObject {
  final int constructorId;
  final Uint8List _raw;

  _TLObject(this.constructorId, this._raw);

  factory _TLObject.parse(Uint8List data) {
    if (data.length < 4) return _TLObject(0, data);
    final id = data.buffer.asByteData().getUint32(0, Endian.little);
    if (id == 0x2144ca19) {
      // rpc_error
      final code = data.buffer.asByteData().getInt32(4, Endian.little);
      final mlen = data.buffer.asByteData().getUint32(8, Endian.little);
      final msg = utf8.decode(data.sublist(12, 12 + mlen));
      throw MtprotoAuthException(msg, code: code.toString());
    }
    return _TLObject(id, data);
  }

  // These helpers do a simple sequential parse; for production use a full TL parser.
  int int32(String _) {
    if (_raw.length < 8) return 0;
    return _raw.buffer.asByteData().getInt32(4, Endian.little);
  }

  int int64(String _) {
    if (_raw.length < 12) return 0;
    return _raw.buffer.asByteData().getInt64(4, Endian.little);
  }

  Uint8List bytes(String _) {
    if (_raw.length < 6) return Uint8List(0);
    final len = _raw[4];
    if (_raw.length < 5 + len) return Uint8List(0);
    return _raw.sublist(5, 5 + len);
  }

  String str(String key) => utf8.decode(bytes(key));
}

// ═══════════════════════════════════════════════════════════
// MtprotoService  (public API used by Riverpod + UI)
// ═══════════════════════════════════════════════════════════

class MtprotoService {
  final AppDatabase _db;
  final FlutterSecureStorage _secure;

  MtprotoAuthState _authState = MtprotoAuthState.initial;
  _Client? _client;

  MtprotoQrToken? _currentQrToken;
  Uint8List? _currentQrTokenBytes;
  Timer? _qrTimer;

  String? _pendingPhone;
  String? _pendingPhoneCodeHash;

  final StreamController<MtprotoAuthState> _stateCtrl =
      StreamController.broadcast();

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

  MtprotoAuthState get authState => _authState;
  Stream<MtprotoAuthState> get authStateStream => _stateCtrl.stream;
  bool get isAuthenticated => _authState == MtprotoAuthState.authenticated;
  MtprotoQrToken? get currentQrToken => _currentQrToken;

  // ── Init ────────────────────────────────────────────────

  Future<void> init() async {
    final raw = await _secure.read(key: AppConstants.secureKeyAuthKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final dcId = int.tryParse(j['dcId'].toString()) ?? 2;
      final creds = await _loadCredentials();
      _client = _Client(apiId: creds.$1, apiHash: creds.$2, dcId: dcId);
      await _client!.connect();
      _setState(MtprotoAuthState.authenticated);
    } catch (_) {
      await _clearSession();
    }
  }

  // ── Credentials ─────────────────────────────────────────

  Future<bool> hasCredentials() async {
    final id   = await _secure.read(key: AppConstants.secureKeyApiId);
    final hash = await _secure.read(key: AppConstants.secureKeyApiHash);
    return (id?.isNotEmpty ?? false) && (hash?.isNotEmpty ?? false);
  }

  Future<void> saveCredentials({required String apiId, required String apiHash}) async {
    await _secure.write(key: AppConstants.secureKeyApiId,   value: apiId.trim());
    await _secure.write(key: AppConstants.secureKeyApiHash, value: apiHash.trim());
  }

  Future<void> clearCredentials() async {
    await _secure.delete(key: AppConstants.secureKeyApiId);
    await _secure.delete(key: AppConstants.secureKeyApiHash);
  }

  // ── QR login ─────────────────────────────────────────────

  Future<MtprotoQrToken> startQrLogin() async {
    final creds = await _loadCredentials();
    _client ??= _Client(apiId: creds.$1, apiHash: creds.$2);
    await _client!.connect();
    final token = await _refreshQrToken();
    _startQrPolling();
    return token;
  }

  Future<MtprotoQrToken> _refreshQrToken() async {
    final r = await _client!.exportLoginToken();
    final uri = 'tg://login?token=${base64Url.encode(r.token).replaceAll('=', '')}';
    _currentQrToken = MtprotoQrToken(uri: uri, expiresAt: r.expires);
    _currentQrTokenBytes = r.token;
    _setState(MtprotoAuthState.waitingQrScan);
    return _currentQrToken!;
  }

  void _startQrPolling() {
    _qrTimer?.cancel();
    _qrTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_authState != MtprotoAuthState.waitingQrScan) { _qrTimer?.cancel(); return; }
      if (_currentQrToken?.isExpired ?? true) {
        try { await _refreshQrToken(); } catch (_) {}
        return;
      }
      try {
        final user = await _client!.importLoginToken(_currentQrTokenBytes!);
        if (user != null) {
          _qrTimer?.cancel();
          await _finaliseAuth(user, phone: user['phone']?.toString() ?? '');
        }
      } catch (_) {}
    });
  }

  // ── Phone login ──────────────────────────────────────────

  Future<void> sendCode(String phone) async {
    final creds = await _loadCredentials();
    _client ??= _Client(apiId: creds.$1, apiHash: creds.$2);
    await _client!.connect();
    _pendingPhone = phone;
    _pendingPhoneCodeHash = await _client!.sendCode(phone);
    _setState(MtprotoAuthState.waitingCode);
  }

  Future<void> signIn(String phone, String code) async {
    if (_client == null || _pendingPhoneCodeHash == null) {
      throw MtprotoAuthException('Call sendCode() first.', code: 'NOT_READY');
    }
    final user = await _client!.signIn(
      phone: phone, phoneCodeHash: _pendingPhoneCodeHash!, code: code);
    await _finaliseAuth(user, phone: phone);
  }

  Future<void> signInWithPassword(String password) async {
    if (_client == null) throw MtprotoAuthException('Not connected.', code: 'NOT_READY');
    final user = await _client!.checkPassword(password);
    await _finaliseAuth(user, phone: _pendingPhone ?? '');
  }

  // ── Sign out ─────────────────────────────────────────────

  Future<void> signOut() async {
    _qrTimer?.cancel();
    try { await _client?.logOut(); } catch (_) {}
    await _client?.close();
    _client = null;
    _currentQrToken = null;
    _currentQrTokenBytes = null;
    _pendingPhoneCodeHash = null;
    await _clearSession();
    await _db.clearAllSessions();
    _setState(MtprotoAuthState.closed);
  }

  // ── File operations ──────────────────────────────────────

  Future<TelegramUploadResult> uploadFile({
    required File file,
    required String mimeType,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    _requireAuth();
    final fileSize = await file.length();
    final isBig = fileSize > 10 * 1024 * 1024;
    final fileId = DateTime.now().millisecondsSinceEpoch;
    const chunkSize = 512 * 1024;
    int part = 0, sent = 0;

    final raf = await file.open();
    try {
      while (sent < fileSize) {
        final end = (sent + chunkSize).clamp(0, fileSize);
        await raf.setPosition(sent);
        final chunk = Uint8List.fromList(await raf.read(end - sent));

        // upload.saveBigFilePart for >10 MB, saveFilePart for smaller
        await _client!.call(
          (_TLWriter()
            ..u32(isBig ? 0xde7b673d : 0xb304a621)
            ..u64(fileId)
            ..u32(part)
            ..u32((fileSize / chunkSize).ceil())
            ..bytes(chunk))
            .build(),
        );

        sent = end;
        part++;
        onProgress?.call(sent, fileSize);
      }
    } finally {
      await raf.close();
    }

    return TelegramUploadResult(
      fileId: fileId.toString(),
      messageId: '0',
      fileSize: fileSize,
    );
  }

  Future<String> downloadFile({
    required String fileId,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    _requireAuth();
    const chunkSize = 1024 * 1024;
    int offset = 0;
    final sink = File(savePath).openWrite();
    try {
      while (true) {
        final res = await _client!.call(
          (_TLWriter()
            ..u32(0xbe5335be) // upload.getFile
            ..u32(0) // flags
            ..u32(0xcbc7ee28) // inputFileLocation placeholder
            ..u32(int.tryParse(fileId) ?? 0)
            ..u32(offset)
            ..u32(chunkSize))
            .build(),
        );
        final chunk = res.bytes('bytes');
        if (chunk.isEmpty) break;
        sink.add(chunk);
        offset += chunk.length;
        onProgress?.call(offset, offset);
        if (chunk.length < chunkSize) break;
      }
    } finally {
      await sink.close();
    }
    return savePath;
  }

  // ── Dispose ──────────────────────────────────────────────

  Future<void> dispose() async {
    _qrTimer?.cancel();
    await _client?.close();
    await _stateCtrl.close();
  }

  // ── Private ──────────────────────────────────────────────

  Future<(int, String)> _loadCredentials() async {
    final rawId   = await _secure.read(key: AppConstants.secureKeyApiId);
    final rawHash = await _secure.read(key: AppConstants.secureKeyApiHash);
    if (rawId == null || rawId.isEmpty || rawHash == null || rawHash.isEmpty) {
      throw MtprotoException('API credentials not set.', code: 'MISSING_CREDENTIALS');
    }
    final apiId = int.tryParse(rawId);
    if (apiId == null || apiId == 0) throw MtprotoException('Invalid API ID: "$rawId"');
    return (apiId, rawHash);
  }

  Future<void> _finaliseAuth(Map<String, dynamic> user, {required String phone}) async {
    await _secure.write(
      key: AppConstants.secureKeyAuthKey,
      value: jsonEncode({'dcId': _client?.dcId ?? 2, 'userId': user['id'] ?? 0, 'phone': phone}),
    );
    await _db.upsertSession(phone: phone, dcId: '${_client?.dcId ?? 2}');
    _setState(MtprotoAuthState.authenticated);
  }

  Future<void> _clearSession() async {
    await _secure.delete(key: AppConstants.secureKeyAuthKey);
    await _secure.delete(key: AppConstants.secureKeyDcId);
    await _secure.delete(key: AppConstants.secureKeyServerSalt);
  }

  void _setState(MtprotoAuthState s) {
    _authState = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  void _requireAuth() {
    if (!isAuthenticated) throw MtprotoException('Not authenticated.', code: 'NOT_AUTHENTICATED');
  }
}
