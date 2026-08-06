import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/usecases/get_user_feedbacks_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/submit_feedback_usecase.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSubmitFeedbackUseCase extends Mock implements SubmitFeedbackUseCase {}
class MockGetUserFeedbacksUseCase extends Mock implements GetUserFeedbacksUseCase {}

void main() {
  late FeedbackBloc bloc;
  late MockSubmitFeedbackUseCase mockSubmitFeedbackUseCase;
  late MockGetUserFeedbacksUseCase mockGetUserFeedbacksUseCase;

  setUpAll(() {
    registerFallbackValue(SubmitFeedbackParams(
      userId: 'user_123',
      userName: 'Test User',
      userEmail: 'test@example.com',
      type: FeedbackType.featureRequest,
      content: 'content',
    ));
  });

  setUp(() {
    mockSubmitFeedbackUseCase = MockSubmitFeedbackUseCase();
    mockGetUserFeedbacksUseCase = MockGetUserFeedbacksUseCase();
    bloc = FeedbackBloc(
      submitFeedbackUseCase: mockSubmitFeedbackUseCase,
      getUserFeedbacksUseCase: mockGetUserFeedbacksUseCase,
    );
  });

  tearDown(() {
    bloc.close();
  });

  final tFeedbackList = <FeedbackEntity>[];

  test('initial state should be FeedbackInitial', () {
    expect(bloc.state, equals(FeedbackInitial()));
  });

  group('SubmitFeedbackEvent', () {
    test('should emit [FeedbackSubmitting, FeedbackSubmitted] on success', () async {
      when(() => mockSubmitFeedbackUseCase(any())).thenAnswer((_) async => const Right(null));

      final expected = [
        FeedbackSubmitting(),
        FeedbackSubmitted(),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const SubmitFeedbackEvent(
        userId: 'user_123',
        userName: 'Test User',
        userEmail: 'test@example.com',
        type: FeedbackType.featureRequest,
        content: 'content',
      ));
    });

    test('should emit [FeedbackSubmitting, FeedbackError] on failure', () async {
      when(() => mockSubmitFeedbackUseCase(any())).thenAnswer((_) async => const Left(ServerFailure('Error')));

      final expected = [
        FeedbackSubmitting(),
        const FeedbackError(message: 'Error'),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const SubmitFeedbackEvent(
        userId: 'user_123',
        userName: 'Test User',
        userEmail: 'test@example.com',
        type: FeedbackType.featureRequest,
        content: 'content',
      ));
    });
  });

  group('LoadUserFeedbacksEvent', () {
    test('should emit [FeedbackLoading, FeedbacksLoaded] on success', () async {
      when(() => mockGetUserFeedbacksUseCase(any())).thenAnswer((_) async => Right(tFeedbackList));

      final expected = [
        FeedbackLoading(),
        FeedbacksLoaded(feedbacks: tFeedbackList),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const LoadUserFeedbacksEvent(userId: 'user_123'));
    });

    test('should emit [FeedbackLoading, FeedbackError] on failure', () async {
      when(() => mockGetUserFeedbacksUseCase(any())).thenAnswer((_) async => const Left(ServerFailure('Error')));

      final expected = [
        FeedbackLoading(),
        const FeedbackError(message: 'Error'),
      ];

      expectLater(bloc.stream, emitsInOrder(expected));

      bloc.add(const LoadUserFeedbacksEvent(userId: 'user_123'));
    });
  });
}
