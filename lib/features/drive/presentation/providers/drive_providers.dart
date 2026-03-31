// In drive_providers.dart — replace the mtprotoServiceProvider with this:
// Also add this import at the top:
//   import 'package:shared_preferences/shared_preferences.dart'; // already present

final mtprotoServiceProvider = FutureProvider<MtprotoService>((ref) async {
  final db     = ref.watch(databaseProvider);
  final secure = ref.watch(secureStorageProvider);
  final service = MtprotoService(db: db, secureStorage: secure);
  await service.init();

  // If already authenticated, wire up TDLib immediately
  if (service.isAuthenticated) {
    final prefs     = await SharedPreferences.getInstance();
    final channelId = prefs.getString(AppConstants.keyChannelId) ?? '';
    if (channelId.isNotEmpty) {
      try {
        await service.initTdlib(channelId: channelId);
      } catch (_) {
        // Non-fatal: falls back to Bot API path in FileRepository
      }
    }
  }

  // Re-init TDLib whenever auth state changes to authenticated
  service.authStateStream.listen((state) async {
    if (state == MtprotoAuthState.authenticated) {
      final prefs     = await SharedPreferences.getInstance();
      final channelId = prefs.getString(AppConstants.keyChannelId) ?? '';
      if (channelId.isNotEmpty) {
        try {
          await service.initTdlib(channelId: channelId);
        } catch (_) {}
      }
    }
  });

  ref.onDispose(service.dispose);
  return service;
});
