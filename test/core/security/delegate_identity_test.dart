// TAS-28 phase 0: the app names the delegate by its delegateId claim and
// falls back to the Auth uid (old tokens, staff, Firebase not ready).
import 'package:delegate_app/core/security/delegate_identity.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockTokenResult extends Mock implements IdTokenResult {}

void main() {
  setUp(DelegateIdentity.resetForTest);

  group('fromClaims', () {
    test('today: claim and uid are the same id', () {
      expect(
        DelegateIdentity.fromClaims(
          uid: 'd1',
          claims: {'role': 'delegate', 'delegateId': 'd1'},
        ),
        'd1',
      );
    });
    test('phase 1 uid (dlg_) still resolves to the delegate doc id', () {
      expect(
        DelegateIdentity.fromClaims(
          uid: 'dlg_abc',
          claims: {'role': 'delegate', 'delegateId': 'd1'},
        ),
        'd1',
      );
    });
    test('old token without the claim: the uid', () {
      expect(
        DelegateIdentity.fromClaims(uid: 'd1', claims: {'role': 'delegate'}),
        'd1',
      );
      expect(DelegateIdentity.fromClaims(uid: 'd1', claims: null), 'd1');
    });
    test('staff token: the uid even with a stray claim', () {
      expect(
        DelegateIdentity.fromClaims(
          uid: 's1',
          claims: {'role': 'hr', 'delegateId': 'd1'},
        ),
        's1',
      );
    });
    test('blank or non-string claim is ignored; no uid gives null', () {
      expect(
        DelegateIdentity.fromClaims(
          uid: 'd1',
          claims: {'role': 'delegate', 'delegateId': ' '},
        ),
        'd1',
      );
      expect(
        DelegateIdentity.fromClaims(
          uid: 'd1',
          claims: {'role': 'delegate', 'delegateId': 7},
        ),
        'd1',
      );
      expect(DelegateIdentity.fromClaims(uid: '', claims: null), isNull);
    });
  });

  group('current / refresh', () {
    late _MockAuth auth;
    late _MockUser user;
    late _MockTokenResult token;

    setUp(() {
      auth = _MockAuth();
      user = _MockUser();
      token = _MockTokenResult();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.getIdTokenResult()).thenAnswer((_) async => token);
    });

    test('signed out: null', () {
      when(() => auth.currentUser).thenReturn(null);
      expect(DelegateIdentity.current(auth), isNull);
      expect(DelegateIdentity.selfIds(auth), isEmpty);
    });

    test('before refresh: the uid; after refresh: the claim', () async {
      when(() => user.uid).thenReturn('dlg_abc');
      when(
        () => token.claims,
      ).thenReturn({'role': 'delegate', 'delegateId': 'd1'});
      expect(DelegateIdentity.current(auth), 'dlg_abc');
      expect(await DelegateIdentity.refresh(auth), 'd1');
      expect(DelegateIdentity.current(auth), 'd1');
      expect(DelegateIdentity.selfIds(auth), {'dlg_abc', 'd1'});
    });

    test("today's token: one id", () async {
      when(() => user.uid).thenReturn('d1');
      when(
        () => token.claims,
      ).thenReturn({'role': 'delegate', 'delegateId': 'd1'});
      await DelegateIdentity.refresh(auth);
      expect(DelegateIdentity.current(auth), 'd1');
      expect(DelegateIdentity.selfIds(auth), {'d1'});
    });

    test('cache belongs to one uid: another user gets its own uid', () async {
      when(() => user.uid).thenReturn('dlg_abc');
      when(
        () => token.claims,
      ).thenReturn({'role': 'delegate', 'delegateId': 'd1'});
      await DelegateIdentity.refresh(auth);
      final other = _MockUser();
      when(() => other.uid).thenReturn('s1');
      when(() => other.getIdTokenResult()).thenThrow(Exception('offline'));
      when(() => auth.currentUser).thenReturn(other);
      expect(DelegateIdentity.current(auth), 's1');
    });

    test('token read fails: refresh falls back to the uid', () async {
      when(() => user.uid).thenReturn('d1');
      when(() => user.getIdTokenResult()).thenThrow(Exception('offline'));
      expect(await DelegateIdentity.refresh(auth), 'd1');
    });
  });
}
