import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';

abstract class AdminRemoteDataSource {
  Future<List<BranchModel>> getBranches();
  Future<BranchModel> addBranch(BranchModel branch);
  Future<BranchModel> updateBranch(BranchModel branch);
  Future<void> deleteBranch(String branchId);
}

class AdminRemoteDataSourceImpl implements AdminRemoteDataSource {
  final FirebaseFirestore firestore;

  AdminRemoteDataSourceImpl({required this.firestore});

  CollectionReference get _branches => firestore.collection('branches');

  @override
  Future<List<BranchModel>> getBranches() async {
    try {
      final snapshot = await _branches.get();
      return snapshot.docs
          .map((doc) => BranchModel.fromFirestore(doc))
          .toList();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب بيانات الفروع.');
    }
  }

  @override
  Future<BranchModel> addBranch(BranchModel branch) async {
    try {
      final ref = await _branches.add(branch.toMap());
      return BranchModel(
        id: ref.id,
        branchName: branch.branchName,
        latitude: branch.latitude,
        longitude: branch.longitude,
        geofenceRadius: branch.geofenceRadius,
      );
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في إضافة الفرع.');
    }
  }

  @override
  Future<BranchModel> updateBranch(BranchModel branch) async {
    try {
      await _branches.doc(branch.id).update(branch.toMap());
      return branch;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تحديث بيانات الفرع.');
    }
  }

  @override
  Future<void> deleteBranch(String branchId) async {
    try {
      await _branches.doc(branchId).delete();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حذف الفرع.');
    }
  }
}
