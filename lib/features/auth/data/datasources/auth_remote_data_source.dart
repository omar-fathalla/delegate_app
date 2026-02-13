import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login(String mobile, String motherName);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseFirestore firestore;

  AuthRemoteDataSourceImpl({required this.firestore});

  @override
  Future<UserModel> login(String mobile, String motherName) async {
    try {
      final querySnapshot = await firestore
          .collection('users')
          .where('mobile', isEqualTo: mobile)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw const AuthFailure('User not found');
      }

      final doc = querySnapshot.docs.first;
      final userData = doc.data();

      if (userData['motherName'] != motherName) {
        throw const AuthFailure('Invalid credentials');
      }

      return UserModel.fromJson(userData, doc.id);
    } catch (e) {
      if (e is AuthFailure) rethrow; // Pass specific failures
      throw const ServerFailure('Login failed due to server error');
    }
  }
}
