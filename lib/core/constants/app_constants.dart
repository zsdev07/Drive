class AppConstants {
  static const String appName = 'ZX Drive';
  static const String appVersion = '1.0.0';
  static const int maxStorageBytes = 5 * 1024 * 1024 * 1024 * 1024; // 5 TB
  static const String maxStorageLabel = '5 TB';
  static const String telegramBaseUrl = 'https://api.telegram.org';
  static const String isarDbName = 'zx_drive_db';

  // ── SharedPrefs keys ───────────────────────────────────
  static const String keyIsOnboarded = 'is_onboarded';
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUserPin = 'user_pin';
  static const String keyBotToken = 'bot_token';
  static const String keyChannelId = 'channel_id';

  // ── MTProto UI state (non-secret; SharedPrefs is fine) ─
  static const String keyMtprotoConnected = 'mtproto_connected';
  static const String keyMtprotoName = 'mtproto_name';
  static const String keyMtprotoPhone = 'mtproto_phone';
  static const String keyMtprotoAvatar = 'mtproto_avatar_initials';

  // ── MTProto secrets (flutter_secure_storage) ───────────
  // These keys are used with SecureStorageService, NOT SharedPreferences.
  static const String secureKeyApiId = 'mtproto_api_id';
  static const String secureKeyApiHash = 'mtproto_api_hash';
  static const String secureKeyAuthKey = 'mtproto_auth_key';
  static const String secureKeyDcId = 'mtproto_dc_id';
  static const String secureKeyServerSalt = 'mtproto_server_salt';

  // ── Upload / download limits ───────────────────────────
  static const int maxUploadBytes = 2 * 1024 * 1024 * 1024; // 2 GB
  static const int maxConcurrentUploads = 10;          // Bot API tier
  static const int maxConcurrentUploadsAccount = 30;   // Account (MTProto) tier
  static const int botApiMaxDownloadBytes = 20 * 1024 * 1024; // 20 MB Bot API limit
  static const int chunkSize512KB = 512 * 1024;        // TDLib parallel chunk size
}
