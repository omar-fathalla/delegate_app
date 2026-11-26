import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:delegate_app/core/utils/google_maps_loader.dart';
import '../../../../core/services/google_places_service.dart';

class LocationPickResult {
  final LatLng location;
  final double radius;
  final String? addressName;

  const LocationPickResult({
    required this.location,
    required this.radius,
    this.addressName,
  });
}

class FullscreenMapPickerDialog extends StatefulWidget {
  final LatLng initialLocation;
  final double initialRadius;
  final String? initialAddress;

  const FullscreenMapPickerDialog({
    super.key,
    required this.initialLocation,
    this.initialRadius = 100.0,
    this.initialAddress,
  });

  static Future<LocationPickResult?> show(
    BuildContext context, {
    required LatLng initialLocation,
    double initialRadius = 100.0,
    String? initialAddress,
  }) {
    return Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullscreenMapPickerDialog(
          initialLocation: initialLocation,
          initialRadius: initialRadius,
          initialAddress: initialAddress,
        ),
      ),
    );
  }

  @override
  State<FullscreenMapPickerDialog> createState() =>
      _FullscreenMapPickerDialogState();
}

class _FullscreenMapPickerDialogState extends State<FullscreenMapPickerDialog> {
  late LatLng _currentLocation;
  late double _currentRadius;
  GoogleMapController? _mapController;
  final GooglePlacesService _placesService = GooglePlacesService();

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  List<PlaceSuggestion> _placeSuggestions = [];
  bool _isFetchingSuggestions = false;
  bool _showSuggestionsDropdown = false;

  String? _resolvedAddress;
  bool _isResolvingAddress = false;
  bool _isLocating = false;
  MapType _currentMapType = MapType.normal;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.initialLocation;
    _currentRadius = widget.initialRadius;
    _resolvedAddress = widget.initialAddress;

    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _searchController.text = widget.initialAddress!;
    }

    if (_resolvedAddress == null) {
      _resolveAddress(_currentLocation);
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    final clean = query.trim();
    if (clean.length < 2) {
      setState(() {
        _placeSuggestions = [];
        _showSuggestionsDropdown = false;
      });
      return;
    }

    _searchDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isFetchingSuggestions = true);
      final results = await _placesService.searchPlaces(clean);
      if (mounted) {
        setState(() {
          _placeSuggestions = results;
          _isFetchingSuggestions = false;
          _showSuggestionsDropdown = results.isNotEmpty;
        });
      }
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searchController.text = suggestion.description;
      _showSuggestionsDropdown = false;
      _isFetchingSuggestions = true;
    });

    LatLng? target = suggestion.location;
    if (target == null && suggestion.placeId.isNotEmpty) {
      target = await _placesService.getPlaceDetails(suggestion.placeId);
    }

    if (target != null && mounted) {
      setState(() {
        _currentLocation = target!;
        _resolvedAddress = suggestion.description;
        _isFetchingSuggestions = false;
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 17),
        ),
      );
    } else if (mounted) {
      setState(() => _isFetchingSuggestions = false);
    }
  }

  Future<void> _handleSearchSubmit(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isFetchingSuggestions = true;
      _showSuggestionsDropdown = false;
    });

    final results = await _placesService.searchPlaces(clean);
    if (results.isNotEmpty) {
      await _selectSuggestion(results.first);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر العثور على موقع: $clean',
            style: GoogleFonts.cairo(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (mounted) {
      setState(() => _isFetchingSuggestions = false);
    }
  }

  Future<void> _resolveAddress(LatLng latLng) async {
    if (!mounted) return;
    setState(() => _isResolvingAddress = true);
    final addr = await _placesService.reverseLookup(latLng);
    if (mounted) {
      setState(() {
        _resolvedAddress = addr;
        _isResolvingAddress = false;
      });
    }
  }

  Future<void> _moveToMyLocation() async {
    setState(() => _isLocating = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      ).catchError((_) async => (await Geolocator.getLastKnownPosition())!);

      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _currentLocation = latLng);
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 16.5),
        ),
      );
      _resolveAddress(latLng);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'تحديد موقع الفرع على الخريطة',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'نوع الخريطة',
            icon: Icon(
              _currentMapType == MapType.normal
                  ? Icons.satellite_alt_rounded
                  : Icons.map_rounded,
            ),
            onPressed: () {
              setState(() {
                _currentMapType = _currentMapType == MapType.normal
                    ? MapType.hybrid
                    : MapType.normal;
              });
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          // ── The Google Map ──────────────────────────────────────────
          GoogleMapsReadyGate(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentLocation,
                zoom: 16,
              ),
              mapType: _currentMapType,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
              onMapCreated: (controller) => _mapController = controller,
              onTap: (pos) {
                setState(() => _currentLocation = pos);
                _resolveAddress(pos);
              },
              markers: {
                Marker(
                  markerId: const MarkerId('selected_branch_pin'),
                  position: _currentLocation,
                  draggable: true,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueViolet,
                  ),
                  onDragEnd: (newPos) {
                    setState(() => _currentLocation = newPos);
                    _resolveAddress(newPos);
                  },
                ),
              },
              circles: {
                Circle(
                  circleId: const CircleId('branch_geofence'),
                  center: _currentLocation,
                  radius: _currentRadius,
                  fillColor: colorScheme.primary.withValues(alpha: 0.22),
                  strokeColor: colorScheme.primary.withValues(alpha: 0.7),
                  strokeWidth: 2,
                ),
              },
            ),
          ),

          // ── Top Search Bar & Suggestions ─────────────────────────────
          PositionedDirectional(
            top: 14,
            start: 16,
            end: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(16),
                  color: colorScheme.surface,
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن اسم المكان، العنوان، أو المدينة...',
                      hintStyle: GoogleFonts.cairo(
                        fontSize: 13.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      prefixIcon: Icon(Icons.search_rounded, color: colorScheme.primary),
                      suffixIcon: _isFetchingSuggestions
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary,
                                ),
                              ),
                            )
                          : (_searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 20),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _showSuggestionsDropdown = false;
                                      _placeSuggestions = [];
                                    });
                                  },
                                )
                              : null),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colorScheme.primary, width: 2),
                      ),
                    ),
                    onChanged: _onSearchChanged,
                    onSubmitted: _handleSearchSubmit,
                  ),
                ),
                if (_showSuggestionsDropdown && _placeSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Card(
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    color: colorScheme.surface,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _placeSuggestions.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: colorScheme.outlineVariant.withValues(alpha: 0.2),
                        ),
                        itemBuilder: (ctx, i) {
                          final item = _placeSuggestions[i];
                          return ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.location_on_rounded,
                                color: colorScheme.primary,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              item.mainText,
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: item.secondaryText.isNotEmpty
                                ? Text(
                                    item.secondaryText,
                                    style: GoogleFonts.cairo(
                                      fontSize: 11.5,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: () => _selectSuggestion(item),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Floating Zoom & Center Buttons ─────────────────────────
          PositionedDirectional(
            top: 76,
            end: 16,
            child: Column(
              children: [
                _buildMapFloatingBtn(
                  icon: Icons.add_rounded,
                  tooltip: 'تكبير',
                  onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                _buildMapFloatingBtn(
                  icon: Icons.remove_rounded,
                  tooltip: 'تصغير',
                  onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 12),
                _buildMapFloatingBtn(
                  icon: Icons.center_focus_strong_rounded,
                  tooltip: 'توسيط على الدبوس',
                  onTap: () => _mapController?.animateCamera(
                    CameraUpdate.newLatLng(_currentLocation),
                  ),
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 8),
                _buildMapFloatingBtn(
                  icon: Icons.my_location_rounded,
                  tooltip: 'موقعي الحالي',
                  isLoading: _isLocating,
                  onTap: _moveToMyLocation,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),

          // ── Bottom Selection & Radius Controller Card ───────────────
          PositionedDirectional(
            bottom: 24,
            start: 16,
            end: 16,
            child: Card(
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Address / Location Info Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.location_on_rounded,
                            color: colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isResolvingAddress
                                    ? 'جاري استخراج العنوان...'
                                    : (_resolvedAddress ?? 'موقع مخصص على الخريطة'),
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_currentLocation.latitude.toStringAsFixed(5)}, ${_currentLocation.longitude.toStringAsFixed(5)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Radius Slider Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'نطاق الحضور والسياج الجغرافي:',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_currentRadius.toInt()} متر',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _currentRadius.clamp(50.0, 500.0),
                      min: 50,
                      max: 500,
                      divisions: 45,
                      activeColor: colorScheme.primary,
                      inactiveColor: colorScheme.primaryContainer,
                      onChanged: (val) {
                        setState(() => _currentRadius = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Confirm Location Button
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          LocationPickResult(
                            location: _currentLocation,
                            radius: _currentRadius,
                            addressName: _resolvedAddress,
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text(
                        'تأكيد هذا الموقع',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapFloatingBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required ColorScheme colorScheme,
    bool isLoading = false,
  }) {
    return Material(
      color: colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : Icon(icon, color: colorScheme.onSurface, size: 22),
        ),
      ),
    );
  }
}
