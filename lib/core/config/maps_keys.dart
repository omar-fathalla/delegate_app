/// Google Maps / Places API keys per environment.
///
/// These are public client keys, restricted in Google Cloud by referrer
/// (web) or app signature (Android). Selected through [AppEnv].
class MapsKeys {
  MapsKeys._();

  /// Production Maps JavaScript key (practice-firebase-72df1). Unchanged.
  static const String prodMapsJs = 'AIzaSyB4gLHxxHshJVbpOR5oq69lLotyfd6mwKs';

  /// Production Places key used by GooglePlacesService. Unchanged.
  static const String prodPlaces = 'AIzaSyDQkxCw7YSM1-qUxcjT9oWA9DNZyp3fsOk';

  /// tashil-dev "Dev Maps/Places web key": referrer-restricted to tashil-dev
  /// hosts and localhost; Maps JavaScript API + Places API only.
  static const String devMapsPlaces = 'AIzaSyB5Kq_ccBFOGWqJgcZk7kyNwrd5TZUjo_g';
}
