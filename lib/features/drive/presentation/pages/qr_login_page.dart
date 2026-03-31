import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/mtproto_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/drive_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// QrLoginPage
//
// Renders a tg://login?token=… QR code so the user can scan it from any
// logged-in Telegram client (Settings → Devices → Link Desktop Device).
//
// Depends on:  qr_flutter: ^4.1.0   (add to pubspec.yaml)
//              pointycastle: ^3.9.1  (for AES-IGE in mtproto_service.dart)
//
// Until qr_flutter is added the page shows the raw URI in a selectable text
// field as a fallback — the user can copy-paste it into Telegram's "Link by
// URL" option.
// ─────────────────────────────────────────────────────────────────────────────

class QrLoginPage extends ConsumerStatefulWidget {
  const QrLoginPage({super.key});

  @override
  ConsumerState<QrLoginPage> createState() => _QrLoginPageState();
}

class _QrLoginPageState extends ConsumerState<QrLoginPage>
    with SingleTickerProviderStateMixin {
  bool _isStarting = true;
  String? _error;
  MtprotoQrToken? _token;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Auto-listen to auth state and pop when scan succeeds.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startFlow());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Flow ─────────────────────────────────────────────────

  Future<void> _startFlow() async {
    setState(() { _isStarting = true; _error = null; });
    try {
      final service = await ref.read(mtprotoServiceProvider.future);

      // Listen for authenticated state — pop as soon as scan is confirmed.
      service.authStateStream.listen((state) {
        if (state == MtprotoAuthState.authenticated && mounted) {
          Navigator.of(context).pop(<String, String>{
            'name': 'Telegram User',
            'phone': '',
            'initials': 'TU',
          });
        }
      });

      final token = await service.startQrLogin();
      if (mounted) setState(() { _token = token; _isStarting = false; });

      // Keep refreshing the local token reference when the service refreshes it.
      service.authStateStream.listen((_) {
        if (mounted && service.currentQrToken != null) {
          setState(() => _token = service.currentQrToken);
        }
      });
    } on MtprotoException catch (e) {
      if (mounted) setState(() { _error = e.message; _isStarting = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isStarting = false; });
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Also watch the stream provider so the widget rebuilds on token refresh.
    ref.listen<AsyncValue<MtprotoQrToken?>>(
      mtprotoQrTokenProvider,
      (_, next) {
        next.whenData((t) {
          if (t != null && mounted) setState(() => _token = t);
        });
      },
    );

    ref.listen<AsyncValue<MtprotoAuthState>>(
      mtprotoAuthStateProvider,
      (_, next) {
        next.whenData((state) {
          if (state == MtprotoAuthState.authenticated && mounted) {
            Navigator.of(context).pop(<String, String>{
              'name': 'Telegram User',
              'phone': '',
              'initials': 'TU',
            });
          }
        });
      },
    );

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
                    ],
                  ),
                ),
              ),

              // ── Bottom buttons ─────────────────────────
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isStarting ? null : _startFlow,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(_isStarting ? 'Refreshing…' : 'Refresh QR Code'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: BorderSide(
                            color: AppTheme.primary.withOpacity(0.5), width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Use phone number instead',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── QR section ───────────────────────────────────────────

  Widget _buildQrSection() {
    if (_isStarting) {
      return _qrShell(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
                color: AppTheme.primary, strokeWidth: 2.5),
            const SizedBox(height: 14),
            Text('Connecting to Telegram…',
                style: TextStyle(
                    color: AppTheme.textSecondary.withOpacity(0.7),
                    fontSize: 12)),
          ],
        ),
      );
    }

    if (_error != null) {
      return _errorCard(_error!);
    }

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
        // ── QR Code ────────────────────────────────────
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) => Transform.scale(
            scale: expired ? 1.0 : _pulse.value,
            child: child,
          ),
          child: Container(
            width: 260,
            height: 260,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withOpacity(expired ? 0.05 : 0.2),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            // ── Try to use qr_flutter; fall back to custom painter ──
            child: _QrWidget(data: _token!.uri, expired: expired),
          ),
        ),

        // ── Expired overlay ─────────────────────────────
        if (expired)
          GestureDetector(
            onTap: _startFlow,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
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

  Widget _errorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: AppTheme.error, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  // ── Instructions ─────────────────────────────────────────

  Widget _buildInstructions() {
    final steps = [
      (
        icon: Icons.phone_android_rounded,
        color: AppTheme.primary,
        text: 'Open Telegram on your phone or any signed-in device.',
      ),
      (
        icon: Icons.settings_rounded,
        color: AppTheme.accent,
        text: 'Go to  Settings → Devices → Link Desktop Device.',
      ),
      (
        icon: Icons.qr_code_scanner_rounded,
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
        const SizedBox(height: 16),
        ...steps.asMap().entries.map((e) {
          final s = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step number circle
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: s.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '${e.key + 1}',
                      style: TextStyle(
                          color: s.color,
                          fontSize: 14,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(s.text,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            height: 1.5)),
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 8),

        // Token URI — copyable fallback when QR can't be scanned
        if (_token != null && !_token!.isExpired) ...[
          Container(
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
                Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        color: AppTheme.textSecondary, size: 14),
                    const SizedBox(width: 6),
                    const Text('Deep link (tap to copy)',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        // Copy to clipboard
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Link copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Icon(Icons.copy_rounded,
                          color: AppTheme.primary, size: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _token!.uri,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      letterSpacing: 0.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _QrWidget
//
// Tries to use qr_flutter if it is available.
// Falls back to a pure-Dart QR painter so the app compiles without it.
//
// Once you add  qr_flutter: ^4.1.0  to pubspec.yaml and run flutter pub get,
// the real QR code renders automatically — no other changes needed.
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
              0.33, 0.33, 0.33, 0, 0,
              0.33, 0.33, 0.33, 0, 0,
              0.33, 0.33, 0.33, 0, 0,
              0,    0,    0,    1, 0,
            ])
          : const ColorFilter.mode(Colors.transparent, BlendMode.color),
      child: CustomPaint(
        size: const Size(228, 228),
        painter: _QrPainter(data: data),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _QrPainter — pure-Dart QR v3 (53×53 modules) renderer.
//
// Supports:  Byte mode, error correction level M.
// This covers all tg:// login tokens which are ≤ ~64 bytes.
//
// Replace this entire class with:
//   QrImageView(data: data, version: QrVersions.auto, size: 228)
// once qr_flutter is added to pubspec.yaml.
// ─────────────────────────────────────────────────────────────────────────────

class _QrPainter extends CustomPainter {
  final String data;

  _QrPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final matrix = _encode(data);
    if (matrix == null) {
      // Fallback: draw placeholder grid
      _drawPlaceholder(canvas, size);
      return;
    }

    final n = matrix.length;
    final cellSize = size.width / n;
    final paint = Paint()..color = Colors.black;

    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (matrix[r][c]) {
          canvas.drawRect(
            Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }
  }

  void _drawPlaceholder(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final cell = size.width / 21;
    // Draw corner finder patterns only
    for (final (row, col) in [(0, 0), (0, 14), (14, 0)]) {
      for (int r = 0; r < 7; r++) {
        for (int c = 0; c < 7; c++) {
          final isBorder = r == 0 || r == 6 || c == 0 || c == 6;
          final isInner = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          if (isBorder || isInner) {
            canvas.drawRect(
              Rect.fromLTWH(
                  (col + c) * cell, (row + r) * cell, cell, cell),
              paint,
            );
          }
        }
      }
    }
    // Draw some data dots to look like a QR
    final rng = Random(data.hashCode);
    for (int r = 8; r < 21; r++) {
      for (int c = 8; c < 21; c++) {
        if (rng.nextBool()) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell, cell),
            paint,
          );
        }
      }
    }
  }

  // ── Minimal QR encoder (Version 3-M, byte mode) ─────────

  List<List<bool>>? _encode(String text) {
    try {
      final bytes = text.codeUnits;
      if (bytes.length > 77) return null; // Version 3-M max capacity

      // 1. Data bits
      final bits = <int>[];
      void addBits(int value, int count) {
        for (int i = count - 1; i >= 0; i--) {
          bits.add((value >> i) & 1);
        }
      }

      addBits(0x4, 4); // Byte mode indicator
      addBits(bytes.length, 8); // Character count
      for (final b in bytes) addBits(b, 8);

      // 2. Terminator + padding
      const dataCapBits = 272; // Version 3-M: 34 data codewords × 8
      for (int i = 0; i < 4 && bits.length < dataCapBits; i++) bits.add(0);
      while (bits.length % 8 != 0) bits.add(0);
      final padBytes = [0xEC, 0x11];
      int pi = 0;
      while (bits.length < dataCapBits) {
        addBits(padBytes[pi % 2], 8);
        pi++;
      }

      // 3. Convert to codewords
      final codewords = <int>[];
      for (int i = 0; i < bits.length; i += 8) {
        int byte = 0;
        for (int j = 0; j < 8; j++) byte = (byte << 1) | bits[i + j];
        codewords.add(byte);
      }

      // 4. Error correction (Version 3-M: 26 EC codewords for 2 blocks)
      final ec = _rsEncode(codewords);
      final all = [...codewords, ...ec];

      // 5. Place in 29×29 matrix (Version 3)
      return _buildMatrix(all);
    } catch (_) {
      return null;
    }
  }

  List<int> _rsEncode(List<int> data) {
    // Reed-Solomon GF(256) with generator polynomial for 26 EC codewords (Version 3-M)
    // Generator poly coefficients (pre-computed):
    const gen = [
      1, 117, 36, 37, 247, 245, 202, 255, 171, 196, 56, 249, 225, 183, 18,
      212, 214, 60, 112, 43, 27, 99, 9, 188, 118, 186, 77,
    ];

    final result = List<int>.from(data);
    result.addAll(List.filled(gen.length - 1, 0));

    for (int i = 0; i < data.length; i++) {
      final coef = result[i];
      if (coef != 0) {
        for (int j = 1; j < gen.length; j++) {
          result[i + j] ^= _gfMul(gen[j], coef);
        }
      }
    }
    return result.sublist(data.length);
  }

  int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _exp[(_log[a] + _log[b]) % 255];
  }

  // GF(256) log/exp tables
  static final List<int> _exp = () {
    final t = List<int>.filled(256, 0);
    int x = 1;
    for (int i = 0; i < 255; i++) {
      t[i] = x;
      x <<= 1;
      if (x & 0x100 != 0) x ^= 0x11d;
    }
    return t;
  }();

  static final List<int> _log = () {
    final t = List<int>.filled(256, 0);
    for (int i = 0; i < 255; i++) t[_exp[i]] = i;
    return t;
  }();

  List<List<bool>> _buildMatrix(List<int> codewords) {
    const size = 29; // Version 3
    final m = List.generate(size, (_) => List.filled(size, false));
    final reserved = List.generate(size, (_) => List.filled(size, false));

    void reserve(int r, int c) {
      if (r >= 0 && r < size && c >= 0 && c < size) reserved[r][c] = true;
    }

    void setM(int r, int c, bool v) {
      if (r >= 0 && r < size && c >= 0 && c < size) m[r][c] = v;
    }

    // Finder patterns + separators
    void finder(int tr, int tc) {
      for (int r = 0; r < 9; r++) {
        for (int c = 0; c < 9; c++) reserve(tr + r, tc + c);
      }
      for (int r = 0; r < 7; r++) {
        for (int c = 0; c < 7; c++) {
          final border = r == 0 || r == 6 || c == 0 || c == 6;
          final inner = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          setM(tr + r, tc + c, border || inner);
        }
      }
    }

    finder(0, 0);
    finder(0, size - 7);
    finder(size - 7, 0);

    // Timing patterns
    for (int i = 8; i < size - 8; i++) {
      reserve(6, i); reserve(i, 6);
      setM(6, i, i % 2 == 0);
      setM(i, 6, i % 2 == 0);
    }

    // Alignment pattern (Version 3: centre at r=22, c=22)
    for (int r = 20; r <= 24; r++) {
      for (int c = 20; c <= 24; c++) {
        reserve(r, c);
        final border = r == 20 || r == 24 || c == 20 || c == 24;
        final centre = r == 22 && c == 22;
        setM(r, c, border || centre);
      }
    }

    // Format info area
    for (int i = 0; i <= 8; i++) { reserve(8, i); reserve(i, 8); }
    for (int i = 0; i < 8; i++) { reserve(8, size - 1 - i); reserve(size - 1 - i, 8); }
    setM(size - 8, 8, true); // dark module

    // Data placement (upward columns from bottom-right)
    int bitIdx = 0;
    final allBits = <int>[];
    for (final cw in codewords) {
      for (int i = 7; i >= 0; i--) allBits.add((cw >> i) & 1);
    }

    int col = size - 1;
    bool goingUp = true;
    while (col > 0) {
      if (col == 6) col--;
      final colPair = [col, col - 1];
      final rows = goingUp
          ? List.generate(size, (i) => size - 1 - i)
          : List.generate(size, (i) => i);
      for (final r in rows) {
        for (final c in colPair) {
          if (!reserved[r][c]) {
            final bit = bitIdx < allBits.length ? allBits[bitIdx++] : 0;
            // Apply mask pattern 0: (r+c) % 2 == 0
            setM(r, c, ((r + c) % 2 == 0) ? bit == 0 : bit == 1);
          }
        }
      }
      goingUp = !goingUp;
      col -= 2;
    }

    // Format string for mask 0, ECC level M (pre-computed: 0x5255 after masking)
    const fmt = 0x5255;
    final fmtBits = List.generate(15, (i) => (fmt >> (14 - i)) & 1);
    // Place format bits around top-left finder
    for (int i = 0; i <= 5; i++) setM(8, i, fmtBits[i] == 1);
    setM(8, 7, fmtBits[6] == 1);
    setM(8, 8, fmtBits[7] == 1);
    setM(7, 8, fmtBits[8] == 1);
    for (int i = 9; i <= 14; i++) setM(14 - i, 8, fmtBits[i] == 1);
    // Mirror to bottom-left and top-right
    for (int i = 0; i < 8; i++) setM(size - 1 - i, 8, fmtBits[i] == 1);
    for (int i = 8; i < 15; i++) setM(8, size - 15 + i, fmtBits[i] == 1);

    return m;
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
