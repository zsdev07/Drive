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
    ));
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _botToken = prefs.getString(AppConstants.keyBotToken)
        ?? dotenv.env['TELEGRAM_BOT_TOKEN'];
    _channelId = prefs.getString(AppConstants.keyChannelId)
        ?? dotenv.env['TELEGRAM_CHANNEL_ID'];
  }

  String get _baseUrl => '/bot$_botToken';

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
    final endpoint = _resolveEndpoint(mimeType);

    final formData = FormData.fromMap({
      'chat_id': _channelId,
      endpoint: await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      ),
    });

    final response = await _dio.post(
      '$_baseUrl/send${_resolveMethod(mimeType)}',
      data: formData,
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent, total);
      },
    );

    final result = response.data['result'];
    final fileObj = _extractFileObj(result, mimeType);

    return TelegramUploadResult(
      fileId: fileObj['file_id'] as String,
      messageId: result['message_id'].toString(),
      fileSize: fileSize,
    );
  }

  // ── Chunked / Resumable Upload ────────────────────────

  /// For large files: tracks offset in SharedPrefs so if interrupted,
  /// it resumes from the last successfully sent chunk.
  Future<TelegramUploadResult> uploadFileResumable({
    required File file,
    required String mimeType,
    required String fileName,
    required String uploadId, // uuid of the FileItem
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await init();

    final fileSize = await file.length();
    final prefs = await SharedPreferences.getInstance();
    final resumeKey = 'upload_offset_$uploadId';

    // Files under 50MB go direct (Telegram handles them fine)
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

    // Large files: split into 49MB chunks and send as media group
    // Telegram bot API max per file is 50MB; we use 49MB to be safe.
    // Each chunk is uploaded as a document. The first chunk's message ID
    // is stored as the "parent" for this upload session.
    const chunkSize = 49 * 1024 * 1024;
    int offset = prefs.getInt(resumeKey) ?? 0;
    int totalSent = offset;

    String? lastFileId;
    String? firstMessageId;

    final raf = await file.open(mode: FileMode.read);

    try {
      while (offset < fileSize) {
        final end = (offset + chunkSize).clamp(0, fileSize);
        final chunkLength = end - offset;

        await raf.setPosition(offset);
        final chunkBytes = await raf.read(chunkLength);

        final chunkName = '${fileName}_part${(offset ~/ chunkSize) + 1}';
        final formData = FormData.fromMap({
          'chat_id': _channelId,
          'document': MultipartFile.fromBytes(
            chunkBytes,
            filename: chunkName,
            contentType: DioMediaType.parse('application/octet-stream'),
          ),
          'caption': offset == 0
              ? '📦 ZX Drive | $fileName | Part ${(offset ~/ chunkSize) + 1}'
              : 'Part ${(offset ~/ chunkSize) + 1}',
        });

        final response = await _dio.post(
          '$_baseUrl/sendDocument',
          data: formData,
          cancelToken: cancelToken,
          onSendProgress: (sent, total) {
            if (total > 0) {
              onProgress?.call(totalSent + sent, fileSize);
            }
          },
        );

        final result = response.data['result'];
        lastFileId = result['document']['file_id'] as String;
        firstMessageId ??= result['message_id'].toString();

        offset = end;
        totalSent = offset;

        // Persist resume offset
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

  Future<String> getDownloadUrl(String fileId) async {
    await init();

    final response = await _dio.get('$_baseUrl/getFile', queryParameters: {
      'file_id': fileId,
    });

    final filePath = response.data['result']['file_path'] as String;
    return 'https://api.telegram.org/file/bot$_botToken/$filePath';
  }

  Future<void> downloadFile({
    required String fileId,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = await getDownloadUrl(fileId);
    await _dio.download(
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
    await _dio.post('$_baseUrl/deleteMessage', data: {
      'chat_id': _channelId,
      'message_id': int.parse(messageId),
    });
  }

  // ── Validate credentials ──────────────────────────────

  Future<bool> validateCredentials({
    required String botToken,
    required String channelId,
  }) async {
    try {
      final testDio = Dio();
      final response = await testDio.get(
        '${AppConstants.telegramBaseUrl}/bot$botToken/getMe',
      );
      return response.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ───────────────────────────────────────────

  String _resolveEndpoint(String mimeType) {
    if (mimeType.startsWith('image/')) return 'photo';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    return 'document';
  }

  String _resolveMethod(String mimeType) {
    if (mimeType.startsWith('image/')) return 'Photo';
    if (mimeType.startsWith('video/')) return 'Video';
    if (mimeType.startsWith('audio/')) return 'Audio';
    return 'Document';
  }

  Map<String, dynamic> _extractFileObj(
      Map<String, dynamic> result, String mimeType) {
    if (mimeType.startsWith('image/')) {
      final photos = result['photo'] as List;
      return photos.last as Map<String, dynamic>;
    }
    if (mimeType.startsWith('video/')) return result['video'];
    if (mimeType.startsWith('audio/')) return result['audio'];
    return result['document'];
  }
}
