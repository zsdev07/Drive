import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'trash_page.dart';

class MtprotoProfilePage extends StatelessWidget {
  final String name;
  final String phone;
  final String initials;
  final VoidCallback onDisconnect;

  const MtprotoProfilePage({
    super.key,
    required this.name,
    required this.phone,
    required this.initials,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 40),
              _buildProfileHeader(),
              const SizedBox(height: 12),
              _buildConnectedBadge(),
              const SizedBox(height: 40),
              _buildSectionLabel('My Sections'),
              const SizedBox(height: 12),
              _buildMenuItems(context),
              const SizedBox(height: 40),
              _buildSectionLabel('Account'),
              const SizedBox(height: 12),
              _buildAccountInfo(),
              const SizedBox(height: 24),
              _buildDisconnectButton(context),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        // Avatar circle with initials
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primary, AppTheme.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Text(
              initials.isNotEmpty ? initials : '?',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name.isNotEmpty ? name : 'Telegram User',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          phone,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.success.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded,
              color: AppTheme.success, size: 14),
          SizedBox(width: 6),
          Text(
            'MTProto Connected',
            style: TextStyle(
              color: AppTheme.success,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItems(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
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
            _MenuItem(
              icon: Icons.delete_rounded,
              iconColor: AppTheme.error,
              title: 'Trash',
              subtitle: 'Deleted files waiting for permanent removal',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TrashPage()),
              ),
            ),
            const Divider(height: 1, color: AppTheme.bgSurface),
            _MenuItem(
              icon: Icons.download_rounded,
              iconColor: AppTheme.primary,
              title: 'Downloaded',
              subtitle: 'Offline files saved to your device',
              badge: 'Coming soon',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Downloaded files — coming in the next update!'),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(16),
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
            _InfoRow(
              label: 'Upload limit',
              value: '2 GB per file',
              valueColor: AppTheme.success,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Download limit',
              value: 'Unlimited',
              valueColor: AppTheme.success,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Auth method',
              value: 'MTProto',
              valueColor: AppTheme.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.error,
          side:
              BorderSide(color: AppTheme.error.withOpacity(0.4), width: 1),
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: () => _confirmDisconnect(context),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 18),
            SizedBox(width: 8),
            Text(
              'Disconnect Account',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDisconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Disconnect Account',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700)),
        content: const Text(
          'Your files stay safe on Telegram. You\'ll return to Bot API mode.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDisconnect();
  }
}

// ── Sub-widgets ───────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  color: AppTheme.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
            color: AppTheme.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppTheme.textSecondary, size: 20),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13)),
        Text(value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}
