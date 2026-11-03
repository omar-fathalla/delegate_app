import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/core/config/maps_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default ENV uses the production Maps and Places keys', () {
    expect(AppEnv.mapsJsApiKey, MapsKeys.prodMapsJs);
    expect(AppEnv.placesApiKey, MapsKeys.prodPlaces);
  });

  test('dev uses the tashil-dev key, never a production key', () {
    expect(AppEnv.mapsJsApiKeyFor('dev'), MapsKeys.devMapsPlaces);
    expect(AppEnv.placesApiKeyFor('dev'), MapsKeys.devMapsPlaces);
    expect(MapsKeys.devMapsPlaces, isNot(MapsKeys.prodMapsJs));
    expect(MapsKeys.devMapsPlaces, isNot(MapsKeys.prodPlaces));
  });

  test('MAPS_API_KEY override wins when set', () {
    expect(AppEnv.mapsJsApiKeyFor('prod', 'override'), 'override');
    expect(AppEnv.placesApiKeyFor('dev', 'override'), 'override');
  });
}
