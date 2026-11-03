import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:delegate_app/core/config/app_env.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Representation of a Google Places suggestion / prediction.
class PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;
  final LatLng? location;

  const PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
    this.location,
  });

  @override
  String toString() => description;
}

/// Service providing live Google Places Autocomplete, Geocoding, and Nearby Place details
/// using the project's authorized Google Maps API key and Android package headers.
class GooglePlacesService {
  static String get _apiKey => AppEnv.placesApiKey;
  static const String _androidPackage = 'com.tashil.delegate';
  static const String _androidCert = '425213bfb15948a1cbfba42989605ebfb558a47e';

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6);

  /// Default predefined hubs and major Egyptian cities for instant 0ms offline navigation
  static final List<PlaceSuggestion> egyptianCities = [
    const PlaceSuggestion(
      placeId: 'city_alex',
      description: 'الإسكندرية، مصر',
      mainText: 'الإسكندرية',
      secondaryText: 'عروس البحر الأبيض المتوسط',
      location: LatLng(31.2001, 29.9187),
    ),
    const PlaceSuggestion(
      placeId: 'city_cairo',
      description: 'القاهرة، مصر',
      mainText: 'القاهرة',
      secondaryText: 'العاصمة',
      location: LatLng(30.0444, 31.2357),
    ),
    const PlaceSuggestion(
      placeId: 'city_giza',
      description: 'الجيزة، مصر',
      mainText: 'الجيزة',
      secondaryText: 'محافظة الجيزة',
      location: LatLng(30.0131, 31.2089),
    ),
    const PlaceSuggestion(
      placeId: 'city_smouha',
      description: 'سموحة، الإسكندرية، مصر',
      mainText: 'سموحة',
      secondaryText: 'قسم سيدي جابر، الإسكندرية',
      location: LatLng(31.2156, 29.9538),
    ),
    const PlaceSuggestion(
      placeId: 'city_nasr_city',
      description: 'مدينة نصر، القاهرة، مصر',
      mainText: 'مدينة نصر',
      secondaryText: 'شرق القاهرة',
      location: LatLng(30.0566, 31.3301),
    ),
    const PlaceSuggestion(
      placeId: 'city_mansoura',
      description: 'المنصورة، الدقهلية، مصر',
      mainText: 'المنصورة',
      secondaryText: 'محافظة الدقهلية',
      location: LatLng(31.0409, 31.3785),
    ),
    const PlaceSuggestion(
      placeId: 'city_tanta',
      description: 'طنطا، الغربية، مصر',
      mainText: 'طنطا',
      secondaryText: 'محافظة الغربية',
      location: LatLng(30.7865, 31.0004),
    ),
    const PlaceSuggestion(
      placeId: 'city_october',
      description: 'مدينة السادس من أكتوبر، الجيزة',
      mainText: '6 أكتوبر',
      secondaryText: 'محافظة الجيزة',
      location: LatLng(29.9723, 30.9427),
    ),
    const PlaceSuggestion(
      placeId: 'city_zayed',
      description: 'مدينة الشيخ زايد، الجيزة',
      mainText: 'الشيخ زايد',
      secondaryText: 'محافظة الجيزة',
      location: LatLng(30.0514, 30.9788),
    ),
    const PlaceSuggestion(
      placeId: 'city_north_coast',
      description: 'الساحل الشمالي، مطروح، مصر',
      mainText: 'الساحل الشمالي',
      secondaryText: 'طريق الإسكندرية - مطروح',
      location: LatLng(30.8872, 29.3512),
    ),
  ];

  /// Queries Google Places Autocomplete API with debounced user input.
  /// Falls back to local Egyptian cities catalog if network is down or API limit reached.
  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return [];
    }

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {
          'input': cleanQuery,
          'language': 'ar',
          'components': 'country:eg',
          'key': _apiKey,
        },
      );

      final request = await _client.getUrl(uri);
      request.headers.set('X-Android-Package', _androidPackage);
      request.headers.set('X-Android-Cert', _androidCert);

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody) as Map<String, dynamic>;
        final status = data['status'] as String?;

        if (status == 'OK' && data['predictions'] is List) {
          final list = (data['predictions'] as List).map((p) {
            final placeId = p['place_id'] as String? ?? '';
            final description = p['description'] as String? ?? '';
            final structured = p['structured_formatting'] as Map<String, dynamic>? ?? {};
            final mainText = structured['main_text'] as String? ?? description;
            final secondaryText = structured['secondary_text'] as String? ?? '';

            return PlaceSuggestion(
              placeId: placeId,
              description: description,
              mainText: mainText,
              secondaryText: secondaryText,
            );
          }).toList();

          if (list.isNotEmpty) {
            return list;
          }
        }
      }
    } catch (e) {
      debugPrint('GooglePlacesService searchPlaces error: $e');
    }

    // Offline / Fallback search across local curated list
    final lowerQuery = cleanQuery.toLowerCase();
    return egyptianCities.where((c) {
      return c.mainText.toLowerCase().contains(lowerQuery) ||
          c.secondaryText.toLowerCase().contains(lowerQuery) ||
          c.description.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Fetches exact latitude and longitude for a given placeId via Google Place Details API.
  Future<LatLng?> getPlaceDetails(String placeId) async {
    // Check if it's one of the predefined local items
    for (final city in egyptianCities) {
      if (city.placeId == placeId && city.location != null) {
        return city.location;
      }
    }

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': placeId,
          'fields': 'geometry,name,formatted_address',
          'language': 'ar',
          'key': _apiKey,
        },
      );

      final request = await _client.getUrl(uri);
      request.headers.set('X-Android-Package', _androidPackage);
      request.headers.set('X-Android-Cert', _androidCert);

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody) as Map<String, dynamic>;
        final status = data['status'] as String?;

        if (status == 'OK' && data['result'] != null) {
          final result = data['result'] as Map<String, dynamic>;
          final geometry = result['geometry'] as Map<String, dynamic>?;
          final location = geometry?['location'] as Map<String, dynamic>?;

          if (location != null) {
            final lat = (location['lat'] as num?)?.toDouble();
            final lng = (location['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              return LatLng(lat, lng);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('GooglePlacesService getPlaceDetails error: $e');
    }

    return null;
  }

  /// Performs reverse lookup to find nearby landmark or address name for given coordinates
  Future<String?> reverseLookup(LatLng latLng) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/nearbysearch/json',
        {
          'location': '${latLng.latitude},${latLng.longitude}',
          'radius': '150',
          'language': 'ar',
          'key': _apiKey,
        },
      );

      final request = await _client.getUrl(uri);
      request.headers.set('X-Android-Package', _androidPackage);
      request.headers.set('X-Android-Cert', _androidCert);

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody) as Map<String, dynamic>;
        final status = data['status'] as String?;

        if (status == 'OK' && data['results'] is List && (data['results'] as List).isNotEmpty) {
          final first = (data['results'] as List).first as Map<String, dynamic>;
          final name = first['name'] as String?;
          final vicinity = first['vicinity'] as String?;
          if (name != null && name.isNotEmpty) {
            if (vicinity != null && vicinity.isNotEmpty && vicinity != name) {
              return '$name، $vicinity';
            }
            return name;
          }
        }
      }
    } catch (e) {
      debugPrint('GooglePlacesService reverseLookup error: $e');
    }
    return null;
  }
}
