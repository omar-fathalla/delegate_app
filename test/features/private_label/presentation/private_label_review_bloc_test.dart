import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';
import 'package:delegate_app/features/private_label/domain/usecases/delete_private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_audits.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_branches.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_products.dart';
import 'package:delegate_app/features/private_label/domain/usecases/review_private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/usecases/save_private_label_product.dart';
import 'package:delegate_app/features/private_label/domain/usecases/update_private_label_audit.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_review_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepo extends Mock implements PrivateLabelRepository {}

void main() {
  late _MockRepo repo;
  late GetPrivateLabelAudits getAudits;
  late ReviewPrivateLabelAudit reviewAudit;
  late GetPrivateLabelProducts getProducts;
  late SavePrivateLabelProduct saveProduct;
  late DeletePrivateLabelAudit deleteAudit;
  late UpdatePrivateLabelAudit updateAudit;
  late GetPrivateLabelBranches getBranches;

  final sampleAudit = PrivateLabelAudit(
    id: 'a1',
    organizationUID: 'org1',
    companyUID: 'comp1',
    delegateUid: 'u1',
    delegateName: 'Delegate 1',
    branchName: 'Branch 1',
    productName: 'Rice 1kg',
    referencePrice: 30.0,
    shelfPrice: 30.0,
    stockStatus: PrivateLabelStockStatus.available,
    productPhotoUrl: 'url1',
    pricePhotoUrl: 'url2',
    auditDate: '2026-10-07',
    auditMonth: '2026-10',
    capturedAt: DateTime(2026, 10, 7, 10, 0),
  );

  setUpAll(() {
    registerFallbackValue(PrivateLabelStockStatus.available);
    registerFallbackValue(sampleAudit);
    registerFallbackValue(const DeleteAuditParams(
      auditId: 'a1',
      organizationUID: 'org1',
      delegateUid: 'u1',
      date: '2026-10-07',
    ));
    registerFallbackValue(const UpdateAuditParams(
      organizationUID: 'org1',
      auditId: 'a1',
      productName: 'Rice 1kg',
      shelfPrice: 30.0,
      stockStatus: PrivateLabelStockStatus.available,
    ));
  });

  setUp(() {
    repo = _MockRepo();
    getAudits = GetPrivateLabelAudits(repo);
    reviewAudit = ReviewPrivateLabelAudit(repo);
    getProducts = GetPrivateLabelProducts(repo);
    saveProduct = SavePrivateLabelProduct(repo);
    deleteAudit = DeletePrivateLabelAudit(repo);
    updateAudit = UpdatePrivateLabelAudit(repo);
    getBranches = GetPrivateLabelBranches(repo);

    when(() => repo.getProducts(any()))
        .thenAnswer((_) async => const Right([]));
    when(() => repo.getBranches(any()))
        .thenAnswer((_) async => const Right(['Branch 1', 'Branch 2']));
  });

  PrivateLabelReviewBloc buildBloc({List<PrivateLabelAudit>? initialAudits}) {
    final bloc = PrivateLabelReviewBloc(
      getAudits: getAudits,
      reviewAudit: reviewAudit,
      getProducts: getProducts,
      saveProduct: saveProduct,
      deleteAudit: deleteAudit,
      updateAudit: updateAudit,
      getBranches: getBranches,
    );
    if (initialAudits != null) {
      bloc.emit(bloc.state.copyWith(
        status: PrivateLabelReviewStatusView.ready,
        audits: initialAudits,
      ));
    }
    return bloc;
  }

  group('PrivateLabelReviewBloc - Delete & Update', () {
    blocTest<PrivateLabelReviewBloc, PrivateLabelReviewState>(
      'removes audit and sets success feedback when delete succeeds',
      build: () {
        when(() => repo.deleteAudit(
              auditId: any(named: 'auditId'),
              organizationUID: any(named: 'organizationUID'),
              delegateUid: any(named: 'delegateUid'),
              date: any(named: 'date'),
            )).thenAnswer((_) async => const Right(unit));
        return buildBloc(initialAudits: [sampleAudit]);
      },
      act: (bloc) => bloc.add(PrivateLabelReviewAuditDeleted(sampleAudit)),
      expect: () => [
        predicate<PrivateLabelReviewState>((s) => s.savingAuditId == sampleAudit.id),
        predicate<PrivateLabelReviewState>((s) =>
            s.savingAuditId == null &&
            s.audits.isEmpty &&
            s.feedback?.isError == false &&
            s.feedback?.message.contains('تم حذف التوثيق') == true),
      ],
    );

    blocTest<PrivateLabelReviewBloc, PrivateLabelReviewState>(
      'shows error feedback when delete fails',
      build: () {
        when(() => repo.deleteAudit(
              auditId: any(named: 'auditId'),
              organizationUID: any(named: 'organizationUID'),
              delegateUid: any(named: 'delegateUid'),
              date: any(named: 'date'),
            )).thenAnswer((_) async => const Left(ServerFailure('فشل الحذف')));
        return buildBloc(initialAudits: [sampleAudit]);
      },
      act: (bloc) => bloc.add(PrivateLabelReviewAuditDeleted(sampleAudit)),
      expect: () => [
        predicate<PrivateLabelReviewState>((s) => s.savingAuditId == sampleAudit.id),
        predicate<PrivateLabelReviewState>((s) =>
            s.savingAuditId == null &&
            s.audits.length == 1 &&
            s.feedback?.isError == true),
      ],
    );

    blocTest<PrivateLabelReviewBloc, PrivateLabelReviewState>(
      'updates audit in state and sets success feedback when update succeeds',
      build: () {
        when(() => repo.updateAudit(
              organizationUID: any(named: 'organizationUID'),
              auditId: any(named: 'auditId'),
              productName: any(named: 'productName'),
              productId: any(named: 'productId'),
              referencePrice: any(named: 'referencePrice'),
              shelfPrice: any(named: 'shelfPrice'),
              stockStatus: any(named: 'stockStatus'),
              barcode: any(named: 'barcode'),
              notes: any(named: 'notes'),
            )).thenAnswer((invocation) async {
          return Right(sampleAudit.copyWith(
            productName: invocation.namedArguments[#productName] as String?,
            shelfPrice: invocation.namedArguments[#shelfPrice] as double?,
          ));
        });
        return buildBloc(initialAudits: [sampleAudit]);
      },
      act: (bloc) {
        final updated = sampleAudit.copyWith(
          productName: 'Rice 1kg Updated',
          shelfPrice: 35.0,
        );
        bloc.add(PrivateLabelReviewAuditUpdated(updated));
      },
      expect: () => [
        predicate<PrivateLabelReviewState>((s) => s.savingAuditId == sampleAudit.id),
        predicate<PrivateLabelReviewState>((s) =>
            s.savingAuditId == null &&
            s.audits.first.productName == 'Rice 1kg Updated' &&
            s.audits.first.shelfPrice == 35.0 &&
            s.feedback?.isError == false &&
            s.feedback?.message.contains('تم تعديل بيانات التوثيق') == true),
      ],
    );

    blocTest<PrivateLabelReviewBloc, PrivateLabelReviewState>(
      'updates selected branch filter',
      build: () => buildBloc(),
      act: (bloc) => bloc.add(const PrivateLabelReviewBranchSelected('Branch 1')),
      expect: () => [
        predicate<PrivateLabelReviewState>((s) => s.selectedBranch == 'Branch 1'),
      ],
    );

    test('initial state defaults to date: null and filter: pending', () {
      final bloc = buildBloc();
      expect(bloc.state.date, isNull);
      expect(bloc.state.filter, PrivateLabelReviewFilter.pending);
    });

    blocTest<PrivateLabelReviewBloc, PrivateLabelReviewState>(
      'date changed clears date in state',
      build: () => buildBloc(),
      seed: () => const PrivateLabelReviewState(date: '2026-10-07'),
      act: (bloc) => bloc.add(const PrivateLabelReviewDateChanged(null)),
      expect: () => [
        predicate<PrivateLabelReviewState>((s) => s.date == null),
      ],
    );

    blocTest<PrivateLabelReviewBloc, PrivateLabelReviewState>(
      'filter changed updates filter state',
      build: () => buildBloc(),
      act: (bloc) => bloc.add(const PrivateLabelReviewFilterChanged(PrivateLabelReviewFilter.all)),
      expect: () => [
        predicate<PrivateLabelReviewState>((s) => s.filter == PrivateLabelReviewFilter.all),
      ],
    );
  });
}
