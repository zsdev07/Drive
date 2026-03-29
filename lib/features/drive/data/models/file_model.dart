import 'package:isar/isar.dart';

part 'file_model.g.dart';

@collection
class FileModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  late String name;
  late String mimeType;
  late int sizeBytes;
  late String telegramFileId;
  late String telegramMessageId;
  String? folderId;

  @enumerated
  late ZXFileType fileType;

  late DateTime uploadedAt;
  late DateTime? lastAccessedAt;
  String? thumbnailFileId;
  bool isStarred = false;
  bool isDeleted = false;

  FileModel({
    required this.uuid,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.telegramFileId,
    required this.telegramMessageId,
    this.folderId,
    required this.fileType,
    required this.uploadedAt,
    this.thumbnailFileId,
    this.isStarred = false,
    this.isDeleted = false,
  });
}

enum ZXFileType { image, video, audio, document, archive, other }
