import 'package:delegate_app/features/auth/domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.id,
    required super.name,
    required super.mobile,
    required super.motherName,
    required super.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, String id) {
    return UserModel(
      id: id,
      name: json['name'] ?? '',
      mobile: json['mobile'] ?? '',
      motherName: json['motherName'] ?? '',
      role: json['role'] ?? 'delegate',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'mobile': mobile,
      'motherName': motherName,
      'role': role,
    };
  }
}
