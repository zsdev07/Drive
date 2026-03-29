import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

enum ZXFileType { image, video, audio, document, archive, other }

extension ZXFileTypeX on ZXFileType {
  String get label => name;

  static ZXFileType fromMime(String mime) {
    if (mime.startsWith('image/')) return ZXFileType.image;
    if (mime.startsWith('video/')) return ZXFileType.video;
    if (mime.startsWith('audio/')) return ZXFileType.audio;
    if (mime.contains('zip') || mime.contains('rar') || mime.contains('tar'))
      return ZXFileType.archive;
    if (mime.contains('pdf') ||
        mime.contains('document') ||
        mime.contains('text') ||
        mime.contains('sheet'))
      return ZXFileType.document;
    return ZXFileType.other;
  }
}

// Upload state for UI
enum UploadStatus { queued, uploading, paused, done, failed }

class UploadTask {
  final String uploadId;
  final String fileName;
  final int totalBytes;
  int sentBytes;
  UploadStatus status;
  String? errorMessage;

  UploadTask({
    required this.uploadId,
    required this.fileName,
    required this.totalBytes,
    this.sentBytes = 0,
    this.status = UploadStatus.queued,
    this.errorMessage,
  });

  double get progress => totalBytes == 0 ? 0 : sentBytes / totalBytes;
}
