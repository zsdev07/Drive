import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _botTokenController = TextEditingController();
  final _channelIdController = TextEditingController();
  bool _isLoading = false;
  bool _showToken = false;

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyBotToken, _botTokenController.text.trim());
    await prefs.setString(AppConstants.keyChannelId, _channelIdController.text.trim());
    if (mounted) {
      setState(() => _isLoading = false);
      context.go('/pin-setup');
    }
  }

  @override
  void dispose() {
    _botTokenController.dispose();
    _channelIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.cloud_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Connect Your\nTelegram',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ZX Drive uses your Telegram bot & channel\nas your personal 5TB storage backend.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 40),
                const Text('Bot Token', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _botTokenController,
                  obscureText: !_showToken,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: '1234567890:AABBcc...',
                    prefixIcon: const Icon(Icons.smart_toy_rounded, color: AppTheme.textSecondary),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showToken ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: AppTheme.textSecondary,
                      ),
                      onPressed: () => setState(() => _showToken = !_showToken),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Bot token is required';
                    if (!v.contains(':')) return 'Invalid bot token format';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                const Text('Channel ID', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _channelIdController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '-100123456789',
                    prefixIcon: Icon(Icons.tag_rounded, color: AppTheme.textSecondary),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Channel ID is required';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2), width: 1),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 18),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Create a bot via @BotFather and a private channel. Add your bot as admin to the channel.',
                          style: TextStyle(color: AppTheme.primary, fontSize: 12, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _isLoading ? null : _continue,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
