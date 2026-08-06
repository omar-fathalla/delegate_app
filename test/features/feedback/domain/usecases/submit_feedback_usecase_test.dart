import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:delegate_app/features/feedback/domain/usecases/submit_feedback_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}
class MockFile extends Mock implements File {}

void main() {
  late SubmitFeedbackUseCase usecase;
  late MockFeedbackRepository mockRepository;

  setUpAll(() {
    registerFallbackValue(FeedbackType.other);
    registerFallbackValue(File('test.png'));
  });

  setUp(() {
    mockRepository = MockFeedbackRepository();
    usecase = SubmitFeedbackUseCase(mockRepository);
  });

  final tParams = SubmitFeedbackParams(
    userId: 'user_123',
    userName: 'Test User',
    userEmail: 'test@example.com',
    type: FeedbackType.featureRequest,
    content: 'Please add a dark mode feature',
  );

  test('should call submitFeedback on repository', () async {
    when(() => mockRepository.submitFeedback(
      userId: any(named: 'userId'),
      userName: any(named: 'userName'),
      userEmail: any(named: 'userEmail'),
      type: any(named: 'type'),
      content: any(named: 'content'),
      screenshot: any(named: 'screenshot'),
    )).thenAnswer((_) async => const Right(null));

    final result = await usecase(tParams);

    expect(result, const Right(null));
    verify(() => mockRepository.submitFeedback(
      userId: tParams.userId,
      userName: tParams.userName,
      userEmail: tParams.userEmail,
      type: tParams.type,
      content: tParams.content,
      screenshot: tParams.screenshot,
    )).called(1);
  });
}
