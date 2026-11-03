import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/google_places_service.dart';
import '../../data/models/branch_model.dart';
import '../bloc/branch_bloc.dart';
import '../widgets/fullscreen_map_picker_dialog.dart';
import 'package:delegate_app/core/utils/google_maps_loader.dart';
import 'branch_details_screen.dart';

class AddBranchScreen extends StatelessWidget {
  final bool showAppBar;
  final String? initialOrganizationUID;
  final String? initialOrganizationName;
  final BranchModel? branchToEdit;

  const AddBranchScreen({
    super.key,
    this.showAppBar = false,
    this.initialOrganizationUID,
    this.initialOrganizationName,
    this.branchToEdit,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<BranchBloc>(),
      child: _AddBranchView(
        showAppBar: showAppBar,
        initialOrganizationUID: initialOrganizationUID,
        initialOrganizationName: initialOrganizationName,
        branchToEdit: branchToEdit,
      ),
    );
  }
}

class _AddBranchView extends StatefulWidget {
  final bool showAppBar;
  final String? initialOrganizationUID;
  final String? initialOrganizationName;
  final BranchModel? branchToEdit;

  const _AddBranchView({
    this.showAppBar = false,
    this.initialOrganizationUID,
    this.initialOrganizationName,
    this.branchToEdit,
  });

  @override
  State<_AddBranchView> createState() => _AddBranchViewState();
}

class _AddBranchViewState extends State<_AddBranchView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _radiusController = TextEditingController(text: '100');

  String? _selectedOrgUID;
  String? _selectedOrgName;
  String? _orgValidationError;
  List<Map<String, dynamic>> _organizations = [];
  bool _isLoadingOrgs = true;

  LatLng? _selectedActionPoint;
  bool _isLocating = false;

  final _searchController = TextEditingController();
  GoogleMapController? _mapController;
  bool _isSearching = false;
  bool _isMapReady = false;

  final GooglePlacesService _placesService = GooglePlacesService();
  Timer? _searchDebounceTimer;
  List<PlaceSuggestion> _placeSuggestions = [];
  bool _isFetchingSuggestions = false;
  bool _showSuggestionsDropdown = false;
  bool _isMapTouching = false;

  // Default fallback location (Alexandria Center, Egypt)
  LatLng _initialLocation = const LatLng(31.2001, 29.9187);

  @override
  void initState() {
    super.initState();
    if (widget.branchToEdit != null) {
      final b = widget.branchToEdit!;
      _nameController.text = b.branchName;
      _radiusController.text = b.geofenceRadius.toInt().toString();
      _selectedOrgUID = b.organizationUID ?? widget.initialOrganizationUID;
      _selectedOrgName = b.organizationName ?? widget.initialOrganizationName;
      final branchLocation = LatLng(b.latitude, b.longitude);
      _initialLocation = branchLocation;
      _selectedActionPoint = branchLocation;
      _searchController.text = b.branchName;
    } else {
      _selectedOrgUID = widget.initialOrganizationUID;
      _selectedOrgName = widget.initialOrganizationName;
      _selectedActionPoint = _initialLocation; // Pin is immediately visible!
      _fetchInitialLocation();
    }
    _loadOrganizations();
  }

  Future<void> _loadOrganizations() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('organizations')
          .get();
      if (!mounted) return;
      final orgs = snapshot.docs.map((doc) {
        final data = doc.data();
        final name = data['name'] as String? ??
            data['title'] as String? ??
            data['orgName'] as String? ??
            doc.id;
        return {
          'uid': doc.id,
          'name': name,
        };
      }).toList();

      orgs.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      setState(() {
        _organizations = orgs;
        _isLoadingOrgs = false;

        if (_selectedOrgUID != null) {
          final found = _organizations.firstWhere(
            (o) => o['uid'] == _selectedOrgUID,
            orElse: () => {},
          );
          if (found.isNotEmpty) {
            _selectedOrgName = found['name'] as String?;
          }
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingOrgs = false);
      }
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _nameController.dispose();
    _radiusController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialLocation() async {
    if (widget.branchToEdit != null) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      // 1. Fast fallback: last known position (0ms)
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && mounted) {
          final userLatLng = LatLng(lastKnown.latitude, lastKnown.longitude);
          setState(() {
            _initialLocation = userLatLng;
            _selectedActionPoint ??= userLatLng;
          });
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: userLatLng, zoom: 15),
            ),
          );
        }
      } catch (_) {}

      // 2. High accuracy with strict timeout so it never hangs the thread
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
      final userLatLng = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() {
          _initialLocation = userLatLng;
          _selectedActionPoint ??= userLatLng;
        });

        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: userLatLng, zoom: 15),
          ),
        );
      }
    } catch (_) {}
  }

  void _showOrganizationPicker() {
    FocusScope.of(context).unfocus();
    String query = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colorScheme = Theme.of(context).colorScheme;
            final filtered = query.trim().isEmpty
                ? _organizations
                : _organizations.where((org) {
                    final name = (org['name'] as String? ?? '').toLowerCase();
                    return name.contains(query.trim().toLowerCase());
                  }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Row(
                        children: [
                          Icon(Icons.corporate_fare_rounded, color: colorScheme.primary),
                          const SizedBox(width: 10),
                          Text(
                            'اختر المنظمة التابع لها الفرع',
                            style: GoogleFonts.cairo(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                    ),
                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'ابحث عن منظمة...',
                          hintStyle: GoogleFonts.cairo(fontSize: 14),
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) {
                          setSheetState(() => query = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // List of Organizations
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _isLoadingOrgs
                                    ? 'جاري تحميل المنظمات...'
                                    : 'لا توجد منظمات مطابقة للبحث',
                                style: GoogleFonts.cairo(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final org = filtered[i];
                                final uid = org['uid'] as String;
                                final name = org['name'] as String;
                                final isSelected = uid == _selectedOrgUID;

                                return ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? colorScheme.primary.withValues(alpha: 0.15)
                                          : colorScheme.surfaceContainerHighest,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.storefront_rounded,
                                      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                      size: 22,
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    style: GoogleFonts.cairo(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? Icon(Icons.check_circle_rounded, color: colorScheme.primary)
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedOrgUID = uid;
                                      _selectedOrgName = name;
                                      _orgValidationError = null;
                                    });
                                    Navigator.pop(sheetContext);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
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
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = suggestion.mainText;
      }
      _showSuggestionsDropdown = false;
      _isSearching = true;
    });

    LatLng? target = suggestion.location;
    if (target == null && suggestion.placeId.isNotEmpty) {
      target = await _placesService.getPlaceDetails(suggestion.placeId);
    }

    if (target != null && mounted) {
      setState(() {
        _selectedActionPoint = target;
        _isSearching = false;
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 16.5),
        ),
      );
    } else if (mounted) {
      setState(() => _isSearching = false);
    }
  }

  void _selectQuickCity(String name, LatLng latLng) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedActionPoint = latLng;
      _searchController.text = name;
      _showSuggestionsDropdown = false;
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: latLng, zoom: 15.5),
      ),
    );
  }

  Future<void> _openFullscreenPicker() async {
    FocusScope.of(context).unfocus();
    final currentPoint = _selectedActionPoint ?? _initialLocation;
    final radiusVal = double.tryParse(_radiusController.text) ?? 100.0;

    final result = await FullscreenMapPickerDialog.show(
      context,
      initialLocation: currentPoint,
      initialRadius: radiusVal,
      initialAddress: _searchController.text.isNotEmpty ? _searchController.text : null,
    );

    if (result != null && mounted) {
      setState(() {
        _selectedActionPoint = result.location;
        _radiusController.text = result.radius.toInt().toString();
        if (result.addressName != null && result.addressName!.isNotEmpty) {
          _searchController.text = result.addressName!;
          if (_nameController.text.trim().isEmpty) {
            _nameController.text = result.addressName!.split('،').first.trim();
          }
        }
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: result.location, zoom: 16.5),
        ),
      );
    }
  }

  Future<void> _searchLocation(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _showSuggestionsDropdown = false;
    });

    try {
      // 1. Try Google Places first
      final places = await _placesService.searchPlaces(clean);
      if (places.isNotEmpty) {
        await _selectSuggestion(places.first);
        return;
      }

      // 2. Native geocoding fallback
      final locations = await locationFromAddress(clean);
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
      } else {
        throw Exception('Location not found');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر العثور على موقع: $clean')),
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
      _isLocating = true;
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

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        throw Exception('Location unavailable');
      }

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
          _isLocating = false;
        });
      }
    }
  }

  void _saveBranch() {
    if (_selectedOrgUID == null || _selectedOrgUID!.isEmpty) {
      setState(() {
        _orgValidationError = 'يرجى اختيار المنظمة أولاً';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار المنظمة أولاً'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_selectedActionPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseSelectLocation),
        ),
      );
      return;
    }

    final branchModel = BranchModel(
      id: widget.branchToEdit?.id ?? '',
      branchName: _nameController.text.trim(),
      latitude: _selectedActionPoint!.latitude,
      longitude: _selectedActionPoint!.longitude,
      geofenceRadius: double.tryParse(_radiusController.text) ?? 100.0,
      organizationUID: _selectedOrgUID,
      organizationName: _selectedOrgName,
    );

    if (widget.branchToEdit != null) {
      context.read<BranchBloc>().add(BranchUpdateRequested(branch: branchModel));
    } else {
      context.read<BranchBloc>().add(BranchAddRequested(branch: branchModel));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final radius = double.tryParse(_radiusController.text) ?? 100.0;
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<BranchBloc, BranchState>(
      listener: (context, state) {
        if (state is BranchActionSuccess) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.branchAddedSuccessfully)));
          final branchModel = state.branch is BranchModel
              ? state.branch as BranchModel
              : BranchModel(
                  id: state.branch.id,
                  branchName: state.branch.branchName,
                  latitude: state.branch.latitude,
                  longitude: state.branch.longitude,
                  geofenceRadius: state.branch.geofenceRadius,
                  organizationUID: state.branch.organizationUID,
                  organizationName: state.branch.organizationName,
                );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => BranchDetailsScreen(branch: branchModel),
            ),
          );
        } else if (state is BranchUpdateSuccess) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.branchUpdatedSuccessfully)));
          final branchModel = state.branch is BranchModel
              ? state.branch as BranchModel
              : BranchModel(
                  id: state.branch.id,
                  branchName: state.branch.branchName,
                  latitude: state.branch.latitude,
                  longitude: state.branch.longitude,
                  geofenceRadius: state.branch.geofenceRadius,
                  organizationUID: state.branch.organizationUID,
                  organizationName: state.branch.organizationName,
                );
          Navigator.of(context).pop(branchModel);
        } else if (state is BranchError) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      builder: (context, state) {
        final isSaving = state is BranchLoading;

        return Scaffold(
          appBar: widget.showAppBar
              ? AppBar(
                  title: Text(
                    widget.branchToEdit != null
                        ? l10n.editBranch
                        : l10n.addBranch,
                  ),
                  centerTitle: true,
                )
              : null,
          backgroundColor: colorScheme.surface,
          body: SafeArea(
            child: SingleChildScrollView(
              physics: _isMapTouching
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Organization Selection Field
                    FormField<String>(
                      initialValue: _selectedOrgUID,
                      validator: (val) {
                        if (_selectedOrgUID == null || _selectedOrgUID!.isEmpty) {
                          return 'يرجى اختيار المنظمة';
                        }
                        return null;
                      },
                      builder: (field) {
                        final hasError = field.hasError || _orgValidationError != null;
                        final errorText = field.errorText ?? _orgValidationError;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: _showOrganizationPicker,
                              borderRadius: BorderRadius.circular(12),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'المنظمة',
                                  labelStyle: TextStyle(
                                    color: hasError
                                        ? colorScheme.error
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.corporate_fare_rounded,
                                    color: hasError
                                        ? colorScheme.error
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  suffixIcon: Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 30,
                                  ),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest,
                                  border: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                      color: hasError
                                          ? colorScheme.error
                                          : colorScheme.outline,
                                    ),
                                  ),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                      color: hasError
                                          ? colorScheme.error
                                          : colorScheme.outline,
                                    ),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(color: colorScheme.primary),
                                  ),
                                ),
                                child: Text(
                                  _selectedOrgName ??
                                      (_isLoadingOrgs
                                          ? 'جاري تحميل المنظمات...'
                                          : 'اختر المنظمة التابع لها الفرع'),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _selectedOrgName != null
                                        ? colorScheme.onSurface
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: _selectedOrgName != null
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                            if (hasError && errorText != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6, right: 12),
                                child: Text(
                                  errorText,
                                  style: TextStyle(
                                    color: colorScheme.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Branch Name Field
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.branchName,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                        ),
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
                      onChanged: _onSearchChanged,
                      style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.searchCityOrRegion,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        prefixIcon: IconButton(
                          icon: Icon(
                            Icons.search_rounded,
                            color: colorScheme.primary,
                          ),
                          tooltip: 'بحث',
                          onPressed: () => _searchLocation(_searchController.text),
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
                        suffixIcon: (_isSearching || _isFetchingSuggestions)
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                                        setState(() {
                                          _placeSuggestions = [];
                                          _showSuggestionsDropdown = false;
                                        });
                                      },
                                    )
                                  : null),
                      ),
                    ),

                    // ── Live Autocomplete Suggestions Dropdown ──
                    if (_showSuggestionsDropdown && _placeSuggestions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Material(
                        color: colorScheme.surfaceContainerHigh,
                        elevation: 3,
                        shadowColor: Colors.black.withValues(alpha: 0.15),
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: _placeSuggestions.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              indent: 48,
                              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                            ),
                            itemBuilder: (ctx, i) {
                              final suggestion = _placeSuggestions[i];
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    color: colorScheme.primary,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  suggestion.mainText,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                subtitle: suggestion.secondaryText.isNotEmpty
                                    ? Text(
                                        suggestion.secondaryText,
                                        style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : null,
                                onTap: () => _selectSuggestion(suggestion),
                              );
                            },
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // ── Quick City & Location Chips ──
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          ActionChip(
                            avatar: _isLocating
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.primary,
                                    ),
                                  )
                                : Icon(Icons.my_location, size: 16, color: colorScheme.primary),
                            label: Text(
                              l10n.myLocation,
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: colorScheme.primaryContainer,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(19),
                            ),
                            onPressed: (_isLocating || isSaving)
                                ? null
                                : _getCurrentLocation,
                          ),
                          const SizedBox(width: 8),
                          for (final city in GooglePlacesService.egyptianCities) ...[
                            ActionChip(
                              label: Text(
                                city.mainText,
                                style: GoogleFonts.cairo(fontSize: 12),
                              ),
                              backgroundColor: colorScheme.surfaceContainerHighest,
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(19),
                              ),
                              onPressed: () => _selectQuickCity(
                                city.mainText,
                                city.location!,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

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
                        overlayColor: colorScheme.primary.withValues(
                          alpha: 0.1,
                        ),
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
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _openFullscreenPicker,
                          icon: const Icon(Icons.fullscreen_rounded, size: 20),
                          label: Text(
                            isArabic ? 'شاشة كاملة' : 'Fullscreen',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Map Container
                    Container(
                      height: 300,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _buildMapWidget(radius, colorScheme),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Branch Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: isSaving ? null : _saveBranch,
                        icon: const Icon(Icons.save_outlined),
                        label: isSaving
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: colorScheme.onPrimary,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                widget.branchToEdit != null
                                    ? l10n.saveChanges
                                    : l10n.saveBranch,
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
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
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapWidget(double radius, ColorScheme colorScheme) {
    return Listener(
      onPointerDown: (_) {
        if (!_isMapTouching) setState(() => _isMapTouching = true);
      },
      onPointerUp: (_) {
        if (_isMapTouching) setState(() => _isMapTouching = false);
      },
      onPointerCancel: (_) {
        if (_isMapTouching) setState(() => _isMapTouching = false);
      },
      child: Stack(
        children: [
          GoogleMapsReadyGate(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _selectedActionPoint ?? _initialLocation,
                zoom: 16,
              ),
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
              onMapCreated: (controller) {
                _mapController = controller;
                if (!_isMapReady) {
                  setState(() => _isMapReady = true);
                }
                if (widget.branchToEdit != null && _selectedActionPoint != null) {
                  controller.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: _selectedActionPoint!,
                        zoom: 16.5,
                      ),
                    ),
                  );
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
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueViolet,
                        ),
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
                        fillColor: colorScheme.primary.withValues(alpha: 0.22),
                        strokeColor: colorScheme.primary.withValues(alpha: 0.65),
                        strokeWidth: 2,
                      ),
                    }
                  : {},
            ),
          ),

          // ── Floating Zoom Buttons on Top-End ──
          PositionedDirectional(
            top: 10,
            end: 10,
            child: Column(
              children: [
                _buildMapMiniBtn(
                  icon: Icons.add_rounded,
                  tooltip: 'تكبير',
                  onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 6),
                _buildMapMiniBtn(
                  icon: Icons.remove_rounded,
                  tooltip: 'تصغير',
                  onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),

          // ── Floating Fullscreen Button on Top-Start ──
          PositionedDirectional(
            top: 10,
            start: 10,
            child: _buildMapMiniBtn(
              icon: Icons.fullscreen_rounded,
              tooltip: 'شاشة كاملة',
              onTap: _openFullscreenPicker,
              colorScheme: colorScheme,
            ),
          ),

          // ── Floating Center on Pin Button on Bottom-End ──
          if (_selectedActionPoint != null)
            PositionedDirectional(
              bottom: 10,
              end: 10,
              child: _buildMapMiniBtn(
                icon: Icons.center_focus_strong_rounded,
                tooltip: 'توسيط الدبوس',
                onTap: () => _mapController?.animateCamera(
                  CameraUpdate.newLatLng(_selectedActionPoint!),
                ),
                colorScheme: colorScheme,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapMiniBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required ColorScheme colorScheme,
  }) {
    return Material(
      color: colorScheme.surface.withValues(alpha: 0.9),
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          child: Icon(icon, color: colorScheme.onSurface, size: 20),
        ),
      ),
    );
  }
}
