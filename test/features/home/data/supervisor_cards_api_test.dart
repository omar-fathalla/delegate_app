// TAS-55: the supervisor card comes from getMySupervisorCards.
import 'package:delegate_app/features/home/data/supervisor_cards_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sends the company and maps the four card fields', () async {
    Map<String, dynamic>? sent;
    final api = SupervisorCardsApi(call: (req) async {
      sent = req;
      return {
        'supervisors': [
          {
            'uid': 's1',
            'displayName': ' مشرف تجريبي ',
            'phoneNumber': '01000000009',
            'email': 'sup@example.test',
            'photoUrl': 'https://example.test/p.jpg',
          },
          'not a map',
        ],
      };
    });
    final cards = await api.fetch(organizationUID: 'o1', companyUID: 'c1');
    expect(sent, {'organizationUID': 'o1', 'companyUID': 'c1'});
    expect(cards, hasLength(1));
    expect(cards.single.displayName, 'مشرف تجريبي');
    expect(cards.single.phoneNumber, '01000000009');
    expect(cards.single.photoUrl, 'https://example.test/p.jpg');
  });

  test('a failure or an odd answer gives an empty list', () async {
    expect(
      await SupervisorCardsApi(call: (_) async => throw Exception('x'))
          .fetch(organizationUID: 'o1', companyUID: 'c1'),
      isEmpty,
    );
    expect(
      await SupervisorCardsApi(call: (_) async => 'nope')
          .fetch(organizationUID: 'o1', companyUID: 'c1'),
      isEmpty,
    );
  });
}
