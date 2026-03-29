import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/onboarding_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/pin_setup_page.dart';
import '../../features/drive/presentation/pages/home_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    routes: [
      GoRoute(path: '/splash', name: 'splash', builder: (c, s) => const SplashPage()),
      GoRoute(path: '/onboarding', name: 'onboarding', builder: (c, s) => const OnboardingPage()),
      GoRoute(path: '/login', name: 'login', builder: (c, s) => const LoginPage()),
      GoRoute(path: '/pin-setup', name: 'pin-setup', builder: (c, s) => const PinSetupPage()),
      GoRoute(path: '/home', name: 'home', builder: (c, s) => const HomePage()),
    ],
  );
});
