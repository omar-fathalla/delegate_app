import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

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
        String? existingPid;
        try {
          final existingByNat = await _firestore
              .collectionGroup('delegates')
              .where('nationalId', isEqualTo: cleanNationalId)
              .limit(1)
              .get();
          if (existingByNat.docs.isNotEmpty) {
            existingPid = existingByNat.docs.first.data()['delegatePublicId'] as String?;
          }
        } catch (_) {}

        final city = _extractCityFromNationalId(cleanNationalId);
        final birthDate = _extractBirthDateFromNationalId(cleanNationalId);
        final gender = _extractGenderFromNationalId(cleanNationalId);

        await _firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('delegates')
            .doc(requestId)
            .set({
          'uid': requestId,
          if (existingPid != null && existingPid.trim().isNotEmpty)
            'delegatePublicId': existingPid.trim(),
          'firstName': firstName,
          'secondName': secondName,
          'thirdName': thirdName,
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'nationalId': nationalId,
          'nationalityID': nationalId,
          if (city.isNotEmpty) 'city': city,
          if (birthDate != null) 'birthDate': Timestamp.fromDate(birthDate),
          if (gender != null && gender.isNotEmpty) 'gender': gender,
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
          'position': 'Promoter',
          'role': 'delegate',
          'registeredVia': 'mobile_app',
          'originOrganizationUID': organizationUID,
          'originOrganizationName': organizationName,
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
              'super_admin',
              'superAdmin',
              'technicalSupport',
              'technical-support',
              'technical_support',
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
  Future<Either<Failure, String>> submitAddOrganizationRequest({
    required String supervisorUid,
    required String supervisorName,
    required String supervisorPhone,
    required String companyUID,
    required String companyName,
    required String targetOrganizationUID,
    required String targetOrganizationName,
    required Delegate existingDelegate,
    required SubscriptionPaymentMethod paymentMethod,
    String? receiptCode,
    File? receiptImage,
    double? fee,
    int? remainingMonths,
  }) async {
    try {
      final docRef = _firestore.collection('delegate_requests').doc();
      final requestId = docRef.id;

      // 1. Upload Receipt Image (if provided)
      String? receiptUrl;
      if (receiptImage != null) {
        final receiptSnap = await _storage
            .ref('delegate_subscription_receipts/$requestId/receipt.jpg')
            .putFile(receiptImage);
        receiptUrl = await receiptSnap.ref.getDownloadURL();
      }

      // 2. Subscription cycle dates and prorated fee
      final cycleCode = SubscriptionCycleHelper.getCycleCode();
      final cycleStartDate = SubscriptionCycleHelper.getCycleStartDate();
      final cycleEndDate = SubscriptionCycleHelper.getCycleEndDate();
      final calculatedRemainingMonths =
          remainingMonths ?? SubscriptionCycleHelper.getRemainingMonthsInCycle();
      final calculatedFee =
          fee ?? SubscriptionCycleHelper.getProratedSubscriptionFee();

      // 3. Extract existing document URLs
      final profileUrl = existingDelegate.personalPhotoUrl ?? '';
      String frontUrl = '';
      String backUrl = '';
      for (final doc in existingDelegate.documents) {
        if (doc.documentKey == DocumentKey.nationalityId) {
          frontUrl = doc.documentURL;
          backUrl = doc.secondaryURL ?? '';
          break;
        }
      }

      final request = DelegateSubscriptionRequest(
        id: requestId,
        supervisorUid: supervisorUid,
        supervisorName: supervisorName,
        supervisorPhone: supervisorPhone,
        companyUID: companyUID,
        companyName: companyName,
        organizationUID: targetOrganizationUID,
        organizationName: targetOrganizationName,
        firstName: existingDelegate.firstName,
        secondName: existingDelegate.middleName,
        thirdName: existingDelegate.lastName,
        fullName: existingDelegate.fullName,
        phoneNumber: existingDelegate.phoneNumber,
        nationalId: existingDelegate.nationalityID,
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
        requestType: 'add_organization',
        existingDelegateUid: existingDelegate.uid,
        currentOrganizationName: existingDelegate.organizationName,
        createdAt: DateTime.now(),
      );

      // 4. Write request to Firestore
      await docRef.set(request.toMap());

      // 5. If branch electronic receipt, record code in used_receipt_codes
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
            'organizationUID': targetOrganizationUID,
            'organizationName': targetOrganizationName,
            'status': 'reserved',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }

      // 6. Send notifications to admins
      final notifTitle = 'طلب إضافة سلسلة جديدة لمندوب';
      final notifBody =
          'طلب المشرف $supervisorName ربط المندوب ${existingDelegate.fullName} بسلسلة $targetOrganizationName (${paymentMethod.displayName})';

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

      return Right(requestId);
    } catch (e) {
      return Left(ServerFailure('فشل إرسال طلب ربط المندوب بالمنظمة: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> submitDeleteDelegateRequest({
    required String supervisorUid,
    required String supervisorName,
    required String supervisorPhone,
    required Delegate delegate,
    required String reason,
  }) async {
    try {
      final now = DateTime.now();

      // 1. Check if a pending delete request already exists for this delegate
      final existingPending = await _firestore
          .collection('delegate_requests')
          .where('existingDelegateUid', isEqualTo: delegate.uid)
          .where('requestType', isEqualTo: 'delete_delegate')
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existingPending.docs.isNotEmpty) {
        return Left(ServerFailure(
          'يوجد طلب حذف معلق بالفعل لهذا المندوب وبانتظار موافقة الإدارة العليا.',
        ));
      }

      // 2. Create the delete request document in delegate_requests
      final docRef = _firestore.collection('delegate_requests').doc();
      final requestId = docRef.id;

      final requestData = {
        'id': requestId,
        'supervisorUid': supervisorUid,
        'supervisorName': supervisorName,
        'supervisorPhone': supervisorPhone,
        'companyUID': delegate.companyUID,
        'companyName': delegate.companyName,
        'organizationUID': delegate.organizationUID,
        'organizationName': delegate.organizationName,
        'firstName': delegate.firstName,
        'secondName': delegate.middleName,
        'thirdName': delegate.lastName,
        'fullName': delegate.fullName,
        'phoneNumber': delegate.phoneNumber,
        'nationalId': delegate.nationalityID,
        'profileImageUrl': delegate.personalPhotoUrl,
        'nationalIdFrontUrl': '',
        'nationalIdBackUrl': '',
        'paymentMethod': 'free_promotion',
        'subscriptionCycle': '',
        'cycleStartDate': now.toIso8601String(),
        'cycleEndDate': now.toIso8601String(),
        'fee': 0.0,
        'remainingMonths': 0,
        'status': 'pending',
        'requestType': 'delete_delegate',
        'existingDelegateUid': delegate.uid,
        'currentOrganizationName': delegate.organizationName,
        'rejectionReason': reason.trim(),
        'createdAt': now.toIso8601String(),
      };

      await docRef.set(requestData);

      // 3. Send notifications to Super Admin & Tech Support
      final notifTitle = 'طلب حذف مندوب جديد';
      final notifBody =
          'طلب المشرف $supervisorName حذف المندوب ${delegate.fullName} (${delegate.companyName})${reason.trim().isNotEmpty ? " - السبب: ${reason.trim()}" : ""}';

      for (final roleKey in ['super-admin', 'technicalSupport', 'role_super_admin', 'role_technical_support']) {
        await _firestore.collection('notifications').add({
          'delegateUid': roleKey,
          'title': notifTitle,
          'body': notifBody,
          'type': 'delegate_delete_request',
          'requestId': requestId,
          'senderName': supervisorName,
          'senderRole': 'supervisor',
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'targetRoles': ['superAdmin', 'technicalSupport'],
        });
      }

      return Right(requestId);
    } catch (e) {
      return Left(ServerFailure('فشل تقديم طلب حذف المندوب: $e'));
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

      // 1. Request status. For new_delegate / add_organization the approval is
      // written in the same WriteBatch as the delegate activation (r4 F2):
      // either both land or the request stays pending.
      final requestRef = _firestore.collection('delegate_requests').doc(request.id);
      final requestApproval = <String, dynamic>{
        'status': 'approved',
        'reviewedBy': reviewerName,
        'reviewedAt': now.toIso8601String(),
      };

      final targetDelegateUid = (request.existingDelegateUid != null &&
              request.existingDelegateUid!.trim().isNotEmpty)
          ? request.existingDelegateUid!.trim()
          : request.id;

      // Special handling for delete_delegate request
      if (request.requestType == 'delete_delegate') {
        await requestRef.update(requestApproval);
        // A. Delete from organizations subcollections
        if (request.companyUID.isNotEmpty) {
          final orgsSnap = await _firestore.collection('organizations').get();
          for (final orgDoc in orgsSnap.docs) {
            final delRef = _firestore
                .collection('organizations')
                .doc(orgDoc.id)
                .collection('companies')
                .doc(request.companyUID)
                .collection('delegates')
                .doc(targetDelegateUid);
            final check = await delRef.get();
            if (check.exists) {
              await delRef.delete();
            }
          }
        }

        // B. CollectionGroup query deletion to ensure no orphan doc exists
        try {
          final groupQuery = await _firestore
              .collectionGroup('delegates')
              .where('uid', isEqualTo: targetDelegateUid)
              .get();
          for (final doc in groupQuery.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}

        // C. Delete from users collection if role is delegate/promoter
        try {
          final userDoc = _firestore.collection('users').doc(targetDelegateUid);
          final uSnap = await userDoc.get();
          if (uSnap.exists) {
            final role = uSnap.data()?['role']?.toString().toLowerCase();
            if (role == 'delegate' || role == 'promoter' || role == null) {
              await userDoc.delete();
            }
          }
        } catch (_) {}

        // D. Delete active tracking session if any
        try {
          final trackingDoc =
              _firestore.collection('delegate_tracking').doc(targetDelegateUid);
          final tSnap = await trackingDoc.get();
          if (tSnap.exists) {
            final crumbs = await trackingDoc.collection('breadcrumbs').get();
            for (final c in crumbs.docs) {
              await c.reference.delete();
            }
            await trackingDoc.delete();
          }
        } catch (_) {}

        // E. Send notification to supervisor that the delete request was approved
        try {
          await _firestore.collection('notifications').add({
            'delegateUid': request.supervisorUid,
            'title': 'تمت الموافقة على حذف المندوب',
            'body':
                'تمت الموافقة على طلب حذف المندوب ${request.fullName} وحذفه نهائياً من المنظومة.',
            'type': 'delegate_deleted',
            'senderName': reviewerName,
            'senderRole': 'superAdmin',
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        } catch (_) {}

        // F. Clear delegates cache
        AdminDelegatesBloc.clearCache();

        return const Right(null);
      }

      final delegatePublicId = await _resolveOrAllocateDelegatePublicId(
        delegateUid: targetDelegateUid,
        nationalId: request.nationalId,
      );

      final city = _extractCityFromNationalId(request.nationalId);
      final birthDate = _extractBirthDateFromNationalId(request.nationalId);
      final gender = _extractGenderFromNationalId(request.nationalId);

      // 2. Update delegate record to active in company branch
      final delegateData = {
        'uid': targetDelegateUid,
        if (delegatePublicId.isNotEmpty) 'delegatePublicId': delegatePublicId,
        'firstName': request.firstName,
        'secondName': request.secondName,
        'thirdName': request.thirdName,
        'fullName': request.fullName,
        'phoneNumber': request.phoneNumber,
        'nationalId': request.nationalId,
        'nationalityID': request.nationalId,
        if (city.isNotEmpty) 'city': city,
        if (birthDate != null) 'birthDate': Timestamp.fromDate(birthDate),
        if (gender != null && gender.isNotEmpty) 'gender': gender,
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
        'position': 'Promoter',
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

      // 2c. Provision delegate record to active in company branch (target organization)
      final allKnownOrgs = <String>{
        request.organizationName.trim(),
        if (request.currentOrganizationName != null &&
            request.currentOrganizationName!.trim().isNotEmpty)
          request.currentOrganizationName!.trim(),
      }.where((s) => s.isNotEmpty).toList();

      final originOrgName = (request.currentOrganizationName != null &&
              request.currentOrganizationName!.trim().isNotEmpty)
          ? request.currentOrganizationName!.trim()
          : request.organizationName.trim();

      final smartPosition = formatSmartPosition(
        allOrgs: allKnownOrgs,
        currentOrgName: request.organizationName,
        originOrgName: originOrgName,
      );

      final isExternal = originOrgName.toLowerCase() != request.organizationName.toLowerCase();

      final targetDelegateData = Map<String, dynamic>.from(delegateData);
      targetDelegateData['position'] = smartPosition;
      targetDelegateData['originOrganizationName'] = originOrgName;
      targetDelegateData['isExternal'] = isExternal;
      targetDelegateData['registeredVia'] = 'mobile_app';
      if (allKnownOrgs.length > 1) {
        targetDelegateData['allOrganizationNames'] = allKnownOrgs;
      }

      targetDelegateData['approvedRequestId'] = request.id;

      final targetRef = _firestore
          .collection('organizations')
          .doc(request.organizationUID)
          .collection('companies')
          .doc(request.companyUID)
          .collection('delegates')
          .doc(targetDelegateUid);

      // Supervisor's own organization (2d for add_organization, 2e copy for
      // new_delegate). Read before the batch.
      String? supOrg;
      String supOrgName = '';
      try {
        final supDoc = await _firestore.collection('users').doc(request.supervisorUid).get();
        supOrg = supDoc.data()?['organizationUID'] as String?;
        supOrgName = supDoc.data()?['organizationName'] as String? ?? '';
      } catch (_) {}
      final hasSupOrg = supOrg != null && supOrg.isNotEmpty && supOrg != request.organizationUID;

      Map<String, dynamic>? supDelegateData;
      DocumentReference<Map<String, dynamic>>? supRef;
      if (request.requestType != 'add_organization' && hasSupOrg) {
        supDelegateData = Map<String, dynamic>.from(delegateData);
        supDelegateData['organizationUID'] = supOrg;
        if (supOrgName.isNotEmpty) {
          supDelegateData['organizationName'] = supOrgName;
        }
        supDelegateData['position'] = formatSmartPosition(
          allOrgs: allKnownOrgs,
          currentOrgName: supOrgName,
          originOrgName: originOrgName,
        );
        supDelegateData['originOrganizationName'] = originOrgName;
        supDelegateData['isExternal'] = originOrgName.toLowerCase() != supOrgName.toLowerCase();
        supDelegateData['registeredVia'] = 'mobile_app';
        if (allKnownOrgs.length > 1) {
          supDelegateData['allOrganizationNames'] = allKnownOrgs;
        }
        supDelegateData['approvedRequestId'] = request.id;
        supRef = _firestore
            .collection('organizations')
            .doc(supOrg)
            .collection('companies')
            .doc(request.companyUID)
            .collection('delegates')
            .doc(targetDelegateUid);
      }

      // 2c/2e. One WriteBatch (same for super-admin and technical support):
      // request -> approved, plus each delegate doc either created in full or,
      // if it already exists as 'pending', activated with a status-only write
      // (status + pending->approved document flips). Profile fields follow
      // after the commit as a plain merge.
      final batch = _firestore.batch();
      batch.update(requestRef, requestApproval);
      final followUps = <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};
      Future<void> addActivation(
        DocumentReference<Map<String, dynamic>> ref,
        Map<String, dynamic> fullData,
      ) async {
        final snap = await ref.get();
        if (!snap.exists) {
          batch.set(ref, fullData);
          return;
        }
        final existing = snap.data() ?? const <String, dynamic>{};
        if (existing['status'] == 'pending') {
          batch.update(ref, buildStatusOnlyActivation(
            existingDocuments: existing['documents'],
            reviewerName: reviewerName,
            reviewedAtIso: now.toIso8601String(),
            approvedRequestId: request.id,
          ));
          followUps[ref] = profileMergeFields(fullData);
        } else {
          batch.set(ref, fullData, SetOptions(merge: true));
        }
      }

      await addActivation(targetRef, targetDelegateData);
      if (supRef != null && supDelegateData != null) {
        await addActivation(supRef, supDelegateData);
      }
      await batch.commit();

      for (final e in followUps.entries) {
        try {
          await e.key.set(e.value, SetOptions(merge: true));
        } catch (_) {}
      }

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

      // 2d. If add_organization: ensure original organization document maintains its own organizationUID/Name and updates allOrganizationNames
      if (request.requestType == 'add_organization' && hasSupOrg) {
        try {
          final origSmartPos = formatSmartPosition(
            allOrgs: allKnownOrgs,
            currentOrgName: supOrgName.isNotEmpty ? supOrgName : request.currentOrganizationName,
            originOrgName: originOrgName,
          );
          await _firestore
              .collection('organizations')
              .doc(supOrg)
              .collection('companies')
              .doc(request.companyUID)
              .collection('delegates')
              .doc(targetDelegateUid)
              .update({
            'position': origSmartPos,
            'allOrganizationNames': FieldValue.arrayUnion([request.organizationName]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }

      // 3. Also ensure user record exists for mobile login with all organization names
      await _firestore.collection('users').doc(targetDelegateUid).set({
        'uid': targetDelegateUid,
        if (delegatePublicId.isNotEmpty) 'delegatePublicId': delegatePublicId,
        'fullName': request.fullName,
        'phoneNumber': request.phoneNumber,
        'phone': request.phoneNumber,
        'role': 'delegate',
        'organizationUID': request.organizationUID,
        'companyUID': request.companyUID,
        'organizationNames': FieldValue.arrayUnion(allKnownOrgs),
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3a. Sync delegatePublicId to any existing delegate records across other organizations
      if (delegatePublicId.isNotEmpty) {
        try {
          final groupQuery = await _firestore
              .collectionGroup('delegates')
              .where('uid', isEqualTo: targetDelegateUid)
              .get();
          for (final doc in groupQuery.docs) {
            final existingPid = doc.data()['delegatePublicId']?.toString().trim();
            if (existingPid == null || existingPid.isEmpty) {
              await doc.reference.set({
                'delegatePublicId': delegatePublicId,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
          }
        } catch (_) {}
      }

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

      // 4. Send notification to supervisor and delegate
      try {
        final isAddOrg = request.requestType == 'add_organization';
        await _firestore.collection('notifications').add({
          'delegateUid': request.supervisorUid,
          'title': isAddOrg
              ? 'تم اعتماد إضافة المندوب للسلسلة بنجاح'
              : 'تم اعتماد المندوب بنجاح',
          'body': isAddOrg
              ? 'تمت الموافقة على إضافة المندوب ${request.fullName} إلى ${request.organizationName}، وأصبح بإمكانه التبديل إليها وتسجيل حضوره.'
              : 'تمت الموافقة على اشتراك المندوب ${request.fullName} في ${request.organizationName}، وأصبح حسابه نشطاً الآن.',
          'type': 'subscription_approved',
          'senderName': 'الإدارة العامة',
          'senderRole': 'superAdmin',
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });

        if (isAddOrg) {
          // Notify the delegate directly
          await _firestore.collection('notifications').add({
            'delegateUid': targetDelegateUid,
            'title': 'تمت إضافتك لسلسلة ${request.organizationName}',
            'body':
                'تمت إضافة سلسلة ${request.organizationName} إلى حسابك بنجاح! يمكنك الآن التبديل إليها وتسجيل حضورك وانصرافك.',
            'type': 'organization_added',
            'senderName': 'الإدارة العامة',
            'senderRole': 'superAdmin',
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
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

      // 2. Update delegate doc status if exists (only for new delegate requests)
      if (request.requestType != 'delete_delegate') {
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
      }

      // 3. Send notification to supervisor
      final notifTitle = request.requestType == 'delete_delegate'
          ? 'تم رفض طلب حذف المندوب'
          : 'تم رفض طلب اشتراك المندوب';
      final notifBody = request.requestType == 'delete_delegate'
          ? 'تم رفض طلب حذف المندوب ${request.fullName}. السبب: $reason'
          : 'تم رفض طلب المندوب ${request.fullName}. السبب: $reason';

      await _firestore.collection('notifications').add({
        'delegateUid': request.supervisorUid,
        'title': notifTitle,
        'body': notifBody,
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

  /// Resolve an existing delegatePublicId across chains or allocate a new atomic sequence from /counters/delegates
  Future<String> _resolveOrAllocateDelegatePublicId({
    required String delegateUid,
    required String nationalId,
  }) async {
    final cleanNat = nationalId.trim();
    final cleanUid = delegateUid.trim();

    // 1. Check if delegate already has a delegatePublicId in any organization by UID
    if (cleanUid.isNotEmpty) {
      try {
        final uidSnap = await _firestore
            .collectionGroup('delegates')
            .where('uid', isEqualTo: cleanUid)
            .get();
        for (final doc in uidSnap.docs) {
          final pid = doc.data()['delegatePublicId']?.toString().trim();
          if (pid != null && pid.isNotEmpty) {
            return pid;
          }
        }
      } catch (_) {}
    }

    // 2. Check if delegate already has a delegatePublicId by national ID
    if (cleanNat.isNotEmpty) {
      try {
        final natSnap = await _firestore
            .collectionGroup('delegates')
            .where('nationalId', isEqualTo: cleanNat)
            .limit(5)
            .get();
        for (final doc in natSnap.docs) {
          final pid = doc.data()['delegatePublicId']?.toString().trim();
          if (pid != null && pid.isNotEmpty) {
            return pid;
          }
        }
      } catch (_) {}
    }

    // 3. Atomically allocate next counter from /counters/delegates
    try {
      final allocated = await _firestore.runTransaction<String>((transaction) async {
        final counterRef = _firestore.collection('counters').doc('delegates');
        final counterSnap = await transaction.get(counterRef);
        int currentCount = 6232;
        if (counterSnap.exists && counterSnap.data() != null) {
          currentCount = (counterSnap.data()!['count'] as num?)?.toInt() ?? 6232;
        }
        final nextCount = currentCount + 1;
        transaction.set(counterRef, {'count': nextCount}, SetOptions(merge: true));
        return 'DEL-$nextCount';
      });
      return allocated;
    } catch (e) {
      debugPrint('Error allocating delegatePublicId: $e');
      return '';
    }
  }

  static String _extractCityFromNationalId(String nationalId) {
    final clean = nationalId.trim();
    if (clean.length == 14 && RegExp(r'^\d+$').hasMatch(clean)) {
      final code = clean.substring(7, 9);
      const govMap = {
        '01': 'القاهرة',
        '02': 'الإسكندرية',
        '03': 'بورسعيد',
        '04': 'السويس',
        '11': 'دمياط',
        '12': 'الدقهلية',
        '13': 'الشرقية',
        '14': 'القليوبية',
        '15': 'كفر الشيخ',
        '16': 'الغربية',
        '17': 'المنوفية',
        '18': 'البحيرة',
        '19': 'الإسماعيلية',
        '21': 'الجيزة',
        '22': 'بني سويف',
        '23': 'الفيوم',
        '24': 'المنيا',
        '25': 'أسيوط',
        '26': 'سوهاج',
        '27': 'قنا',
        '28': 'أسوان',
        '29': 'الأقصر',
        '31': 'البحر الأحمر',
        '32': 'الوادي الجديد',
        '33': 'مطروح',
        '34': 'شمال سيناء',
        '35': 'جنوب سيناء',
        '88': 'خارج الجمهورية',
      };
      return govMap[code] ?? '';
    }
    return '';
  }

  static DateTime? _extractBirthDateFromNationalId(String nationalId) {
    final clean = nationalId.trim();
    if (clean.length == 14 && RegExp(r'^\d+$').hasMatch(clean)) {
      final century = clean[0] == '2' ? 1900 : (clean[0] == '3' ? 2000 : null);
      if (century != null) {
        final year = century + int.parse(clean.substring(1, 3));
        final month = int.parse(clean.substring(3, 5));
        final day = int.parse(clean.substring(5, 7));
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          return DateTime(year, month, day);
        }
      }
    }
    return null;
  }

  static String? _extractGenderFromNationalId(String nationalId) {
    final clean = nationalId.trim();
    if (clean.length == 14 && RegExp(r'^\d+$').hasMatch(clean)) {
      final digit = int.tryParse(clean[12]);
      if (digit != null) {
        return digit % 2 == 0 ? 'female' : 'male';
      }
    }
    return null;
  }

  /// Generates a clean, concise, single-line position label for web and mobile tables
  /// dynamically indicating secondary chains or count of other chains without cluttering
  static String formatSmartPosition({
    required List<String> allOrgs,
    String? currentOrgName,
    String? originOrgName,
    String basePosition = 'Promoter',
  }) {
    if (allOrgs.isEmpty) return basePosition;

    final uniqueOrgs = allOrgs
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toSet()
        .toList();

    if (uniqueOrgs.isEmpty) return basePosition;

    final cur = currentOrgName?.trim().toLowerCase();
    final origin = (originOrgName != null && originOrgName.trim().isNotEmpty)
        ? originOrgName.trim()
        : uniqueOrgs.first;
    final originLower = origin.toLowerCase();

    // 1. Only 1 organization
    if (uniqueOrgs.length == 1) {
      if (cur != null && cur.isNotEmpty && uniqueOrgs.first.toLowerCase() != cur) {
        return '$basePosition (${uniqueOrgs.first})';
      }
      return basePosition;
    }

    // 2. Exactly 2 organizations
    if (uniqueOrgs.length == 2) {
      if (cur != null && cur.isNotEmpty) {
        final otherOrg = uniqueOrgs.firstWhere(
          (o) => o.toLowerCase() != cur,
          orElse: () => uniqueOrgs.first,
        );
        return '$basePosition ($otherOrg)';
      }
      return '$basePosition (${uniqueOrgs[0]}، ${uniqueOrgs[1]})';
    }

    // 3. 3 or more organizations (e.g. 5 or 6 chains)
    if (cur != null && cur.isNotEmpty && cur == originLower) {
      return '$basePosition (مشترك - ${uniqueOrgs.length} سلاسل)';
    } else {
      final otherCount = uniqueOrgs.length - 1;
      return '$basePosition ($origin + $otherCount سلاسل)';
    }
  }
}

/// r4 F4: status-only activation payload for an existing 'pending' delegate
/// doc. Same list size and order; each 'pending' entry flips to 'approved'
/// with only documentStatus / reviewedBy / reviewedAt changed.
@visibleForTesting
Map<String, dynamic> buildStatusOnlyActivation({
  required dynamic existingDocuments,
  required String reviewerName,
  required String reviewedAtIso,
  required String approvedRequestId,
}) {
  final out = <String, dynamic>{
    'status': 'active',
    'reviewedBy': reviewerName,
    'reviewedAt': reviewedAtIso,
    'approvedRequestId': approvedRequestId,
    'updatedAt': FieldValue.serverTimestamp(),
  };
  if (existingDocuments is List) {
    out['documents'] = existingDocuments.map((e) {
      if (e is Map && e['documentStatus'] == 'pending') {
        return <String, dynamic>{
          ...Map<String, dynamic>.from(e),
          'documentStatus': 'approved',
          'reviewedBy': reviewerName,
          'reviewedAt': reviewedAtIso,
        };
      }
      return e;
    }).toList();
  }
  return out;
}

/// Profile / subscription fields written after the approval batch commits.
/// Never status, documents, the request binding, or document URLs.
@visibleForTesting
Map<String, dynamic> profileMergeFields(Map<String, dynamic> full) {
  const excluded = {
    'status', 'documents', 'approvedRequestId', 'profileImageUrl',
    'personalPhotoURL', 'photoURL', 'nationalIdFrontUrl', 'nationalIdBackUrl',
    'receiptImageUrl',
  };
  return Map<String, dynamic>.from(full)..removeWhere((k, _) => excluded.contains(k));
}

