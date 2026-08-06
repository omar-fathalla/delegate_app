import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:delegate_app/features/feedback/domain/usecases/update_feedback_status_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  late UpdateFeedbackStatusUseCase usecase;
  late MockFeedbackRepository mockRepository;

  setUpAll(() {
    registerFallbackValue(FeedbackStatus.pending);
  });

  setUp(() {
    mockRepository = MockFeedbackRepository();
    usecase = UpdateFeedbackStatusUseCase(mockRepository);
  });

  final tParams = UpdateFeedbackStatusParams(
    feedbackId: 'test_id',
    status: FeedbackStatus.resolved,
    adminResponse: 'Fixed',
  );

  test('should call updateFeedbackStatus on repository', () async {
    when(() => mockRepository.updateFeedbackStatus(
      feedbackId: any(named: 'feedbackId'),
      status: any(named: 'status'),
      adminResponse: any(named: 'adminResponse'),
    )).thenAnswer((_) async => const Right(null));

    final result = await usecase(tParams);

    expect(result, const Right(null));
    verify(() => mockRepository.updateFeedbackStatus(
      feedbackId: tParams.feedbackId,
      status: tParams.status,
      adminResponse: tParams.adminResponse,
    )).called(1);
  });
}
