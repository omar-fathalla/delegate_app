import 'package:flutter/foundation.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/features/marketing/presentation/pages/branch_live_refresh_controller.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/app_loading_indicator.dart';
import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/marketing/data/models/floor_verification_model.dart';
import 'package:delegate_app/features/marketing/data/services/floor_verification_service.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/marketing/data/services/real_test_metrics.dart';
import 'package:delegate_app/core/config/read_reduction_flags.dart';
import 'package:delegate_app/features/marketing/data/datasources/today_attendance_query.dart';

/// الشاشة الرئيسية للفروع - تعرض جميع الفروع المفضلة في نفس الصفحة
class BranchHomeScreen extends StatelessWidget {
  final Delegate marketingUser;
  final bool showAppBar;

  /// True while this screen's tab is selected in the hosting shell. Drives
  /// the live listener and its timers (IndexedStack offstage tabs don't get
  /// TickerMode disabled). Null = always active (pushed route).
  final ValueListenable<bool>? isActive;

  const BranchHomeScreen({
    super.key,
    required this.marketingUser,
    this.showAppBar = false,
    this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = di.sl<MarketingBloc>();
        // Single fetch path: preferences listener loads attendance once.
        // Favorites collapse defaults are applied in the view when prefs load.
        bloc.add(LoadBranchPreferences(userId: marketingUser.uid));
        return bloc;
      },
      child: _BranchHomeView(
        marketingUser: marketingUser,
        showAppBar: showAppBar,
        isActive: isActive,
      ),
    );
  }
}

class _BranchHomeView extends StatefulWidget {
  final Delegate marketingUser;
  final bool showAppBar;
  final ValueListenable<bool>? isActive;

  const _BranchHomeView({
    required this.marketingUser,
    this.showAppBar = false,
    this.isActive,
  });

  @override
  State<_BranchHomeView> createState() => _BranchHomeViewState();
}

class _BranchHomeViewState extends State<_BranchHomeView>
    with LiveTabVisibility<_BranchHomeView> {
  @override
  ValueListenable<bool>? get liveActiveListenable => widget.isActive;

  @override
  void onLiveVisibilityChanged() {
    final visible = liveTabVisible;
    final reload = shouldReloadOnShow(
      wasVisible: _lastLiveVisible,
      isVisible: visible,
      lastSync: _lastSyncTime,
      now: DateTime.now(),
    );
    _lastLiveVisible = visible;
    if (reload && mounted && _favoriteBranches.isNotEmpty) {
      // Back on the tab: catch up on check-ins made while hidden (the
      // listener skips its initial snapshot). _loadAllBranches re-syncs the
      // listener itself.
      _loadAllBranches(context, _favoriteBranches);
      return;
    }
    _syncLiveListener();
  }

  bool _lastLiveVisible = true;

  /// Whether the user is following "today" (vs. browsing a past date), so a
  /// day change (midnight or resume on a later day) rolls over to the new day.
  bool _followToday = true;

  List<String> _favoriteBranches = [];
  bool _prefsLoaded = false;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Set of collapsed branch names. When favorites >= 5, all but the active
  /// (or first) branch start collapsed; expand on tap (lazy card build).
  final Set<String> _collapsedBranches = {};
  bool _didApplyDefaultCollapse = false;

  /// Cache of last loaded state to prevent full-screen blinking during incremental loads
  AllBranchesAttendanceLoaded? _lastLoadedState;

  /// Floor verification service for 0ms local cache and background cloud sync
  late final FloorVerificationService _floorService;

  /// Map of delegateId -> FloorVerificationItem for the selected date
  Map<String, FloorVerificationItem> _floorVerifications = {};

  /// Filter state per branch: 'all' | 'remaining' | 'verified' | 'missing'
  final Map<String, String> _branchFilter = {};

  /// Periodic timer for auto-refresh heartbeat (every 30s)
  Timer? _autoRefreshTimer;

  /// App lifecycle listener to sync immediately upon app resume
  AppLifecycleListener? _lifecycleListener;

  /// Timestamp of the last successful sync with server
  DateTime? _lastSyncTime;

  /// Today-only attendance listener (refresh signal) and its state.
  BranchLiveRefreshController? _live;
  String? _liveSignature;
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    try {
      _floorService = di.sl<FloorVerificationService>();
      final prefService = di.sl<BranchPreferenceService>();
      final favorites = prefService.getFavoriteBranches(widget.marketingUser.uid);
      _favoriteBranches = favorites;
      _prefsLoaded = true;
      _applyDefaultCollapseIfNeeded(favorites);
      _floorVerifications = _floorService.getLocalVerifications(_selectedDate);
      _syncFloorVerificationsFromCloud();

      // Read-reduction Phase 1: a today-only snapshot listener replaces the
      // 30 s forceServer timer. The timer only runs if `branch_live_listener`
      // is switched off in Remote Config (kill switch).
      // Disabled during REAL_TEST_METRICS so cold/warm measurements are not polluted.
      if (!RealTestMetrics.enabled &&
          !ReadReductionFlags.instance.branchLiveListener) {
        _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          // Only for today's view on a visible tab (past dates don't change).
          if (mounted &&
              _favoriteBranches.isNotEmpty &&
              _isSelectedDateToday() &&
              liveTabVisible &&
              _appResumed) {
            _loadAllBranches(context, _favoriteBranches, forceRefresh: true);
            _syncFloorVerificationsFromCloud();
          }
        });
      }

      // Revalidate once on resume; pause the listener in the background.
      _lifecycleListener = AppLifecycleListener(
        onResume: () {
          _appResumed = true;
          if (mounted &&
              shouldRollOverToToday(
                followToday: _followToday,
                selected: _selectedDate,
                now: DateTime.now(),
              )) {
            // Resumed on a later day while following today → same path as
            // the midnight timer (moves the date, reloads, re-subscribes).
            _onLocalMidnight();
            return;
          }
          if (mounted && _favoriteBranches.isNotEmpty) {
            _loadAllBranches(context, _favoriteBranches);
            _syncFloorVerificationsFromCloud();
          }
          _syncLiveListener();
        },
        onPause: () {
          _appResumed = false;
          _syncLiveListener();
        },
      );
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode (routes) + the shell's isActive (tabs) → see LiveTabVisibility.
    _lastLiveVisible = liveTabVisible;
    _syncLiveListener();
  }

  bool _isSelectedDateToday() {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  String get _orgIdForQueries => widget.marketingUser.organizationUID.isNotEmpty
      ? widget.marketingUser.organizationUID
      : kDefaultOrganizationId;

  /// Starts, restarts or stops the today-only listener so it only runs while
  /// the tab is visible, the app is in the foreground and today is selected.
  void _syncLiveListener() {
    final shouldRun = !RealTestMetrics.enabled &&
        ReadReductionFlags.instance.branchLiveListener &&
        mounted &&
        liveTabVisible &&
        _appResumed &&
        _favoriteBranches.isNotEmpty &&
        _isSelectedDateToday() &&
        di.sl.isRegistered<FirebaseFirestore>();
    final signature = shouldRun
        ? '$_orgIdForQueries|${(List.of(_favoriteBranches)..sort()).join(',')}|'
            '${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}'
        : null;
    if (signature == _liveSignature) return;
    _live?.stop();
    _live = null;
    _liveSignature = signature;
    if (signature == null) return;
    final start =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final branches = List.of(_favoriteBranches);
    final orgId = _orgIdForQueries;
    final firestore = di.sl<FirebaseFirestore>();
    _live = BranchLiveRefreshController(
      watch: () => watchTodayBranchAttendanceChanges(
        firestore: firestore,
        branchNames: branches,
        organizationId: orgId,
        dayStart: start,
        dayEnd: start.add(const Duration(days: 1)),
      ),
      branchKeyBackfilled: () => ReadReductionFlags.instance.branchKeyBackfilled,
      onReload: ({required bool force}) {
        if (mounted && _favoriteBranches.isNotEmpty) {
          _loadAllBranches(context, _favoriteBranches, forceRefresh: force);
        }
      },
      onMidnight: _onLocalMidnight,
    )..start();
  }

  /// Day roll-over while the screen stays open on "today": move to the new
  /// day, reload, and let [_syncLiveListener] re-subscribe for the new range.
  void _onLocalMidnight() {
    if (!mounted) return;
    final now = DateTime.now();
    if (shouldRollOverToToday(
      followToday: _followToday,
      selected: _selectedDate,
      now: now,
    )) {
      setState(() => _selectedDate = now);
    }
    _liveSignature = null; // force a fresh subscription + midnight timer
    if (_favoriteBranches.isNotEmpty) {
      _loadAllBranches(context, _favoriteBranches, forceRefresh: true);
    } else {
      _syncLiveListener();
    }
  }

  @override
  void dispose() {
    _live?.stop();
    _autoRefreshTimer?.cancel();
    _lifecycleListener?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _syncFloorVerificationsFromCloud() async {
    if (_favoriteBranches.isEmpty) return;
    try {
      final cloudData = await _floorService.fetchCloudVerifications(
        date: _selectedDate,
        branchNames: _favoriteBranches,
      );
      if (mounted) {
        setState(() {
          _floorVerifications = cloudData;
        });
      }
    } catch (_) {}
  }

  void _toggleFloorVerification(Map<String, dynamic> record, [String? fallbackBranch]) {
    final delegateId = record['delegateId'] as String? ?? '';
    final branchName = (record['branchName'] as String? ?? fallbackBranch ?? '').trim();
    if (delegateId.isEmpty || branchName.isEmpty) return;

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final currentItem = _floorVerifications[delegateId];

    if (currentItem != null && currentItem.isVerified) {
      // Toggle OFF -> unverified
      HapticFeedback.lightImpact();
      _floorService.removeVerification(
        dateStr: dateStr,
        branchName: branchName,
        delegateId: delegateId,
      );
      setState(() {
        _floorVerifications.remove(delegateId);
      });
    } else {
      // Toggle ON -> verified (متواجد بالصالة)
      HapticFeedback.mediumImpact();
      final item = FloorVerificationItem(
        delegateId: delegateId,
        branchName: branchName,
        date: dateStr,
        status: 'verified',
        timestamp: DateTime.now(),
        verifiedBy: widget.marketingUser.uid,
        verifierName: widget.marketingUser.fullName.isNotEmpty
            ? widget.marketingUser.fullName
            : 'مشرف الصالة',
      );
      _floorService.saveVerification(item: item);
      setState(() {
        _floorVerifications[delegateId] = item;
      });
    }
  }

  void _showFloorVerificationDialog(BuildContext context, Map<String, dynamic> record, [String? fallbackBranch]) {
    final delegateId = record['delegateId'] as String? ?? '';
    final branchName = (record['branchName'] as String? ?? fallbackBranch ?? '').trim();
    final fullName = record['fullName'] as String? ?? 'المندوب';
    if (delegateId.isEmpty || branchName.isEmpty) return;

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final currentItem = _floorVerifications[delegateId];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bCtx) {
        final theme = Theme.of(bCtx);
        final cs = theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'تحديد حالة التواجد بالصالة',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fullName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                // Option 1: متواجد بالصالة (تم التأكد)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: currentItem?.isVerified == true
                          ? const Color(0xFF2E7D32)
                          : cs.outlineVariant.withValues(alpha: 0.3),
                      width: currentItem?.isVerified == true ? 1.5 : 1,
                    ),
                  ),
                  tileColor: currentItem?.isVerified == true
                      ? const Color(0xFFE8F5E9)
                      : cs.surfaceContainerLow,
                  leading: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF2E7D32),
                    size: 26,
                  ),
                  title: const Text(
                    'متواجد بالصالة (تم التحقق)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                  subtitle: const Text(
                    'المندوب حاضر ومتواجد في مكانه/الستاند',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: currentItem?.isVerified == true
                      ? const Icon(Icons.done_rounded, color: Color(0xFF2E7D32))
                      : null,
                  onTap: () {
                    Navigator.pop(bCtx);
                    HapticFeedback.mediumImpact();
                    final item = FloorVerificationItem(
                      delegateId: delegateId,
                      branchName: branchName,
                      date: dateStr,
                      status: 'verified',
                      timestamp: DateTime.now(),
                      verifiedBy: widget.marketingUser.uid,
                      verifierName: widget.marketingUser.fullName.isNotEmpty
                          ? widget.marketingUser.fullName
                          : 'مشرف الصالة',
                    );
                    _floorService.saveVerification(item: item);
                    setState(() {
                      _floorVerifications[delegateId] = item;
                    });
                  },
                ),
                const SizedBox(height: 10),

                // Option 2: غير متواجد بالصالة (غائب عن الستاند)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: currentItem?.isMissing == true
                          ? const Color(0xFFC62828)
                          : cs.outlineVariant.withValues(alpha: 0.3),
                      width: currentItem?.isMissing == true ? 1.5 : 1,
                    ),
                  ),
                  tileColor: currentItem?.isMissing == true
                       ? const Color(0xFFFFEBEE)
                      : cs.surfaceContainerLow,
                  leading: const Icon(
                    Icons.cancel_rounded,
                    color: Color(0xFFC62828),
                    size: 26,
                  ),
                  title: const Text(
                    'غير متواجد بالصالة',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                  subtitle: const Text(
                    'مسجل حضور في التطبيق لكنه غير متواجد فعلياً',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: currentItem?.isMissing == true
                      ? const Icon(Icons.done_rounded, color: Color(0xFFC62828))
                      : null,
                  onTap: () {
                    Navigator.pop(bCtx);
                    HapticFeedback.heavyImpact();
                    final item = FloorVerificationItem(
                      delegateId: delegateId,
                      branchName: branchName,
                      date: dateStr,
                      status: 'missing',
                      timestamp: DateTime.now(),
                      verifiedBy: widget.marketingUser.uid,
                      verifierName: widget.marketingUser.fullName.isNotEmpty
                          ? widget.marketingUser.fullName
                          : 'مشرف الصالة',
                    );
                    _floorService.saveVerification(item: item);
                    setState(() {
                      _floorVerifications[delegateId] = item;
                    });
                  },
                ),

                if (currentItem != null) ...[
                  const SizedBox(height: 10),
                  // Option 3: إلغاء التحديد
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    leading: Icon(
                      Icons.restart_alt_rounded,
                      color: cs.onSurfaceVariant,
                      size: 24,
                    ),
                    title: const Text(
                      'إعادة تعيين (لم يتم المرور بعد)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(bCtx);
                      HapticFeedback.lightImpact();
                      _floorService.removeVerification(
                        dateStr: dateStr,
                        branchName: branchName,
                        delegateId: delegateId,
                      );
                      setState(() {
                        _floorVerifications.remove(delegateId);
                      });
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _applyDefaultCollapseIfNeeded(List<String> favorites) {
    if (_didApplyDefaultCollapse) return;
    if (favorites.length < 5) return;
    _didApplyDefaultCollapse = true;
    final active = di
        .sl<BranchPreferenceService>()
        .getActiveBranch(widget.marketingUser.uid);
    final keepOpen = (active != null &&
            active.isNotEmpty &&
            favorites.contains(active))
        ? active
        : favorites.first;
    _collapsedBranches
      ..clear()
      ..addAll(favorites.where((b) => b != keepOpen));
  }

  void _toggleBranchExpansion(String branchName) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_collapsedBranches.contains(branchName)) {
        _collapsedBranches.remove(branchName);
      } else {
        _collapsedBranches.add(branchName);
      }
    });
  }

  void _collapseAll(List<String> branches) {
    HapticFeedback.lightImpact();
    setState(() {
      _collapsedBranches.addAll(branches);
    });
  }

  void _expandAll() {
    HapticFeedback.lightImpact();
    setState(() {
      _collapsedBranches.clear();
    });
  }

  void _loadAllBranches(
    BuildContext context,
    List<String> favorites, {
    bool forceRefresh = false,
  }) {
    if (favorites.isEmpty) return;
    _followToday = _isSelectedDateToday();
    context.read<MarketingBloc>().add(
      LoadAllFavoriteBranchesAttendance(
        favoriteBranches: favorites,
        organizationId: widget.marketingUser.organizationUID.isNotEmpty
            ? widget.marketingUser.organizationUID
            : kDefaultOrganizationId,
        date: _selectedDate,
        forceRefresh: forceRefresh,
      ),
    );
    // Favorites / selected date may have changed → (re)start or stop listener.
    _syncLiveListener();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (picked != null && picked != _selectedDate) {
      if (!mounted) return;
      setState(() {
        _selectedDate = picked;
        _floorVerifications = _floorService.getLocalVerifications(picked);
      });
      _loadAllBranches(context, _favoriteBranches, forceRefresh: true);
      _syncFloorVerificationsFromCloud();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<MarketingBloc, MarketingState>(
      listenWhen: (prev, curr) =>
          curr is BranchPreferencesLoaded ||
          curr is AllBranchesAttendanceLoaded ||
          curr is AllBranchesAttendanceError ||
          curr is AllBranchesAttendanceLoading,
      listener: (context, state) {
        if (state is AllBranchesAttendanceLoaded) {
          _lastSyncTime = DateTime.now();
        }
        if (state is BranchPreferencesLoaded) {
          final favorites = state.favoriteBranches;
          setState(() {
            _favoriteBranches = favorites;
            _prefsLoaded = true;
            _applyDefaultCollapseIfNeeded(favorites);
          });
          if (favorites.isEmpty) {
            // لا توجد فروع → افتح المنتقي
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showBranchPicker(context);
            });
          } else {
            // حمّل بيانات كل الفروع دفعة واحدة
            _loadAllBranches(context, favorites);
          }
        }
      },
      buildWhen: (prev, curr) =>
          curr is BranchPreferencesLoaded ||
          curr is AllBranchesAttendanceLoading ||
          curr is AllBranchesAttendanceLoaded ||
          curr is AllBranchesAttendanceError,
      builder: (context, state) {
        if (!_prefsLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        Widget body;

        if (_favoriteBranches.isEmpty) {
          body = _buildEmptyState(context, colorScheme);
        } else if (state is AllBranchesAttendanceLoaded) {
          _lastLoadedState = state;
          body = _buildAllBranches(context, state, colorScheme);
        } else if (state is AllBranchesAttendanceLoading) {
          if (_lastLoadedState != null && _lastLoadedState!.data.isNotEmpty) {
            body = _buildAllBranches(context, _lastLoadedState!, colorScheme);
          } else {
            body = _buildLoadingSkeletons(colorScheme);
          }
        } else if (state is AllBranchesAttendanceError) {
          if (_lastLoadedState != null && _lastLoadedState!.data.isNotEmpty) {
            body = _buildAllBranches(context, _lastLoadedState!, colorScheme);
          } else {
            body = _buildError(context, state.message, colorScheme);
          }
        } else if (_lastLoadedState != null && _lastLoadedState!.data.isNotEmpty) {
          body = _buildAllBranches(
            context,
            _lastLoadedState!.copyWith(favoriteBranches: _favoriteBranches),
            colorScheme,
          );
        } else {
          body = _buildLoadingSkeletons(colorScheme);
        }

        final content = Stack(
          children: [
            body,
            // ─── FAB: إضافة فرع ───────────────────────────────────────────
            Positioned(
              bottom: 16,
              left: 16,
              child: FloatingActionButton.extended(
                heroTag: null,
                onPressed: () => _showBranchPicker(context),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('إضافة فرع'),
                elevation: 3,
              ),
            ),
          ],
        );

        if (widget.showAppBar) {
          return Scaffold(
            backgroundColor: colorScheme.surfaceContainerLowest,
            appBar: AppBar(
              backgroundColor: colorScheme.surfaceContainer,
              elevation: 0,
              shape: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              title: Text(
                'متابعة حضور الفروع',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              centerTitle: false,
              actions: [
                if (_favoriteBranches.length > 1)
                  IconButton(
                    icon: Icon(
                      _collapsedBranches.length >= _favoriteBranches.length
                          ? Icons.unfold_more_rounded
                          : Icons.unfold_less_rounded,
                    ),
                    tooltip: _collapsedBranches.length >= _favoriteBranches.length
                        ? 'فتح الكل'
                        : 'طي الكل',
                    onPressed: () {
                      if (_collapsedBranches.length >= _favoriteBranches.length) {
                        _expandAll();
                      } else {
                        _collapseAll(_favoriteBranches);
                      }
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.calendar_month_rounded),
                  tooltip: 'تغيير التاريخ',
                  onPressed: _selectDate,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'تحديث',
                  onPressed: () => _loadAllBranches(context, _favoriteBranches, forceRefresh: true),
                ),
              ],
            ),
            body: content,
          );
        }

        return content;
      },
    );
  }

  // ─── Empty State ─────────────────────────────────────────────────────────
  Widget _buildEmptyState(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.store_mall_directory_rounded,
              size: 56,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'لم تضف أي فرع بعد',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'أضف فروعك لمتابعة الحضور اليومي',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showBranchPicker(context),
            icon: const Icon(Icons.add_location_alt_rounded),
            label: const Text('إضافة فرع'),
          ),
        ],
      ),
    );
  }

  // ─── Loading Skeletons ────────────────────────────────────────────────────
  Widget _buildLoadingSkeletons(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _favoriteBranches.length,
      itemBuilder: (_, index) => _BranchSectionSkeleton(
        branchName: _favoriteBranches[index],
        colorScheme: colorScheme,
      ),
    );
  }

  // ─── Error ──────────────────────────────────────────────────────────────
  Widget _buildError(
    BuildContext context,
    String message,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 56, color: colorScheme.error),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => _loadAllBranches(context, _favoriteBranches),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  // ─── All Branches Sections ───────────────────────────────────────────────
  Widget _buildAllBranches(
    BuildContext context,
    AllBranchesAttendanceLoaded state,
    ColorScheme colorScheme,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        _loadAllBranches(context, _favoriteBranches, forceRefresh: true);
        await _syncFloorVerificationsFromCloud();
      },
      child: CustomScrollView(
        slivers: [
          if (state.isEnriching)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'جاري استكمال الأسماء والصور…',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // ─── تاريخ اليوم ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Card(
                elevation: 0,
                color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                  ),
                ),
                child: InkWell(
                  onTap: () => _selectDate(),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('EEEE، d MMMM yyyy', 'ar').format(_selectedDate),
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          color: colorScheme.primary,
                        ),
                        const Spacer(),
                        if (_lastSyncTime != null)
                          Tooltip(
                            message: 'آخر مزامنة ناجحة مع السيرفر: ${DateFormat('h:mm:ss a', 'ar').format(_lastSyncTime!)}',
                            child: Container(
                              margin: const EdgeInsetsDirectional.only(end: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF2E7D32),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'مُتصل (${DateFormat('h:mm a', 'ar').format(_lastSyncTime!)})',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2E7D32),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (!DateUtils.isSameDay(_selectedDate, DateTime.now()))
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedDate = DateTime.now();
                              });
                              _loadAllBranches(context, _favoriteBranches, forceRefresh: true);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 0,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'اليوم',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ─── شريط البحث عن مندوب أو شركة ────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                },
                decoration: InputDecoration(
                  hintText: 'ابحث باسم المندوب أو اسم الشركة...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: colorScheme.primary,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),
          ),

          // ─── شريط التحكم بالفروع (إذا كان هناك أكثر من فرع) ──────────────
          if (state.favoriteBranches.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.store_mall_directory_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'الفروع المتابعة (${state.favoriteBranches.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        if (_collapsedBranches.length >= state.favoriteBranches.length) {
                          _expandAll();
                        } else {
                          _collapseAll(state.favoriteBranches);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _collapsedBranches.length >= state.favoriteBranches.length
                                  ? Icons.unfold_more_rounded
                                  : Icons.unfold_less_rounded,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _collapsedBranches.length >= state.favoriteBranches.length
                                  ? 'فتح الكل'
                                  : 'طي الكل',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ─── قسم لكل فرع (header sliver + virtualized rows when expanded) ──
          for (final branchName in state.favoriteBranches)
            ..._buildBranchSlivers(
              context,
              branchName,
              state.data[branchName] ?? [],
              colorScheme,
              isBranchLoading: state.isBranchLoading(branchName),
            ),

          // مسافة أسفل الصفحة
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ─── Branch Section (Header + virtualized Delegate Cards) ─────────────────
  List<Widget> _buildBranchSlivers(
    BuildContext context,
    String branchName,
    List<Map<String, dynamic>> records,
    ColorScheme colorScheme, {
    bool isBranchLoading = false,
  }) {
    final query = _searchQuery.toLowerCase();
    final totalCount = records.length;
    final presentCount = records.where((r) => r['checkOutTime'] == null).length;
    final checkedOutCount = totalCount - presentCount;
    final isExpanded = !_collapsedBranches.contains(branchName);

    // Floor Verification Stats
    final verifiedCount = records.where((r) => _floorVerifications[r['delegateId']]?.isVerified == true).length;
    final missingCount = records.where((r) => _floorVerifications[r['delegateId']]?.isMissing == true).length;
    final remainingCount = totalCount - verifiedCount - missingCount;

    // Filter by branch floor status
    final currentFilter = _branchFilter[branchName] ?? 'all';
    final searchFilteredRecords = query.isEmpty
        ? records
        : records.where((r) {
            final name = (r['fullName'] as String? ?? '').toLowerCase();
            final company = (r['companyName'] as String? ?? '').toLowerCase();
            final phone = (r['phoneNumber'] as String? ?? '').toLowerCase();
            return name.contains(query) || company.contains(query) || phone.contains(query);
          }).toList();

    final displayRecords = searchFilteredRecords.where((r) {
      final dId = r['delegateId'] as String? ?? '';
      final vItem = _floorVerifications[dId];
      if (currentFilter == 'not_checked_out') {
        return r['checkOutTime'] == null;
      } else if (currentFilter == 'checked_out') {
        return r['checkOutTime'] != null;
      } else if (currentFilter == 'remaining') {
        return vItem == null || (!vItem.isVerified && !vItem.isMissing);
      } else if (currentFilter == 'verified') {
        return vItem?.isVerified == true;
      } else if (currentFilter == 'missing') {
        return vItem?.isMissing == true;
      }
      return true;
    }).toList();


    final slivers = <Widget>[];

    Widget branchHeader() {
      return AnimatedContainer(
        duration: AppMotionDurations.short4,
        curve: AppMotionCurves.emphasized,
        margin: EdgeInsets.fromLTRB(16, 12, 16, isExpanded ? 0 : 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer,
              colorScheme.secondaryContainer,
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: isExpanded
              ? const BorderRadius.vertical(
                  top: Radius.circular(16),
                  bottom: Radius.circular(4),
                )
              : BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: isExpanded
                ? const BorderRadius.vertical(
                    top: Radius.circular(16),
                    bottom: Radius.circular(4),
                  )
                : BorderRadius.circular(16),
            onTap: () => _toggleBranchExpansion(branchName),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.storefront_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          branchName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      if (totalCount > 0)
                        Container(
                          margin: const EdgeInsetsDirectional.only(end: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$totalCount مندوب',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                          size: 20,
                        ),
                        tooltip: 'إزالة الفرع من القائمة',
                        style: IconButton.styleFrom(
                          backgroundColor:
                              colorScheme.surface.withValues(alpha: 0.8),
                          padding: const EdgeInsets.all(6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () =>
                            _confirmRemoveBranch(context, branchName),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: AppMotionDurations.short4,
                        curve: AppMotionCurves.emphasized,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: colorScheme.onPrimaryContainer,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  if (totalCount > 0) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 44),
                      child: Text(
                        '$presentCount حاضر • $checkedOutCount منصرف • تم فحص $verifiedCount من $totalCount',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    slivers.add(SliverToBoxAdapter(child: branchHeader()));

    if (!isExpanded) {
      return slivers;
    }

    if (isBranchLoading && records.isEmpty) {
      slivers.add(SliverToBoxAdapter(child: _buildBranchLoadingCard(colorScheme)));
      return slivers;
    }
    if (records.isEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: _buildEmptyBranchPlaceholder(query, colorScheme),
      ));
      return slivers;
    }

    // Filter/progress chrome (not virtualized — small).
    slivers.add(SliverToBoxAdapter(
      child: _buildDelegatesContainer(
        context,
        branchName,
        records,
        displayRecords,
        colorScheme,
        verifiedCount: verifiedCount,
        missingCount: missingCount,
        remainingCount: remainingCount,
        presentCount: presentCount,
        checkedOutCount: checkedOutCount,
        currentFilter: currentFilter,
        rowsOnly: false,
        chromeOnly: true,
      ),
    ));

    if (displayRecords.isEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
              left: BorderSide(color: colorScheme.outlineVariant),
              right: BorderSide(color: colorScheme.outlineVariant),
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
          child: _buildEmptyFilterPlaceholder(
            context,
            branchName,
            currentFilter,
            verifiedCount,
            missingCount,
            totalCount,
            colorScheme,
          ),
        ),
      ));
      return slivers;
    }

    slivers.add(
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final record = displayRecords[index];
            final isLast = index == displayRecords.length - 1;
            final delegateId = record['delegateId'] as String? ?? '$index';
            return KeyedSubtree(
              key: ValueKey('delegate_${branchName}_$delegateId'),
              child: Container(
                margin: EdgeInsets.fromLTRB(16, 0, 16, isLast ? 8 : 0),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  border: Border(
                    left: BorderSide(color: colorScheme.outlineVariant),
                    right: BorderSide(color: colorScheme.outlineVariant),
                    bottom: isLast
                        ? BorderSide(color: colorScheme.outlineVariant)
                        : BorderSide.none,
                  ),
                  borderRadius: isLast
                      ? const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        )
                      : BorderRadius.zero,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDelegateRow(
                      context,
                      record,
                      colorScheme,
                      branchName,
                    ),
                    if (!isLast)
                      Divider(
                        height: 1,
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                        indent: 68,
                      ),
                  ],
                ),
              ),
            );
          },
          childCount: displayRecords.length,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
        ),
      ),
    );
    return slivers;
  }

  Widget _buildBranchLoadingCard(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(4),
          bottom: Radius.circular(16),
        ),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'جاري تحميل بيانات الفرع...',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBranchPlaceholder(String query, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(4),
          bottom: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          Icon(
            query.isNotEmpty
                ? Icons.search_off_rounded
                : Icons.people_outline_rounded,
            color: colorScheme.outlineVariant,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            query.isNotEmpty
                ? 'لا يوجد مندوب مطابق للبحث في هذا الفرع'
                : 'لا يوجد حضور اليوم',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDelegatesContainer(
    BuildContext context,
    String branchName,
    List<Map<String, dynamic>> allRecords,
    List<Map<String, dynamic>> displayRecords,
    ColorScheme colorScheme, {
    required int verifiedCount,
    required int missingCount,
    required int remainingCount,
    required int presentCount,
    required int checkedOutCount,
    required String currentFilter,
    bool chromeOnly = false,
    bool rowsOnly = false,
  }) {
    final totalCount = allRecords.length;
    final verifiedPercent = totalCount > 0 ? (verifiedCount / totalCount) : 0.0;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, chromeOnly ? 0 : 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(4),
          bottom: Radius.circular(chromeOnly ? 0 : 16),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── شريط تقدم التحقق الميداني بالصالة والفلاتر السريعة ───
          if (totalCount > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Row: عنوان الفحص ونسبة الإنجاز
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 15,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'التحقق الميداني بالصالة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'تم التحقق من $verifiedCount / $totalCount (${(verifiedPercent * 100).toInt()}%)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: verifiedCount == totalCount && totalCount > 0
                              ? const Color(0xFF2E7D32)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // شريط التقدم المرئي
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: verifiedPercent,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        verifiedCount == totalCount && totalCount > 0
                            ? const Color(0xFF2E7D32)
                            : colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // فلاتر سريعة بنقرة واحدة (Quick Filters)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFloorFilterChip(
                          label: 'الكل',
                          count: totalCount,
                          icon: Icons.group_rounded,
                          isSelected: currentFilter == 'all',
                          colorScheme: colorScheme,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _branchFilter[branchName] = 'all';
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        // فلتر الذين لم يسجلوا انصراف (حاضر بالفرع)
                        _buildFloorFilterChip(
                          label: 'لم ينصرف',
                          count: presentCount,
                          icon: Icons.pending_actions_rounded,
                          isSelected: currentFilter == 'not_checked_out',
                          colorScheme: colorScheme,
                          badgeColor: presentCount > 0 ? const Color(0xFFE65100) : null,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _branchFilter[branchName] = 'not_checked_out';
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildFloorFilterChip(
                          label: 'المتبقي للمرور',
                          count: remainingCount,
                          icon: Icons.directions_walk_rounded,
                          isSelected: currentFilter == 'remaining',
                          colorScheme: colorScheme,
                          badgeColor: remainingCount > 0 ? colorScheme.primary : null,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _branchFilter[branchName] = 'remaining';
                            });
                          },
                        ),
                        const SizedBox(width: 6),
                        _buildFloorFilterChip(
                          label: 'تم التحقق',
                          count: verifiedCount,
                          icon: Icons.check_circle_rounded,
                          isSelected: currentFilter == 'verified',
                          colorScheme: colorScheme,
                          badgeColor: verifiedCount > 0 ? const Color(0xFF2E7D32) : null,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _branchFilter[branchName] = 'verified';
                            });
                          },
                        ),
                        if (missingCount > 0 || currentFilter == 'missing') ...[
                          const SizedBox(width: 6),
                          _buildFloorFilterChip(
                            label: 'غير متواجد',
                            count: missingCount,
                            icon: Icons.cancel_rounded,
                            isSelected: currentFilter == 'missing',
                            colorScheme: colorScheme,
                            badgeColor: const Color(0xFFC62828),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _branchFilter[branchName] = 'missing';
                              });
                            },
                          ),
                        ],
                        if (checkedOutCount > 0 || currentFilter == 'checked_out') ...[
                          const SizedBox(width: 6),
                          _buildFloorFilterChip(
                            label: 'منصرف',
                            count: checkedOutCount,
                            icon: Icons.output_rounded,
                            isSelected: currentFilter == 'checked_out',
                            colorScheme: colorScheme,
                            badgeColor: colorScheme.onSurfaceVariant,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _branchFilter[branchName] = 'checked_out';
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Rows are virtualized via SliverList in _buildBranchSlivers when
          // chromeOnly is true (default for the >=5 favorites collapse path).
          if (!chromeOnly) ...[
            if (displayRecords.isEmpty)
              _buildEmptyFilterPlaceholder(
                context,
                branchName,
                currentFilter,
                verifiedCount,
                missingCount,
                totalCount,
                colorScheme,
              )
            else
              ...displayRecords.asMap().entries.map((entry) {
                final isLast = entry.key == displayRecords.length - 1;
                return Column(
                  children: [
                    _buildDelegateRow(
                      context,
                      entry.value,
                      colorScheme,
                      branchName,
                    ),
                    if (!isLast)
                      Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        indent: 68,
                      ),
                  ],
                );
              }),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyFilterPlaceholder(
    BuildContext context,
    String branchName,
    String filter,
    int verifiedCount,
    int missingCount,
    int totalCount,
    ColorScheme colorScheme,
  ) {
    if (filter == 'remaining' && totalCount > 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F5E9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.task_alt_rounded,
                size: 38,
                color: Color(0xFF2E7D32),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'اكتمل المرور على جميع مناديب الفرع!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF1B5E20),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'تم التحقق من $verifiedCount مندوب${missingCount > 0 ? " ورصد $missingCount غير متواجد" : ""}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _branchFilter[branchName] = 'all';
                });
              },
              icon: const Icon(Icons.people_outline_rounded, size: 18),
              label: const Text('عرض جميع المناديب'),
            ),
          ],
        ),
      );
    }

    String msg = 'لا توجد عناصر مطابقة';
    IconData icon = Icons.info_outline_rounded;
    if (filter == 'not_checked_out') {
      msg = 'جميع المناديب في هذا الفرع قاموا بتسجيل الانصراف';
      icon = Icons.check_circle_outline_rounded;
    } else if (filter == 'checked_out') {
      msg = 'لم يقم أي مندوب بتسجيل الانصراف بعد';
      icon = Icons.access_time_rounded;
    } else if (filter == 'verified') {
      msg = 'لم يتم التحقق من أي مندوب بعد';
      icon = Icons.check_circle_outline_rounded;
    } else if (filter == 'missing') {
      msg = 'لا يوجد أي مندوب رُصد كغير متواجد';
      icon = Icons.check_circle_outline_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 36, color: colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Text(
            msg,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _branchFilter[branchName] = 'all';
              });
            },
            child: const Text('عرض الكل'),
          ),
        ],
      ),
    );
  }

  Widget _buildFloorFilterChip({
    required String label,
    required int count,
    required IconData icon,
    required bool isSelected,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
    Color? badgeColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: AppMotionDurations.short3,
          curve: AppMotionCurves.standard,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? colorScheme.onPrimary
                    : (badgeColor ?? colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.onPrimary.withValues(alpha: 0.25)
                      : (badgeColor?.withValues(alpha: 0.12) ??
                          colorScheme.surfaceContainerHighest),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : (badgeColor ?? colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Delegate Row ─────────────────────────────────────────────────────────
  Widget _buildDelegateRow(
    BuildContext context,
    Map<String, dynamic> record,
    ColorScheme colorScheme, [
    String? branchName,
  ]) {
    final String rawName = (record['fullName'] as String?)?.trim() ?? '';
    final bool incomplete = record['profileIncomplete'] == true;
    final String fullName = rawName.isNotEmpty
        ? rawName
        : (incomplete ? '…' : 'مندوب');
    final String companyName = record['companyName'] as String? ?? '';
    final String? imageUrl = record['personalPhotoURL'] as String? ??
        record['imageUrl'] as String?;
    final checkIn = record['checkInTime'] as Timestamp?;
    final checkOut = record['checkOutTime'] as Timestamp?;
    final bool hasCheckOut = checkOut != null;

    final checkInStr = checkIn != null
        ? DateFormat('hh:mm a', 'ar').format(checkIn.toDate())
        : '--:--';
    final checkOutStr = checkOut != null
        ? DateFormat('hh:mm a', 'ar').format(checkOut.toDate())
        : '--:--';

    final hasPhoto = imageUrl != null && imageUrl.isNotEmpty;

    // Floor verification item for this delegate
    final delegateId = record['delegateId'] as String? ?? '';
    final vItem = _floorVerifications[delegateId];
    final isVerified = vItem?.isVerified == true;
    final isMissing = vItem?.isMissing == true;

    Color? rowBgColor;
    if (isVerified) {
      rowBgColor = const Color(0xFF2E7D32).withValues(alpha: 0.04);
    } else if (isMissing) {
      rowBgColor = const Color(0xFFC62828).withValues(alpha: 0.04);
    }

    return Material(
      color: rowBgColor ?? Colors.transparent,
      child: InkWell(
        onTap: () => _openAttendanceHistory(context, record),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Avatar (صورة المندوب أو الحرف الأول مع إمكانية التكبير عند الضغط)
              GestureDetector(
                onTap: hasPhoto
                    ? () => _showImagePreview(
                          context,
                          imageUrl,
                          fullName,
                          companyName,
                        )
                    : null,
                child: AppAvatar(
                  imageUrl: hasPhoto ? imageUrl : null,
                  fallbackText: fullName,
                  radius: 22,
                  backgroundColor: hasCheckOut
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.primaryContainer,
                  foregroundColor: hasCheckOut
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onPrimaryContainer,
                  badge: hasPhoto
                      ? Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.zoom_in_rounded,
                            size: 10,
                            color: colorScheme.primary,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              // Name & Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (companyName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        companyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _miniChip(
                          Icons.login_rounded,
                          checkInStr,
                          colorScheme.tertiaryContainer,
                          colorScheme.onTertiaryContainer,
                        ),
                        _miniChip(
                          Icons.logout_rounded,
                          checkOutStr,
                          hasCheckOut
                              ? colorScheme.errorContainer.withValues(alpha: 0.6)
                              : colorScheme.surfaceContainerHighest,
                          hasCheckOut
                              ? colorScheme.onErrorContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Trailing actions: Call Supervisor + Status Pill + Quick Floor Verification Button
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // زر اتصال بمشرف المندوب
                      IconButton(
                        icon: Icon(
                          Icons.phone_in_talk_rounded,
                          color: colorScheme.primary,
                          size: 18,
                        ),
                        tooltip: 'اتصال بمشرف المندوب',
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                          padding: const EdgeInsets.all(5),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _contactSupervisor(context, record),
                      ),
                      const SizedBox(width: 6),
                      // حالة الحضور (حاضر / منصرف)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: hasCheckOut
                              ? colorScheme.surfaceContainerHighest
                              : colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          hasCheckOut ? 'منصرف' : 'حاضر',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: hasCheckOut
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // ── زر الفحص التفاعلي السريع (Floor Verification Button) ──
                      _buildFloorVerificationButton(
                        context,
                        record,
                        vItem,
                        colorScheme,
                        branchName,
                      ),
                    ],
                  ),
                  // وقت الفحص الميداني
                  if (vItem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVerified
                                ? Icons.verified_rounded
                                : Icons.error_outline_rounded,
                            size: 11,
                            color: isVerified
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${isVerified ? "تم المرور" : "غير متواجد"} • ${DateFormat('hh:mm a', 'ar').format(vItem.timestamp)}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isVerified
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFC62828),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloorVerificationButton(
    BuildContext context,
    Map<String, dynamic> record,
    FloorVerificationItem? vItem,
    ColorScheme colorScheme, [
    String? branchName,
  ]) {
    final isVerified = vItem?.isVerified == true;
    final isMissing = vItem?.isMissing == true;

    Color bg;
    Color border;
    Color fg;
    IconData icon;
    String label;

    if (isVerified) {
      bg = const Color(0xFFE8F5E9);
      border = const Color(0xFF2E7D32);
      fg = const Color(0xFF1B5E20);
      icon = Icons.check_circle_rounded;
      label = 'تم المرور';
    } else if (isMissing) {
      bg = const Color(0xFFFFEBEE);
      border = const Color(0xFFC62828);
      fg = const Color(0xFFB71C1C);
      icon = Icons.cancel_rounded;
      label = 'غير متواجد';
    } else {
      bg = colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
      border = colorScheme.outlineVariant.withValues(alpha: 0.6);
      fg = colorScheme.onSurfaceVariant;
      icon = Icons.radio_button_unchecked_rounded;
      label = 'فحص';
    }

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: isVerified
            ? 'تم التحقق • اضغط للإلغاء أو ضغطة مطولة لتغيير الحالة'
            : (isMissing
                ? 'غير متواجد بالصالة • اضغط للتحقق أو ضغطة مطولة للخيارات'
                : 'اضغط لتأكيد التواجد بالصالة • ضغطة مطولة لتحديد غير متواجد'),
        child: InkWell(
          onTap: () => _toggleFloorVerification(record, branchName),
          onLongPress: () => _showFloorVerificationDialog(context, record, branchName),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: AppMotionDurations.short3,
            curve: AppMotionCurves.standard,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: isVerified || isMissing ? 1.2 : 1),
              boxShadow: isVerified
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isVerified || isMissing ? FontWeight.bold : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniChip(IconData icon, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: fg, fontSize: 11)),
        ],
      ),
    );
  }

  // ─── Contact Supervisor (اتصال بمشرف المندوب) ──────────────────────────
  Future<void> _contactSupervisor(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final String delegateName = record['fullName'] as String? ?? 'المندوب';
    final String companyName = record['companyName'] as String? ?? '';
    final String companyUID = record['companyUID'] as String? ?? '';
    final delegateData = record['delegateData'] as Map<String, dynamic>?;

    String? supName = record['supervisorName'] as String? ??
        delegateData?['supervisorName'] as String?;
    String? supPhone = record['supervisorPhone'] as String? ??
        delegateData?['supervisorPhone'] as String?;

    // If supervisor phone is not directly present, resolve it dynamically
    if (supPhone == null || supPhone.trim().isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final firestore = di.sl<FirebaseFirestore>();

        // 1. Check createdBy in users
        final createdBy = (record['createdBy'] ?? delegateData?['createdBy']) as String?;
        if (createdBy != null && createdBy.isNotEmpty) {
          final supDoc = await firestore.collection('users').doc(createdBy).get();
          if (supDoc.exists && supDoc.data() != null) {
            final data = supDoc.data()!;
            final phone = data['phoneNumber'] as String? ?? data['phone'] as String?;
            if (phone != null && phone.isNotEmpty) {
              supPhone = phone;
              supName ??= data['displayName'] as String? ?? data['name'] as String?;
            }
          }
        }

        // 2. If still empty, search users for company-admin or supervisor of this company
        if ((supPhone == null || supPhone.isEmpty) && companyUID.isNotEmpty) {
          final querySnap = await firestore
              .collection('users')
              .where('companyUID', isEqualTo: companyUID)
              .where('role', whereIn: ['company-admin', 'supervisor'])
              .limit(1)
              .get();

          if (querySnap.docs.isNotEmpty) {
            final data = querySnap.docs.first.data();
            final phone = data['phoneNumber'] as String? ?? data['phone'] as String?;
            if (phone != null && phone.isNotEmpty) {
              supPhone = phone;
              supName ??= data['displayName'] as String? ?? data['name'] as String?;
            }
          }
        }

        // 3. If still empty, check company document in organizations
        final effectiveOrg = widget.marketingUser.organizationUID.isNotEmpty
            ? widget.marketingUser.organizationUID
            : (record['organizationId'] as String? ??
                delegateData?['organizationUID'] as String? ??
                kDefaultOrganizationId);

        if ((supPhone == null || supPhone.isEmpty) &&
            companyUID.isNotEmpty &&
            effectiveOrg.isNotEmpty) {
          final compDoc = await firestore
              .collection('organizations')
              .doc(effectiveOrg)
              .collection('companies')
              .doc(companyUID)
              .get();
          if (compDoc.exists && compDoc.data() != null) {
            final compData = compDoc.data()!;
            final phone = compData['supervisorPhone'] as String? ??
                compData['phone'] as String? ??
                compData['phoneNumber'] as String?;
            if (phone != null && phone.isNotEmpty) {
              supPhone = phone;
              supName ??= compData['supervisorName'] as String? ??
                  (companyName.isNotEmpty ? 'مشرف $companyName' : null);
            }
          }
        }

        // Cache for subsequent taps
        if (supPhone != null && supPhone.isNotEmpty) {
          record['supervisorPhone'] = supPhone;
          if (supName != null) record['supervisorName'] = supName;
        }
      } catch (_) {
      } finally {
        if (context.mounted) Navigator.of(context).pop();
      }
    }

    if (!context.mounted) return;

    _showSupervisorModal(
      context: context,
      delegateName: delegateName,
      companyName: companyName,
      supervisorName: (supName != null && supName.isNotEmpty)
          ? supName
          : (companyName.isNotEmpty ? 'مشرف $companyName' : 'مشرف المندوب'),
      supervisorPhone: supPhone,
    );
  }

  void _showSupervisorModal({
    required BuildContext context,
    required String delegateName,
    required String companyName,
    required String supervisorName,
    required String? supervisorPhone,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPhone = supervisorPhone != null && supervisorPhone.trim().isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(sheetCtx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header Avatar & Titles
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.supervisor_account_rounded,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الاتصال بمشرف المندوب',
                          style: GoogleFonts.cairo(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '$delegateName ${companyName.isNotEmpty ? '• $companyName' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (hasPhone) ...[
                // Supervisor Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              supervisorName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'مشرف الشركة',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_iphone_rounded,
                            size: 20,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              supervisorPhone,
                              style: GoogleFonts.cairo(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            tooltip: 'نسخ الرقم',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: supervisorPhone),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم نسخ رقم المشرف إلى الحافظة'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons (Call / WhatsApp)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _callPhone(supervisorPhone);
                        },
                        icon: const Icon(Icons.phone_in_talk_rounded),
                        label: Text(
                          'اتصال الآن',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: Colors.green.withValues(alpha: 0.15),
                          foregroundColor: Colors.green.shade800,
                        ),
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          _openWhatsApp(supervisorPhone, delegateName);
                        },
                        icon: const Icon(Icons.chat_rounded, color: Colors.green),
                        label: Text(
                          'واتساب',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Empty state for supervisor phone
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.phone_disabled_rounded,
                        size: 40,
                        color: colorScheme.error.withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'لا يوجد رقم هاتف مسجل لمشرف هذا المندوب',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (companyName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'شركة: $companyName',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('إغلاق'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _openWhatsApp(String phone, String delegateName) async {
    var cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '2$cleanPhone';
    }
    final message = Uri.encodeComponent('مرحباً، بخصوص المندوب: $delegateName');
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=$message');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  // ─── Open Attendance History ───────────────────────────────────────────────
  void _openAttendanceHistory(BuildContext context, Map<String, dynamic> record) {
    final delegateData = record['delegateData'] as Map<String, dynamic>?;
    final delegateId = record['delegateId'] as String? ?? '';
    if (delegateId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات للمندوب')),
      );
      return;
    }
    try {
      final safeData = Map<String, dynamic>.from(delegateData ?? {});
      safeData.putIfAbsent('uid', () => delegateId);
      safeData.putIfAbsent('fullName', () => record['fullName'] ?? 'مندوب');
      safeData.putIfAbsent('phoneNumber', () => record['phoneNumber'] ?? '');
      safeData.putIfAbsent('companyName', () => record['companyName'] ?? '');
      safeData.putIfAbsent('companyUID', () => record['companyUID'] ?? '');
      final effectiveOrg = widget.marketingUser.organizationUID.isNotEmpty
          ? widget.marketingUser.organizationUID
          : (record['organizationId'] as String? ?? kDefaultOrganizationId);
      safeData['organizationUID'] = effectiveOrg;
      safeData.putIfAbsent('status', () => 'Active');
      safeData.putIfAbsent('role', () => 'delegate');

      final delegate = DelegateModel.fromJson(safeData, delegateId);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceScreen(delegate: delegate, viewOnly: true),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح سجل الحضور')),
      );
    }
  }

  // ─── Image Preview (تكبير الصورة) ──────────────────────────────────────────
  void _showImagePreview(
    BuildContext context,
    String imageUrl,
    String name,
    String company,
  ) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with name & close button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (company.isNotEmpty)
                            Text(
                              company,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Image Container with InteractiveViewer (pinch & zoom)
              Flexible(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Container(
                    color: Colors.black,
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.65,
                      maxWidth: double.infinity,
                    ),
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                                SizedBox(height: 8),
                                Text(
                                  'تعذّر عرض الصورة',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Branch Picker ─────────────────────────────────────────────────────────
  void _showBranchPicker(BuildContext context) {
    final bloc = context.read<MarketingBloc>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => BranchPickerBottomSheet(
        userId: widget.marketingUser.uid,
        organizationId: widget.marketingUser.organizationUID,
        userRole: widget.marketingUser.role,
        currentFavorites: _favoriteBranches,
        onBranchSelected: (branchName) {
          setState(() {
            _collapsedBranches.remove(branchName);
          });
          bloc.add(AddFavoriteBranch(
            userId: widget.marketingUser.uid,
            branchName: branchName,
          ));
        },
      ),
    );
  }

  // ─── Remove Branch ─────────────────────────────────────────────────────────
  void _confirmRemoveBranch(BuildContext context, String branchName) {
    final bloc = context.read<MarketingBloc>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    Widget buildConfirmContent(BuildContext modalContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          isDesktop ? 20 : 12,
          20,
          24 + MediaQuery.viewInsetsOf(modalContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isDesktop) ...[
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Icon(Icons.delete_rounded, color: colorScheme.error, size: 24),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'حذف الفرع',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'هل تريد إزالة "$branchName" من قائمة فروعك المتابعة؟',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(modalContext),
                        child: Center(
                          child: Text(
                            'إلغاء',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                  ),
                  Expanded(
                    child: Material(
                      color: colorScheme.error.withValues(alpha: 0.12),
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(modalContext);
                          setState(() {
                            _collapsedBranches.remove(branchName);
                          });
                          bloc.add(RemoveFavoriteBranch(
                            userId: widget.marketingUser.uid,
                            branchName: branchName,
                          ));
                        },
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_rounded, size: 18, color: colorScheme.error),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'حذف',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (dialogCtx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: buildConfirmContent(dialogCtx),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetCtx) => buildConfirmContent(sheetCtx),
      );
    }
  }

  // ─── Export Attendance to Excel Modal ──────────────────────────────────────
  Future<void> _showExportExcelModal(
    BuildContext context, {
    String? preselectedBranch,
    Map<String, List<Map<String, dynamic>>>? branchRecords,
    bool initialOnlyNotCheckedOut = false,
  }) async {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    // CSV/search must use enriched data — wait briefly if first-paint still enriching.
    if (_lastLoadedState?.isEnriching == true) {
      final bloc = context.read<MarketingBloc>();
      final completer = Completer<void>();
      late final StreamSubscription sub;
      sub = bloc.stream.listen((s) {
        if (s is AllBranchesAttendanceLoaded && !s.isEnriching) {
          _lastLoadedState = s;
          if (!completer.isCompleted) completer.complete();
          sub.cancel();
        }
      });
      try {
        await completer.future.timeout(const Duration(seconds: 8));
      } catch (_) {
        await sub.cancel();
      }
      if (!context.mounted) return;
    }

    final targetBranchRecords = branchRecords ?? (_lastLoadedState?.data ?? {});
    final branches = preselectedBranch != null
        ? [preselectedBranch]
        : (targetBranchRecords.isNotEmpty
            ? targetBranchRecords.keys.toList()
            : _favoriteBranches);

    if (branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد فروع لتصدير بياناتها')),
      );
      return;
    }

    if (isDesktop) {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => Dialog(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _ExportExcelBottomSheet(
              selectedDate: _selectedDate,
              branches: branches,
              branchRecords: targetBranchRecords,
              preselectedBranch: preselectedBranch,
              initialOnlyNotCheckedOut: initialOnlyNotCheckedOut,
              floorVerifications: _floorVerifications,
              isDesktop: true,
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) => _ExportExcelBottomSheet(
          selectedDate: _selectedDate,
          branches: branches,
          branchRecords: targetBranchRecords,
          preselectedBranch: preselectedBranch,
          initialOnlyNotCheckedOut: initialOnlyNotCheckedOut,
          floorVerifications: _floorVerifications,
          isDesktop: false,
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton loading card
// ─────────────────────────────────────────────────────────────────────────────
class _BranchSectionSkeleton extends StatelessWidget {
  final String branchName;
  final ColorScheme colorScheme;
  const _BranchSectionSkeleton({
    required this.branchName,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header skeleton
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Icon(Icons.location_on_rounded,
                  color: colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                branchName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        // Body skeleton
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          height: 80,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Branch Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class BranchPickerBottomSheet extends StatefulWidget {
  final String userId;
  final String organizationId;
  final UserRole? userRole;
  final List<String> currentFavorites;
  final void Function(String branchName) onBranchSelected;

  const BranchPickerBottomSheet({
    super.key,
    required this.userId,
    required this.organizationId,
    this.userRole,
    required this.currentFavorites,
    required this.onBranchSelected,
  });

  @override
  State<BranchPickerBottomSheet> createState() =>
      _BranchPickerBottomSheetState();
}

class _BranchPickerBottomSheetState extends State<BranchPickerBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allBranches = [];
  List<Map<String, dynamic>> _filtered = [];
  List<Map<String, String>> _organizations = [];
  String? _selectedOrgUID;
  bool _loading = true;
  String? _error;

  bool get isSuperAdminOrTechSupport {
    final r = widget.userRole;
    if (r == null) return false;
    return r == UserRole.superAdmin ||
        r == UserRole.technicalSupport ||
        r.name.toLowerCase().contains('super') ||
        r.name.toLowerCase().contains('technical');
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final firestore = di.sl<FirebaseFirestore>();

      // 1. Fetch organizations if Super Admin or Tech Support
      final List<Map<String, String>> orgs = [];
      try {
        final orgSnapshot = await firestore.collection('organizations').get();
        for (final doc in orgSnapshot.docs) {
          final d = doc.data();
          final name = (d['name'] ?? d['title'] ?? '').toString().trim();
          final uid = (d['uid'] ?? d['organizationUID'] ?? doc.id).toString().trim();
          if (name.isNotEmpty) {
            orgs.add({'uid': uid.isNotEmpty ? uid : doc.id, 'name': name});
          }
        }
      } catch (_) {}

      // Ensure Fathalla Market exists and is placed at the top as default
      final hasFathalla = orgs.any((o) =>
          (o['name'] ?? '').toLowerCase().contains('fathalla') ||
          o['uid'] == kDefaultOrganizationId);
      if (!hasFathalla) {
        orgs.insert(0, {'uid': kDefaultOrganizationId, 'name': 'fathalla market'});
      } else {
        final fIndex = orgs.indexWhere((o) =>
            (o['name'] ?? '').toLowerCase().contains('fathalla') ||
            o['uid'] == kDefaultOrganizationId);
        if (fIndex > 0) {
          final item = orgs.removeAt(fIndex);
          orgs.insert(0, item);
        }
      }

      _selectedOrgUID = orgs.first['uid'];

      // 2. Fetch all branches
      final snapshot = await firestore.collection('branches').get();
      final docs = snapshot.docs.map((d) {
        final data = d.data();
        final name = (data['branchName'] as String?) ??
            (data['name'] as String?) ??
            (data['title'] as String?) ??
            '';
        return {
          'id': d.id,
          'branchName': name,
          'organizationUID': (data['organizationUID'] ?? data['organizationId'] ?? data['orgId'] ?? '').toString().trim(),
          'organizationName': (data['organizationName'] ?? data['orgName'] ?? data['organization_name'] ?? '').toString().trim(),
        };
      }).where((b) => (b['branchName'] as String).isNotEmpty).toList();

      docs.sort((a, b) =>
          (a['branchName'] ?? '').compareTo(b['branchName'] ?? ''));

      if (mounted) {
        setState(() {
          _organizations = orgs;
          _allBranches = docs;
          _loading = false;
          _applyFilter();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'فشل في جلب الفروع';
          _loading = false;
        });
      }
    }
  }

  bool _matchesOrg(Map<String, dynamic> branch, String targetOrgUID, String targetOrgName) {
    final bOrgUID = (branch['organizationUID'] ?? '').toString().trim();
    final bOrgName = (branch['organizationName'] ?? '').toString().trim().toLowerCase();
    final bName = (branch['branchName'] ?? '').toString().trim().toLowerCase();
    final tOrgName = targetOrgName.trim().toLowerCase();

    // 1. Direct UID match
    if (targetOrgUID.isNotEmpty && bOrgUID.isNotEmpty && bOrgUID == targetOrgUID) {
      return true;
    }

    // 2. Direct Name match
    if (tOrgName.isNotEmpty && bOrgName.isNotEmpty && bOrgName == tOrgName) {
      return true;
    }

    // 3. Name contains or branchName contains org name
    if (tOrgName.isNotEmpty && bName.contains(tOrgName)) {
      return true;
    }

    // 4. If target is Fathalla Market:
    if (tOrgName.contains('fathalla') || targetOrgUID == kDefaultOrganizationId) {
      if (bOrgUID.isEmpty && bOrgName.isEmpty) {
        final isOtherOrg = bName.contains('جملة') ||
            bName.contains('زهران') ||
            bName.contains('كارفور') ||
            bName.contains('بيت الجملة');
        if (!isOtherOrg) return true;
      }
    }

    // 5. If target is Gomla Market:
    if (tOrgName.contains('جملة') || tOrgName.contains('gomla') || targetOrgUID == '5DE6702w6hFwycJfZyqM') {
      if (bName.contains('جملة') || bOrgName.contains('جملة') || bOrgUID == '5DE6702w6hFwycJfZyqM') {
        return true;
      }
    }

    // 6. If target is Zahran Market:
    if (tOrgName.contains('زهران') || tOrgName.contains('zahran') || targetOrgUID == 'bKmvQOGNjYnfkzuGWq55') {
      if (bName.contains('زهران') || bOrgName.contains('زهران') || bOrgUID == 'bKmvQOGNjYnfkzuGWq55') {
        return true;
      }
    }

    // 7. If target is Carrefour:
    if (tOrgName.contains('كارفور') || tOrgName.contains('carrefour') || targetOrgUID == 'TjdANTbys7alTSahTyb7') {
      if (bName.contains('كارفور') || bOrgName.contains('كارفور') || bOrgUID == 'TjdANTbys7alTSahTyb7') {
        return true;
      }
    }

    // 8. If target is Beit El Gomla:
    if (tOrgName.contains('بيت الجملة') || targetOrgUID == 'tLU900K8StXVFcn6AgDn') {
      if (bName.contains('بيت الجملة') || bOrgName.contains('بيت الجملة') || bOrgUID == 'tLU900K8StXVFcn6AgDn') {
        return true;
      }
    }

    return false;
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();

    String targetOrgName = 'fathalla market';
    String targetOrgUID = kDefaultOrganizationId;

    if (isSuperAdminOrTechSupport) {
      if (_selectedOrgUID != null) {
        targetOrgUID = _selectedOrgUID!;
        final found = _organizations.firstWhere(
          (o) => o['uid'] == _selectedOrgUID,
          orElse: () => {'uid': targetOrgUID, 'name': 'fathalla market'},
        );
        targetOrgName = found['name'] ?? 'fathalla market';
      }
    } else {
      // For all regular users: strictly locked to fathalla market
      targetOrgName = 'fathalla market';
      targetOrgUID = kDefaultOrganizationId;
    }

    final orgBranches = _allBranches.where((b) {
      return _matchesOrg(b, targetOrgUID, targetOrgName);
    }).toList();

    _filtered = q.isEmpty
        ? orgBranches
        : orgBranches.where((b) {
            final name = (b['branchName'] as String? ?? '').toLowerCase();
            return name.contains(q);
          }).toList();
  }

  void _onSearch(String query) {
    setState(() {
      _applyFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.70,
      maxChildSize: 0.94,
      minChildSize: 0.45,
      builder: (context, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.outline.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.add_location_alt_rounded, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'إضافة فرع',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (!isSuperAdminOrTechSupport) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.business_rounded,
                          size: 14,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'fathalla market',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // For Super Admin and Technical Support: Dropdown Menu for Organizations
          if (isSuperAdminOrTechSupport && _organizations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                key: ValueKey('branch_picker_org_$_selectedOrgUID'),
                initialValue: _selectedOrgUID,
                isExpanded: true,
                dropdownColor: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                decoration: InputDecoration(
                  labelText: 'اختر السلسلة / المنظمة',
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: Icon(
                    Icons.corporate_fare_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                items: _organizations.map((org) {
                  final isSelected = org['uid'] == _selectedOrgUID;
                  return DropdownMenuItem<String>(
                    value: org['uid'],
                    child: Row(
                      children: [
                        Icon(
                          Icons.business_rounded,
                          size: 18,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          org['name']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (uid) {
                  if (uid != null && uid != _selectedOrgUID) {
                    setState(() {
                      _selectedOrgUID = uid;
                      _applyFilter();
                    });
                  }
                },
              ),
            ),
          ],

          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'ابحث عن فرع...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                            const SizedBox(height: 8),
                            Text(_error!),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });
                                _loadData();
                              },
                              child: const Text('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      )
                    : _filtered.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Text(
                                'لا توجد فروع مطابقة لهذه السلسلة',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _filtered.length,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemBuilder: (context, index) {
                              final branch = _filtered[index];
                              final name =
                                  branch['branchName'] as String? ?? 'فرع';
                              final isAlreadyAdded =
                                  widget.currentFavorites.contains(name);

                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isAlreadyAdded
                                        ? colorScheme.primaryContainer
                                        : colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.store_rounded,
                                    color: isAlreadyAdded
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: isAlreadyAdded
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                trailing: isAlreadyAdded
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle_rounded,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'مضاف',
                                            style: TextStyle(
                                              color: colorScheme.primary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onTap: isAlreadyAdded
                                    ? null
                                    : () {
                                        Navigator.pop(context);
                                        widget.onBranchSelected(name);
                                      },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Export Attendance to Excel Modal Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _ExportExcelBottomSheet extends StatefulWidget {
  final DateTime selectedDate;
  final List<String> branches;
  final Map<String, List<Map<String, dynamic>>> branchRecords;
  final String? preselectedBranch;
  final bool initialOnlyNotCheckedOut;
  final Map<String, FloorVerificationItem> floorVerifications;
  final bool isDesktop;

  const _ExportExcelBottomSheet({
    required this.selectedDate,
    required this.branches,
    required this.branchRecords,
    this.preselectedBranch,
    this.initialOnlyNotCheckedOut = false,
    required this.floorVerifications,
    required this.isDesktop,
  });

  @override
  State<_ExportExcelBottomSheet> createState() => _ExportExcelBottomSheetState();
}

class _ExportExcelBottomSheetState extends State<_ExportExcelBottomSheet> {
  late String? _selectedBranch;
  late bool _onlyNotCheckedOut;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _selectedBranch = widget.preselectedBranch;
    _onlyNotCheckedOut = widget.initialOnlyNotCheckedOut;
  }

  List<Map<String, dynamic>> _getTargetRecords() {
    final List<Map<String, dynamic>> result = [];
    if (_selectedBranch != null) {
      final list = widget.branchRecords[_selectedBranch] ?? [];
      for (final r in list) {
        final withBranch = Map<String, dynamic>.from(r);
        withBranch['branchName'] ??= _selectedBranch;
        result.add(withBranch);
      }
    } else {
      widget.branchRecords.forEach((bName, list) {
        for (final r in list) {
          final withBranch = Map<String, dynamic>.from(r);
          withBranch['branchName'] ??= bName;
          result.add(withBranch);
        }
      });
    }

    if (_onlyNotCheckedOut) {
      return result.where((r) => r['checkOutTime'] == null).toList();
    }
    return result;
  }

  int _getPresentCount() {
    int count = 0;
    if (_selectedBranch != null) {
      final list = widget.branchRecords[_selectedBranch] ?? [];
      count += list.where((r) => r['checkOutTime'] == null).length;
    } else {
      widget.branchRecords.forEach((_, list) {
        count += list.where((r) => r['checkOutTime'] == null).length;
      });
    }
    return count;
  }

  int _getTotalCount() {
    int count = 0;
    if (_selectedBranch != null) {
      count = (widget.branchRecords[_selectedBranch] ?? []).length;
    } else {
      widget.branchRecords.forEach((_, list) {
        count += list.length;
      });
    }
    return count;
  }

  Future<void> _handleExport() async {
    if (_isExporting) return;
    final records = _getTargetRecords();
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سجلات مطابقة للخيارات المحددة')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final buffer = StringBuffer();
      // UTF-8 BOM for Arabic support in Microsoft Excel
      buffer.write('\uFEFF');

      final dayName = DateFormat('EEEE', 'ar').format(widget.selectedDate);
      final dateStr = DateFormat('yyyy-MM-dd', 'en').format(widget.selectedDate);
      final branchTitle = _selectedBranch ?? 'جميع الفروع المتابعة';
      final filterTitle = _onlyNotCheckedOut ? 'المناديب الذين لم ينصرفوا فقط' : 'كشف الحضور الكامل';

      // Header metadata
      buffer.writeln('كشف متابعة حضور الفروع');
      buffer.writeln('الفرع:,"$branchTitle"');
      buffer.writeln('اليوم:,"$dayName"');
      buffer.writeln('التاريخ:,"$dateStr"');
      buffer.writeln('نوع الكشف:,"$filterTitle"');
      buffer.writeln('إجمالي المناديب:,"${records.length}"');
      buffer.writeln('');

      // Columns requested by user:
      // اسم الشركة, اسم المندوب, اليوم, رقم التليفون + التفاصيل الميدانية
      buffer.writeln('م,اسم الشركة,اسم المندوب,اليوم,التاريخ,رقم التليفون,الفرع,وقت الحضور,وقت الانصراف,حالة الانصراف,التحقق الميداني بالصالة');

      for (var i = 0; i < records.length; i++) {
        final r = records[i];
        final companyName = (r['companyName'] as String? ?? 'غير محدد').replaceAll('"', '""');
        final fullName = (r['fullName'] as String? ?? 'مندوب').replaceAll('"', '""');
        final rawPhone = (r['phoneNumber'] as String? ?? '').replaceAll('"', '""');
        // Prepend tab so Excel strictly preserves leading zero
        final phone = rawPhone.isNotEmpty ? '\t$rawPhone' : 'غير مسجل';
        final branch = (r['branchName'] as String? ?? branchTitle).replaceAll('"', '""');

        final checkIn = r['checkInTime'] as Timestamp?;
        final checkOut = r['checkOutTime'] as Timestamp?;

        final checkInStr = checkIn != null
            ? DateFormat('hh:mm a', 'ar').format(checkIn.toDate())
            : 'لم يسجل';
        final checkOutStr = checkOut != null
            ? DateFormat('hh:mm a', 'ar').format(checkOut.toDate())
            : 'لم يسجل انصراف';
        final statusStr = checkOut != null ? 'منصرف' : 'حاضر (لم ينصرف)';

        final dId = r['delegateId'] as String? ?? '';
        final vItem = widget.floorVerifications[dId];
        final floorStr = vItem?.isVerified == true
            ? 'تم التحقق بالصالة'
            : (vItem?.isMissing == true ? 'غير متواجد' : 'لم يتم المرور');

        buffer.writeln(
          '${i + 1},"$companyName","$fullName","$dayName","$dateStr","$phone","$branch","$checkInStr","$checkOutStr","$statusStr","$floorStr"',
        );
      }

      final safeBranch = branchTitle
          .replaceAll(RegExp(r'[\/\\?%*:|"<> ]'), '_')
          .trim();
      final suffix = _onlyNotCheckedOut ? '_لم_ينصرفوا' : '_كامل';
      final fileName = 'كشف_حضور_$safeBranch${suffix}_$dateStr.csv';

      await FileDownloadHelper.downloadString(
        content: buffer.toString(),
        fileName: fileName,
        mimeType: 'text/csv;charset=utf-8',
        shareText: 'كشف حضور $branchTitle - $dayName $dateStr',
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('تم تصدير كشف Excel بنجاح: $fileName')),
              ],
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء التصدير: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presentCount = _getPresentCount();
    final totalCount = _getTotalCount();

    final contentWidget = Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        widget.isDesktop ? 20 : 12,
        20,
        widget.isDesktop ? 20 : (20 + MediaQuery.of(context).viewInsets.bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle for mobile
          if (!widget.isDesktop) ...[
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Title & Icon Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                  ),
                ),
                child: const Icon(
                  Icons.table_chart_rounded,
                  color: Color(0xFF2E7D32),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تصدير كشف الحضور إلى Excel',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('EEEE، d MMMM yyyy', 'ar').format(widget.selectedDate),
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

          // Branch selection dropdown (if multiple branches and not preselected)
          if (widget.preselectedBranch == null && widget.branches.length > 1) ...[
            Text(
              'الفرع المستهدف:',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedBranch,
                  isExpanded: true,
                  icon: const Icon(Icons.expand_more_rounded),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('جميع الفروع المتابعة (${widget.branches.length})'),
                    ),
                    ...widget.branches.map(
                      (b) => DropdownMenuItem<String?>(
                        value: b,
                        child: Text(b),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedBranch = val;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          Text(
            'نطاق التصدير:',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),

          // Option 1: المناديب الذين لم ينصرفوا فقط (الأولوية لطلب المستخدم)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _onlyNotCheckedOut = true);
            },
            child: AnimatedContainer(
              duration: AppMotionDurations.short3,
              curve: AppMotionCurves.standard,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _onlyNotCheckedOut
                    ? const Color(0xFFE65100).withValues(alpha: 0.08)
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _onlyNotCheckedOut
                      ? const Color(0xFFE65100)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: _onlyNotCheckedOut ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE65100).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.pending_actions_rounded,
                      color: Color(0xFFE65100),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'المناديب الذين لم ينصرفوا فقط',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE65100).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$presentCount حاضر',
                                style: const TextStyle(
                                  color: Color(0xFFE65100),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'تصدير اسم الشركة، المندوب، اليوم، ورقم التليفون للمتواجدين بالفرع',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _onlyNotCheckedOut
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: _onlyNotCheckedOut
                        ? const Color(0xFFE65100)
                        : colorScheme.outlineVariant,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Option 2: كشف الحضور الكامل
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _onlyNotCheckedOut = false);
            },
            child: AnimatedContainer(
              duration: AppMotionDurations.short3,
              curve: AppMotionCurves.standard,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: !_onlyNotCheckedOut
                    ? const Color(0xFF2E7D32).withValues(alpha: 0.08)
                    : colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: !_onlyNotCheckedOut
                      ? const Color(0xFF2E7D32)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: !_onlyNotCheckedOut ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: Color(0xFF2E7D32),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'كشف الحضور الكامل (الكل)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$totalCount مندوب',
                                style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'يشمل كافة المناديب الحاضرين والمنصرفين خلال اليوم',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    !_onlyNotCheckedOut
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: !_onlyNotCheckedOut
                        ? const Color(0xFF2E7D32)
                        : colorScheme.outlineVariant,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Connected Action Button Group
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                // زر التصدير
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
                    onTap: _isExporting ? null : _handleExport,
                    child: Center(
                      child: _isExporting
                          ? const AppLoadingIndicator(size: 20, color: Color(0xFF2E7D32))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.file_download_rounded,
                                  size: 18,
                                  color: Color(0xFF2E7D32),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'تصدير Excel',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E7D32),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),

                // Vertical Divider
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 8,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),

                // زر الإلغاء
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
                    onTap: _isExporting ? null : () => Navigator.of(context).pop(),
                    child: Center(
                      child: Text(
                        'إلغاء',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.isDesktop) {
      return contentWidget;
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: contentWidget,
    );
  }
}

