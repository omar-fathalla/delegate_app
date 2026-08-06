import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:delegate_app/features/feedback/domain/usecases/delete_feedback_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  late DeleteFeedbackUseCase usecase;
  late MockFeedbackRepository mockRepository;

  setUp(() {
    mockRepository = MockFeedbackRepository();
    usecase = DeleteFeedbackUseCase(mockRepository);
  });

  test('should call deleteFeedback on repository', () async {
    when(() => mockRepository.deleteFeedback(any())).thenAnswer((_) async => const Right(null));

    final result = await usecase('test_id');

    expect(result, const Right(null));
    verify(() => mockRepository.deleteFeedback('test_id')).called(1);
  });
}
