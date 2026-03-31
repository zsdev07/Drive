import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/mtproto_service.dart';
import '../providers/drive_providers.dart';

enum _Mode { code, password }

class MtprotoOtpPage extends ConsumerStatefulWidget {
  final String phone;
  const MtprotoOtpPage({super.key, required this.phone});

  @override
  ConsumerState<MtprotoOtpPage> createState() => _MtprotoOtpPageState();
}

class _MtprotoOtpPageState extends ConsumerState<MtprotoOtpPage> {
  final List<TextEditingController> _digitCtrlrs =
      List.generate(5, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(5, (_) => FocusNode());

  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  _Mode _mode = _Mode.code;
  bool _isLoading = false;
  bool _showPassword = false;
  String? _error;
  String? _twoFaHint;

  @override
  void dispose() {
    for (final c in _digitCtrlrs) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String get _otp => _digitCtrlrs.map((c) => c.text).join();

  Future<void> _verifyCode() async {
    if (_otp.length < 5) {
      setState(() => _error = 'Please enter the full 5-digit code');
      return;
    }
    _setLoading(true);
    try {
      final mtproto = await ref.read(mtprotoServiceProvider.future);
      await mtproto.signIn(widget.phone, _otp);
      _onAuthSuccess();
    } on MtprotoTwoFactorRequired catch (e) {
      setState(() {
        _mode = _Mode.password;
        _twoFaHint = e.hint.isNotEmpty ? e.hint : null;
        _error = null;
      });
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _passwordFocus.requestFocus());
    } on MtprotoAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _verifyPassword() async {
    final password = _passwordCtrl.text.trim();
    if (password.isEmpty) {
      setState(() => _error = 'Password cannot be empty');
      return;
    }
    _setLoading(true);
    try {
      final mtproto = await ref.read(mtprotoServiceProvider.future);
      await mtproto.signInWithPassword(password);
      _onAuthSuccess();
    } on MtprotoAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      _setLoading(false);
    }
  }

  void _onAuthSuccess() {
    if (!mounted) return;
    const name = 'Telegram User';
    Navigator.of(context).pop(<String, String>{
      'name': name,
      'phone': widget.phone,
      'initials': _initialsFrom(name),
    });
  }

  void _setLoading(bool v) { if (mounted) setState(() => _isLoading = v); }

  String _initialsFrom(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  void _onDigitChanged(String value, int index) {
    if (value.length == 1 && index < 4) _focusNodes[index + 1].requestFocus();
    else if (value.isEmpty && index > 0) _focusNodes[index - 1].requestFocus();
    setState(() => _error = null);
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
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _mode == _Mode.code ? _buildCodeMode() : _buildPasswordMode(),
        ),
      ),
    );
  }

  Widget _buildCodeMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _modeIcon(Icons.message_rounded,
            AppTheme.primary.withOpacity(0.12), AppTheme.primary),
        const SizedBox(height: 24),
        const Text('Enter the Code',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            )),
        const SizedBox(height: 10),
        RichText(
          text: TextSpan(
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 14, height: 1.6),
            children: [
              const TextSpan(text: 'Telegram sent a 5-digit code to '),
              TextSpan(
                text: widget.phone,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(5, (i) {
            return SizedBox(
              width: 54, height: 60,
              child: TextFormField(
                controller: _digitCtrlrs[i],
                focusNode: _focusNodes[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: AppTheme.bgCard,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.08), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 2),
                  ),
                ),
                onChanged: (v) => _onDigitChanged(v, i),
              ),
            );
          }),
        ),
        _errorWidget(),
        const SizedBox(height: 32),
        _submitButton('Submit', _verifyCode),
        const SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Wrong number? Go back',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _modeIcon(Icons.lock_rounded,
            AppTheme.warning.withOpacity(0.12), AppTheme.warning),
        const SizedBox(height: 24),
        const Text('Two-Factor Auth',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            )),
        const SizedBox(height: 10),
        Text(
          _twoFaHint != null
              ? 'Your account has a cloud password. Hint: "$_twoFaHint"'
              : 'Your account has a cloud password. Enter it below.',
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          obscureText: !_showPassword,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Cloud password',
            prefixIcon: const Icon(Icons.lock_outline_rounded,
                color: AppTheme.textSecondary, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: AppTheme.textSecondary, size: 20,
              ),
              onPressed: () =>
                  setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        _errorWidget(),
        const SizedBox(height: 32),
        _submitButton('Verify Password', _verifyPassword),
        const SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _mode = _Mode.code),
            child: const Text('Back to code',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _modeIcon(IconData icon, Color bg, Color fg) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(16)),
      child: Icon(icon, color: fg, size: 28),
    );
  }

  Widget _errorWidget() {
    if (_error == null) return const SizedBox(height: 14);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(_error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _submitButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        child: _isLoading
            ? const SizedBox(
                height: 20, width: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Text(label),
      ),
    );
  }
}
