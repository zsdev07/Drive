import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';

class MtprotoOtpPage extends StatefulWidget {
  final int apiId;
  final String apiHash;
  final String phone;

  const MtprotoOtpPage({
    super.key,
    required this.apiId,
    required this.apiHash,
    required this.phone,
  });

  @override
  State<MtprotoOtpPage> createState() => _MtprotoOtpPageState();
}

class _MtprotoOtpPageState extends State<MtprotoOtpPage> {
  final List<TextEditingController> _digitCtrlrs =
      List.generate(5, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(5, (_) => FocusNode());
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _digitCtrlrs) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  String get _otp => _digitCtrlrs.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length < 5) {
      setState(() => _error = 'Please enter the full 5-digit code');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // TODO: Wire TDLib — call tdlib.verifyCode(widget.apiId, widget.apiHash, widget.phone, _otp)
    // On success, tdlib returns the user's profile (name, phone, avatar)
    // For now: simulate verification, then pop back with a fake profile result
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    // Simulate a successful auth — replace with real TDLib profile data
    final name = 'Telegram User';
    final initials = _initialsFrom(name);

    // Pop back to MtprotoAuthPage with result — auth page forwards it to AccountPage
    if (mounted) {
      Navigator.of(context).pop(<String, String>{
        'name': name,
        'phone': widget.phone,
        'initials': initials,
      });
    }
  }

  String _initialsFrom(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  void _onDigitChanged(String value, int index) {
    if (value.length == 1 && index < 4) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.message_rounded,
                    color: AppTheme.primary, size: 28),
              ),
              const SizedBox(height: 24),
              const Text(
                'Enter the Code',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                  children: [
                    const TextSpan(
                        text: 'Telegram sent a 5-digit code to '),
                    TextSpan(
                      text: widget.phone,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // OTP digit boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(5, (i) {
                  return SizedBox(
                    width: 54,
                    height: 60,
                    child: TextFormField(
                      controller: _digitCtrlrs[i],
                      focusNode: _focusNodes[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                        filled: true,
                        fillColor: AppTheme.bgCard,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.08),
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (v) => _onDigitChanged(v, i),
                    ),
                  );
                }),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppTheme.error, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      _error!,
                      style: const TextStyle(
                          color: AppTheme.error, fontSize: 12),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verify,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Submit'),
                ),
              ),
              const SizedBox(height: 24),

              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Wrong number? Go back',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
