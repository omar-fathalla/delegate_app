import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/usecases/delete_feedback_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/get_all_feedbacks_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/update_feedback_status_usecase.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGetAllFeedbacksUseCase extends Mock implements GetAllFeedbacksUseCase {}
class MockUpdateFeedbackStatusUseCase extends Mock implements UpdateFeedbackStatusUseCase {}
class MockDeleteFeedbackUseCase extends Mock implements DeleteFeedbackUseCase {}

void main() {
  late AdminFeedbackBloc bloc;
  late MockGetAllFeedbacksUseCase mockGetAllFeedbacksUseCase;
  late MockUpdateFeedbackStatusUseCase mockUpdateFeedbackStatusUseCase;
  late MockDeleteFeedbackUseCase mockDeleteFeedbackUseCase;

  setUpAll(() {
    registerFallbackValue(UpdateFeedbackStatusParams(
      feedbackId: 'test_id',
      status: FeedbackStatus.resolved,
    ));
  });

  setUp(() {
    mockGetAllFeedbacksUseCase = MockGetAllFeedbacksUseCase();
    mockUpdateFeedbackStatusUseCase = MockUpdateFeedbackStatusUseCase();
    mockDeleteFeedbackUseCase = MockDeleteFeedbackUseCase();
    
    bloc = AdminFeedbackBloc(
      getAllFeedbacksUseCase: mockGetAllFeedbacksUseCase,
      updateFeedbackStatusUseCase: mockUpdateFeedbackStatusUseCase,
      deleteFeedbackUseCase: mockDeleteFeedbackUseCase,
    );
  });

  tearDown(() {
    bloc.close();
  });

  final tFeedbackList = <FeedbackEntity>[];

  test('initial state should be AdminFeedbackInitial', () {
    expect(bloc.state, equals(AdminFeedbackInitial()));
  });

  group('LoadAllFeedbacksEvent', () {
    test('should emit [AdminFeedbackLoading, AdminFeedbacksLoaded] on success', () async {
      when(() => mockGetAllFeedbacksUseCase()).thenAnswer((_) async => Right(tFeedbackList));

      final expected = [
        AdminFeedbackLoading(),
        AdminFeedbacksLoaded(feedbacks: tFeedbackList),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const LoadAllFeedbacksEvent());
    });

    test('should emit [AdminFeedbackLoading, AdminFeedbackError] on failure', () async {
      when(() => mockGetAllFeedbacksUseCase()).thenAnswer((_) async => const Left(ServerFailure('Error')));

      final expected = [
        AdminFeedbackLoading(),
        const AdminFeedbackError(message: 'Error'),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const LoadAllFeedbacksEvent());
    });
  });

  group('UpdateFeedbackStatusEvent', () {
    test('should update status and trigger LoadAllFeedbacksEvent', () async {
      when(() => mockUpdateFeedbackStatusUseCase(any())).thenAnswer((_) async => const Right(null));
      when(() => mockGetAllFeedbacksUseCase()).thenAnswer((_) async => Right(tFeedbackList));

      final expected = [
        AdminFeedbackLoading(),
        AdminFeedbacksLoaded(feedbacks: tFeedbackList),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const UpdateFeedbackStatusEvent(
        feedbackId: 'test_id',
        status: FeedbackStatus.resolved,
      ));
    });

    test('should emit [AdminFeedbackError] on failure', () async {
      when(() => mockUpdateFeedbackStatusUseCase(any())).thenAnswer((_) async => const Left(ServerFailure('Error')));

      final expected = [
        const AdminFeedbackError(message: 'Error'),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const UpdateFeedbackStatusEvent(
        feedbackId: 'test_id',
        status: FeedbackStatus.resolved,
      ));
    });
  });

  group('DeleteFeedbackEvent', () {
    test('should delete feedback and trigger LoadAllFeedbacksEvent', () async {
      when(() => mockDeleteFeedbackUseCase(any())).thenAnswer((_) async => const Right(null));
      when(() => mockGetAllFeedbacksUseCase()).thenAnswer((_) async => Right(tFeedbackList));

      final expected = [
        AdminFeedbackLoading(),
        AdminFeedbacksLoaded(feedbacks: tFeedbackList),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const DeleteFeedbackEvent('test_id'));
    });

    test('should emit [AdminFeedbackError] on failure', () async {
      when(() => mockDeleteFeedbackUseCase(any())).thenAnswer((_) async => const Left(ServerFailure('Error')));

      final expected = [
        const AdminFeedbackError(message: 'Error'),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const DeleteFeedbackEvent('test_id'));
    });
  });
}
