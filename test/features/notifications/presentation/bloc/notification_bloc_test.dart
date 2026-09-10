import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/domain/usecases/delete_notification_for_user.dart';
import 'package:delegate_app/features/notifications/domain/usecases/delete_all_notifications_for_user.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_notifications.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_unread_count.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_all_notifications_read.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_notification_read.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGetNotifications extends Mock implements GetNotifications {}
class MockGetUnreadCount extends Mock implements GetUnreadCount {}
class MockMarkNotificationRead extends Mock implements MarkNotificationRead {}
class MockMarkAllNotificationsRead extends Mock implements MarkAllNotificationsRead {}
class MockDeleteNotificationForUser extends Mock implements DeleteNotificationForUser {}
class MockDeleteAllNotificationsForUser extends Mock implements DeleteAllNotificationsForUser {}

class FakeGetNotificationsParams extends Fake implements GetNotificationsParams {}
class FakeGetUnreadCountParams extends Fake implements GetUnreadCountParams {}
class FakeMarkNotificationReadParams extends Fake implements MarkNotificationReadParams {}
class FakeMarkAllNotificationsReadParams extends Fake implements MarkAllNotificationsReadParams {}
class FakeDeleteNotificationForUserParams extends Fake implements DeleteNotificationForUserParams {}
class FakeDeleteAllNotificationsForUserParams extends Fake implements DeleteAllNotificationsForUserParams {}

void main() {
  late NotificationBloc bloc;
  late MockGetNotifications mockGetNotifications;
  late MockGetUnreadCount mockGetUnreadCount;
  late MockMarkNotificationRead mockMarkNotificationRead;
  late MockMarkAllNotificationsRead mockMarkAllNotificationsRead;
  late MockDeleteNotificationForUser mockDeleteNotificationForUser;
  late MockDeleteAllNotificationsForUser mockDeleteAllNotificationsForUser;

  setUpAll(() {
    registerFallbackValue(FakeGetNotificationsParams());
    registerFallbackValue(FakeGetUnreadCountParams());
    registerFallbackValue(FakeMarkNotificationReadParams());
    registerFallbackValue(FakeMarkAllNotificationsReadParams());
    registerFallbackValue(FakeDeleteNotificationForUserParams());
    registerFallbackValue(FakeDeleteAllNotificationsForUserParams());
  });

  setUp(() {
    mockGetNotifications = MockGetNotifications();
    mockGetUnreadCount = MockGetUnreadCount();
    mockMarkNotificationRead = MockMarkNotificationRead();
    mockMarkAllNotificationsRead = MockMarkAllNotificationsRead();
    mockDeleteNotificationForUser = MockDeleteNotificationForUser();
    mockDeleteAllNotificationsForUser = MockDeleteAllNotificationsForUser();

    bloc = NotificationBloc(
      getNotifications: mockGetNotifications,
      getUnreadCount: mockGetUnreadCount,
      markNotificationRead: mockMarkNotificationRead,
      markAllNotificationsRead: mockMarkAllNotificationsRead,
      deleteNotificationForUser: mockDeleteNotificationForUser,
      deleteAllNotificationsForUser: mockDeleteAllNotificationsForUser,
    );
  });

  final tNotificationList = [
    NotificationEntity(
      id: '1',
      delegateUid: 'del1',
      organizationId: 'org1',
      companyId: 'comp1',
      title: 'Title',
      body: 'Body',
      type: 'general',
      isRead: false,
      createdAt: DateTime(2023),
    )
  ];

  test('initial state should be NotificationInitial', () {
    expect(bloc.state, equals(NotificationInitial()));
  });

  blocTest<NotificationBloc, NotificationState>(
    'should emit [NotificationLoading, NotificationLoaded] when LoadNotifications is successful',
    build: () {
      when(() => mockGetNotifications(any()))
          .thenAnswer((_) async => Right(tNotificationList));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadNotifications(delegateUid: 'del1', organizationId: 'org1')),
    expect: () => [
      NotificationLoading(),
      NotificationLoaded(notifications: tNotificationList, unreadCount: 1),
    ],
  );

  blocTest<NotificationBloc, NotificationState>(
    'should emit [NotificationLoading, NotificationError] when LoadNotifications fails',
    build: () {
      when(() => mockGetNotifications(any()))
          .thenAnswer((_) async => const Left(ServerFailure('Error')));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadNotifications(delegateUid: 'del1', organizationId: 'org1')),
    expect: () => [
      NotificationLoading(),
      const NotificationError('Error'),
    ],
  );

  blocTest<NotificationBloc, NotificationState>(
    'should emit NotificationLoaded with updated count on UnreadCountUpdated',
    build: () => bloc,
    act: (bloc) => bloc.add(const UnreadCountUpdated(5)),
    expect: () => [
      const NotificationLoaded(notifications: [], unreadCount: 5),
    ],
  );

  blocTest<NotificationBloc, NotificationState>(
    'should call markNotificationRead and reload notifications on MarkAsRead',
    build: () {
      when(() => mockMarkNotificationRead(any()))
          .thenAnswer((_) async => const Right(null));
      when(() => mockGetNotifications(any()))
          .thenAnswer((_) async => Right(tNotificationList));
      return bloc;
    },
    act: (bloc) => bloc.add(const MarkAsRead(notificationId: 'notif1', delegateUid: 'del1', organizationId: 'org1')),
    expect: () => [
      NotificationLoading(),
      NotificationLoaded(notifications: tNotificationList, unreadCount: 1),
    ],
    verify: (_) {
      verify(() => mockMarkNotificationRead(any())).called(1);
      verify(() => mockGetNotifications(any())).called(1);
    },
  );

  blocTest<NotificationBloc, NotificationState>(
    'should call markAllNotificationsRead and reload notifications on MarkAllAsRead',
    build: () {
      when(() => mockMarkAllNotificationsRead(any()))
          .thenAnswer((_) async => const Right(null));
      when(() => mockGetNotifications(any()))
          .thenAnswer((_) async => Right(tNotificationList));
      return bloc;
    },
    act: (bloc) => bloc.add(const MarkAllAsRead(delegateUid: 'del1', organizationId: 'org1')),
    expect: () => [
      NotificationLoading(),
      NotificationLoaded(notifications: tNotificationList, unreadCount: 1),
    ],
    verify: (_) {
      verify(() => mockMarkAllNotificationsRead(any())).called(1);
      verify(() => mockGetNotifications(any())).called(1);
    },
  );

  blocTest<NotificationBloc, NotificationState>(
    'should clear state immediately and call deleteAllNotificationsForUser on DeleteAllNotificationsRequested',
    build: () {
      when(() => mockDeleteAllNotificationsForUser(any()))
          .thenAnswer((_) async => const Right(null));
      return bloc;
    },
    act: (bloc) => bloc.add(const DeleteAllNotificationsRequested(
      delegateUid: 'del1',
      organizationId: 'org1',
      notificationIds: ['1', '2'],
    )),
    expect: () => [
      const NotificationLoaded(notifications: [], unreadCount: 0),
    ],
    verify: (_) {
      verify(() => mockDeleteAllNotificationsForUser(any())).called(1);
    },
  );
}
