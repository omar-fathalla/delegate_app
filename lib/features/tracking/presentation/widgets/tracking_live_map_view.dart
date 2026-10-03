import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/delegate_tracking_session.dart';
import '../../domain/entities/tracking_breadcrumb.dart';
import '../../data/services/delegate_tracking_service.dart';
import '../../../../core/utils/google_maps_loader.dart';
import '../../../../core/widgets/app_avatar.dart';
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

  final DelegateTrackingService _trackingService = DelegateTrackingService();
  StreamSubscription<List<TrackingBreadcrumb>>? _breadcrumbsSubscription;
  List<TrackingBreadcrumb> _activeBreadcrumbs = [];
  bool _isLoadingTrail = false;

  BitmapDescriptor? _greenMarker;
  BitmapDescriptor? _orangeMarker;
  BitmapDescriptor? _greyMarker;
  BitmapDescriptor? _branchMarker;

  Timer? _mapsAvailabilityTimer;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, inside, outside, offline

  @override
  void initState() {
    super.initState();
    _loadCustomMarkers();
    _checkMapsAvailability();
  }

  void _checkMapsAvailability() {
    _mapsAvailabilityTimer?.cancel();
    if (isGoogleMapsAvailable) {
      if (mounted) setState(() {});
      return;
    }
    int attempts = 0;
    _mapsAvailabilityTimer =
        Timer.periodic(const Duration(milliseconds: 400), (timer) {
      attempts++;
      if (isGoogleMapsAvailable) {
        timer.cancel();
        if (mounted) setState(() {});
      } else if (attempts >= 50) {
        timer.cancel();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _mapsAvailabilityTimer?.cancel();
    _breadcrumbsSubscription?.cancel();
    _searchController.dispose();
    _mapController = null;
    super.dispose();
  }

  Future<void> _loadCustomMarkers() async {
    try {
      final green = await _createCustomPin(
        color: const Color(0xFF2E7D32),
        icon: Icons.person_rounded,
      );
      final orange = await _createCustomPin(
        color: const Color(0xFFC65102),
        icon: Icons.warning_rounded,
      );
      final grey = await _createCustomPin(
        color: const Color(0xFF757575),
        icon: Icons.person_outline_rounded,
      );
      final branch = await _createCustomPin(
        color: const Color(0xFF0288D1),
        icon: Icons.storefront_rounded,
      );

      if (mounted) {
        setState(() {
          _greenMarker = green;
          _orangeMarker = orange;
          _greyMarker = grey;
          _branchMarker = branch;
        });
      }
    } catch (e) {
      debugPrint('Error generating custom pins: $e');
    }
  }

  static Future<BitmapDescriptor> _createCustomPin({
    required Color color,
    required IconData icon,
    int size = 96,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    );

    final double width = size.toDouble();
    final double height = size.toDouble();
    final double radius = (width / 2) - 8;
    final Offset center = Offset(width / 2, radius + 4);

    // 1. Drop Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(center.translate(0, 3), radius, shadowPaint);

    // 2. Base pin circle
    final fillPaint = Paint()..color = color;
    canvas.drawCircle(center, radius, fillPaint);

    // 3. Crisp white ring
    final ringPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(center, radius - 2, ringPaint);

    // 4. Draw Icon in Center
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.44,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      ),
    );

    // 5. Pin Needle bottom pointer
    final path = Path();
    path.moveTo(center.dx - 12, center.dy + radius - 2);
    path.lineTo(center.dx, height - 2);
    path.lineTo(center.dx + 12, center.dy + radius - 2);
    path.close();

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, fillPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  void _selectSession(DelegateTrackingSession? session) {
    if (session == null) {
      _breadcrumbsSubscription?.cancel();
      _breadcrumbsSubscription = null;
      setState(() {
        _selectedSession = null;
        _activeBreadcrumbs = [];
        _isLoadingTrail = false;
      });
      // إغلاق تفاصيل المندوب يحافظ على موقع الكاميرا الحالي دون زوم أوت عنيف
      return;
    }

    final isSameSession = _selectedSession?.delegateId == session.delegateId;
    if (isSameSession) {
      if (_activeBreadcrumbs.isNotEmpty) {
        _fitTrailBounds(_activeBreadcrumbs);
      } else {
        _focusOnDelegate(session);
      }
      return;
    }

    _breadcrumbsSubscription?.cancel();
    setState(() {
      _selectedSession = session;
      _activeBreadcrumbs = [];
      _isLoadingTrail = true;
    });

    _focusOnDelegate(session);

    _breadcrumbsSubscription = _trackingService
        .streamBreadcrumbs(delegateId: session.delegateId, limit: 150)
        .listen(
      (crumbs) {
        if (mounted && _selectedSession?.delegateId == session.delegateId) {
          setState(() {
            _activeBreadcrumbs = crumbs;
            _isLoadingTrail = false;
          });
          if (crumbs.isNotEmpty) {
            _fitTrailBounds(crumbs);
          }
        }
      },
      onError: (e) {
        debugPrint('Error streaming breadcrumbs for ${session.delegateName}: $e');
        if (mounted) {
          setState(() => _isLoadingTrail = false);
        }
      },
    );
  }

  void _focusOnDelegate(DelegateTrackingSession session) {
    if (!mounted) return;
    final lat = session.lastLatitude ?? session.branchLat;
    final lng = session.lastLongitude ?? session.branchLng;
    if (lat != 0 && lng != 0 && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: 16.5,
          ),
        ),
      );
    }
  }

  void _fitTrailBounds(List<TrackingBreadcrumb> crumbs) {
    if (!mounted || _mapController == null) return;

    final session = _selectedSession;
    final validCrumbs = crumbs.where((c) => c.latitude != 0 && c.longitude != 0).toList();

    if (validCrumbs.isEmpty) {
      if (session != null) {
        _focusOnDelegate(session);
      }
      return;
    }

    double minLat = validCrumbs.first.latitude;
    double maxLat = validCrumbs.first.latitude;
    double minLng = validCrumbs.first.longitude;
    double maxLng = validCrumbs.first.longitude;

    final baseLat = session?.branchLat ?? 0.0;
    final baseLng = session?.branchLng ?? 0.0;

    for (final c in validCrumbs) {
      // حماية من النقاط الشاذة: استبعاد أي نقطة تبعد أكثر من 30 كم عن الفرع منعاً لتمدد الخريطة
      if (baseLat != 0 && baseLng != 0) {
        final distToBranch = Geolocator.distanceBetween(
          baseLat,
          baseLng,
          c.latitude,
          c.longitude,
        );
        if (distToBranch > 30000) continue;
      }

      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLng) minLng = c.longitude;
      if (c.longitude > maxLng) maxLng = c.longitude;
    }

    if (session != null && session.branchLat != 0 && session.branchLng != 0) {
      final bLat = session.branchLat;
      final bLng = session.branchLng;
      if (bLat < minLat) minLat = bLat;
      if (bLat > maxLat) maxLat = bLat;
      if (bLng < minLng) minLng = bLng;
      if (bLng > maxLng) maxLng = bLng;
    }

    // إذا كانت المسافة صغيرة جداً، نثبت الزوم المريح (16.5) على المركز
    if ((maxLat - minLat).abs() < 0.0015 && (maxLng - minLng).abs() < 0.0015) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
            zoom: 16.5,
          ),
        ),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat - 0.001, minLng - 0.001),
      northeast: LatLng(maxLat + 0.001, maxLng + 0.001),
    );
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  double _calculateTrailTotalDistance(List<TrackingBreadcrumb> crumbs) {
    if (crumbs.length < 2) return 0.0;
    double totalMeters = 0.0;
    for (int i = 0; i < crumbs.length - 1; i++) {
      totalMeters += Geolocator.distanceBetween(
        crumbs[i].latitude,
        crumbs[i].longitude,
        crumbs[i + 1].latitude,
        crumbs[i + 1].longitude,
      );
    }
    return totalMeters;
  }

  Widget _buildRouteTrailHeader(
    ColorScheme colorScheme,
    TextTheme textTheme,
    DelegateTrackingSession session,
  ) {
    final distanceMeters = _calculateTrailTotalDistance(_activeBreadcrumbs);
    final distanceKmStr = (distanceMeters / 1000).toStringAsFixed(2);
    final pointsCount = _activeBreadcrumbs.length;
    final speed = session.speed;
    final battery = session.batteryLevel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.route_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    session.delegateName,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'مسار اليوم',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timeline_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(
                    '$pointsCount نقطة',
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.straighten_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(
                    '$distanceKmStr كم',
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (speed != null && speed > 0) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.speed_rounded, size: 13, color: colorScheme.primary),
                    const SizedBox(width: 3),
                    Text(
                      '${speed.toStringAsFixed(1)} كم/س',
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (battery != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      battery > 20 ? Icons.battery_charging_full_rounded : Icons.battery_alert_rounded,
                      size: 13,
                      color: battery > 50
                          ? const Color(0xFF2E7D32)
                          : (battery > 20 ? const Color(0xFFEF6C00) : const Color(0xFFD32F2F)),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$battery%',
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (_isLoadingTrail) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
            color: colorScheme.primary,
            tooltip: 'توسيط نطاق المسار والمندوب',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              if (_activeBreadcrumbs.isNotEmpty) {
                _fitTrailBounds(_activeBreadcrumbs);
              } else {
                _focusOnDelegate(session);
              }
            },
          ),
          // زر محاكاة وبث حركة وتيليمتري حية للتجربة السريعة
          IconButton(
            icon: const Icon(Icons.play_circle_filled_rounded, size: 20),
            color: colorScheme.primary,
            tooltip: 'محاكاة وبث حركة وتيليمتري حية للتجربة',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _simulateMovementForSession(session),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            color: colorScheme.onSurfaceVariant,
            tooltip: 'إغلاق المسار',
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(28, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _selectSession(null),
          ),
        ],
      ),
    );
  }

  Future<void> _simulateMovementForSession(DelegateTrackingSession session) async {
    final baseLat = session.lastLatitude ?? session.branchLat;
    final baseLng = session.lastLongitude ?? session.branchLng;
    if (baseLat == 0 && baseLng == 0) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('جارٍ بث تيليميتري ومسار تحرك حي للمندوب ${session.delegateName}...'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    await _trackingService.simulateDelegateMovement(
      delegateId: session.delegateId,
      baseLat: baseLat,
      baseLng: baseLng,
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 45) {
      return 'الآن';
    } else if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} د';
    } else {
      final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
      final minute = time.minute.toString().padLeft(2, '0');
      final period = time.hour >= 12 ? 'م' : 'ص';
      return '$hour:$minute $period';
    }
  }

  Future<void> _callDelegatePhone(BuildContext context, String phone) async {
    var p = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (p.startsWith('01') && p.length == 11) {
      p = '+20${p.substring(1)}';
    }
    if (p.isEmpty) return;
    final uri = Uri.parse('tel:$p');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر بدء المكالمة الهاتفية.')),
      );
    }
  }

  List<DelegateTrackingSession> get _panelFilteredSessions {
    return widget.sessions.where((s) {
      if (_statusFilter == 'inside' && !s.isInside) return false;
      if (_statusFilter == 'outside' && !s.isOutside) return false;
      if (_statusFilter == 'offline' && !s.isOffline) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatch = s.delegateName.toLowerCase().contains(q);
        final branchMatch = s.branchName.toLowerCase().contains(q);
        final phoneMatch = s.delegatePhone.contains(q);
        if (!nameMatch && !branchMatch && !phoneMatch) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 850;

    if (isWide) {
      return Row(
        textDirection: TextDirection.rtl,
        children: [
          // لوحة قائمة المناديب الجانبية الحية
          SizedBox(
            width: 360,
            child: _buildDelegatesSidePanel(context),
          ),
          // مساحة الخريطة التفاعلية الحية
          Expanded(
            child: _buildMapContent(context),
          ),
        ],
      );
    }

    return Stack(
      children: [
        _buildMapContent(context),
        if (widget.sessions.isNotEmpty)
          PositionedDirectional(
            bottom: _selectedSession != null ? 240 : 20,
            start: 16,
            child: FloatingActionButton.extended(
              heroTag: 'mobile_delegates_sheet_btn',
              onPressed: () => _showMobileDelegatesSheet(context),
              icon: const Icon(Icons.people_alt_rounded),
              label: Text('المناديب الحاضرين (${widget.sessions.length})'),
            ),
          ),
      ],
    );
  }

  Widget _buildMapContent(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    // التحقق الآمن من جاهزية وتحميل خدمة الخرائط في بيئة الويب
    if (!isGoogleMapsAvailable) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.map_outlined,
                size: 52,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'خدمة الخرائط قيد التحميل...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'يرجى التأكد من اتصال الإنترنت وإعادة تحميل الصفحة.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: () {
                  _checkMapsAvailability();
                  setState(() {});
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    // مزامنة المندوب المختار مع البيانات الحية المحدثة
    DelegateTrackingSession? activeSession = _selectedSession;
    if (activeSession != null) {
      final selectedId = activeSession.delegateId;
      for (final s in widget.sessions) {
        if (s.delegateId == selectedId) {
          activeSession = s;
          break;
        }
      }
    }

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
          fillColor: colorScheme.primary.withValues(alpha: 0.12),
          strokeColor: colorScheme.primary.withValues(alpha: 0.7),
          strokeWidth: 2,
        ),
      );
    }

    // إضافة دوائر نقاط المسار (Breadcrumb Waypoints) عند اختيار مندوب
    if (activeSession != null && _activeBreadcrumbs.isNotEmpty) {
      for (int i = 0; i < _activeBreadcrumbs.length; i++) {
        final c = _activeBreadcrumbs[i];
        circles.add(
          Circle(
            circleId: CircleId('crumb_${activeSession.delegateId}_$i'),
            center: LatLng(c.latitude, c.longitude),
            radius: 5,
            fillColor: c.isInside
                ? const Color(0xFF2E7D32).withValues(alpha: 0.8)
                : const Color(0xFFC65102).withValues(alpha: 0.8),
            strokeColor: Colors.white,
            strokeWidth: 1,
          ),
        );
      }
    }

    // 3. بناء دبابيس المناديب والفروع ومسار البداية
    final Set<Marker> markers = {};

    // دبابيس الفروع
    for (final entry in uniqueBranches.entries) {
      final s = entry.value;
      markers.add(
        Marker(
          markerId: MarkerId('branch_${s.branchName}'),
          position: LatLng(s.branchLat, s.branchLng),
          icon: _branchMarker ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: 'فرع: ${s.branchName}',
            snippet: 'نطاق الأمان: ${s.geofenceRadius.toInt()} متر',
          ),
        ),
      );
    }

    // نقطة بداية المسار للمندوب المختار (إذا توفرت نقاط)
    if (activeSession != null && _activeBreadcrumbs.isNotEmpty) {
      final start = _activeBreadcrumbs.first;
      markers.add(
        Marker(
          markerId: MarkerId('start_${activeSession.delegateId}'),
          position: LatLng(start.latitude, start.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: InfoWindow(
            title: 'نقطة الانطلاق (البداية)',
            snippet: _formatTime(start.timestamp),
          ),
        ),
      );
    }

    // دبابيس المناديب بالألوان الثلاثية المعتمدة
    for (final s in widget.sessions) {
      final lat = s.lastLatitude ?? s.branchLat;
      final lng = s.lastLongitude ?? s.branchLng;
      if (lat == 0 && lng == 0) continue;

      BitmapDescriptor markerIcon;
      String statusSnippet;

      // 🟢 نقطة خضراء: متواجد داخل نطاق الصيدلية/الفرع
      // 🟠 نقطة برتقالية: تحرك خارج نطاق الفرع
      // ⚪ نقطة رمادية: غير متصل أو لم يسجل حضور
      if (s.isOutside) {
        markerIcon = _orangeMarker ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
        final excess = (s.currentDistanceMeters - s.geofenceRadius).toInt();
        statusSnippet = '🟠 خارج النطاق بـ $excess متر';
      } else if (s.isOffline) {
        markerIcon = _greyMarker ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
        statusSnippet = '⚪ غير متصل بالشبكة / لم يسجل';
      } else {
        markerIcon = _greenMarker ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
        statusSnippet = '🟢 داخل النطاق (${s.currentDistanceMeters.toInt()}م)';
      }

      markers.add(
        Marker(
          markerId: MarkerId('delegate_${s.delegateId}'),
          position: LatLng(lat, lng),
          icon: markerIcon,
          infoWindow: InfoWindow(
            title: s.delegateName,
            snippet: statusSnippet,
          ),
          onTap: () {
            _selectSession(s);
          },
        ),
      );
    }

    // 4. خط مسار التحرك الفعلي (Polylines)
    final Set<Polyline> polylines = {};
    if (activeSession != null && _activeBreadcrumbs.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: PolylineId('trail_${activeSession.delegateId}'),
          points: _activeBreadcrumbs
              .map((c) => LatLng(c.latitude, c.longitude))
              .toList(),
          color: colorScheme.primary,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialCenter,
            zoom: 15.0,
          ),
          circles: circles,
          markers: markers,
          polylines: polylines,
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
              _selectSession(null);
            }
          },
        ),

        // أزرار التحكم الطافية (إعادة الضبط والتحديث)
        Positioned(
          top: 16,
          left: 16,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'recenter_map_btn',
                backgroundColor: colorScheme.surface,
                foregroundColor: colorScheme.primary,
                onPressed: () => _fitMapBounds(forceLocalScope: true),
                tooltip: 'توسيط النطاق المحلي (المحافظة/المندوب)',
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

        // دليل ألوان الدبابيس الثلاثي (Legend)
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLegendItem('داخل النطاق', const Color(0xFF2E7D32)),
                const SizedBox(height: 5),
                _buildLegendItem('خارج النطاق', const Color(0xFFC65102)),
                const SizedBox(height: 5),
                _buildLegendItem('غير متصل / لم يسجل', const Color(0xFF757575)),
              ],
            ),
          ),
        ),

        // شريط إحصائيات مسار المندوب الطافي في أعلى الخريطة
        if (activeSession != null)
          Positioned(
            top: 16,
            left: 76,
            right: 180,
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildRouteTrailHeader(colorScheme, textTheme, activeSession),
            ),
          ),

        // بطاقة المندوب المختار الحية أسفل الخريطة
        if (activeSession != null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: DelegateTrackingCard(
              session: activeSession,
              onClose: () => _selectSession(null),
              onFocusOnMap: () {
                if (_activeBreadcrumbs.isNotEmpty) {
                  _fitTrailBounds(_activeBreadcrumbs);
                } else {
                  _focusOnDelegate(activeSession!);
                }
              },
              onRefreshPing: () => _simulateMovementForSession(activeSession!),
              onToggleTracking: (val) {
                widget.onToggleTracking(activeSession!);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDelegatesSidePanel(BuildContext context, {bool isSheet = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final filtered = _panelFilteredSessions;
    final totalCount = widget.sessions.length;
    final insideCount = widget.sessions.where((s) => s.isInside).length;
    final outsideCount = widget.sessions.where((s) => s.isOutside).length;
    final offlineCount = widget.sessions.where((s) => s.isOffline).length;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: isSheet
            ? null
            : Border(
                left: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.groups_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المناديب الحاضرين',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '$totalCount مندوب مسجل حضور اليوم',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onRefresh != null)
                  IconButton.filledTonal(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'تحديث الحاضرين',
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.sync_rounded),
                  ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الفرع...',
                hintStyle: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Quick Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'الكل ($totalCount)',
                  isSelected: _statusFilter == 'all',
                  onTap: () => setState(() => _statusFilter = 'all'),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: '🟢 داخل ($insideCount)',
                  isSelected: _statusFilter == 'inside',
                  onTap: () => setState(() => _statusFilter = 'inside'),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: '🟠 خارج ($outsideCount)',
                  isSelected: _statusFilter == 'outside',
                  onTap: () => setState(() => _statusFilter = 'outside'),
                ),
                if (offlineCount > 0) ...[
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: '⚪ غير متصل ($offlineCount)',
                    isSelected: _statusFilter == 'offline',
                    onTap: () => setState(() => _statusFilter = 'offline'),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Delegates List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_search_rounded,
                            size: 40,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.sessions.isEmpty
                                ? 'لم يتم تسجيل حضور أي مندوب اليوم بعد'
                                : 'لا توجد نتائج مطابقة للبحث',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (widget.onRefresh != null) ...[
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: widget.onRefresh,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('تحديث القائمة'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final s = filtered[index];
                      final isSelected = _selectedSession?.delegateId == s.delegateId;

                      Color statusColor;
                      String statusText;
                      if (s.isOutside) {
                        statusColor = const Color(0xFFC65102);
                        final excess = (s.currentDistanceMeters - s.geofenceRadius).toInt();
                        statusText = 'خارج النطاق ($excessم)';
                      } else if (s.isOffline) {
                        statusColor = const Color(0xFF757575);
                        statusText = 'غير متصل';
                      } else {
                        statusColor = const Color(0xFF2E7D32);
                        statusText = 'داخل النطاق (${s.currentDistanceMeters.toInt()}م)';
                      }

                      return Material(
                        color: isSelected
                            ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            if (isSheet) Navigator.pop(context);
                            _selectSession(s);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                // Avatar with status indicator
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    AppAvatar(
                                      imageUrl: s.avatarUrl,
                                      fallbackText: s.delegateName,
                                      radius: 20,
                                      backgroundColor: statusColor.withValues(alpha: 0.15),
                                      foregroundColor: statusColor,
                                    ),
                                    PositionedDirectional(
                                      bottom: 0,
                                      end: 0,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: colorScheme.surface,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              s.delegateName,
                                              style: textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSurface,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            _formatTime(s.lastUpdated),
                                            style: textTheme.labelSmall?.copyWith(
                                              color: colorScheme.onSurfaceVariant,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.storefront_outlined,
                                            size: 13,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              s.branchName,
                                              style: textTheme.bodySmall?.copyWith(
                                                color: colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          statusText,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                if (s.delegatePhone.trim().isNotEmpty) ...[
                                  IconButton(
                                    icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                                    color: const Color(0xFF2E7D32),
                                    tooltip: 'اتصال هاتفي بالمندوب (${s.delegatePhone})',
                                    visualDensity: VisualDensity.compact,
                                    style: IconButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(32, 32),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => _callDelegatePhone(context, s.delegatePhone),
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                IconButton(
                                  icon: Icon(
                                    Icons.my_location_rounded,
                                    size: 18,
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                  tooltip: 'تحديد الموقع على الخريطة',
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(32, 32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    if (isSheet) Navigator.pop(context);
                                    _selectSession(s);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  void _showMobileDelegatesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: _buildDelegatesSidePanel(ctx, isSheet: true),
            );
          },
        );
      },
    );
  }

  Widget _buildLegendItem(String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  void _fitMapBounds({bool forceLocalScope = true}) {
    if (!mounted || _mapController == null || widget.sessions.isEmpty) return;

    // 1. إذا كان هناك مندوب محدد، نثبت النطاق عليه وعلى فرعه ومساره دون إبعاد الكاميرا
    if (_selectedSession != null) {
      if (_activeBreadcrumbs.isNotEmpty) {
        _fitTrailBounds(_activeBreadcrumbs);
      } else {
        _focusOnDelegate(_selectedSession!);
      }
      return;
    }

    // 2. تجميع الإحداثيات الصالحة للمناديب والفروع
    final validPoints = <LatLng>[];
    for (final s in widget.sessions) {
      final lat = s.lastLatitude ?? s.branchLat;
      final lng = s.lastLongitude ?? s.branchLng;
      if (lat != 0 && lng != 0) {
        validPoints.add(LatLng(lat, lng));
      }
    }

    if (validPoints.isEmpty) return;

    if (validPoints.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: validPoints.first, zoom: 16.0),
        ),
      );
      return;
    }

    // 3. عزل التجمعات الجغرافية للمدن (منع الجمع بين محافظات متباعدة مثل الإسكندرية وطنطا 120كم)
    List<LatLng> targetCluster = validPoints;

    if (forceLocalScope) {
      List<LatLng> bestCluster = [];
      for (final candidate in validPoints) {
        final cluster = validPoints.where((p) {
          final distance = Geolocator.distanceBetween(
            candidate.latitude,
            candidate.longitude,
            p.latitude,
            p.longitude,
          );
          return distance <= 30000; // نطاق أقصى 30 كم داخل نفس المدينة
        }).toList();

        if (cluster.length > bestCluster.length) {
          bestCluster = cluster;
        }
      }

      if (bestCluster.isNotEmpty) {
        targetCluster = bestCluster;
      }
    }

    double minLat = targetCluster.first.latitude;
    double maxLat = targetCluster.first.latitude;
    double minLng = targetCluster.first.longitude;
    double maxLng = targetCluster.first.longitude;

    for (final p in targetCluster) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // إذا كانت جميع نقاط التجمع قريبة جداً (نفس الفرع أو منطقة متطابقة)
    if ((maxLat - minLat).abs() < 0.003 && (maxLng - minLng).abs() < 0.003) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
            zoom: 16.0,
          ),
        ),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat - 0.005, minLng - 0.005),
      northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
  }
}
