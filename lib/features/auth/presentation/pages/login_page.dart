import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
// login_page is at features/auth/presentation/pages/
// mtproto_auth_page is at features/drive/presentation/pages/
import '../../../drive/presentation/pages/mtproto_auth_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Bot API state ─────────────────────────────────────────
  final _botFormKey = GlobalKey<FormState>();
  final _botTokenController = TextEditingController();
  final _channelIdController = TextEditingController();
  bool _isBotLoading = false;
  bool _showToken = false;

  // ── MTProto state ─────────────────────────────────────────
  bool _isMtprotoLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _botTokenController.dispose();
    _channelIdController.dispose();
    super.dispose();
  }

  // ── Bot API continue ──────────────────────────────────────

  Future<void> _botContinue() async {
    if (!_botFormKey.currentState!.validate()) return;
    setState(() => _isBotLoading = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        AppConstants.keyBotToken, _botTokenController.text.trim());
    await prefs.setString(
        AppConstants.keyChannelId, _channelIdController.text.trim());
    if (mounted) {
      setState(() => _isBotLoading = false);
      context.go('/pin-setup');
    }
  }

  // ── MTProto continue ──────────────────────────────────────

  Future<void> _mtprotoContinue() async {
    setState(() => _isMtprotoLoading = true);
    try {
      final result = await Navigator.push<Map<String, String>>(
        context,
        MaterialPageRoute(builder: (_) => const MtprotoAuthPage()),
      );

      if (result != null && mounted) {
        // Save MTProto session flags so the app knows auth mode.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(AppConstants.keyMtprotoConnected, true);
        await prefs.setString(
            AppConstants.keyMtprotoName, result['name'] ?? 'Telegram User');
        await prefs.setString(
            AppConstants.keyMtprotoPhone, result['phone'] ?? '');
        await prefs.setString(
            AppConstants.keyMtprotoAvatar, result['initials'] ?? '?');
        if (mounted) context.go('/pin-setup');
      }
    } finally {
      if (mounted) setState(() => _isMtprotoLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.cloud_rounded,
                        color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 28),
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
                    'Choose how to connect. Bot API is quick.\nMTProto unlocks 2 GB uploads.',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        height: 1.6),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),

            // ── Tab bar ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppTheme.textSecondary,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'Bot API'),
                    Tab(text: 'MTProto'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),

            // ── Tab views ──────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _BotApiTab(
                    formKey: _botFormKey,
                    botTokenController: _botTokenController,
                    channelIdController: _channelIdController,
                    isLoading: _isBotLoading,
                    showToken: _showToken,
                    onToggleToken: () =>
                        setState(() => _showToken = !_showToken),
                    onContinue: _botContinue,
                  ),
                  _MtprotoTab(
                    isLoading: _isMtprotoLoading,
                    onContinue: _mtprotoContinue,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bot API tab ───────────────────────────────────────────────────────────────

class _BotApiTab extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController botTokenController;
  final TextEditingController channelIdController;
  final bool isLoading;
  final bool showToken;
  final VoidCallback onToggleToken;
  final VoidCallback onContinue;

  const _BotApiTab({
    required this.formKey,
    required this.botTokenController,
    required this.channelIdController,
    required this.isLoading,
    required this.showToken,
    required this.onToggleToken,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Label('Bot Token'),
            const SizedBox(height: 8),
            TextFormField(
              controller: botTokenController,
              obscureText: !showToken,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: '1234567890:AABBcc…',
                prefixIcon: const Icon(Icons.smart_toy_rounded,
                    color: AppTheme.textSecondary),
                suffixIcon: IconButton(
                  icon: Icon(
                    showToken
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: AppTheme.textSecondary,
                  ),
                  onPressed: onToggleToken,
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Bot token is required';
                if (!v.contains(':')) return 'Invalid bot token format';
                return null;
              },
            ),
            const SizedBox(height: 20),
            const _Label('Channel ID'),
            const SizedBox(height: 8),
            TextFormField(
              controller: channelIdController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: '-100123456789',
                prefixIcon:
                    Icon(Icons.tag_rounded, color: AppTheme.textSecondary),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Channel ID is required';
                return null;
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.primary.withOpacity(0.2), width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppTheme.primary, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Create a bot via @BotFather and a private channel. Add your bot as admin to the channel.',
                      style: TextStyle(
                          color: AppTheme.primary, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : onContinue,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── MTProto tab ───────────────────────────────────────────────────────────────

class _MtprotoTab extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onContinue;

  const _MtprotoTab({required this.isLoading, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feature highlights
          _FeatureTile(
            icon: Icons.upload_rounded,
            color: AppTheme.primary,
            title: '2 GB file uploads',
            subtitle: 'vs 50 MB on Bot API',
          ),
          const SizedBox(height: 12),
          _FeatureTile(
            icon: Icons.download_rounded,
            color: const Color(0xFF34C759),
            title: 'Unlimited downloads',
            subtitle: 'No Bot API 20 MB cap',
          ),
          const SizedBox(height: 12),
          _FeatureTile(
            icon: Icons.security_rounded,
            color: const Color(0xFFFF9500),
            title: 'Credentials on device',
            subtitle: 'Stored in secure storage',
          ),
          const SizedBox(height: 28),

          // What you need
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.primary.withOpacity(0.15), width: 1),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What you need',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '• Your Telegram phone number\n'
                  '• API ID + Hash from my.telegram.org\n'
                  '• Access to Telegram app for OTP',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isLoading ? null : onContinue,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Connect with MTProto'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            Text(subtitle,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600),
    );
  }
}
