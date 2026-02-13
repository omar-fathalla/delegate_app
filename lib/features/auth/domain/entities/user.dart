import 'package:equatable/equatable.dart';

class User extends Equatable {
  final String id;
  final String name;
  final String mobile;
  final String motherName; // Used as password
  final String role; // e.g., 'delegate'

  const User({
    required this.id,
    required this.name,
    required this.mobile,
    required this.motherName,
    required this.role,
  });

  @override
  List<Object> get props => [id, name, mobile, motherName, role];
}
