import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  group('AntiFraud Distinct Calendar Days Calculation Tests', () {
    // Replicate the exact aggregation logic used in AntiFraudAuditScreen
    Map<String, Set<String>> computeDelegateDistinctDays(List<Map<String, dynamic>> logs) {
      final Map<String, Set<String>> delegateDistinctDaysMap = {};
      for (final item in logs) {
        DateTime? effectiveDate;
        if (item['timestamp'] is DateTime) {
          effectiveDate = item['timestamp'] as DateTime;
        } else if (item['realTimestamp'] != null) {
          effectiveDate = DateTime.tryParse(item['realTimestamp'].toString());
        } else if (item['createdAt'] != null) {
          effectiveDate = DateTime.tryParse(item['createdAt'].toString());
        }
        if (effectiveDate == null) continue;

        final dayString = DateFormat('yyyy-MM-dd').format(effectiveDate);
        final uid = (item['delegateUid'] ?? '').toString().trim();
        final phone = (item['delegatePhone'] ?? '').toString().trim();
        final name = (item['delegateName'] ?? '').toString().trim();

        final keys = <String>{};
        if (uid.isNotEmpty) keys.add('uid:$uid');
        if (phone.isNotEmpty) keys.add('phone:$phone');
        if (name.isNotEmpty) keys.add('name:$name');
        if (keys.isEmpty) continue;

        Set<String>? sharedDaysSet;
        final connectedKeys = <String>{...keys};

        for (final k in keys) {
          if (delegateDistinctDaysMap.containsKey(k)) {
            if (sharedDaysSet == null) {
              sharedDaysSet = delegateDistinctDaysMap[k];
            } else {
              sharedDaysSet.addAll(delegateDistinctDaysMap[k]!);
            }
          }
        }

        sharedDaysSet ??= <String>{};
        sharedDaysSet.add(dayString);

        // Link all keys pointing to this delegate's set
        for (final entry in delegateDistinctDaysMap.entries) {
          if (identical(entry.value, sharedDaysSet)) {
            connectedKeys.add(entry.key);
          }
        }

        for (final k in connectedKeys) {
          delegateDistinctDaysMap[k] = sharedDaysSet;
        }
      }
      return delegateDistinctDaysMap;
    }

    int getDistinctDays(Map<String, dynamic> data, Map<String, Set<String>> daysMap) {
      final uid = (data['delegateUid'] ?? '').toString().trim();
      if (uid.isNotEmpty && daysMap.containsKey('uid:$uid')) {
        return daysMap['uid:$uid']!.length;
      }
      final phone = (data['delegatePhone'] ?? '').toString().trim();
      if (phone.isNotEmpty && daysMap.containsKey('phone:$phone')) {
        return daysMap['phone:$phone']!.length;
      }
      final name = (data['delegateName'] ?? '').toString().trim();
      if (name.isNotEmpty && daysMap.containsKey('name:$name')) {
        return daysMap['name:$name']!.length;
      }
      return 1;
    }

    test('should count multiple attempts on the SAME calendar day as exactly 1 day', () {
      final logs = [
        {
          'delegateUid': 'del-001',
          'delegateName': 'وليد محمد',
          'delegatePhone': '01148755563',
          'createdAt': '2026-09-22T09:15:00.000Z',
        },
        {
          'delegateUid': 'del-001',
          'delegateName': 'وليد محمد',
          'delegatePhone': '01148755563',
          'createdAt': '2026-09-22T10:19:00.000Z',
        },
        {
          'delegateUid': 'del-001',
          'delegateName': 'وليد محمد',
          'delegatePhone': '01148755563',
          'createdAt': '2026-09-22T14:30:00.000Z',
        },
      ];

      final map = computeDelegateDistinctDays(logs);
      final count = getDistinctDays(logs.first, map);

      expect(count, equals(1), reason: 'Multiple attempts on same day must equal 1 day');
    });

    test('should count attempts across different calendar days as distinct days count', () {
      final logs = [
        {
          'delegateUid': 'del-002',
          'delegateName': 'حبيبه جميل',
          'delegatePhone': '01155735356',
          'createdAt': '2026-09-20T08:00:00.000Z',
        },
        {
          'delegateUid': 'del-002',
          'delegateName': 'حبيبه جميل',
          'delegatePhone': '01155735356',
          'createdAt': '2026-09-21T09:00:00.000Z',
        },
        {
          'delegateUid': 'del-002',
          'delegateName': 'حبيبه جميل',
          'delegatePhone': '01155735356',
          'createdAt': '2026-09-21T11:30:00.000Z', // Same day repeat, should not increment
        },
        {
          'delegateUid': 'del-002',
          'delegateName': 'حبيبه جميل',
          'delegatePhone': '01155735356',
          'createdAt': '2026-09-22T10:15:00.000Z',
        },
      ];

      final map = computeDelegateDistinctDays(logs);
      final count = getDistinctDays(logs.first, map);

      // 4 total attempts, but on 3 distinct days: 2026-09-20, 2026-09-21, 2026-09-22
      expect(count, equals(3), reason: '4 attempts across 3 distinct days must equal 3');
    });

    test('should correctly unify logs when some logs identify by UID and others by Phone', () {
      final logs = [
        {
          'delegateUid': 'del-003',
          'delegatePhone': '01011112222',
          'createdAt': '2026-09-18T10:00:00.000Z',
        },
        {
          'delegateUid': '',
          'delegatePhone': '01011112222',
          'createdAt': '2026-09-19T10:00:00.000Z',
        },
      ];

      final map = computeDelegateDistinctDays(logs);
      final countByUid = getDistinctDays({'delegateUid': 'del-003'}, map);
      final countByPhone = getDistinctDays({'delegatePhone': '01011112222'}, map);

      expect(countByUid, equals(2));
      expect(countByPhone, equals(2));
    });

    test('should fallback to 1 day if delegate has no prior or matching logs', () {
      final map = computeDelegateDistinctDays([]);
      final count = getDistinctDays({'delegateUid': 'unknown-del'}, map);

      expect(count, equals(1));
    });
  });
}
