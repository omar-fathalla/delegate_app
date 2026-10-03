import 'google_maps_loader_stub.dart'
    if (dart.library.js_interop) 'google_maps_loader_web.dart' as loader;

/// Safely checks if Google Maps SDK is initialized and ready to render
bool get isGoogleMapsAvailable => loader.isGoogleMapsAvailable();
