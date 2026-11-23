import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// خدمة تدقيق الأمان ومكافحة التلاعب ورصد أجهزة الـ Fake Location
class SecurityAuditService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// جلب معلومات عنوان الـ IP والمدينة الحقيقية ومزود الخدمة عبر الإنترنت
  static Future<Map<String, String>> _fetchNetworkIpInfo() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(Uri.parse('https://ipapi.co/json/'));
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        client.close();
        final ip = data['ip']?.toString() ?? '';
        final city = data['city']?.toString() ?? '';
        final region = data['region']?.toString() ?? '';
        final country = data['country_name']?.toString() ?? '';
        final org = data['org']?.toString() ?? '';

        final locParts = <String>[];
        if (city.isNotEmpty) locParts.add(city);
        if (region.isNotEmpty && region != city) locParts.add(region);
        if (country.isNotEmpty) locParts.add(country);

        final locationSummary = locParts.join(', ');

        return {
          'ip': ip,
          'city': city,
          'region': region,
          'country': country,
          'isp': org,
          'networkLocation': locationSummary.isNotEmpty
              ? (org.isNotEmpty ? '$locationSummary ($org)' : locationSummary)
              : (ip.isNotEmpty ? 'IP: $ip' : ''),
        };
      }
      client.close();
    } catch (_) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        final request = await client.getUrl(Uri.parse('https://api.ipify.org?format=json'));
        final response = await request.close().timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          client.close();
          final ip = data['ip']?.toString() ?? '';
          return {
            'ip': ip,
            'networkLocation': ip.isNotEmpty ? 'IP: $ip' : '',
          };
        }
        client.close();
      } catch (_) {}
    }
    return {};
  }

  /// تسجيل محاولة استخدام Fake GPS أو تزييف الموقع الجغرافي في سجل الأمان
  static Future<void> logMockLocationViolation({
    required Delegate delegate,
    required Position position,
    required String deviceModel,
    String? branchName,
    String? branchUID,
    String? actionType,
    DateTime? realTimestamp,
  }) async {
    try {
      final docRef = _firestore.collection('security_audit_logs').doc();
      final now = realTimestamp ?? DateTime.now();
      final mockTime = position.timestamp;

      // Fetch network IP & ISP Geolocation
      final netInfo = await _fetchNetworkIpInfo();

      String resolvedBranchName = branchName?.trim() ?? '';
      String resolvedBranchUID = branchUID?.trim() ?? '';

      // If branchName is empty, determine the nearest branch from mock coordinates
      if (resolvedBranchName.isEmpty) {
        try {
          // TAS-259: reuse the once-per-session branches list (already
          // loaded by the attendance screen's display cache) instead of a
          // full-collection read on every fake-GPS attempt.
          final branchDocs = await BranchesSessionCache.load(_firestore);
          double minDistance = double.infinity;
          String bestName = '';
          String bestId = '';

          for (final doc in branchDocs) {
            final bData = doc.data();
            final bName = (bData['branchName'] as String?) ??
                (bData['name'] as String?) ??
                (bData['title'] as String?) ??
                doc.id;

            double? bLat;
            double? bLng;

            if (bData['location'] is Map) {
              bLat = (bData['location']['latitude'] as num?)?.toDouble();
              bLng = (bData['location']['longitude'] as num?)?.toDouble();
            } else if (bData['latitude'] != null && bData['longitude'] != null) {
              bLat = (bData['latitude'] as num?)?.toDouble();
              bLng = (bData['longitude'] as num?)?.toDouble();
            }

            if (bLat != null && bLng != null) {
              final dist = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                bLat,
                bLng,
              );
              if (dist < minDistance) {
                minDistance = dist;
                bestName = bName;
                bestId = doc.id;
              }
            }
          }

          if (bestName.isNotEmpty) {
            resolvedBranchName = bestName;
            resolvedBranchUID = bestId;
          }
        } catch (_) {}
      }

      await docRef.set({
        'id': docRef.id,
        'delegateUid': delegate.uid,
        'delegateName': delegate.fullName.isNotEmpty
            ? delegate.fullName
            : '${delegate.firstName} ${delegate.lastName}'.trim(),
        'delegatePhone': delegate.phoneNumber,
        'organizationUID': delegate.organizationUID,
        'companyUID': delegate.companyUID,
        'companyName': delegate.companyName,
        'branchUID': resolvedBranchUID,
        'branchName': resolvedBranchName,
        'actionType': actionType ?? 'تسجيل حضور/انصراف',
        'deviceModel': deviceModel.isNotEmpty ? deviceModel : 'Unknown Device',
        'violationType': 'fake_gps',
        'violationTitle': 'استخدام برنامج تزييف الموقع (Fake GPS)',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'isMocked': true,
        'ipAddress': netInfo['ip'] ?? '',
        'ipCity': netInfo['city'] ?? '',
        'ipRegion': netInfo['region'] ?? '',
        'ipCountry': netInfo['country'] ?? '',
        'ipIsp': netInfo['isp'] ?? '',
        'networkLocation': netInfo['networkLocation'] ?? '',
        'mockTimestamp': mockTime.toIso8601String(),
        'realTimestamp': now.toIso8601String(),
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': now.toIso8601String(),
        'status': 'pending_review',
      });

      debugPrint('Security audit logged: Fake GPS attempt by ${delegate.fullName} on $deviceModel (Resolved Branch: $resolvedBranchName, Action: $actionType)');
    } catch (e) {
      debugPrint('Error logging security audit: $e');
    }
  }
}
