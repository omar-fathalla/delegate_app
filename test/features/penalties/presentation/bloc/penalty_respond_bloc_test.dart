import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/create_penalty_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_all_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_company_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Repo extends Mock implements PenaltyRepository {}

class _Create extends Mock implements CreatePenaltyUseCase {}

class _Company extends Mock implements GetCompanyPenaltiesUseCase {}

class _All extends Mock implements GetAllPenaltiesUseCase {}

/// TAS-365: RespondToPenaltyEvent → respondToPenalty callable arguments,
/// and a refusal keeps the list (PenaltyActionFailedState).
void main() {
  late _Repo repo;
  PenaltyBloc build() => PenaltyBloc(
        createPenaltyUseCase: _Create(),
        getCompanyPenaltiesUseCase: _Company(),
        getAllPenaltiesUseCase: _All(),
        repository: repo,
      );
  setUp(() => repo = _Repo());

  void stub(Either<Failure, String> r) => when(() => repo.respondToPenalty(
        penaltyId: any(named: 'penaltyId'),
        action: any(named: 'action'),
        reason: any(named: 'reason'),
        decision: any(named: 'decision'),
      )).thenAnswer((_) async => r);

  blocTest<PenaltyBloc, PenaltyState>(
    'dispute sends action dispute with the reason (message 8.2)',
    setUp: () => stub(const Right('DISPUTED')),
    build: build,
    act: (b) => b.add(const RespondToPenaltyEvent(
        penaltyId: 'p1', action: PenaltyResponseAction.dispute, reason: 'غلط')),
    expect: () => [
      const PenaltyActionSuccessState(
          'اعتراضك اتبعت: الجزاء مش هيتخصم لحد ما الإدارة ترد.'),
    ],
    verify: (_) => verify(() => repo.respondToPenalty(
        penaltyId: 'p1', action: 'dispute', reason: 'غلط', decision: null)).called(1),
  );

  blocTest<PenaltyBloc, PenaltyState>(
    'uphold maps to resolve / uphold',
    setUp: () => stub(const Right('ISSUED')),
    build: build,
    act: (b) => b.add(const RespondToPenaltyEvent(
        penaltyId: 'p1', action: PenaltyResponseAction.upholdDispute, reason: 'واضح')),
    verify: (_) => verify(() => repo.respondToPenalty(
        penaltyId: 'p1', action: 'resolve', reason: 'واضح', decision: 'uphold')).called(1),
  );

  blocTest<PenaltyBloc, PenaltyState>(
    'a refusal (e.g. window closed) is an action failure, not a page error',
    setUp: () => stub(const Left(ServerFailure('مدة الاعتراض خلصت'))),
    build: build,
    act: (b) => b.add(const RespondToPenaltyEvent(
        penaltyId: 'p1', action: PenaltyResponseAction.dispute, reason: 'غلط')),
    expect: () => [const PenaltyActionFailedState('مدة الاعتراض خلصت')],
  );
}
