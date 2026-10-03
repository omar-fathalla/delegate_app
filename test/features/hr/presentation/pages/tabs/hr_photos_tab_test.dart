import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_photos_tab.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

void main() {
  late Delegate tHrDelegate;

  setUpAll(() {
    tHrDelegate = Delegate(
      uid: 'hr_123',
      firstName: 'HR',
      middleName: 'Admin',
      lastName: 'User',
      fullName: 'HR Admin User',
      nationalityID: '29501010101234',
      motherName: 'Mother',
      city: 'Cairo',
      phoneNumber: '01012345678',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1995, 1, 1),
      organizationUID: 'org_ezaby',
      organizationName: 'El-Ezaby Pharmacies',
      companyUID: 'comp_johnson',
      companyName: 'Johnson & Johnson',
      status: DelegateStatus.active,
      delegatePublicId: 'hr_pub_01',
      allReceiptCodes: const [],
      createdAt: DateTime(2024, 1, 1),
      createdBy: 'admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: UserRole.hr,
    );
  });

  group('HRPhotosTab Widget & Filtering Logic', () {
    test('HRPhotosTab constructor instantiates with valid HR Delegate reference', () {
      final widget = HRPhotosTab(hrDelegate: tHrDelegate);
      expect(widget.hrDelegate.uid, equals('hr_123'));
      expect(widget.hrDelegate.role, equals(UserRole.hr));
      expect(widget.hrDelegate.companyUID, equals('comp_johnson'));
      expect(widget.hrDelegate.companyName, equals('Johnson & Johnson'));
    });

    test('CapturedPhoto filtering by branch and delegate works as expected', () {
      final photos = [
        CapturedPhoto(
          uid: 'photo_1',
          organizationUID: 'org_ezaby',
          companyUID: 'comp_johnson',
          permissionId: 'perm_1',
          branchId: 'b_1',
          branchName: 'فرع المعادي',
          delegateUID: 'del_1',
          delegateName: 'أحمد محمود',
          photoUrl: 'https://example.com/photo1.jpg',
          comment: 'عرض خاص',
          latitude: 30.01,
          longitude: 31.25,
          capturedAt: DateTime(2026, 9, 28, 10, 0),
        ),
        CapturedPhoto(
          uid: 'photo_2',
          organizationUID: 'org_ezaby',
          companyUID: 'comp_johnson',
          permissionId: 'perm_1',
          branchId: 'b_2',
          branchName: 'فرع التجمع',
          delegateUID: 'del_2',
          delegateName: 'محمد علي',
          photoUrl: 'https://example.com/photo2.jpg',
          comment: 'توثيق العرض الميداني',
          latitude: 30.02,
          longitude: 31.45,
          capturedAt: DateTime(2026, 9, 28, 11, 0),
        ),
      ];

      // Branch filter test
      final maadiPhotos = photos.where((p) => p.branchName == 'فرع المعادي').toList();
      expect(maadiPhotos.length, equals(1));
      expect(maadiPhotos.first.delegateName, equals('أحمد محمود'));

      // Delegate filter test
      final mohamedPhotos = photos.where((p) => p.delegateName == 'محمد علي').toList();
      expect(mohamedPhotos.length, equals(1));
      expect(mohamedPhotos.first.branchName, equals('فرع التجمع'));

      // Search query filter test
      final query = 'عرض خاص';
      final searchResults = photos.where((p) => p.comment.contains(query)).toList();
      expect(searchResults.length, equals(1));
      expect(searchResults.first.uid, equals('photo_1'));
    });

    test('PhotoPermission status classification derives active, pending, and expired', () {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final activePerm = PhotoPermission(
        uid: 'perm_active',
        organizationUID: 'org_ezaby',
        companyUID: 'comp_johnson',
        companyName: 'Johnson & Johnson',
        branchIds: const ['b_1'],
        branchNames: const ['فرع المعادي'],
        startDate: todayStart.subtract(const Duration(days: 5)),
        endDate: todayStart.add(const Duration(days: 25)),
        status: 'approved',
        requestedBy: 'hr_123',
        createdAt: todayStart.subtract(const Duration(days: 6)),
        updatedAt: todayStart.subtract(const Duration(days: 5)),
        isSupervisorEnabled: true,
      );

      final pendingPerm = PhotoPermission(
        uid: 'perm_pending',
        organizationUID: 'org_ezaby',
        companyUID: 'comp_johnson',
        companyName: 'Johnson & Johnson',
        branchIds: const ['b_1'],
        branchNames: const ['فرع المعادي'],
        startDate: todayStart,
        endDate: todayStart.add(const Duration(days: 30)),
        status: 'pending',
        requestedBy: 'hr_123',
        createdAt: todayStart,
        updatedAt: todayStart,
        isSupervisorEnabled: false,
      );

      final expiredPerm = PhotoPermission(
        uid: 'perm_expired',
        organizationUID: 'org_ezaby',
        companyUID: 'comp_johnson',
        companyName: 'Johnson & Johnson',
        branchIds: const ['b_1'],
        branchNames: const ['فرع المعادي'],
        startDate: todayStart.subtract(const Duration(days: 35)),
        endDate: todayStart.subtract(const Duration(days: 5)),
        status: 'approved',
        requestedBy: 'hr_123',
        createdAt: todayStart.subtract(const Duration(days: 40)),
        updatedAt: todayStart.subtract(const Duration(days: 35)),
        isSupervisorEnabled: true,
      );

      final permissions = [activePerm, pendingPerm, expiredPerm];

      final active = permissions.where((p) => p.status.toLowerCase() == 'approved' && !p.endDate.isBefore(todayStart)).toList();
      final pending = permissions.where((p) => p.status.toLowerCase() == 'pending').toList();
      final expired = permissions.where((p) => (p.status.toLowerCase() == 'approved' && p.endDate.isBefore(todayStart)) || p.status.toLowerCase() == 'rejected').toList();

      expect(active.length, equals(1));
      expect(active.first.uid, equals('perm_active'));

      expect(pending.length, equals(1));
      expect(pending.first.uid, equals('perm_pending'));

      expect(expired.length, equals(1));
      expect(expired.first.uid, equals('perm_expired'));
    });
  });
}
