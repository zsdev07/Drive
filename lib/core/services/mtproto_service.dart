// ═══════════════════════════════════════════════════════════
// REPLACE the two FILE OPS methods in mtproto_service.dart
// (lines starting "// ══ FILE OPS" through the end of downloadFile)
// with the code below.
//
// Also add this import at the top of the file:
//   import 'tdlib_service.dart';
// ═══════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════
// FILE OPS  — delegated to TdlibService
// ══════════════════════════════════════════════════════════

// Add this field to the MtprotoService class (next to _db, _secure, _dio):
//   TdlibService? _tdlib;

/// Call this after init() once the user is authenticated.
/// [channelId] is the numeric channel id stored in SharedPrefs.
Future<void> initTdlib({required String channelId}) async {
  await _loadCredentials();
  _tdlib ??= TdlibService();
  await _tdlib!.init(
    apiId: _apiId!,
    apiHash: _apiHash!,
    phone: '',
  );
  _tdlibChannelId = channelId;
}

String? _tdlibChannelId;
TdlibService? _tdlib;

Future<TelegramUploadResult> uploadFile({
  required File file,
  required String mimeType,
  required String fileName,
  void Function(int sent, int total)? onProgress,
}) async {
  _requireAuth();

  if (_tdlib == null || _tdlibChannelId == null) {
    throw MtprotoException(
      'TdlibService not initialised. Call initTdlib() first.',
      code: 'TDLIB_NOT_READY',
    );
  }

  final result = await _tdlib!.uploadFile(
    file: file,
    mimeType: mimeType,
    fileName: fileName,
    channelId: _tdlibChannelId!,
    onProgress: onProgress,
  );

  return TelegramUploadResult(
    fileId: result.fileId,
    messageId: result.messageId,
    fileSize: result.fileSize,
  );
}

Future<String> downloadFile({
  required String fileId,
  required String savePath,
  void Function(int received, int total)? onProgress,
}) async {
  _requireAuth();

  if (_tdlib == null) {
    throw MtprotoException(
      'TdlibService not initialised. Call initTdlib() first.',
      code: 'TDLIB_NOT_READY',
    );
  }

  return _tdlib!.downloadFile(
    fileId: fileId,
    savePath: savePath,
    onProgress: onProgress,
  );
}

// Also update dispose() to include:
//   await _tdlib?.dispose();
