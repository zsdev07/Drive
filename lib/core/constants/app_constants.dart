class AppConstants {
  static const String appName = 'ZX Drive';
  static const String appVersion = '1.0.0';
  static const int maxStorageBytes = 5 * 1024 * 1024 * 1024 * 1024; // 5 TB
  static const String maxStorageLabel = '5 TB';
  static const String telegramBaseUrl = 'https://api.telegram.org';
  static const String isarDbName = 'zx_drive_db';
  static const String keyIsOnboarded = 'is_onboarded';
  static const String keyIsLoggedIn = 'is_logged_in';
  static const String keyUserPin = 'user_pin';
  static const String keyBotToken = 'bot_token';
  static const String keyChannelId = 'channel_id';
  static const int maxUploadBytes = 2 * 1024 * 1024 * 1024; // 2 GB
  static const int maxConcurrentUploads = 10;          // Bot API tier
  static const int maxConcurrentUploadsAccount = 30;   // Account (MTProto) tier
  static const int botApiMaxDownloadBytes = 20 * 1024 * 1024; // 20 MB Bot API limit
}
