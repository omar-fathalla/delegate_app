import 'package:flutter/material.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/models/branch_model.dart';

class AddBranchScreen extends StatefulWidget {
  const AddBranchScreen({super.key});

  @override
  State<AddBranchScreen> createState() => _AddBranchScreenState();
}

class _AddBranchScreenState extends State<AddBranchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _radiusController = TextEditingController(text: '100');

  LatLng? _selectedActionPoint;
  bool _isLoading = false;

  final _searchController = TextEditingController();
  GoogleMapController? _mapController;
  bool _isSearching = false;
  bool _isMapReady = false;

  // Default fallback location (Riyadh) — will be replaced by GPS on init
  LatLng _initialLocation = const LatLng(24.7136, 46.6753);

  @override
  void initState() {
    super.initState();
    // Auto-detect user's GPS location on screen load
    _fetchInitialLocation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _radiusController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Fetches the user's current GPS position and updates the map.
  Future<void> _fetchInitialLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final userLatLng = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _initialLocation = userLatLng;
        });

        // If map is already created, animate to user's location
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: userLatLng, zoom: 14),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching initial location: $e');
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        final newLatLng = LatLng(loc.latitude, loc.longitude);

        setState(() {
          _selectedActionPoint = newLatLng;
        });

        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: newLatLng, zoom: 16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not find location: $query')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.locationServicesDisabled,
              ),
            ),
          );
        }
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.locationPermissionDenied,
                ),
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.locationPermissionDenied,
              ),
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final newLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _selectedActionPoint = newLatLng;
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: newLatLng, zoom: 16),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.errorFetchingLocation),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveBranch() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedActionPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseSelectLocation),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final newBranch = BranchModel(
        id: '', // Firestore will auto-generate if we add() or we can generate a UUID
        branchName: _nameController.text.trim(),
        latitude: _selectedActionPoint!.latitude,
        longitude: _selectedActionPoint!.longitude,
        geofenceRadius: double.tryParse(_radiusController.text) ?? 100.0,
      );

      final docRef = await FirebaseFirestore.instance
          .collection('branches')
          .add(newBranch.toMap());

      final savedBranch = BranchModel(
        id: docRef.id,
        branchName: newBranch.branchName,
        latitude: newBranch.latitude,
        longitude: newBranch.longitude,
        geofenceRadius: newBranch.geofenceRadius,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.branchAddedSuccessfully,
            ),
          ),
        );
        // Navigate to details directly instead of going back
        context.pushReplacement('/admin/branch-details', extra: savedBranch);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.errorGeneral)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final radius = double.tryParse(_radiusController.text) ?? 100.0;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branch Name Field
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: l10n.branchName,
                    labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                    prefixIcon: Icon(
                      Icons.storefront_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.primary),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.pleaseEnterBranchName;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Search Location Field
                TextFormField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onFieldSubmitted: _searchLocation,
                  style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: l10n.searchCityOrRegion,
                    labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                    prefixIcon: Icon(
                      Icons.search_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.outline),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.primary),
                    ),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : (_searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    FocusScope.of(context).unfocus();
                                    setState(() {});
                                  },
                                )
                              : null),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                // Current Location Pill Button
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _getCurrentLocation,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: Text(
                      l10n.myLocation,
                      style: const TextStyle(fontSize: 14),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Geofence Radius Slider
                Text(
                  isArabic
                      ? 'نطاق السياج الجغرافي: ${radius.toInt()} متر'
                      : 'Geofence Radius: ${radius.toInt()}m',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: colorScheme.primary,
                    inactiveTrackColor: colorScheme.primaryContainer,
                    trackHeight: 4,
                    thumbColor: colorScheme.primary,
                    overlayColor: colorScheme.primary.withValues(alpha: 0.1),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 20,
                    ),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: radius.clamp(50.0, 500.0),
                    min: 50,
                    max: 500,
                    onChanged: (value) {
                      setState(() {
                        _radiusController.text = value.toStringAsFixed(0);
                      });
                    },
                  ),
                ),
                // Slider Labels
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '50m',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '500m',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Select Location on Map Header
                Row(
                  children: [
                    Icon(
                      Icons.map_outlined,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isArabic
                          ? 'اختر الموقع على الخريطة'
                          : 'Select Location on Map',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.normal,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Map Container
                Container(
                  height: 280,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: colorScheme
                        .surfaceContainerHighest, // placeholder background
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildMapWidget(radius, colorScheme),
                  ),
                ),
                const SizedBox(height: 24),

                // Save Branch Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _saveBranch,
                    icon: const Icon(Icons.save_outlined),
                    label: _isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: colorScheme.onPrimary,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            l10n.saveBranch,
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              height:
                                  1.2, // Fix vertical alignment/clipping for Cairo
                            ),
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(27),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48), // Padding at bottom for scroll
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapWidget(double radius, ColorScheme colorScheme) {
    if (!_isMapReady && _selectedActionPoint == null) {
      // Return the map directly, but it might take a moment to initialize
    }
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _selectedActionPoint ?? _initialLocation,
        zoom: _selectedActionPoint == null ? 12 : 16,
      ),
      myLocationEnabled:
          false, // UI indicates location is done via the button, not map layer directly but we can enable
      myLocationButtonEnabled:
          false, // The maps standard button hides to conform to UI
      zoomControlsEnabled: true,
      onMapCreated: (controller) {
        _mapController = controller;
        if (!_isMapReady) {
          setState(() => _isMapReady = true);
        }
      },
      onTap: (LatLng position) {
        setState(() {
          _selectedActionPoint = position;
        });
      },
      markers: _selectedActionPoint != null
          ? {
              Marker(
                markerId: const MarkerId('branch_location'),
                position: _selectedActionPoint!,
                draggable: true,
                onDragEnd: (newPosition) {
                  setState(() {
                    _selectedActionPoint = newPosition;
                  });
                },
              ),
            }
          : {},
      circles: _selectedActionPoint != null
          ? {
              Circle(
                circleId: const CircleId('geofence_area'),
                center: _selectedActionPoint!,
                radius: radius,
                fillColor: colorScheme.primary.withValues(alpha: 0.2),
                strokeColor: colorScheme.primary.withValues(alpha: 0.5),
                strokeWidth: 2,
              ),
            }
          : {},
    );
  }
}
