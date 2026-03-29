import 'package:isar/isar.dart';

part 'user_model.g.dart';

@collection
class UserModel {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uid;

  late String name;
  late String email;
  String? photoUrl;
  String? pin;
  late String botToken;
  late String channelId;

  @enumerated
  late AuthProvider authProvider;

  late DateTime createdAt;
  late DateTime lastLoginAt;
  late int usedStorageBytes;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.pin,
    required this.botToken,
    required this.channelId,
    required this.authProvider,
    required this.createdAt,
    required this.lastLoginAt,
    this.usedStorageBytes = 0,
  });
}

enum AuthProvider { google, pin }
