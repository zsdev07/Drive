import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import 'mtproto_auth_page.dart';
import 'mtproto_profile_page.dart';

// SharedPrefs keys for MTProto session
const String _keyMtprotoConnected = 'mtproto_connected';
const String _keyMtprotoName = 'mtproto_name';
const String _keyMtprotoPhone = 'mtproto_phone';
const String _keyMtprotoAvatar = 'mtproto_avatar_initials';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;
  bool _isConnected = false;
  String _name = '';
  String _phone = '';
  String _initials = '';

  @override
  void initState() {
    super.initState();
    // Optimised floating: translate-only, no opacity/blur. ~0% GPU cost.
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final connected = prefs.getBool(_keyMtprotoConnected) ?? false;
    if (connected) {
      setState(() {
        _isConnected = true;
        _name = prefs.getString(_keyMtprotoName) ?? '';
        _phone = prefs.getString(_keyMtprotoPhone) ?? '';
        _initials = prefs.getString(_keyMtprotoAvatar) ?? '';
      });
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isConnected
        ? MtprotoProfilePage(
            name: _name,
            phone: _phone,
            initials: _initials,
            onDisconnect: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove(_keyMtprotoConnected);
              await prefs.remove(_keyMtprotoName);
              await prefs.remove(_keyMtprotoPhone);
              await prefs.remove(_keyMtprotoAvatar);
              if (mounted) setState(() => _isConnected = false);
            },
          )
        : _buildUpsellPage();
  }

  Widget _buildUpsellPage() {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              _buildFloatingIcon(),
              const SizedBox(height: 32),
              _buildHeader(),
              const SizedBox(height: 36),
              _buildBenefitsGrid(),
              const SizedBox(height: 36),
              _buildComparisonTable(),
              const SizedBox(height: 40),
              _buildJoinButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingIcon() {
    return AnimatedBuilder(
      animation: _floatController,
      builder: (_, child) {
        // Pure translate — GPU-free on low-end devices
        final dy = math.sin(_floatController.value * math.pi) * 10.0;
        return Transform.translate(
          offset: Offset(0, dy),
          child: child,
        );
      },
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primary, AppTheme.accent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.35),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.cloud_rounded, color: Colors.white, size: 52),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          'Unlock Full Power',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Connect your Telegram account to break free from Bot API limits and get blazing-fast transfers.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 15,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildBenefitsGrid() {
    const benefits = [
      _Benefit(
        icon: Icons.storage_rounded,
        color: Color(0xFF4F6FFF),
        title: '2 GB per file',
        subtitle: 'vs 50 MB on Bot API',
      ),
      _Benefit(
        icon: Icons.bolt_rounded,
        color: Color(0xFF00C48C),
        title: 'Instant uploads',
        subtitle: 'MTProto parallel chunks',
      ),
      _Benefit(
        icon: Icons.download_rounded,
        color: Color(0xFF00D4FF),
        title: '10× faster downloads',
        subtitle: 'No 20 MB ceiling ever',
      ),
      _Benefit(
        icon: Icons.folder_zip_rounded,
        color: Color(0xFFFFB800),
        title: 'All file types',
        subtitle: 'Zero codec restrictions',
      ),
      _Benefit(
        icon: Icons.security_rounded,
        color: Color(0xFF7C3AED),
        title: 'End-to-end secure',
        subtitle: 'Your account, your data',
      ),
      _Benefit(
        icon: Icons.sync_rounded,
        color: Color(0xFFDB2777),
        title: 'Resume uploads',
        subtitle: 'Pick up where you left off',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What you get',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
          ),
          itemCount: benefits.length,
          itemBuilder: (_, i) => _BenefitCard(benefit: benefits[i]),
        ),
      ],
    );
  }

  Widget _buildComparisonTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bot API vs Account Auth',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // Header row
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text('Feature',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('Bot API',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('Account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.bgSurface),
              ..._comparisonRows(),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _comparisonRows() {
    const rows = [
      _CompRow('Upload limit', '50 MB', '2 GB', true),
      _CompRow('Download limit', '20 MB', 'Unlimited', true),
      _CompRow('Upload speed', 'Standard', '10× faster', true),
      _CompRow('File types', 'Restricted', 'All types', true),
      _CompRow('Concurrent uploads', '10 files', '30 files', true),
      _CompRow('Resume transfers', 'Partial', 'Full support', true),
      _CompRow('Cost', 'Free', 'Free', false),
    ];
    return rows.asMap().entries.map((entry) {
      final isLast = entry.key == rows.length - 1;
      final row = entry.value;
      return _ComparisonRow(row: row, isLast: isLast);
    }).toList();
  }

  Widget _buildJoinButton() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            onPressed: () async {
              final result = await Navigator.push<Map<String, String>>(
                context,
                MaterialPageRoute(
                    builder: (_) => const MtprotoAuthPage()),
              );
              if (result != null && mounted) {
                final name = result['name'] ?? '';
                final phone = result['phone'] ?? '';
                final initials = result['initials'] ?? '';
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(_keyMtprotoConnected, true);
                await prefs.setString(_keyMtprotoName, name);
                await prefs.setString(_keyMtprotoPhone, phone);
                await prefs.setString(_keyMtprotoAvatar, initials);
                setState(() {
                  _isConnected = true;
                  _name = name;
                  _phone = phone;
                  _initials = initials;
                });
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_rounded, size: 20),
                SizedBox(width: 10),
                Text(
                  'Join Now!',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Free forever · No credit card · Your data stays on Telegram',
          style: TextStyle(
            color: AppTheme.textSecondary.withOpacity(0.7),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Data models ───────────────────────────────────────────


class _Benefit {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _Benefit(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle});
}

class _CompRow {
  final String feature;
  final String botApi;
  final String account;
  final bool accountWins;
  const _CompRow(this.feature, this.botApi, this.account, this.accountWins);
}

// ── Sub-widgets ───────────────────────────────────────────

class _BenefitCard extends StatelessWidget {
  final _Benefit benefit;
  const _BenefitCard({required this.benefit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: benefit.color.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: benefit.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(benefit.icon, color: benefit.color, size: 18),
          ),
          const Spacer(),
          Text(
            benefit.title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            benefit.subtitle,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final _CompRow row;
  final bool isLast;
  const _ComparisonRow({required this.row, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(row.feature,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13)),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  row.botApi,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (row.accountWins) ...[
                      const Icon(Icons.check_circle_rounded,
                          color: AppTheme.success, size: 14),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        row.account,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: row.accountWins
                              ? AppTheme.success
                              : AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: row.accountWins
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(height: 1, color: AppTheme.bgSurface),
      ],
    );
  }
}
