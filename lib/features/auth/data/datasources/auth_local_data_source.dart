import 'dart:convert';

import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String cachedDelegateKey = 'cachedDelegate';
const String cachedAllDelegatesKey = 'cachedAllDelegates';

abstract class AuthLocalDataSource {
  /// حفظ بيانات المندوب محلياً
  Future<void> cacheDelegateData(DelegateModel delegate);

  /// استرجاع بيانات المندوب المحفوظة
  DelegateModel? getCachedDelegateData();

  /// حفظ بيانات جميع المنظمات للمندوب الحالي
  Future<void> cacheAllDelegatesData(List<DelegateModel> delegates);

  /// استرجاع بيانات جميع المنظمات
  List<DelegateModel> getCachedAllDelegatesData();

  /// مسح بيانات المندوب المحفوظة
  Future<void> clearCachedData();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final SharedPreferences sharedPreferences;

  AuthLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<void> cacheDelegateData(DelegateModel delegate) async {
    try {
      final jsonMap = delegate.toLocalJson();
      final jsonString = json.encode(jsonMap);
      await sharedPreferences.setString(cachedDelegateKey, jsonString);
    } catch (e) {
      throw CacheFailure('فشل في حفظ البيانات محلياً: $e');
    }
  }

  @override
  DelegateModel? getCachedDelegateData() {
    try {
      final jsonString = sharedPreferences.getString(cachedDelegateKey);
      if (jsonString == null) return null;
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      return DelegateModel.fromJson(jsonMap, jsonMap['uid'] ?? '');
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> cacheAllDelegatesData(List<DelegateModel> delegates) async {
    try {
      final jsonList = delegates.map((d) => d.toLocalJson()).toList();
      final jsonString = json.encode(jsonList);
      await sharedPreferences.setString(cachedAllDelegatesKey, jsonString);
    } catch (e) {
      throw CacheFailure('فشل في حفظ بيانات المنظمات: $e');
    }
  }

  @override
  List<DelegateModel> getCachedAllDelegatesData() {
    try {
      final jsonString = sharedPreferences.getString(cachedAllDelegatesKey);
      if (jsonString == null) return [];
      final jsonList = json.decode(jsonString) as List<dynamic>;
      return jsonList
          .map(
            (item) => DelegateModel.fromJson(
              item as Map<String, dynamic>,
              (item as Map)['uid'] ?? '',
            ),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> clearCachedData() async {
    // 1. مسح المفاتيح الأساسية لبيانات المندوب والمنظمات
    await sharedPreferences.remove(cachedDelegateKey);
    await sharedPreferences.remove(cachedAllDelegatesKey);

    // 2. مسح شامل لكافة الكاشات والبيانات المرتبطة بالمستخدم والجلسة السابقة
    // مع الإبقاء الصارم على معرّف الجهاز الثابت (persistent_app_device_uuid)
    // وإعدادات التطبيق العامة (الثيم، اللغة، وحالة طلب تقييم التطبيق)
    final allKeys = sharedPreferences.getKeys();
    final keysToRemove = <String>[];

    for (final key in allKeys) {
      if (key == cachedDelegateKey || key == cachedAllDelegatesKey) continue;

      // الحفاظ على معرّف البصمة الرقمية للهاتف وإعدادات واجهة المستخدم العامة
      if (key == 'persistent_app_device_uuid' ||
          key == 'app_theme_mode' ||
          key == 'locale_code' ||
          key.startsWith('review_service_')) {
        continue;
      }

      // مسح كافة كاشات الحضور والانصراف، الإشعارات، الجزاءات، الأذونات، الفروع، والسلاسل
      if (key.startsWith('cachedAttendance') ||
          key.startsWith('cached_attendance') ||
          key.startsWith('activeAttendance') ||
          key.startsWith('cachedOfflineQueue') ||
          key.startsWith('cached_penalties') ||
          key.startsWith('cached_leaves') ||
          key.startsWith('cached_recent_photos') ||
          key.startsWith('marketing_recent_photos') ||
          key.startsWith('photo_permission') ||
          key.startsWith('photo_permissions') ||
          key.startsWith('cached_notifications') ||
          key.startsWith('user_notifications') ||
          key.startsWith('supervisor_orgs_') ||
          key.startsWith('offline_actions_') ||
          key.startsWith('user_session_') ||
          key.startsWith('cached_device_') ||
          key.startsWith('fav_branches_') ||
          key.startsWith('active_branch_') ||
          key.startsWith('cached_due_receipts_') ||
          key.startsWith('billing_') ||
          key.startsWith('company_penalties_') ||
          key.startsWith('pinned_violation_') ||
          key.startsWith('selected_departments_')) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      await sharedPreferences.remove(key);
    }
  }
}
