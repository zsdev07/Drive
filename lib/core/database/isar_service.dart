import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/drive/data/models/file_model.dart';
import '../../features/drive/data/models/folder_model.dart';
import '../../features/auth/data/models/user_model.dart';

class IsarService {
  static late Isar isar;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    isar = await Isar.open(
      [FileModelSchema, FolderModelSchema, UserModelSchema],
      directory: dir.path,
      name: 'zx_drive_db',
    );
  }
}
