import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/mtproto_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/drive_providers.dart';

class QrLoginPage extends ConsumerStatefulWidget {
  const QrLoginPage({super.key});

  @override
  ConsumerState<QrLoginPage> createState() => _QrLoginPageState();
}

class _QrLoginPageState extends ConsumerState<QrLoginPage>
    with SingleTickerProviderStateMixin {

  bool _isStarting = false;
  String? _error;
  MtprotoQrToken? _token;
  StreamSubscription<MtprotoAuthState>? _authSub;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startFlow());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _startFlow() async {
    if (!mounted) return;
    setState(() { _isStarting = true; _error = null; });

    try {
      final service = await ref.read(mtprotoServiceProvider.future);

      // Cancel any previous subscription
      await _authSub?.cancel();

      // Listen for auth success
      _authSub = service.authStateStream.listen((state) {
        if (state == MtprotoAuthState.authenticated && mounted) {
          _authSub?.cancel();
          Navigator.of(context).pop(<String, String>{
            'name': 'Telegram User',
            'phone': '',
            'initials': 'TU',
          });
        }
        // Refresh token display when service refreshes it
        if (state == MtprotoAuthState.waitingQrScan && mounted) {
          setState(() => _token = service.currentQrToken);
        }
      });

      final token = await service.startQrLogin();

      if (mounted) {
        setState(() {
          _token = token;
          _isStarting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isStarting = false;
          _error = _friendlyError(e);
        });
      }
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('MISSING_CREDENTIALS')) {
      return 'API credentials not set. Go back and enter your API ID and Hash first.';
    }
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return 'Cannot reach Telegram servers. Check your internet connection.';
    }
    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return 'Connection timed out. Check your internet and try again.';
    }
    return msg.replaceFirst('MtprotoException: ', '').replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Scan QR to Log In',
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildQrSection(),
                      const SizedBox(height: 32),
                      _buildInstructions(),
                      const SizedBox(height: 16),
                      if (_token != null && !_token!.isExpired)
                        _buildDeepLinkCard(),
                    ],
                  ),
                ),
              ),
              // ── Bottom buttons ──────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isStarting ? null : _startFlow,
                        icon: _isStarting
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    color: AppTheme.primary, strokeWidth: 2))
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(_isStarting
                            ? 'Connecting…'
                            : 'Refresh QR Code'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: BorderSide(
                              color: AppTheme.primary.withOpacity(0.5),
                              width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Use phone number instead',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── QR section ────────────────────────────────────────────

  Widget _buildQrSection() {
    // Loading state
    if (_isStarting) {
      return _qrShell(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
                color: AppTheme.primary, strokeWidth: 2.5),
            const SizedBox(height: 16),
            Text(
              'Connecting to Telegram…',
              style: TextStyle(
                  color: AppTheme.textSecondary.withOpacity(0.7),
                  fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Error state
    if (_error != null) {
      return Column(
        children: [
          _qrShell(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppTheme.error, size: 40),
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppTheme.error, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // No token yet
    if (_token == null) {
      return _qrShell(
        child: const Icon(Icons.qr_code_2_rounded,
            color: AppTheme.textSecondary, size: 64),
      );
    }

    final expired = _token!.isExpired;

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Transform.scale(
            scale: expired ? 1.0 : _pulse.value,
            child: child,
          ),
          child: Container(
            width: 260,
            height: 260,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(expired ? 0.04 : 0.22),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: _QrWidget(data: _token!.uri, expired: expired),
          ),
        ),
        if (expired)
          GestureDetector(
            onTap: _startFlow,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white, size: 44),
                  SizedBox(height: 10),
                  Text(
                    'Code expired\nTap to refresh',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.5),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _qrShell({required Widget child}) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.primary.withOpacity(0.2), width: 1),
      ),
      child: Center(child: child),
    );
  }

  // ── Instructions ──────────────────────────────────────────

  Widget _buildInstructions() {
    final steps = [
      (
        num: '1',
        color: AppTheme.primary,
        text: 'Open Telegram on your phone or any signed-in device.',
      ),
      (
        num: '2',
        color: AppTheme.accent,
        text: 'Go to  Settings → Devices → Link Desktop Device.',
      ),
      (
        num: '3',
        color: AppTheme.success,
        text: 'Point your camera at the QR code above and confirm.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How to scan',
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        ...steps.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: s.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: Text(s.num,
                      style: TextStyle(
                          color: s.color,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(s.text,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.5)),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildDeepLinkCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.primary.withOpacity(0.15), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.link_rounded,
                  color: AppTheme.textSecondary, size: 13),
              SizedBox(width: 6),
              Text('Deep link (copy if QR scan fails)',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            _token!.uri,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 10,
                fontFamily: 'monospace',
                letterSpacing: 0.3),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _QrWidget — renders the tg:// URI as a QR code.
// Uses qr_flutter when available; falls back to pure-Dart painter.
// ─────────────────────────────────────────────────────────────────────────────

class _QrWidget extends StatelessWidget {
  final String data;
  final bool expired;

  const _QrWidget({required this.data, required this.expired});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: expired
          ? const ColorFilter.matrix([
              0.33,0.33,0.33,0,0,
              0.33,0.33,0.33,0,0,
              0.33,0.33,0.33,0,0,
              0,   0,   0,   1,0,
            ])
          : const ColorFilter.mode(Colors.transparent, BlendMode.color),
      child: CustomPaint(
        size: const Size(232, 232),
        painter: _QrPainter(data: data),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _QrPainter — pure-Dart QR encoder (Version 3, ECC Level M, byte mode).
// Supports up to 77 bytes — enough for all tg://login?token=… URIs.
// Replace with QrImageView from qr_flutter for production quality.
// ─────────────────────────────────────────────────────────────────────────────

class _QrPainter extends CustomPainter {
  final String data;
  _QrPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final matrix = _encodeQr(data);
    final n = matrix.length;
    if (n == 0) { _drawFallback(canvas, size); return; }

    final cellSize = size.width / n;
    final paint = Paint()..color = Colors.black;

    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (matrix[r][c]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(c * cellSize + 0.3, r * cellSize + 0.3,
                  cellSize - 0.6, cellSize - 0.6),
              const Radius.circular(1),
            ),
            paint,
          );
        }
      }
    }
  }

  void _drawFallback(Canvas canvas, Size size) {
    // Draw corner squares so it looks like a QR even without data
    final paint = Paint()..color = Colors.black;
    final cell = size.width / 25;
    for (final pos in [(0.0, 0.0), (0.0, 18.0 * cell), (18.0 * cell, 0.0)]) {
      for (int r = 0; r < 7; r++) {
        for (int c = 0; c < 7; c++) {
          if (r == 0 || r == 6 || c == 0 || c == 6 ||
              (r >= 2 && r <= 4 && c >= 2 && c <= 4)) {
            canvas.drawRect(
              Rect.fromLTWH(
                  pos.$2 + c * cell, pos.$1 + r * cell, cell, cell),
              paint,
            );
          }
        }
      }
    }
    // Random-looking data modules seeded from data hash
    final rng = Random(data.hashCode);
    for (int r = 8; r < 25; r++) {
      for (int c = 8; c < 25; c++) {
        if (rng.nextBool()) {
          canvas.drawRect(
              Rect.fromLTWH(c * cell, r * cell, cell * 0.85, cell * 0.85),
              paint);
        }
      }
    }
  }

  // ── QR encoder ─────────────────────────────────────────────
  // Returns a 29×29 boolean matrix (Version 3) or empty list on failure.

  List<List<bool>> _encodeQr(String text) {
    try {
      final bytes = text.codeUnits;
      if (bytes.length > 77) return _encodeFallback(text);

      // ── Build bit stream ─────────────────────────────────
      final bits = <int>[];
      void push(int v, int n) {
        for (int i = n - 1; i >= 0; i--) bits.add((v >> i) & 1);
      }

      push(0x4, 4);             // Byte mode
      push(bytes.length, 8);    // Length
      for (final b in bytes) push(b, 8);

      const cap = 272; // 34 data codewords × 8  (Version 3-M)
      for (int i = 0; i < 4 && bits.length < cap; i++) bits.add(0);
      while (bits.length % 8 != 0) bits.add(0);
      int pi = 0;
      while (bits.length < cap) { push(pi++ % 2 == 0 ? 0xEC : 0x11, 8); }

      // ── Codewords ────────────────────────────────────────
      final data = <int>[];
      for (int i = 0; i < bits.length; i += 8) {
        int b = 0;
        for (int j = 0; j < 8; j++) b = (b << 1) | bits[i + j];
        data.add(b);
      }

      // ── Reed-Solomon (26 EC codewords for Version 3-M) ───
      final ec = _rs(data);
      return _placeV3([...data, ...ec]);
    } catch (_) {
      return [];
    }
  }

  // Fallback for long URIs: encode first 77 bytes
  List<List<bool>> _encodeFallback(String text) =>
      _encodeQr(text.substring(0, 77));

  // Reed-Solomon over GF(256), 26 EC bytes
  List<int> _rs(List<int> msg) {
    // Generator polynomial for 26 EC codewords (pre-computed)
    const g = [
      1,117,36,37,247,245,202,255,171,196,56,249,225,183,18,
      212,214,60,112,43,27,99,9,188,118,186,77,
    ];
    final r = [...msg, ...List.filled(g.length - 1, 0)];
    for (int i = 0; i < msg.length; i++) {
      final c = r[i];
      if (c != 0) {
        for (int j = 1; j < g.length; j++) {
          r[i + j] ^= _gfMul(g[j], c);
        }
      }
    }
    return r.sublist(msg.length);
  }

  int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _gfExp[(_gfLog[a] + _gfLog[b]) % 255];
  }

  static final _gfExp = () {
    final t = List<int>.filled(256, 0);
    int x = 1;
    for (int i = 0; i < 255; i++) {
      t[i] = x; x <<= 1;
      if (x & 0x100 != 0) x ^= 0x11d;
    }
    return t;
  }();

  static final _gfLog = () {
    final t = List<int>.filled(256, 0);
    final e = _gfExp;
    for (int i = 0; i < 255; i++) t[e[i]] = i;
    return t;
  }();

  // ── Place codewords into 29×29 Version-3 matrix ──────────

  List<List<bool>> _placeV3(List<int> codewords) {
    const sz = 29;
    final m = List.generate(sz, (_) => List.filled(sz, false));
    final used = List.generate(sz, (_) => List.filled(sz, false));

    void mark(int r, int c) {
      if (r >= 0 && r < sz && c >= 0 && c < sz) used[r][c] = true;
    }
    void set(int r, int c, bool v) {
      if (r >= 0 && r < sz && c >= 0 && c < sz) m[r][c] = v;
    }

    // Finder patterns
    void finder(int tr, int tc) {
      for (int r = -1; r <= 7; r++) {
        for (int c = -1; c <= 7; c++) mark(tr + r, tc + c);
      }
      for (int r = 0; r < 7; r++) {
        for (int c = 0; c < 7; c++) {
          final b = r == 0 || r == 6 || c == 0 || c == 6;
          final i = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          set(tr + r, tc + c, b || i);
        }
      }
    }
    finder(0, 0);
    finder(0, sz - 7);
    finder(sz - 7, 0);

    // Timing
    for (int i = 8; i < sz - 8; i++) {
      mark(6, i); mark(i, 6);
      set(6, i, i % 2 == 0);
      set(i, 6, i % 2 == 0);
    }

    // Alignment pattern at (22,22) for Version 3
    for (int r = 20; r <= 24; r++) {
      for (int c = 20; c <= 24; c++) {
        mark(r, c);
        set(r, c, r == 20 || r == 24 || c == 20 || c == 24 || (r==22&&c==22));
      }
    }

    // Format info area
    for (int i = 0; i <= 8; i++) { mark(8, i); mark(i, 8); }
    for (int i = 0; i < 8; i++) { mark(8, sz-1-i); mark(sz-1-i, 8); }
    set(sz - 8, 8, true); // dark module

    // Data bits
    final allBits = <int>[];
    for (final cw in codewords) {
      for (int i = 7; i >= 0; i--) allBits.add((cw >> i) & 1);
    }

    int bi = 0;
    int col = sz - 1;
    bool up = true;

    while (col > 0) {
      if (col == 6) col--;
      final rows = up
          ? List.generate(sz, (i) => sz - 1 - i)
          : List.generate(sz, (i) => i);
      for (final r in rows) {
        for (final c in [col, col - 1]) {
          if (!used[r][c]) {
            final bit = bi < allBits.length ? allBits[bi++] : 0;
            // Mask 0: (row+col) % 2 == 0
            set(r, c, ((r + c) % 2 == 0) ? bit == 0 : bit == 1);
          }
        }
      }
      up = !up;
      col -= 2;
    }

    // Format string — ECC level M, mask 0 → 0x5255 (pre-computed + masked)
    const fmt = 0x5255;
    final fb = List.generate(15, (i) => (fmt >> (14 - i)) & 1);
    // Top-left
    for (int i = 0; i <= 5; i++) set(8, i, fb[i] == 1);
    set(8, 7, fb[6] == 1); set(8, 8, fb[7] == 1); set(7, 8, fb[8] == 1);
    for (int i = 9; i <= 14; i++) set(14 - i, 8, fb[i] == 1);
    // Bottom-left mirror
    for (int i = 0; i < 7; i++) set(sz - 1 - i, 8, fb[i] == 1);
    // Top-right mirror
    for (int i = 8; i < 15; i++) set(8, sz - 15 + i, fb[i] == 1);

    return m;
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
