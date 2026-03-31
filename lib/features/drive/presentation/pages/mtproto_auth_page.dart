import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/mtproto_service.dart';
import '../providers/drive_providers.dart';
import 'mtproto_credentials_page.dart';
import 'mtproto_instructions_page.dart';
import 'mtproto_otp_page.dart';
import 'qr_login_page.dart';

// ── Country model ─────────────────────────────────────────────────────────────

class _Country {
  final String name;
  final String flag;
  final String dialCode;
  final int minDigits;
  final int maxDigits;

  const _Country({
    required this.name,
    required this.flag,
    required this.dialCode,
    required this.minDigits,
    required this.maxDigits,
  });
}

// ── Country list ──────────────────────────────────────────────────────────────

const List<_Country> _kCountries = [
  _Country(name: 'India',          flag: '🇮🇳', dialCode: '+91',  minDigits: 10, maxDigits: 10),
  _Country(name: 'United States',  flag: '🇺🇸', dialCode: '+1',   minDigits: 10, maxDigits: 10),
  _Country(name: 'United Kingdom', flag: '🇬🇧', dialCode: '+44',  minDigits: 10, maxDigits: 10),
  _Country(name: 'Australia',      flag: '🇦🇺', dialCode: '+61',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Canada',         flag: '🇨🇦', dialCode: '+1',   minDigits: 10, maxDigits: 10),
  _Country(name: 'Germany',        flag: '🇩🇪', dialCode: '+49',  minDigits: 10, maxDigits: 11),
  _Country(name: 'France',         flag: '🇫🇷', dialCode: '+33',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Italy',          flag: '🇮🇹', dialCode: '+39',  minDigits: 9,  maxDigits: 10),
  _Country(name: 'Spain',          flag: '🇪🇸', dialCode: '+34',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Brazil',         flag: '🇧🇷', dialCode: '+55',  minDigits: 10, maxDigits: 11),
  _Country(name: 'Mexico',         flag: '🇲🇽', dialCode: '+52',  minDigits: 10, maxDigits: 10),
  _Country(name: 'Japan',          flag: '🇯🇵', dialCode: '+81',  minDigits: 10, maxDigits: 10),
  _Country(name: 'China',          flag: '🇨🇳', dialCode: '+86',  minDigits: 11, maxDigits: 11),
  _Country(name: 'South Korea',    flag: '🇰🇷', dialCode: '+82',  minDigits: 9,  maxDigits: 10),
  _Country(name: 'Russia',         flag: '🇷🇺', dialCode: '+7',   minDigits: 10, maxDigits: 10),
  _Country(name: 'Indonesia',      flag: '🇮🇩', dialCode: '+62',  minDigits: 9,  maxDigits: 12),
  _Country(name: 'Pakistan',       flag: '🇵🇰', dialCode: '+92',  minDigits: 10, maxDigits: 10),
  _Country(name: 'Bangladesh',     flag: '🇧🇩', dialCode: '+880', minDigits: 10, maxDigits: 10),
  _Country(name: 'Nigeria',        flag: '🇳🇬', dialCode: '+234', minDigits: 10, maxDigits: 10),
  _Country(name: 'South Africa',   flag: '🇿🇦', dialCode: '+27',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Egypt',          flag: '🇪🇬', dialCode: '+20',  minDigits: 10, maxDigits: 10),
  _Country(name: 'Saudi Arabia',   flag: '🇸🇦', dialCode: '+966', minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'UAE',            flag: '🇦🇪', dialCode: '+971', minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Turkey',         flag: '🇹🇷', dialCode: '+90',  minDigits: 10, maxDigits: 10),
  _Country(name: 'Netherlands',    flag: '🇳🇱', dialCode: '+31',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Sweden',         flag: '🇸🇪', dialCode: '+46',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Norway',         flag: '🇳🇴', dialCode: '+47',  minDigits: 8,  maxDigits: 8 ),
  _Country(name: 'Switzerland',    flag: '🇨🇭', dialCode: '+41',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Singapore',      flag: '🇸🇬', dialCode: '+65',  minDigits: 8,  maxDigits: 8 ),
  _Country(name: 'Malaysia',       flag: '🇲🇾', dialCode: '+60',  minDigits: 9,  maxDigits: 10),
  _Country(name: 'Philippines',    flag: '🇵🇭', dialCode: '+63',  minDigits: 10, maxDigits: 10),
  _Country(name: 'Thailand',       flag: '🇹🇭', dialCode: '+66',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Vietnam',        flag: '🇻🇳', dialCode: '+84',  minDigits: 9,  maxDigits: 10),
  _Country(name: 'Argentina',      flag: '🇦🇷', dialCode: '+54',  minDigits: 10, maxDigits: 10),
  _Country(name: 'Colombia',       flag: '🇨🇴', dialCode: '+57',  minDigits: 10, maxDigits: 10),
  _Country(name: 'Kenya',          flag: '🇰🇪', dialCode: '+254', minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Ghana',          flag: '🇬🇭', dialCode: '+233', minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Poland',         flag: '🇵🇱', dialCode: '+48',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Ukraine',        flag: '🇺🇦', dialCode: '+380', minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Portugal',       flag: '🇵🇹', dialCode: '+351', minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Greece',         flag: '🇬🇷', dialCode: '+30',  minDigits: 10, maxDigits: 10),
  _Country(name: 'New Zealand',    flag: '🇳🇿', dialCode: '+64',  minDigits: 8,  maxDigits: 9 ),
  _Country(name: 'Israel',         flag: '🇮🇱', dialCode: '+972', minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Iran',           flag: '🇮🇷', dialCode: '+98',  minDigits: 10, maxDigits: 10),
  _Country(name: 'Iraq',           flag: '🇮🇶', dialCode: '+964', minDigits: 10, maxDigits: 10),
  _Country(name: 'Sri Lanka',      flag: '🇱🇰', dialCode: '+94',  minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Nepal',          flag: '🇳🇵', dialCode: '+977', minDigits: 10, maxDigits: 10),
  _Country(name: 'Myanmar',        flag: '🇲🇲', dialCode: '+95',  minDigits: 9,  maxDigits: 10),
  _Country(name: 'Ethiopia',       flag: '🇪🇹', dialCode: '+251', minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Tanzania',       flag: '🇹🇿', dialCode: '+255', minDigits: 9,  maxDigits: 9 ),
  _Country(name: 'Morocco',        flag: '🇲🇦', dialCode: '+212', minDigits: 9,  maxDigits: 9 ),
];

// ── Page ──────────────────────────────────────────────────────────────────────

class MtprotoAuthPage extends ConsumerStatefulWidget {
  const MtprotoAuthPage({super.key});

  @override
  ConsumerState<MtprotoAuthPage> createState() => _MtprotoAuthPageState();
}

class _MtprotoAuthPageState extends ConsumerState<MtprotoAuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _phoneFocus = FocusNode();

  _Country _selected = _kCountries.first;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkCredentials());
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  // ── Credential gate ───────────────────────────────────────

  Future<void> _checkCredentials() async {
    final service = await ref.read(mtprotoServiceProvider.future);
    final has = await service.hasCredentials();
    if (!has && mounted) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const MtprotoCredentialsPage()),
      );
      if (saved != true && mounted) Navigator.pop(context);
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');
  String get _e164 => '${_selected.dialCode}${_digitsOnly(_phoneCtrl.text)}';

  // ── Country picker ────────────────────────────────────────

  void _showCountryPicker() {
    final searchCtrl = TextEditingController();
    List<_Country> filtered = List.from(_kCountries);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            builder: (_, scrollCtrl) {
              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textSecondary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Select Country',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search country or dial code…',
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppTheme.textSecondary, size: 20),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded,
                                    color: AppTheme.textSecondary, size: 18),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setSheet(() => filtered = List.from(_kCountries));
                                },
                              )
                            : null,
                      ),
                      onChanged: (q) {
                        final lower = q.toLowerCase();
                        setSheet(() {
                          filtered = _kCountries
                              .where((c) =>
                                  c.name.toLowerCase().contains(lower) ||
                                  c.dialCode.contains(q))
                              .toList();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Color(0xFF2A2D45), height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final c = filtered[i];
                        final isSelected = c.name == _selected.name;
                        return InkWell(
                          onTap: () {
                            setState(() => _selected = c);
                            _phoneCtrl.clear();
                            Navigator.pop(ctx);
                            Future.delayed(
                              const Duration(milliseconds: 150),
                              () => _phoneFocus.requestFocus(),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            color: isSelected
                                ? AppTheme.primary.withOpacity(0.08)
                                : Colors.transparent,
                            child: Row(
                              children: [
                                Text(c.flag,
                                    style: const TextStyle(fontSize: 24)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(c.name,
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppTheme.primary
                                            : AppTheme.textPrimary,
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      )),
                                ),
                                Text(c.dialCode,
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppTheme.primary
                                          : AppTheme.textSecondary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    )),
                                if (isSelected) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check_circle_rounded,
                                      color: AppTheme.primary, size: 18),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        });
      },
    );
  }

  // ── Send code ─────────────────────────────────────────────

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;

    final service = await ref.read(mtprotoServiceProvider.future);
    final has = await service.hasCredentials();
    if (!has) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const MtprotoCredentialsPage()),
      );
      if (saved != true) return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      await service.sendCode(_e164);
      if (!mounted) return;

      final result = await Navigator.push<Map<String, String>>(
        context,
        MaterialPageRoute(builder: (_) => MtprotoOtpPage(phone: _e164)),
      );
      if (result != null && mounted) Navigator.pop(context, result);
    } on MtprotoException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── QR login ──────────────────────────────────────────────

  Future<void> _openQrLogin() async {
    final service = await ref.read(mtprotoServiceProvider.future);
    final has = await service.hasCredentials();
    if (!has && mounted) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const MtprotoCredentialsPage()),
      );
      if (saved != true) return;
    }
    if (!mounted) return;
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (_) => const QrLoginPage()),
    );
    if (result != null && mounted) Navigator.pop(context, result);
  }

  // ── Build ─────────────────────────────────────────────────

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
        actions: [
          IconButton(
            tooltip: 'Edit API credentials',
            icon: const Icon(Icons.key_rounded,
                color: AppTheme.textSecondary, size: 20),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MtprotoCredentialsPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Header icon ─────────────────────────────
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(height: 24),

                const Text('Auth Your Account',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    )),
                const SizedBox(height: 8),
                const Text(
                  'Connect via MTProto for 2 GB uploads,\nblazing downloads, and no limits.',
                  style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 36),

                const _FieldLabel('Phone Number'),
                const SizedBox(height: 8),

                // ── Country picker + number field ────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _showCountryPicker,
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: const Border.fromBorderSide(
                              BorderSide(color: Color(0xFF2A2D45), width: 1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_selected.flag,
                                style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 6),
                            Text(_selected.dialCode,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                )),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down_rounded,
                                color: AppTheme.textSecondary, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _phoneCtrl,
                        focusNode: _phoneFocus,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(_selected.maxDigits),
                        ],
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          letterSpacing: 1.5,
                        ),
                        decoration: InputDecoration(
                          hintText: '${_selected.minDigits} digit number',
                          prefixIcon: const Icon(Icons.phone_rounded,
                              color: AppTheme.textSecondary, size: 20),
                          suffixIcon: _phoneCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      color: AppTheme.textSecondary, size: 18),
                                  onPressed: () =>
                                      setState(() => _phoneCtrl.clear()),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final digits = _digitsOnly(v ?? '');
                          if (digits.isEmpty) return 'Phone number required';
                          if (digits.length < _selected.minDigits) {
                            return 'Need ${_selected.minDigits} digits for ${_selected.name}';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),

                // ── E164 preview ─────────────────────────────
                if (_phoneCtrl.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppTheme.primary.withOpacity(0.25), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            color: AppTheme.primary, size: 13),
                        const SizedBox(width: 5),
                        Text(_e164,
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            )),
                      ],
                    ),
                  ),
                ],

                // ── Error banner ─────────────────────────────
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.error.withOpacity(0.3), width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppTheme.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppTheme.error, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // ── Instructions card ─────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withOpacity(0.2), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppTheme.primary, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'A code will be sent to your Telegram app. No .env required — credentials are stored securely on device.',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const MtprotoInstructionsPage())),
                              child: const Text('See Instructions →',
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                // ── Send Code button ──────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendCode,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Send Code'),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Divider ───────────────────────────────────
                Row(
                  children: [
                    Expanded(
                        child: Divider(
                            color: AppTheme.textSecondary.withOpacity(0.2),
                            thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                          style: TextStyle(
                              color: AppTheme.textSecondary.withOpacity(0.6),
                              fontSize: 12)),
                    ),
                    Expanded(
                        child: Divider(
                            color: AppTheme.textSecondary.withOpacity(0.2),
                            thickness: 1)),
                  ],
                ),

                const SizedBox(height: 16),

                // ── QR Code login button ──────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _openQrLogin,
                    icon: const Icon(Icons.qr_code_rounded, size: 18),
                    label: const Text('Log in with QR Code'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(
                          color: AppTheme.primary.withOpacity(0.45), width: 1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Field label ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ));
  }
}
