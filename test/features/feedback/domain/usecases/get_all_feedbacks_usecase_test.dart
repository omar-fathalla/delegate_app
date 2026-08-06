import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:delegate_app/features/feedback/domain/usecases/get_all_feedbacks_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  late GetAllFeedbacksUseCase usecase;
  late MockFeedbackRepository mockRepository;

  setUp(() {
    mockRepository = MockFeedbackRepository();
    usecase = GetAllFeedbacksUseCase(mockRepository);
  });

  final tFeedbackList = <FeedbackEntity>[];

  test('should get list of feedbacks from repository', () async {
    when(() => mockRepository.getAllFeedbacks()).thenAnswer((_) async => Right(tFeedbackList));

    final result = await usecase();

    expect(result, Right(tFeedbackList));
    verify(() => mockRepository.getAllFeedbacks()).called(1);
  });
}
