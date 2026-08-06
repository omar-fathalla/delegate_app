import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:delegate_app/features/feedback/domain/usecases/get_user_feedbacks_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  late GetUserFeedbacksUseCase usecase;
  late MockFeedbackRepository mockRepository;

  setUp(() {
    mockRepository = MockFeedbackRepository();
    usecase = GetUserFeedbacksUseCase(mockRepository);
  });

  final tFeedbackList = <FeedbackEntity>[];

  test('should get list of feedbacks for a user from repository', () async {
    when(() => mockRepository.getUserFeedbacks(any())).thenAnswer((_) async => Right(tFeedbackList));

    final result = await usecase('user_123');

    expect(result, Right(tFeedbackList));
    verify(() => mockRepository.getUserFeedbacks('user_123')).called(1);
  });
}
