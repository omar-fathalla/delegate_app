import 'package:flutter/material.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
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

  @override
  void dispose() {
    _nameController.dispose();
    _radiusController.dispose();
    _searchController.dispose();
    super.dispose();
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
    const initialLocation = LatLng(24.7136, 46.6753); // Default location
    final radius = double.tryParse(_radiusController.text) ?? 100.0;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addBranch)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideScreen = constraints.maxWidth > 800;

          if (isWideScreen) {
            // Web / Tablet Layout (Side by Side)
            return Row(
              children: [
                Expanded(
                  flex: 1,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: _buildForm(l10n),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        start: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: _buildMap(initialLocation, radius, l10n),
                  ),
                ),
              ],
            );
          } else {
            // Mobile Layout (Stacked)
            return Column(
              children: [
                // Top half: Map
                Expanded(
                  flex: 4,
                  child: _buildMap(initialLocation, radius, l10n),
                ),
                // Bottom half: Form
                Expanded(
                  flex: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: _buildForm(l10n),
                    ),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.adminDashboard,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l10n.branchName,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              filled: true,
              fillColor: Colors.grey.withValues(alpha: 0.05),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return l10n.pleaseEnterBranchName;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _radiusController,
            decoration: InputDecoration(
              labelText: l10n.geofenceRadius,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              filled: true,
              fillColor: Colors.grey.withValues(alpha: 0.05),
              suffixText: 'm', // Meters indicator
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) {
              setState(() {});
            },
          ),
          const SizedBox(height: 24),
          if (_selectedActionPoint != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l10n.branchLocation}:\n${_selectedActionPoint!.latitude.toStringAsFixed(4)}, ${_selectedActionPoint!.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          ElevatedButton(
            onPressed: _isLoading ? null : _saveBranch,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    l10n.saveBranch,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(
    LatLng initialLocation,
    double radius,
    AppLocalizations l10n,
  ) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _selectedActionPoint ?? initialLocation,
            zoom: _selectedActionPoint == null ? 12 : 16,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          onMapCreated: (controller) => _mapController = controller,
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
                    fillColor: Colors.blue.withValues(alpha: 0.2),
                    strokeColor: Colors.blue,
                    strokeWidth: 2,
                  ),
                }
              : {},
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: _searchLocation,
                decoration: InputDecoration(
                  hintText: l10n.searchCityOrRegion,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            FocusScope.of(context).unfocus();
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          child: FloatingActionButton.extended(
            heroTag: 'myLocationFab',
            onPressed: _isLoading ? null : _getCurrentLocation,
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF1565C0),
            icon: const Icon(Icons.my_location),
            label: Text(
              l10n.myLocation,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
