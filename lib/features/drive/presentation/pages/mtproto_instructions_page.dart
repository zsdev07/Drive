import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class MtprotoInstructionsPage extends StatelessWidget {
  const MtprotoInstructionsPage({super.key});

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
          'How to get API credentials',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Intro
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppTheme.primary, size: 18),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'API credentials come from Telegram directly. It takes about 2 minutes and is completely free.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Step-by-step guide',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ..._steps.map((step) => _StepCard(step: step)),
              const SizedBox(height: 28),

              // Warning
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.warning.withOpacity(0.25),
                    width: 1,
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppTheme.warning, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Never share your API Hash with anyone. Treat it like a password — it gives access to your Telegram account.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary, width: 1.5),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Got it — go back',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  static const _steps = [
    _Step(
      number: 1,
      title: 'Open my.telegram.org',
      body:
          'On your phone or computer, open a browser and go to my.telegram.org. This is the official Telegram developer portal.',
      icon: Icons.open_in_browser_rounded,
      color: Color(0xFF4F6FFF),
    ),
    _Step(
      number: 2,
      title: 'Log in with your phone number',
      body:
          'Enter your Telegram phone number (with country code). Telegram will send a confirmation code to your Telegram app. Enter that code to log in.',
      icon: Icons.phone_android_rounded,
      color: Color(0xFF00C48C),
    ),
    _Step(
      number: 3,
      title: 'Go to "API development tools"',
      body:
          'Once logged in, click on "API development tools" from the menu. This is where you create your app credentials.',
      icon: Icons.build_rounded,
      color: Color(0xFFFFB800),
    ),
    _Step(
      number: 4,
      title: 'Create a new application',
      body:
          'Fill in the form: App title (e.g. "My ZX Drive"), Short name (e.g. "zxdrive"), and Platform (choose "Other"). Click "Create application".',
      icon: Icons.add_box_rounded,
      color: Color(0xFF7C3AED),
    ),
    _Step(
      number: 5,
      title: 'Copy your API ID and API Hash',
      body:
          'You will see your App api_id (a number like 12345678) and App api_hash (a long string like a1b2c3d4...). Copy both of these into ZX Drive.',
      icon: Icons.copy_rounded,
      color: Color(0xFF00D4FF),
    ),
  ];
}

class _Step {
  final int number;
  final String title;
  final String body;
  final IconData icon;
  final Color color;
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
  });
}

class _StepCard extends StatelessWidget {
  final _Step step;
  const _StepCard({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Number circle + connector line
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: step.color.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: step.color.withOpacity(0.3), width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '${step.number}',
                    style: TextStyle(
                      color: step.color,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(step.icon, color: step.color, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step.title,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step.body,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
