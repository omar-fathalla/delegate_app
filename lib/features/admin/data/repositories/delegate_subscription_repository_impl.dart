import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';

class DelegateSubscriptionRepositoryImpl implements DelegateSubscriptionRepository {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  DelegateSubscriptionRepositoryImpl({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<Either<Failure, String>> submitSubscriptionRequest({
    required String supervisorUid,
    required String supervisorName,
    required String supervisorPhone,
    required String companyUID,
    required String companyName,
    required String organizationUID,
    required String organizationName,
    required String firstName,
    required String secondName,
    required String thirdName,
    required String phoneNumber,
    required String nationalId,
    required File profileImage,
    required File nationalIdFront,
    required File nationalIdBack,
    required SubscriptionPaymentMethod paymentMethod,
    String? receiptCode,
    File? receiptImage,
    double? fee,
    int? remainingMonths,
  }) async {
    try {
      final docRef = _firestore.collection('delegate_requests').doc();
      final requestId = docRef.id;

      // 0. Duplicate prevention: Check if a request already exists with the same nationalId or phoneNumber
      final cleanNationalId = nationalId.trim();
      final cleanPhone = phoneNumber.trim();

      // Check existing requests with same national ID
      final existingById = await _firestore
          .collection('delegate_requests')
          .where('nationalId', isEqualTo: cleanNationalId)
          .get();

      for (final doc in existingById.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (status == 'pending') {
          return const Left(ServerFailure(
            'يوجد طلب تسجيل معلق بالفعل لهذا المندوب بنفس الرقم القومي، بانتظار مراجعة واعتماد الإدارة.',
          ));
        } else if (status == 'approved') {
          return const Left(ServerFailure(
            'هذا المندوب مسجل ومعتمد بالفعل في النظام بنفس الرقم القومي.',
          ));
        }
      }

      // Check existing requests with same phone number
      final existingByPhone = await _firestore
          .collection('delegate_requests')
          .where('phoneNumber', isEqualTo: cleanPhone)
          .get();

      for (final doc in existingByPhone.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (status == 'pending') {
          return Left(ServerFailure(
            'يوجد طلب تسجيل معلق بالفعل مسجل برقم الهاتف ($cleanPhone)، بانتظار مراجعة واعتماد الإدارة.',
          ));
        } else if (status == 'approved') {
          return Left(ServerFailure(
            'رقم الهاتف ($cleanPhone) مسجل بالفعل لمندوب معتمد في النظام.',
          ));
        }
      }

      // Check if phone number already belongs to an existing active delegate
      try {
        final existingDelegateByPhone = await _firestore
            .collectionGroup('delegates')
            .where('phoneNumber', isEqualTo: cleanPhone)
            .limit(1)
            .get();
        if (existingDelegateByPhone.docs.isNotEmpty) {
          final delData = existingDelegateByPhone.docs.first.data();
          if (delData['status'] != 'inactive') {
            return Left(ServerFailure(
              'رقم الهاتف ($cleanPhone) مسجل ومستخدم بالفعل لمندوب حالي في النظام.',
            ));
          }
        }
      } catch (_) {
        // Fallback gracefully if collectionGroup rules restrict supervisor access
      }

      // 0b. Payment method & receipt validation
      if (paymentMethod == SubscriptionPaymentMethod.branchReceipt) {
        final cleanCode = (receiptCode ?? '').trim();
        if (cleanCode.length != 5) {
          return const Left(ServerFailure('كود الإيصال الخماسي مطلوب ويجب أن يتكون من 5 أرقام بالضبط.'));
        }
        if (receiptImage == null) {
          return const Left(ServerFailure('يرجى إرفاق صورة الإيصال الإلكتروني الصادر من تسويق الفرع.'));
        }
        final checkUsed = await isReceiptCodeUsed(cleanCode);
        final isUsed = checkUsed.fold((_) => false, (used) => used);
        if (isUsed) {
          return Left(ServerFailure(
            'كود الإيصال الخماسي ($cleanCode) مستخدم مسبقاً في النظام ولا يمكن تكراره.',
          ));
        }
      } else if (paymentMethod == SubscriptionPaymentMethod.instaPay) {
        if (receiptImage == null) {
          return const Left(ServerFailure('يرجى إرفاق صورة إيصال التحويل أو إشعار الدفع من تطبيق انستاباي.'));
        }
      }

      // 1. Upload Profile Image
      final profileSnap = await _storage
          .ref('delegate_documents/$requestId/profile.jpg')
          .putFile(profileImage);
      final profileUrl = await profileSnap.ref.getDownloadURL();

      // 2. Upload National ID Front
      final frontSnap = await _storage
          .ref('delegate_documents/$requestId/national_id_front.jpg')
          .putFile(nationalIdFront);
      final frontUrl = await frontSnap.ref.getDownloadURL();

      // 3. Upload National ID Back
      final backSnap = await _storage
          .ref('delegate_documents/$requestId/national_id_back.jpg')
          .putFile(nationalIdBack);
      final backUrl = await backSnap.ref.getDownloadURL();

      // 4. Upload Receipt Image (if provided)
      String? receiptUrl;
      if (receiptImage != null) {
        final receiptSnap = await _storage
            .ref('delegate_subscription_receipts/$requestId/receipt.jpg')
            .putFile(receiptImage);
        receiptUrl = await receiptSnap.ref.getDownloadURL();
      }

      // 5. Subscription cycle dates and prorated fee
      final cycleCode = SubscriptionCycleHelper.getCycleCode();
      final cycleStartDate = SubscriptionCycleHelper.getCycleStartDate();
      final cycleEndDate = SubscriptionCycleHelper.getCycleEndDate();
      final calculatedRemainingMonths =
          remainingMonths ?? SubscriptionCycleHelper.getRemainingMonthsInCycle();
      final calculatedFee =
          fee ?? SubscriptionCycleHelper.getProratedSubscriptionFee();

      final fullName = '$firstName $secondName $thirdName'.trim();

      final request = DelegateSubscriptionRequest(
        id: requestId,
        supervisorUid: supervisorUid,
        supervisorName: supervisorName,
        supervisorPhone: supervisorPhone,
        companyUID: companyUID,
        companyName: companyName,
        organizationUID: organizationUID,
        organizationName: organizationName,
        firstName: firstName,
        secondName: secondName,
        thirdName: thirdName,
        fullName: fullName,
        phoneNumber: phoneNumber,
        nationalId: nationalId,
        profileImageUrl: profileUrl,
        nationalIdFrontUrl: frontUrl,
        nationalIdBackUrl: backUrl,
        paymentMethod: paymentMethod,
        receiptCode: receiptCode,
        receiptImageUrl: receiptUrl,
        subscriptionCycle: cycleCode,
        cycleStartDate: cycleStartDate,
        cycleEndDate: cycleEndDate,
        fee: calculatedFee,
        remainingMonths: calculatedRemainingMonths,
        status: SubscriptionRequestStatus.pending,
        createdAt: DateTime.now(),
      );

      // 6. Write request to Firestore
      await docRef.set(request.toMap());

      // 6b. If branch electronic receipt, record code in used_receipt_codes
      if (paymentMethod == SubscriptionPaymentMethod.branchReceipt &&
          receiptCode != null &&
          receiptCode.trim().isNotEmpty) {
        try {
          await _firestore.collection('used_receipt_codes').doc(receiptCode.trim()).set({
            'receiptCode': receiptCode.trim(),
            'requestId': requestId,
            'supervisorUid': supervisorUid,
            'supervisorName': supervisorName,
            'companyUID': companyUID,
            'companyName': companyName,
            'organizationUID': organizationUID,
            'organizationName': organizationName,
            'status': 'reserved',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }

      // 7. Create pending delegate placeholder if permissions permit
      try {
        await _firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('delegates')
            .doc(requestId)
            .set({
          'uid': requestId,
          'firstName': firstName,
          'secondName': secondName,
          'thirdName': thirdName,
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'nationalId': nationalId,
          'nationalityID': nationalId,
          'organizationUID': organizationUID,
          'organizationName': organizationName,
          'companyUID': companyUID,
          'companyName': companyName,
          'profileImageUrl': profileUrl,
          'nationalIdFrontUrl': frontUrl,
          'nationalIdBackUrl': backUrl,
          'documents': [
            {
              'documentKey': 'personalPhoto',
              'documentStatus': 'pending',
              'documentURL': profileUrl,
              'uploadedAt': DateTime.now().toIso8601String(),
            },
            {
              'documentKey': 'nationalityId',
              'documentStatus': 'pending',
              'documentURL': frontUrl,
              'secondaryURL': backUrl,
              'uploadedAt': DateTime.now().toIso8601String(),
            },
            if (receiptUrl != null && receiptUrl.isNotEmpty)
              {
                'documentKey': 'paymentReceipt',
                'documentStatus': 'pending',
                'documentURL': receiptUrl,
                'receiptCode': receiptCode,
                'uploadedAt': DateTime.now().toIso8601String(),
              },
          ],
          'status': 'pending',
          'position': 'promoter',
          'role': 'delegate',
          'isDeductedFromCompany':
              paymentMethod == SubscriptionPaymentMethod.companyDeduction,
          'receiptCode': receiptCode,
          'subscriptionCycle': cycleCode,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Cross-organization submission: The supervisor has submitted the request to delegate_requests,
        // and the actual delegate document will be officially provisioned upon approval by Super Admin/Tech Support.
      }

      // 8. Notify Technical Support and Super Admins ONLY (Restricted Targeting)
      final notifTitle = 'طلب إضافة مندوب جديد';
      final notifBody =
          'قام المشرف $supervisorName ($companyName) بطلب تسجيل المندوب $fullName لمنظمة $organizationName';

      try {
        final targetUsersSnap = await _firestore
            .collection('users')
            .where('role', whereIn: [
              'super-admin',
              'superAdmin',
              'technicalSupport',
              'technical-support',
            ])
            .get();

        final batch = _firestore.batch();

        // 1. Direct notifications to individual Super Admin and Tech Support users
        for (final doc in targetUsersSnap.docs) {
          final data = doc.data();
          final phone = (data['phoneNumber'] ?? data['phone'])?.toString();
          final ref = _firestore.collection('notifications').doc();
          batch.set(ref, {
            'delegateUid': doc.id,
            if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
            'title': notifTitle,
            'body': notifBody,
            'type': 'delegate_subscription_request',
            'requestId': requestId,
            'senderName': supervisorName,
            'senderRole': 'supervisor',
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
            'targetRoles': ['superAdmin', 'technicalSupport'],
          });
        }

        // 2. Role-based fallback notifications for session logins (e.g. super-admin-login)
        for (final roleKey in [
          'super-admin',
          'superAdmin',
          'role_super_admin',
          'technicalSupport',
          'technical-support',
          'role_technical_support',
        ]) {
          final ref = _firestore.collection('notifications').doc();
          batch.set(ref, {
            'delegateUid': roleKey,
            'title': notifTitle,
            'body': notifBody,
            'type': 'delegate_subscription_request',
            'requestId': requestId,
            'senderName': supervisorName,
            'senderRole': 'supervisor',
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
            'targetRoles': ['superAdmin', 'technicalSupport'],
          });
        }

        await batch.commit();
      } catch (e) {
        // Fallback: write role-targeted notifications
        for (final roleKey in ['super-admin', 'technicalSupport', 'role_super_admin', 'role_technical_support']) {
          await _firestore.collection('notifications').add({
            'delegateUid': roleKey,
            'title': notifTitle,
            'body': notifBody,
            'type': 'delegate_subscription_request',
            'requestId': requestId,
            'senderName': supervisorName,
            'senderRole': 'supervisor',
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
            'targetRoles': ['superAdmin', 'technicalSupport'],
          });
        }
      }

      return Right(requestId);
    } catch (e) {
      return Left(ServerFailure('فشل إرسال طلب تسجيل المندوب: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> isReceiptCodeUsed(String receiptCode) async {
    try {
      final cleanCode = receiptCode.trim();
      if (cleanCode.length != 5) {
        return const Right(false);
      }

      // 1. Check used_receipt_codes collection (O(1) doc get)
      try {
        final usedDoc = await _firestore.collection('used_receipt_codes').doc(cleanCode).get();
        if (usedDoc.exists) {
          final data = usedDoc.data();
          if (data?['status'] != 'rejected') {
            return const Right(true);
          }
        }
      } catch (_) {}

      // 2. Check delegate_requests where receiptCode == cleanCode and status != 'rejected'
      try {
        final reqSnap = await _firestore
            .collection('delegate_requests')
            .where('receiptCode', isEqualTo: cleanCode)
            .get();
        for (final doc in reqSnap.docs) {
          final status = doc.data()['status'] as String?;
          if (status != 'rejected') {
            return const Right(true);
          }
        }
      } catch (_) {}

      // 3. Check collectionGroup('delegates') where receiptCode == cleanCode
      try {
        final delSnap = await _firestore
            .collectionGroup('delegates')
            .where('receiptCode', isEqualTo: cleanCode)
            .limit(1)
            .get();
        if (delSnap.docs.isNotEmpty) {
          return const Right(true);
        }
      } catch (_) {}

      return const Right(false);
    } catch (e) {
      return Left(ServerFailure('تعذر التحقق من كود الإيصال: $e'));
    }
  }

  @override
  Stream<List<DelegateSubscriptionRequest>> getSubscriptionRequestsStream({
    SubscriptionRequestStatus? statusFilter,
    String? organizationUID,
    String? companyUID,
  }) {
    Query query = _firestore.collection('delegate_requests');

    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter.name);
    }
    if (organizationUID != null && organizationUID.isNotEmpty) {
      query = query.where('organizationUID', isEqualTo: organizationUID);
    }
    if (companyUID != null && companyUID.isNotEmpty) {
      query = query.where('companyUID', isEqualTo: companyUID);
    }

    return query.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) {
        return DelegateSubscriptionRequest.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();

      // Sort client-side by createdAt descending (newest first)
      // to avoid requiring composite indexes in Firestore
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  @override
  Future<Either<Failure, void>> approveSubscriptionRequest({
    required DelegateSubscriptionRequest request,
    required String reviewerUid,
    required String reviewerName,
  }) async {
    try {
      final now = DateTime.now();

      // 1. Update Request status
      await _firestore.collection('delegate_requests').doc(request.id).update({
        'status': 'approved',
        'reviewedBy': reviewerName,
        'reviewedAt': now.toIso8601String(),
      });

      // 2. Update delegate record to active in company branch
      final delegateData = {
        'uid': request.id,
        'firstName': request.firstName,
        'secondName': request.secondName,
        'thirdName': request.thirdName,
        'fullName': request.fullName,
        'phoneNumber': request.phoneNumber,
        'nationalId': request.nationalId,
        'nationalityID': request.nationalId,
        'organizationUID': request.organizationUID,
        'organizationName': request.organizationName,
        'companyUID': request.companyUID,
        'companyName': request.companyName,
        'profileImageUrl': request.profileImageUrl,
        'nationalIdFrontUrl': request.nationalIdFrontUrl,
        'nationalIdBackUrl': request.nationalIdBackUrl,
        'documents': [
          if (request.profileImageUrl.isNotEmpty)
            {
              'documentKey': 'personalPhoto',
              'documentStatus': 'approved',
              'documentURL': request.profileImageUrl,
              'uploadedAt': now.toIso8601String(),
            },
          if (request.nationalIdFrontUrl.isNotEmpty ||
              request.nationalIdBackUrl.isNotEmpty)
            {
              'documentKey': 'nationalityId',
              'documentStatus': 'approved',
              'documentURL': request.nationalIdFrontUrl,
              'secondaryURL': request.nationalIdBackUrl,
              'uploadedAt': now.toIso8601String(),
            },
          if (request.receiptImageUrl != null &&
              request.receiptImageUrl!.isNotEmpty)
            {
              'documentKey': 'paymentReceipt',
              'documentStatus': 'approved',
              'documentURL': request.receiptImageUrl,
              'receiptCode': request.receiptCode,
              'uploadedAt': now.toIso8601String(),
            },
        ],
        'status': 'active',
        'position': 'promoter',
        'role': 'delegate',
        'isDeductedFromCompany':
            request.paymentMethod == SubscriptionPaymentMethod.companyDeduction,
        'receiptCode': request.receiptCode,
        'subscription': {
          'cycle': request.subscriptionCycle,
          'startDate': request.cycleStartDate.toIso8601String(),
          'endDate': request.cycleEndDate.toIso8601String(),
          'isPaid': true,
          'paymentMethod': request.paymentMethod.name,
          'approvedBy': reviewerName,
          'approvedAt': now.toIso8601String(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 2a. Ensure the company exists under the target organization
      try {
        await _firestore
            .collection('organizations')
            .doc(request.organizationUID)
            .collection('companies')
            .doc(request.companyUID)
            .set({
          'id': request.companyUID,
          'uid': request.companyUID,
          'name': request.companyName,
          'organizationUID': request.organizationUID,
          'organizationName': request.organizationName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        // Log non-blocking auxiliary error
      }

      // 2b. Ensure the supervisor is linked as admin of this company under the target organization
      try {
        await _firestore
            .collection('organizations')
            .doc(request.organizationUID)
            .collection('companies')
            .doc(request.companyUID)
            .collection('admins')
            .doc(request.supervisorUid)
            .set({
          'uid': request.supervisorUid,
          'name': request.supervisorName,
          'phone': request.supervisorPhone,
          'role': 'company-admin',
          'companyUID': request.companyUID,
          'companyName': request.companyName,
          'organizationUID': request.organizationUID,
          'organizationName': request.organizationName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        // Log non-blocking auxiliary error
      }

      // 2c. Provision delegate record to active in company branch (target organization)
      await _firestore
          .collection('organizations')
          .doc(request.organizationUID)
          .collection('companies')
          .doc(request.companyUID)
          .collection('delegates')
          .doc(request.id)
          .set(delegateData, SetOptions(merge: true));

      // 2d. If supervisor belongs to a different primary organization, also provision in supervisor's branch
      try {
        final supDoc = await _firestore.collection('users').doc(request.supervisorUid).get();
        final supOrg = supDoc.data()?['organizationUID'] as String?;
        if (supOrg != null && supOrg.isNotEmpty && supOrg != request.organizationUID) {
          await _firestore
              .collection('organizations')
              .doc(supOrg)
              .collection('companies')
              .doc(request.companyUID)
              .collection('delegates')
              .doc(request.id)
              .set(delegateData, SetOptions(merge: true));
        }
      } catch (_) {}

      // 3. Also ensure user record exists for mobile login
      await _firestore.collection('users').doc(request.id).set({
        'uid': request.id,
        'fullName': request.fullName,
        'phoneNumber': request.phoneNumber,
        'phone': request.phoneNumber,
        'role': 'delegate',
        'organizationUID': request.organizationUID,
        'companyUID': request.companyUID,
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3b. Update used_receipt_codes if branch receipt
      if (request.receiptCode != null && request.receiptCode!.trim().isNotEmpty) {
        try {
          await _firestore.collection('used_receipt_codes').doc(request.receiptCode!.trim()).set({
            'status': 'approved',
            'approvedAt': FieldValue.serverTimestamp(),
            'approvedBy': reviewerName,
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      // 4. Send notification to supervisor
      try {
        await _firestore.collection('notifications').add({
          'delegateUid': request.supervisorUid,
          'title': 'تم اعتماد المندوب بنجاح',
          'body':
              'تمت الموافقة على اشتراك المندوب ${request.fullName} في ${request.organizationName}، وأصبح حسابه نشطاً الآن.',
          'type': 'subscription_approved',
          'senderName': 'الإدارة العامة',
          'senderRole': 'superAdmin',
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      } catch (e) {
        // Log non-blocking auxiliary error
      }

      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('فشل اعتماد طلب المندوب: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> rejectSubscriptionRequest({
    required DelegateSubscriptionRequest request,
    required String reason,
    required String reviewerUid,
    required String reviewerName,
  }) async {
    try {
      final now = DateTime.now();

      // 1. Update request status to rejected
      await _firestore.collection('delegate_requests').doc(request.id).update({
        'status': 'rejected',
        'rejectionReason': reason,
        'reviewedBy': reviewerName,
        'reviewedAt': now.toIso8601String(),
      });

      // 2. Update delegate doc status if exists
      try {
        await _firestore
            .collection('organizations')
            .doc(request.organizationUID)
            .collection('companies')
            .doc(request.companyUID)
            .collection('delegates')
            .doc(request.id)
            .set({
          'status': 'rejected',
          'statusReason': reason,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

      // 3. Send notification to supervisor
      await _firestore.collection('notifications').add({
        'delegateUid': request.supervisorUid,
        'title': 'تم رفض طلب اشتراك المندوب',
        'body': 'تم رفض طلب المندوب ${request.fullName}. السبب: $reason',
        'type': 'subscription_rejected',
        'senderName': reviewerName,
        'senderRole': 'superAdmin',
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // 4. Release used receipt code so it can be corrected or reused
      if (request.receiptCode != null && request.receiptCode!.trim().isNotEmpty) {
        try {
          await _firestore.collection('used_receipt_codes').doc(request.receiptCode!.trim()).delete();
        } catch (_) {}
      }

      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('فشل رفض الطلب: $e'));
    }
  }
}
