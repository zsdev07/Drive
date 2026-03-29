import 'package:isar/isar.dart';

part 'folder_model.g.dart';

@collection
class FolderModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  late String name;
  String? parentFolderId;
  String? colorHex;
  String? iconName;
  late DateTime createdAt;
  late DateTime updatedAt;
  bool isDeleted = false;

  FolderModel({
    required this.uuid,
    required this.name,
    this.parentFolderId,
    this.colorHex,
    this.iconName,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });
}
