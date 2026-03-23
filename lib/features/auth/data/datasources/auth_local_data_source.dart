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
          .map((item) => DelegateModel.fromJson(
              item as Map<String, dynamic>, (item as Map)['uid'] ?? ''))
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> clearCachedData() async {
    await sharedPreferences.remove(cachedDelegateKey);
    await sharedPreferences.remove(cachedAllDelegatesKey);
  }
}
