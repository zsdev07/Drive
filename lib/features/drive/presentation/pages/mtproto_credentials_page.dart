import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/mtproto_service.dart';
import '../providers/drive_providers.dart';

/// Screen where the user enters their Telegram API ID + API Hash.
/// Values are written to flutter_secure_storage and read by [MtprotoService].
/// Navigate here (push) before [MtprotoAuthPage] when credentials are not set.
class MtprotoCredentialsPage extends ConsumerStatefulWidget {
  const MtprotoCredentialsPage({super.key});

  @override
  ConsumerState<MtprotoCredentialsPage> createState() =>
      _MtprotoCredentialsPageState();
}

class _MtprotoCredentialsPageState
    extends ConsumerState<MtprotoCredentialsPage> {
  final _formKey = GlobalKey<FormState>();
  final _apiIdCtrl = TextEditingController();
  final _apiHashCtrl = TextEditingController();
  bool _isLoading = false;
  bool _showHash = false;
  String? _error;

  @override
  void dispose() {
    _apiIdCtrl.dispose();
    _apiHashCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // mtprotoServiceProvider is a FutureProvider — await its future.
      final service = await ref.read(mtprotoServiceProvider.future);
      await service.saveCredentials(
        apiId: _apiIdCtrl.text.trim(),
        apiHash: _apiHashCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true); // true = saved
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Icon ────────────────────────────────────────
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child:
                      const Icon(Icons.key_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 24),

                const Text(
                  'MTProto Credentials',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your Telegram API ID and API Hash.\nGet them from my.telegram.org → API development tools.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 32),

                // ── Info card ────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withOpacity(0.2), width: 1),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: AppTheme.primary, size: 16),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '1. Open my.telegram.org\n'
                          '2. Log in with your phone number\n'
                          '3. Tap "API development tools"\n'
                          '4. Copy your App api_id and api_hash here',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            height: 1.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ── API ID ───────────────────────────────────────
                const _FieldLabel('API ID'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _apiIdCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '12345678',
                    prefixIcon: Icon(Icons.tag_rounded,
                        color: AppTheme.textSecondary, size: 20),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'API ID is required';
                    if (int.tryParse(v.trim()) == null) return 'Must be a number';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // ── API Hash ─────────────────────────────────────
                const _FieldLabel('API Hash'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _apiHashCtrl,
                  obscureText: !_showHash,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    letterSpacing: 1.2,
                  ),
                  decoration: InputDecoration(
                    hintText: 'a1b2c3d4e5f6...',
                    prefixIcon: const Icon(Icons.lock_outline_rounded,
                        color: AppTheme.textSecondary, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showHash
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _showHash = !_showHash),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'API Hash is required';
                    if (v.trim().length < 16) return 'API Hash looks too short';
                    return null;
                  },
                ),

                // ── Error ────────────────────────────────────────
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

                const SizedBox(height: 36),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save & Continue'),
                  ),
                ),
                const SizedBox(height: 24),

                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
