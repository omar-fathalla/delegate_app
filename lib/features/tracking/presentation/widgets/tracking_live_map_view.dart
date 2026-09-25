import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../domain/entities/delegate_tracking_session.dart';
import 'delegate_tracking_card.dart';

class TrackingLiveMapView extends StatefulWidget {
  final List<DelegateTrackingSession> sessions;
  final ValueChanged<DelegateTrackingSession> onToggleTracking;
  final VoidCallback? onRefresh;

  const TrackingLiveMapView({
    super.key,
    required this.sessions,
    required this.onToggleTracking,
    this.onRefresh,
  });

  @override
  State<TrackingLiveMapView> createState() => _TrackingLiveMapViewState();
}

class _TrackingLiveMapViewState extends State<TrackingLiveMapView> {
  GoogleMapController? _mapController;
  DelegateTrackingSession? _selectedSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 1. حساب المركز الافتراضي
    LatLng initialCenter = const LatLng(30.0444, 31.2357); // Cairo default
    if (widget.sessions.isNotEmpty) {
      final first = widget.sessions.first;
      initialCenter = LatLng(
        first.lastLatitude ?? first.branchLat,
        first.lastLongitude ?? first.branchLng,
      );
    }

    // 2. تجميع دوائر نطاق الفروع
    final Set<Circle> circles = {};
    final Map<String, DelegateTrackingSession> uniqueBranches = {};
    for (final s in widget.sessions) {
      if (s.branchLat != 0 && s.branchLng != 0) {
        uniqueBranches[s.branchName] = s;
      }
    }

    for (final entry in uniqueBranches.entries) {
      final s = entry.value;
      circles.add(
        Circle(
          circleId: CircleId('geofence_${s.branchName}'),
          center: LatLng(s.branchLat, s.branchLng),
          radius: s.geofenceRadius,
          fillColor: colorScheme.primary.withValues(alpha: 0.15),
          strokeColor: colorScheme.primary,
          strokeWidth: 2,
        ),
      );
    }

    // 3. بناء دبابيس المناديب والفروع
    final Set<Marker> markers = {};

    // دبابيس الفروع
    for (final entry in uniqueBranches.entries) {
      final s = entry.value;
      markers.add(
        Marker(
          markerId: MarkerId('branch_${s.branchName}'),
          position: LatLng(s.branchLat, s.branchLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: 'فرع: ${s.branchName}',
            snippet: 'نطاق الأمان: ${s.geofenceRadius.toInt()} متر',
          ),
        ),
      );
    }

    // دبابيس المناديب
    for (final s in widget.sessions) {
      final lat = s.lastLatitude ?? s.branchLat;
      final lng = s.lastLongitude ?? s.branchLng;
      if (lat == 0 && lng == 0) continue;

      double hue;
      String statusSnippet;
      if (s.isOutside) {
        hue = BitmapDescriptor.hueRed;
        final excess = (s.currentDistanceMeters - s.geofenceRadius).toInt();
        statusSnippet = '🔴 خارج النطاق بـ $excess متر';
      } else if (s.isOffline) {
        hue = BitmapDescriptor.hueOrange;
        statusSnippet = '🟠 غير متصل بالشبكة';
      } else {
        hue = BitmapDescriptor.hueGreen;
        statusSnippet = '🟢 داخل النطاق (${s.currentDistanceMeters.toInt()}م)';
      }

      markers.add(
        Marker(
          markerId: MarkerId('delegate_${s.delegateId}'),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: s.delegateName,
            snippet: statusSnippet,
          ),
          onTap: () {
            setState(() => _selectedSession = s);
          },
        ),
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialCenter,
            zoom: 16.0,
          ),
          circles: circles,
          markers: markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          onMapCreated: (controller) {
            _mapController = controller;
            _fitMapBounds();
          },
          onTap: (_) {
            if (_selectedSession != null) {
              setState(() => _selectedSession = null);
            }
          },
        ),

        // أزرار التحكم الطافية
        Positioned(
          top: 16,
          left: 16,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'recenter_map_btn',
                backgroundColor: colorScheme.surface,
                foregroundColor: colorScheme.primary,
                onPressed: _fitMapBounds,
                tooltip: 'إعادة ضبط نطاق الخريطة',
                child: const Icon(Icons.crop_free_rounded),
              ),
              const SizedBox(height: 8),
              if (widget.onRefresh != null)
                FloatingActionButton.small(
                  heroTag: 'refresh_map_btn',
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.primary,
                  onPressed: widget.onRefresh,
                  tooltip: 'تحديث فوري',
                  child: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
        ),

        // دليل ألوان الدبابيس
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLegendItem('داخل النطاق', colorScheme.tertiary),
                const SizedBox(height: 4),
                _buildLegendItem('خارج النطاق', colorScheme.error),
                const SizedBox(height: 4),
                _buildLegendItem('أوفلاين', colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),

        // بطاقة المندوب المختار أسفل الخريطة
        if (_selectedSession != null)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: DelegateTrackingCard(
              session: _selectedSession!,
              onToggleTracking: (val) {
                widget.onToggleTracking(_selectedSession!);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildLegendItem(String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  void _fitMapBounds() {
    if (_mapController == null || widget.sessions.isEmpty) return;

    double? minLat, maxLat, minLng, maxLng;
    for (final s in widget.sessions) {
      final lat = s.lastLatitude ?? s.branchLat;
      final lng = s.lastLongitude ?? s.branchLng;
      if (lat == 0 && lng == 0) continue;

      minLat = minLat == null ? lat : (lat < minLat ? lat : minLat);
      maxLat = maxLat == null ? lat : (lat > maxLat ? lat : maxLat);
      minLng = minLng == null ? lng : (lng < minLng ? lng : minLng);
      maxLng = maxLng == null ? lng : (lng > maxLng ? lng : maxLng);
    }

    if (minLat != null && maxLat != null && minLng != null && maxLng != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(minLat - 0.002, minLng - 0.002),
        northeast: LatLng(maxLat + 0.002, maxLng + 0.002),
      );
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50),
      );
    }
  }
}
