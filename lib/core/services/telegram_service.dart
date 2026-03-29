import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

class TelegramUploadResult {
  final String fileId;
  final String messageId;
  final int fileSize;

  TelegramUploadResult({
    required this.fileId,
    required this.messageId,
    required this.fileSize,
  });
}

/// Thrown when Telegram returns ok:false — carries the real error description.
class TelegramApiException implements Exception {
  final int errorCode;
  final String description;
  TelegramApiException(this.errorCode, this.description);

  @override
  String toString() => 'Telegram [$errorCode]: $description';
}

class TelegramService {
  late final Dio _dio;
  String? _botToken;
  String? _channelId;

  TelegramService() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.telegramBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(minutes: 10),
      // Don't let Dio throw on non-2xx — we read the body ourselves
      // so we can surface the real Telegram error message.
      validateStatus: (_) => true,
    ));
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _botToken = prefs.getString(AppConstants.keyBotToken) ??
        dotenv.env['TELEGRAM_BOT_TOKEN'];
    _channelId = prefs.getString(AppConstants.keyChannelId) ??
        dotenv.env['TELEGRAM_CHANNEL_ID'];
  }

  String get _baseUrl => '/bot$_botToken';

  /// Normalise channel id — Telegram requires the -100 prefix.
  String get _normalizedChannelId {
    final raw = (_channelId ?? '').trim();
    if (raw.isEmpty) return raw;
    if (raw.startsWith('@')) return raw;
    if (raw.startsWith('-100')) return raw;
    if (raw.startsWith('-')) return '-100${raw.substring(1)}';
    return '-100$raw';
  }

  void _checkResponse(Response response) {
    final data = response.data;
    if (data is Map && data['ok'] == true) return;

    final code =
        (data is Map ? data['error_code'] : response.statusCode) ?? 0;
    final desc = (data is Map ? data['description'] : null) ??
        'HTTP ${response.statusCode}';
    throw TelegramApiException(code as int, desc as String);
  }

  // ── Upload ────────────────────────────────────────────

  Future<TelegramUploadResult> uploadFile({
    required File file,
    required String mimeType,
    required String fileName,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await init();

    final fileSize = await file.length();

    // Always sendDocument — avoids codec validation 400s from
    // sendPhoto / sendVideo / sendAudio endpoints.
    final formData = FormData.fromMap({
      'chat_id': _normalizedChannelId,
      'document': await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      ),
      'caption': 'ZX Drive | $fileName',
    });

    final response = await _dio.post(
      '$_baseUrl/sendDocument',
      data: formData,
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent, total);
      },
    );

    _checkResponse(response);

    final result = response.data['result'] as Map<String, dynamic>;
    final fileObj = result['document'] as Map<String, dynamic>;

    return TelegramUploadResult(
      fileId: fileObj['file_id'] as String,
      messageId: result['message_id'].toString(),
      fileSize: fileSize,
    );
  }

  // ── Chunked / Resumable Upload ────────────────────────

  Future<TelegramUploadResult> uploadFileResumable({
    required File file,
    required String mimeType,
    required String fileName,
    required String uploadId,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await init();

    final fileSize = await file.length();
    final prefs = await SharedPreferences.getInstance();
    final resumeKey = 'upload_offset_$uploadId';

    // Files ≤ 50 MB go direct
    if (fileSize <= 50 * 1024 * 1024) {
      final result = await uploadFile(
        file: file,
        mimeType: mimeType,
        fileName: fileName,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      await prefs.remove(resumeKey);
      return result;
    }

    // Large files: 49 MB chunks
    const chunkSize = 49 * 1024 * 1024;
    int offset = prefs.getInt(resumeKey) ?? 0;
    int totalSent = offset;

    String? lastFileId;
    String? firstMessageId;

    final raf = await file.open(mode: FileMode.read);
    try {
      while (offset < fileSize) {
        final end = (offset + chunkSize).clamp(0, fileSize);
        await raf.setPosition(offset);
        final chunkBytes = await raf.read(end - offset);

        final partNumber = (offset ~/ chunkSize) + 1;
        final formData = FormData.fromMap({
          'chat_id': _normalizedChannelId,
          'document': MultipartFile.fromBytes(
            chunkBytes,
            filename: '${fileName}_part$partNumber',
            contentType:
                DioMediaType.parse('application/octet-stream'),
          ),
          'caption': offset == 0
              ? 'ZX Drive | $fileName | Part $partNumber'
              : 'Part $partNumber',
        });

        final response = await _dio.post(
          '$_baseUrl/sendDocument',
          data: formData,
          cancelToken: cancelToken,
          onSendProgress: (sent, total) {
            if (total > 0) onProgress?.call(totalSent + sent, fileSize);
          },
        );

        _checkResponse(response);

        final result =
            response.data['result'] as Map<String, dynamic>;
        lastFileId =
            (result['document'] as Map<String, dynamic>)['file_id']
                as String;
        firstMessageId ??= result['message_id'].toString();

        offset = end;
        totalSent = offset;
        await prefs.setInt(resumeKey, offset);
      }
    } finally {
      await raf.close();
    }

    await prefs.remove(resumeKey);
    return TelegramUploadResult(
      fileId: lastFileId!,
      messageId: firstMessageId!,
      fileSize: fileSize,
    );
  }

  // ── Download ──────────────────────────────────────────

  /// Bot API getFile only works for files ≤ 20 MB.
  Future<String> getDownloadUrl(String fileId) async {
    await init();
    final response = await _dio.get(
      '$_baseUrl/getFile',
      queryParameters: {'file_id': fileId},
    );
    _checkResponse(response);
    final filePath =
        response.data['result']['file_path'] as String;
    return 'https://api.telegram.org/file/bot$_botToken/$filePath';
  }

  Future<void> downloadFile({
    required String fileId,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = await getDownloadUrl(fileId);

    // Use a separate Dio instance for file download (no validateStatus override needed)
    final downloadDio = Dio();
    await downloadDio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received, total);
      },
    );
  }

  // ── Delete ────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    await init();
    final response = await _dio.post(
      '$_baseUrl/deleteMessage',
      data: {
        'chat_id': _normalizedChannelId,
        'message_id': int.parse(messageId),
      },
    );
    _checkResponse(response);
  }

  // ── Validate credentials ──────────────────────────────

  Future<bool> validateCredentials({
    required String botToken,
    required String channelId,
  }) async {
    try {
      final testDio =
          Dio(BaseOptions(validateStatus: (_) => true));
      final response = await testDio.get(
        '${AppConstants.telegramBaseUrl}/bot$botToken/getMe',
      );
      return response.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
