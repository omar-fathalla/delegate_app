// Web-only list-detail for «طلبات اشتراك واعتماد المناديب».
// Built only when WebRuntimePolicy.isWeb. Mobile keeps the card list.
import 'package:delegate_app/web/hr_system/company_chain_requests_panel.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_profile_edit_access.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/admin/presentation/pages/edit_delegate_profile_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/super_admin_subscription_financial_report_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Two panes from this content width up. 600–839 stays a single pane.
const double kSubscriptionTwoPaneMinWidth = 840;

/// List pane at content widths of 1200 and up.
const double kSubscriptionListPaneWide = 440;

/// List pane below 1200 (and at or above the two-pane breakpoint).
const double kSubscriptionListPaneNarrow = 380;

const double kSubscriptionPaneRadius = 28;
const double kSubscriptionPaneGap = 24;

/// Number face. Production uses Roboto. Tests can point this at Cairo,
/// because the widget-test font aliases Roboto to a glyph-less face.
@visibleForTesting
String subscriptionNumberFontFamily = 'Roboto';

TextStyle subscriptionNumberStyle(TextStyle? base) =>
    (base ?? const TextStyle()).copyWith(
      fontFamily: subscriptionNumberFontFamily,
      fontFamilyFallback: const ['Cairo', 'sans-serif'],
    );

/// Same people who see اعتماد / رفض on the existing card.
/// Company supervisors and HR can open the queue; they cannot change status.
bool subscriptionRequestReviewerCanDecide(UserRole role) =>
    role == UserRole.superAdmin || role == UserRole.technicalSupport;

/// Web-only failed approve/reject. M3 snackbar: inverse surface, floating,
/// at most 560 wide, 24 inset. The extra bottom inset clears the decision bar
/// (about 72 tall) so the bar is not covered. No outline — the shape has no side.
void showSubscriptionDecisionFailure(
  BuildContext context,
  String message,
  VoidCallback retry,
) {
  final cs = Theme.of(context).colorScheme;
  final width = MediaQuery.sizeOf(context).width;
  const maxWidth = 560.0;
  const inset = 24.0;
  final horizontal = width > maxWidth + inset * 2
      ? (width - maxWidth) / 2
      : inset;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: cs.inverseSurface,
      // Elevation paints a hard black shelf under the bar in this renderer.
      // The inverse surface already separates it; no border, no shadow.
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(horizontal, 0, horizontal, inset + 72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      content: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onInverseSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            style: ButtonStyle(
              animationDuration: Duration.zero,
              foregroundColor: WidgetStatePropertyAll(cs.inversePrimary),
              overlayColor: WidgetStatePropertyAll(
                cs.inversePrimary.withValues(alpha: 0.08),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 12),
              ),
              minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: retry,
            child: Text(
              'إعادة المحاولة',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.inversePrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Gender encoded in an Egyptian national ID (digit 13, odd = male).
/// Null when the loaded id is missing or not 14 digits.
DelegateGender? delegateGenderFromNationalId(String nationalId) {
  final clean = nationalId.trim();
  if (clean.length != 14 || !RegExp(r'^\d+$').hasMatch(clean)) return null;
  final digit = int.tryParse(clean[12]);
  if (digit == null) return null;
  return digit.isEven ? DelegateGender.female : DelegateGender.male;
}

/// Web success copy. Uses the delegate's gender when the national ID has it.
String subscriptionDecisionSuccessMessage(
  DelegateSubscriptionRequest request, {
  required bool deleted,
}) {
  final gender = delegateGenderFromNationalId(request.nationalId);
  final name = request.fullName.trim();
  if (deleted) {
    return switch (gender) {
      DelegateGender.female => 'تم حذف المندوبة $name من المنظومة.',
      DelegateGender.male => 'تم حذف المندوب $name من المنظومة.',
      null => 'تم حذف الحساب من المنظومة.',
    };
  }
  return switch (gender) {
    DelegateGender.female => 'تم اعتماد المندوبة $name وتفعيل حسابها.',
    DelegateGender.male => 'تم اعتماد المندوب $name وتفعيل حسابه.',
    null => 'تم اعتماد الطلب وتفعيل الحساب.',
  };
}

String subscriptionRequestTypeLabel(DelegateSubscriptionRequest request) {
  if (request.isAddOrganizationRequest) return 'طلب ربط بسلسلة إضافية';
  if (request.isRenewalRequest) return 'طلب تجديد اشتراك';
  if (request.isNationalIdUpdateRequest) return 'طلب تعديل الرقم القومي';
  if (request.isDeleteRequest) return 'طلب حذف مندوب';
  return 'طلب اشتراك مندوب جديد';
}

String subscriptionChainLabel(DelegateSubscriptionRequest request) {
  final org = request.organizationName.trim();
  if (org.isNotEmpty) return org;
  final company = request.companyName.trim();
  if (company.isNotEmpty) return company;
  return 'بدون سلسلة';
}

String subscriptionCostLabel(DelegateSubscriptionRequest request) {
  final cycle = request.subscriptionCycle.trim();
  final year = RegExp(r'(20\d{2})').firstMatch(cycle)?.group(1);
  final freePromo =
      request.paymentMethod == SubscriptionPaymentMethod.freePromotion ||
      request.paymentStatus == SubscriptionPaymentStatus.waived;
  if (freePromo) {
    if (year != null) return 'مجاناً (اشتراك $year)';
    if (cycle.isNotEmpty) return 'مجاناً (اشتراك $cycle)';
    return 'مجاناً';
  }
  if (request.paymentMethod == SubscriptionPaymentMethod.notRequired ||
      request.isAddOrganizationRequest ||
      request.fee <= 0) {
    return 'مجاناً';
  }
  return '${SubscriptionCycleHelper.formatEgp(request.fee)} ج.م';
}

String subscriptionRelativeTime(DateTime time, [DateTime? now]) {
  final clock = now ?? DateTime.now();
  final local = time.toLocal();
  final today = DateTime(clock.year, clock.month, clock.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = clock.difference(local);
  if (diff.isNegative || diff.inMinutes < 1) return 'الآن';
  if (day == today && diff.inMinutes < 60) {
    final m = diff.inMinutes;
    if (m == 1) return 'من دقيقة';
    if (m == 2) return 'من دقيقتين';
    if (m <= 10) return 'من $m دقايق';
    return 'من $m دقيقة';
  }
  if (day == today) {
    final h = diff.inHours.clamp(1, 23);
    if (h == 1) return 'من ساعة';
    if (h == 2) return 'من ساعتين';
    if (h <= 10) return 'من $h ساعات';
    return 'من $h ساعة';
  }
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == yesterday) return 'امبارح';
  final days = today.difference(day).inDays;
  if (days >= 2 && days < 7) {
    if (days == 2) return 'من يومين';
    return 'من $days أيام';
  }
  return subscriptionDateTimeLabel(local);
}

/// One absolute stamp, used for the request time and the result line.
/// Example: 16/11/2026 · 8:54 م
String subscriptionDateTimeLabel(DateTime time) {
  final local = time.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final h24 = local.hour;
  final hour = h24 % 12 == 0 ? 12 : h24 % 12;
  final min = local.minute.toString().padLeft(2, '0');
  final suffix = h24 < 12 ? 'ص' : 'م';
  return '$d/$m/${local.year} · $hour:$min $suffix';
}

/// Same left-to-right stamp «وقت الطلب» uses. A separate [Directionality]
/// keeps «م» / «ص» inside the run. A bidi isolate in an Arabic sentence
/// lets that letter jump out in front of the time.
Widget subscriptionLtrText(String value, TextStyle? style) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Text(value, style: subscriptionNumberStyle(style)),
  );
}

/// Result sentence split around the absolute stamp. The stamp is rendered
/// with [subscriptionLtrText], not concatenated into the Arabic run.
({String before, DateTime? at, String after})? subscriptionOutcomeParts(
  DelegateSubscriptionRequest request,
) {
  final who = request.reviewedBy?.trim();
  final hasWho = who != null && who.isNotEmpty;
  final at = request.reviewedAt;
  final reason = request.rejectionReason?.trim();
  final hasReason = reason != null && reason.isNotEmpty;
  final reviewer = hasWho ? 'بواسطة $who' : null;

  if (request.status == SubscriptionRequestStatus.approved) {
    final action = request.isDeleteRequest
        ? 'تم تنفيذ الحذف'
        : request.isNationalIdUpdateRequest
        ? 'تم اعتماد تعديل الرقم القومي'
        : 'تم الاعتماد';
    return (
      before: [
        action,
        ?reviewer,
        if (at != null) 'يوم',
      ].join(' '),
      at: at,
      after: '',
    );
  }
  if (request.status == SubscriptionRequestStatus.rejected) {
    final before = [
      'تم الرفض',
      ?reviewer,
      if (at != null) 'يوم',
    ].join(' ');
    final after = hasReason ? '. السبب: $reason' : '';
    if (!hasWho && at == null && !hasReason) {
      return (before: 'تم رفض الطلب', at: null, after: '');
    }
    return (before: before, at: at, after: after);
  }
  return null;
}

class DelegateSubscriptionRequestsWeb extends StatefulWidget {
  final Delegate currentAdmin;
  final Future<bool?> Function(DelegateSubscriptionRequest request) onApprove;
  final Future<bool?> Function(DelegateSubscriptionRequest request) onReject;

  /// Skips the repository stream. Used to render the layout with local data.
  final List<DelegateSubscriptionRequest>? requestsOverride;
  final bool loadingOverride;
  final String? errorOverride;

  final SubscriptionRequestStatus? initialStatusFilter;
  final bool initialShowAll;
  final String? initialSelectedId;
  final bool initialDetailOpen;
  final bool initialNewestFirst;

  const DelegateSubscriptionRequestsWeb({
    super.key,
    required this.currentAdmin,
    required this.onApprove,
    required this.onReject,
    this.requestsOverride,
    this.loadingOverride = false,
    this.errorOverride,
    this.initialStatusFilter,
    this.initialShowAll = false,
    this.initialSelectedId,
    this.initialDetailOpen = false,
    this.initialNewestFirst = true,
  });

  @override
  State<DelegateSubscriptionRequestsWeb> createState() =>
      _DelegateSubscriptionRequestsWebState();
}

class _DelegateSubscriptionRequestsWebState
    extends State<DelegateSubscriptionRequestsWeb> {
  late SubscriptionRequestStatus? _statusFilter;
  late bool _newestFirst;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _listFocus = FocusNode();
  String _query = '';
  String? _selectedId;
  bool _detailOpen = false;
  bool _deciding = false;
  bool _listFocused = false;
  String? _advanceWhenLeavesPending;
  Stream<List<DelegateSubscriptionRequest>>? _stream;

  List<DelegateSubscriptionRequest> _loaded = const [];
  List<DelegateSubscriptionRequest> _displayed = const [];
  bool _compact = true;

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialShowAll
        ? null
        : (widget.initialStatusFilter ?? SubscriptionRequestStatus.pending);
    _newestFirst = widget.initialNewestFirst;
    _selectedId = widget.initialSelectedId;
    _detailOpen = widget.initialDetailOpen;
    _listFocus.addListener(() {
      if (!mounted) return;
      setState(() => _listFocused = _listFocus.hasFocus);
    });
    if (widget.requestsOverride == null) {
      _stream = _openStream();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  Stream<List<DelegateSubscriptionRequest>> _openStream() {
    final admin = widget.currentAdmin;
    final repo = sl<DelegateSubscriptionRepository>();
    return repo.getSubscriptionRequestsStream(
      statusFilter: null,
      companyUID:
          (admin.role == UserRole.superAdmin ||
              admin.role == UserRole.technicalSupport ||
              admin.role == UserRole.organizationAdmin)
          ? null
          : (admin.companyUID.isNotEmpty ? admin.companyUID : null),
      organizationUID: admin.role == UserRole.organizationAdmin
          ? (admin.organizationUID.isNotEmpty ? admin.organizationUID : null)
          : null,
    );
  }

  List<DelegateSubscriptionRequest> _scope(
    List<DelegateSubscriptionRequest> raw,
  ) {
    final admin = widget.currentAdmin;
    if (admin.role == UserRole.admin && admin.companyUID.isNotEmpty) {
      return raw.where((r) => r.companyUID == admin.companyUID).toList();
    }
    return raw;
  }

  List<DelegateSubscriptionRequest> _sort(
    List<DelegateSubscriptionRequest> items,
  ) {
    final copy = [...items];
    copy.sort(
      (a, b) => _newestFirst
          ? b.createdAt.compareTo(a.createdAt)
          : a.createdAt.compareTo(b.createdAt),
    );
    return copy;
  }

  bool _matches(DelegateSubscriptionRequest request) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return request.fullName.toLowerCase().contains(q) ||
        request.phoneNumber.toLowerCase().contains(q) ||
        request.nationalId.toLowerCase().contains(q) ||
        request.proposedNationalId.toLowerCase().contains(q);
  }

  void _retryStream() {
    setState(() => _stream = _openStream());
  }

  KeyEventResult _onListKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _openFocused();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveSelection(int delta) {
    final items = _displayed;
    if (items.isEmpty) return;
    final current = items.indexWhere((r) => r.id == _selectedId);
    final nextIndex = current < 0
        ? (delta > 0 ? 0 : items.length - 1)
        : (current + delta).clamp(0, items.length - 1);
    setState(() => _selectedId = items[nextIndex].id);
  }

  void _openFocused() {
    if (_displayed.isEmpty) return;
    setState(() {
      _selectedId ??= _displayed.first.id;
      if (_compact) _detailOpen = true;
    });
  }

  void _select(DelegateSubscriptionRequest request, {required bool open}) {
    _listFocus.requestFocus();
    setState(() {
      _selectedId = request.id;
      _advanceWhenLeavesPending = null;
      if (open) _detailOpen = true;
    });
  }

  Future<void> _decide(
    DelegateSubscriptionRequest request,
    Future<bool?> Function() run,
  ) async {
    if (_deciding) return;
    setState(() => _deciding = true);
    bool? result;
    try {
      result = await run();
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
    if (!mounted || result == null) return;
    if (result) {
      _advanceFrom(request.id);
    } else {
      setState(() => _advanceWhenLeavesPending = request.id);
    }
  }

  void _advanceFrom(String id) {
    if (!mounted) return;
    final pending = _sort(
      _loaded
          .where((r) => r.status == SubscriptionRequestStatus.pending)
          .toList(),
    );
    final index = pending.indexWhere((r) => r.id == id);
    String? nextId;
    if (index >= 0 && index + 1 < pending.length) {
      nextId = pending[index + 1].id;
    } else if (index > 0) {
      nextId = pending[index - 1].id;
    } else {
      for (final item in pending) {
        if (item.id != id) {
          nextId = item.id;
          break;
        }
      }
    }
    if (nextId == id) nextId = null;
    setState(() {
      _advanceWhenLeavesPending = null;
      _selectedId = nextId;
      if (nextId == null) _detailOpen = false;
    });
  }

  void _maybeScheduleAdvance(List<DelegateSubscriptionRequest> loaded) {
    final id = _advanceWhenLeavesPending;
    if (id == null) return;
    final matches = loaded.where((r) => r.id == id);
    final stillPending =
        matches.isNotEmpty &&
        matches.first.status == SubscriptionRequestStatus.pending;
    if (stillPending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _advanceWhenLeavesPending != id) return;
      _advanceFrom(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final override = widget.requestsOverride;
    if (override != null) {
      return _scaffold(
        loading: widget.loadingOverride,
        error: widget.errorOverride,
        requests: widget.loadingOverride ? const [] : override,
      );
    }
    return StreamBuilder<List<DelegateSubscriptionRequest>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return _scaffold(loading: false, error: '${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return _scaffold(loading: true);
        }
        return _scaffold(
          loading: false,
          requests: _scope(snapshot.data ?? const []),
        );
      },
    );
  }

  Widget _scaffold({
    required bool loading,
    String? error,
    List<DelegateSubscriptionRequest> requests = const [],
  }) {
    final cs = Theme.of(context).colorScheme;
    final loaded = _sort(requests);
    _loaded = loaded;
    if (!loading && error == null) _maybeScheduleAdvance(loaded);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoPane = width >= kSubscriptionTwoPaneMinWidth;
        _compact = !twoPane;
        final selected = _find(loaded, _selectedId);
        final showCompact =
            !twoPane &&
            !loading &&
            error == null &&
            _detailOpen &&
            selected != null;
        if (showCompact) {
          final opened = selected;
          return Scaffold(
            backgroundColor: cs.surface,
            body: _compactDetail(opened),
            bottomNavigationBar: decisionBarFor(
              opened,
              role: widget.currentAdmin.role,
              deciding: _deciding,
              compact: true,
              onApprove: () =>
                  _decide(opened, () => widget.onApprove(opened)),
              onReject: () => _decide(opened, () => widget.onReject(opened)),
            ),
          );
        }
        return Scaffold(
          backgroundColor: cs.surface,
          body: twoPane
              ? _twoPane(loaded, loading: loading, error: error, width: width)
              : _singlePane(loaded, loading: loading, error: error),
        );
      },
    );
  }

  Widget _twoPane(
    List<DelegateSubscriptionRequest> loaded, {
    required bool loading,
    required String? error,
    required double width,
  }) {
    final listWidth = width >= 1200
        ? kSubscriptionListPaneWide
        : kSubscriptionListPaneNarrow;
    final selected = _find(loaded, _selectedId);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: listWidth,
            child: _pane(
              surface: true,
              child: _listColumn(loaded, loading: loading, error: error),
            ),
          ),
          const SizedBox(width: kSubscriptionPaneGap),
          Expanded(
            child: _pane(
              surface: false,
              child: loading
                  ? const SizedBox.expand()
                  : error != null
                  ? const SizedBox.expand()
                  : AnimatedSwitcher(
                      duration: AppMotionDurations.medium2,
                      reverseDuration: AppMotionDurations.short3,
                      switchInCurve: AppMotionCurves.standardDecelerate,
                      switchOutCurve: AppMotionCurves.standardAccelerate,
                      child: _detailOrPlaceholder(
                        loaded,
                        selected,
                        pinnedBar: true,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _singlePane(
    List<DelegateSubscriptionRequest> loaded, {
    required bool loading,
    required String? error,
  }) {
    return _pane(
      surface: true,
      margin: const EdgeInsets.all(12),
      child: _listColumn(loaded, loading: loading, error: error),
    );
  }

  Widget _pane({
    required bool surface,
    required Widget child,
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(kSubscriptionPaneRadius),
          border: surface
              ? null
              : Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kSubscriptionPaneRadius),
          child: child,
        ),
      ),
    );
  }

  Widget _listColumn(
    List<DelegateSubscriptionRequest> loaded, {
    required bool loading,
    required String? error,
  }) {
    final pending = loaded
        .where((r) => r.status == SubscriptionRequestStatus.pending)
        .length;
    final approved = loaded
        .where((r) => r.status == SubscriptionRequestStatus.approved)
        .length;
    final rejected = loaded
        .where((r) => r.status == SubscriptionRequestStatus.rejected)
        .length;
    final filtered = loaded.where((r) {
      final statusOk = _statusFilter == null || r.status == _statusFilter;
      return statusOk && _matches(r);
    }).toList();
    _displayed = filtered;

    final pendingEmpty =
        !loading &&
        error == null &&
        _query.isEmpty &&
        _statusFilter == SubscriptionRequestStatus.pending &&
        pending == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _searchBar(),
              const SizedBox(height: 12),
              _filterRow(
                pending: pending,
                approved: approved,
                rejected: rejected,
                total: loaded.length,
              ),
              const SizedBox(height: 4),
              _sortRow(),
              // Company-level «طلب ضم سلسلة» requests (no delegate on them).
              if (widget.requestsOverride == null)
                CompanyChainRequestsPanel(reviewer: widget.currentAdmin),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const _SkeletonList()
              : error != null
              ? _loadError(error)
              : pendingEmpty
              ? _pendingEmpty()
              : filtered.isEmpty
              ? _noMatches()
              : _list(filtered),
        ),
      ],
    );
  }

  Widget _searchBar() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: cs.onSurface,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: cs.surfaceContainerHigh,
          hintText: 'ابحث بالاسم أو الموبايل أو الرقم القومي',
          hintStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'مسح',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                  icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _filterRow({
    required int pending,
    required int approved,
    required int rejected,
    required int total,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _filterChip('الكل', total, null),
        _filterChip('قيد المراجعة', pending, SubscriptionRequestStatus.pending),
        _filterChip('المعتمدة', approved, SubscriptionRequestStatus.approved),
        _filterChip('المرفوضة', rejected, SubscriptionRequestStatus.rejected),
      ],
    );
  }

  Widget _filterChip(
    String label,
    int count,
    SubscriptionRequestStatus? status,
  ) {
    final cs = Theme.of(context).colorScheme;
    final selected = _statusFilter == status;
    final base = Theme.of(context).textTheme.labelLarge;
    return FilterChip(
      label: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: label),
            TextSpan(
              text: ' $count',
              style: subscriptionNumberStyle(base),
            ),
          ],
        ),
      ),
      selected: selected,
      showCheckmark: true,
      checkmarkColor: cs.onSecondaryContainer,
      selectedColor: cs.secondaryContainer,
      backgroundColor: cs.surfaceContainerHigh,
      side: BorderSide(color: cs.outlineVariant),
      labelStyle: base?.copyWith(
        color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => setState(() => _statusFilter = status),
    );
  }

  Widget _sortRow() {
    final cs = Theme.of(context).colorScheme;
    final embedded = context.findAncestorWidgetOfExactType<IndexedStack>() != null;
    final showBack = !embedded && Navigator.canPop(context);
    return Row(
      children: [
        if (showBack)
          IconButton(
            tooltip: 'رجوع',
            onPressed: () => Navigator.maybePop(context),
            icon: const BackButtonIcon(),
          ),
        PopupMenuButton<bool>(
          tooltip: 'ترتيب الطلبات',
          initialValue: _newestFirst,
          color: cs.surfaceContainerHigh,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          onSelected: (value) => setState(() => _newestFirst = value),
          itemBuilder: (context) => [
            _sortItem(true, 'الأحدث فوق'),
            _sortItem(false, 'الأقدم فوق'),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _newestFirst ? 'الأحدث فوق' : 'الأقدم فوق',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (widget.currentAdmin.role == UserRole.superAdmin)
          IconButton(
            tooltip: 'التقرير المالي والجرد',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SuperAdminSubscriptionFinancialReportScreen(
                    adminDelegate: widget.currentAdmin,
                  ),
                ),
              );
            },
            icon: Icon(Icons.analytics_rounded, color: cs.onSurfaceVariant),
          ),
      ],
    );
  }

  PopupMenuItem<bool> _sortItem(bool newest, String label) {
    final cs = Theme.of(context).colorScheme;
    final selected = _newestFirst == newest;
    return PopupMenuItem<bool>(
      value: newest,
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (selected)
            Icon(Icons.check_rounded, color: cs.primary, size: 18),
        ],
      ),
    );
  }

  Widget _list(List<DelegateSubscriptionRequest> items) {
    final hideStatus = _statusFilter == SubscriptionRequestStatus.pending;
    return Focus(
      focusNode: _listFocus,
      onKeyEvent: _onListKey,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final request = items[index];
          return _RequestRow(
            request: request,
            selected: request.id == _selectedId,
            focused: _listFocused && request.id == _selectedId,
            showStatusChip: !hideStatus,
            onTap: () => _select(request, open: _compact),
          );
        },
      ),
    );
  }

  Widget _pendingEmpty({bool action = true}) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'مفيش طلبات مستنية مراجعتك',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (action) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => setState(() => _statusFilter = null),
                child: const Text('عرض الكل'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noMatches() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        'لا توجد نتائج مطابقة',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _loadError(String message) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(
              'تعذر تحميل الطلبات',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: cs.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: widget.requestsOverride == null
                  ? _retryStream
                  : () {},
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  DelegateSubscriptionRequest? _find(
    List<DelegateSubscriptionRequest> loaded,
    String? id,
  ) {
    if (id == null) return null;
    for (final request in loaded) {
      if (request.id == id) return request;
    }
    return null;
  }

  Widget _detailOrPlaceholder(
    List<DelegateSubscriptionRequest> loaded,
    DelegateSubscriptionRequest? selected, {
    required bool pinnedBar,
  }) {
    final pendingEmpty =
        _query.isEmpty &&
        _statusFilter == SubscriptionRequestStatus.pending &&
        loaded
            .where((r) => r.status == SubscriptionRequestStatus.pending)
            .isEmpty;
    if (pendingEmpty) {
      return const SizedBox.expand();
    }
    if (selected == null) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Text(
          'اختار طلب من القائمة',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    return _DetailBody(
      key: ValueKey(selected.id),
      request: selected,
      admin: widget.currentAdmin,
      deciding: _deciding,
      pinnedBar: pinnedBar,
      onApprove: () => _decide(selected, () => widget.onApprove(selected)),
      onReject: () => _decide(selected, () => widget.onReject(selected)),
    );
  }

  Widget _compactDetail(DelegateSubscriptionRequest request) {
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                tooltip: 'رجوع',
                onPressed: () => setState(() => _detailOpen = false),
                icon: const BackButtonIcon(),
              ),
              Expanded(
                child: Text(
                  'تفاصيل الطلب',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _DetailBody(
            key: ValueKey('compact-${request.id}'),
            request: request,
            admin: widget.currentAdmin,
            deciding: _deciding,
            pinnedBar: false,
            onApprove: () {},
            onReject: () {},
          ),
        ),
      ],
    );
  }
}

class _RequestRow extends StatelessWidget {
  final DelegateSubscriptionRequest request;
  final bool selected;
  final bool focused;
  final bool showStatusChip;
  final VoidCallback onTap;

  const _RequestRow({
    required this.request,
    required this.selected,
    required this.focused,
    required this.showStatusChip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final pending = request.status == SubscriptionRequestStatus.pending;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: focused
                  ? Border.all(color: cs.primary, width: 2)
                  : null,
            ),
            child: Row(
              children: [
                _Avatar(request: request, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        request.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${subscriptionRequestTypeLabel(request)} · ${subscriptionChainLabel(request)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: selected
                              ? cs.onSecondaryContainer
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subscriptionRelativeTime(request.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (pending)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                if (showStatusChip) _StatusChip(request: request),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final DelegateSubscriptionRequest request;

  const _StatusChip({required this.request});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon, String label, double fill) =
        switch (request.status) {
          SubscriptionRequestStatus.pending => (
            cs.tertiaryContainer,
            cs.onTertiaryContainer,
            Symbols.schedule_rounded,
            'قيد المراجعة',
            0.0,
          ),
          SubscriptionRequestStatus.approved => (
            cs.primaryContainer,
            cs.onPrimaryContainer,
            Symbols.check_circle_rounded,
            'معتمد',
            1.0,
          ),
          SubscriptionRequestStatus.rejected => (
            cs.surfaceContainerHighest,
            cs.onSurfaceVariant,
            Icons.block_rounded,
            'مرفوض',
            0.0,
          ),
          SubscriptionRequestStatus.cancelled => (
            cs.surfaceContainerHighest,
            cs.onSurfaceVariant,
            Icons.block_rounded,
            'ملغى',
            0.0,
          ),
          SubscriptionRequestStatus.expired => (
            cs.surfaceContainerHighest,
            cs.onSurfaceVariant,
            Symbols.schedule_rounded,
            'منتهي',
            0.0,
          ),
        };
    final outlined = request.status == SubscriptionRequestStatus.cancelled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: outlined ? Border.all(color: cs.outline) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg, fill: fill),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final DelegateSubscriptionRequest request;
  final double radius;

  const _Avatar({required this.request, required this.radius});

  @override
  Widget build(BuildContext context) {
    final url = request.profileImageUrl.trim();
    return AppAvatar(
      imageUrl: url.isEmpty ? null : url,
      fallbackText: _initials(request.fullName),
      radius: radius,
      verbatimFallback: true,
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '؟';
    String glyph(String word) {
      final iterator = word.runes.iterator;
      if (!iterator.moveNext()) return '';
      return String.fromCharCode(iterator.current);
    }

    if (parts.length == 1) return glyph(parts.first);
    return '${glyph(parts[0])}${glyph(parts[1])}';
  }
}

class _DetailBody extends StatelessWidget {
  final DelegateSubscriptionRequest request;
  final Delegate admin;
  final bool deciding;
  final bool pinnedBar;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _DetailBody({
    super.key,
    required this.request,
    required this.admin,
    required this.deciding,
    required this.pinnedBar,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final bar = pinnedBar
        ? decisionBarFor(
            request,
            role: admin.role,
            deciding: deciding,
            compact: false,
            onApprove: onApprove,
            onReject: onReject,
          )
        : null;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _DetailContent(
                  request: request,
                  admin: admin,
                  showInlineNote: !pinnedBar,
                ),
              ),
            ),
          ),
        ),
        ?bar,
      ],
    );
  }
}

class _DetailContent extends StatelessWidget {
  final DelegateSubscriptionRequest request;
  final Delegate admin;
  final bool showInlineNote;

  const _DetailContent({
    required this.request,
    required this.admin,
    required this.showInlineNote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final outcome = subscriptionOutcomeParts(request);
    final showOutcome =
        request.status == SubscriptionRequestStatus.approved ||
        request.status == SubscriptionRequestStatus.rejected;
    final inlineNote = showInlineNote ? _noteFor(request, admin.role) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(request: request, radius: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.fullName,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  _StatusChip(request: request),
                  const SizedBox(height: 8),
                  Text(
                    '${subscriptionRequestTypeLabel(request)} · ${subscriptionRelativeTime(request.createdAt)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (showOutcome && outcome != null) ...[
          const SizedBox(height: 16),
          _OutcomeCard(request: request, parts: outcome),
        ],
        if (request.isAddOrganizationRequest) ...[
          const SizedBox(height: 24),
          _sectionTitle(context, 'طلب ربط بسلسلة إضافية'),
          const SizedBox(height: 8),
          _chainLink(context),
        ],
        if (request.isNationalIdUpdateRequest) ...[
          const SizedBox(height: 24),
          _sectionTitle(context, 'تعديل الرقم القومي'),
          const SizedBox(height: 8),
          _ltrValue(
            context,
            '${request.nationalId} → ${request.proposedNationalId}',
          ),
        ],
        if (request.isDeleteRequest &&
            request.status == SubscriptionRequestStatus.pending &&
            (request.rejectionReason?.trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: 24),
          _sectionTitle(context, 'سبب طلب الحذف'),
          const SizedBox(height: 8),
          Text(request.rejectionReason!.trim()),
        ],
        if (request.isRenewalRequest) ...[
          const SizedBox(height: 24),
          Text(
            request.items.isEmpty
                ? 'طلب تجديد اشتراك'
                : 'طلب تجديد اشتراك لعدد ${request.items.length}',
            style: theme.textTheme.bodyLarge,
          ),
        ],
        const SizedBox(height: 24),
        _sectionTitle(context, 'بيانات المندوب'),
        const SizedBox(height: 12),
        _facts(context),
        const SizedBox(height: 24),
        _sectionTitle(context, 'المستندات'),
        const SizedBox(height: 12),
        _documents(context),
        if (canSupervisorEditSubscriptionRequest(
          request,
          role: admin.role,
          callerCompanyUID: admin.companyUID,
        )) ...[
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditDelegateProfileScreen(
                      supervisor: admin,
                      request: request,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_rounded),
              label: const Text('تعديل بيانات الطلب'),
            ),
          ),
        ],
        if (inlineNote != null) ...[
          const SizedBox(height: 20),
          Text(
            inlineNote,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _chainLink(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final from = request.currentOrganizationName?.trim().isNotEmpty == true
        ? request.currentOrganizationName!.trim()
        : 'السلسلة الحالية';
    final to = request.organizationName.trim().isNotEmpty
        ? request.organizationName.trim()
        : 'السلسلة الجديدة';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              'من',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            _chainChip(context, from, target: false),
            Icon(
              // arrow_forward mirrors once with the text direction. In RTL
              // that lands on a left-pointing arrow, from the source chip
              // toward the target. arrow_back would be mirrored a second time.
              Icons.arrow_forward_rounded,
              key: const ValueKey('chain_link_arrow'),
              color: cs.onSurface,
            ),
            Text(
              'إلى',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            _chainChip(context, to, target: true),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'طلب إضافة سلسلة للمندوب. الاشتراك الحالي يغطي السلاسل بدون رسوم إضافية.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _chainChip(BuildContext context, String label, {required bool target}) {
    final cs = Theme.of(context).colorScheme;
    final bg = target ? cs.secondaryContainer : cs.surfaceContainerHigh;
    final fg = target ? cs.onSecondaryContainer : cs.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _facts(BuildContext context) {
    final requester = request.supervisorName.trim().isEmpty
        ? 'غير مسجّل'
        : request.supervisorName.trim();
    final fields = <Widget>[
      _fact(
        context,
        icon: Icons.phone_rounded,
        label: 'رقم الموبايل',
        value: request.phoneNumber,
        ltr: true,
        copy: true,
      ),
      _fact(
        context,
        icon: Icons.badge_rounded,
        label: 'الرقم القومي',
        value: request.nationalId,
        ltr: true,
        copy: true,
      ),
      _fact(
        context,
        icon: Icons.apartment_rounded,
        label: 'الشركة',
        value: request.companyName.trim().isEmpty ? '—' : request.companyName,
      ),
      _fact(
        context,
        icon: Icons.person_rounded,
        label: 'قدّم الطلب',
        value: requester,
      ),
      _fact(
        context,
        icon: Symbols.schedule_rounded,
        label: 'وقت الطلب',
        value: subscriptionDateTimeLabel(request.createdAt),
        ltr: true,
      ),
      _fact(
        context,
        icon: Icons.payments_rounded,
        label: 'التكلفة',
        value: subscriptionCostLabel(request),
        ltr: true,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final two = constraints.maxWidth >= 520;
        if (!two) {
          return Column(
            children: [
              for (final field in fields) ...[
                field,
                const SizedBox(height: 12),
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < fields.length; i += 2) {
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: fields[i]),
                const SizedBox(width: 16),
                Expanded(
                  child: i + 1 < fields.length
                      ? fields[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
          rows.add(const SizedBox(height: 12));
        }
        return Column(children: rows);
      },
    );
  }

  Widget _fact(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool ltr = false,
    bool copy = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shown = value.trim().isEmpty ? '—' : value.trim();
    final compact = MediaQuery.sizeOf(context).width < kSubscriptionTwoPaneMinWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 26),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(child: _valueText(context, shown, ltr)),
              if (copy && shown != '—')
                _CopyButton(text: shown, alwaysVisible: compact),
            ],
          ),
        ),
      ],
    );
  }

  Widget _valueText(BuildContext context, String value, bool ltr) {
    final style = Theme.of(context).textTheme.bodyLarge;
    if (!ltr) return Text(value, style: style);
    return _ltrValue(context, value, style: style);
  }

  Widget _ltrValue(BuildContext context, String value, {TextStyle? style}) {
    return subscriptionLtrText(
      value,
      style ?? Theme.of(context).textTheme.bodyLarge,
    );
  }

  Widget _documents(BuildContext context) {
    final front = request.nationalIdFrontUrl.trim();
    final back = request.nationalIdBackUrl.trim();
    final photo = request.profileImageUrl.trim();
    final hasId = front.isNotEmpty || back.isNotEmpty;
    if (!hasId && photo.isEmpty) {
      return Text(
        'لا توجد مستندات مرفقة',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasId)
          _documentButton(
            context,
            label: 'عرض صورة البطاقة',
            icon: Icons.badge_rounded,
            onPressed: () => _openId(context, front, back),
          ),
        if (photo.isNotEmpty)
          _documentButton(
            context,
            label: 'صور المندوب',
            icon: Icons.photo_library_rounded,
            onPressed: () => _showImage(
              context,
              'الصورة الشخصية - ${request.fullName}',
              photo,
            ),
          )
        else
          Text(
            'مفيش صور',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  /// Tonal document action. The label is a plain [Text] in the row, not the
  /// icon-button's Flexible child, so a narrow detail pane cannot squeeze it
  /// to nothing. Colors snap with the theme: a lerped fill against a previous
  /// label color is what made this pill look blank at 1024.
  Widget _documentButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    final fg = cs.onSecondaryContainer;
    final text = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: fg,
      fontWeight: FontWeight.w700,
    );
    return FilledButton(
      style: ButtonStyle(
        animationDuration: Duration.zero,
        backgroundColor: WidgetStatePropertyAll(cs.secondaryContainer),
        foregroundColor: WidgetStatePropertyAll(fg),
        iconColor: WidgetStatePropertyAll(fg),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStatePropertyAll(text),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Text(label, style: text),
        ],
      ),
    );
  }

  Future<void> _openId(BuildContext context, String front, String back) async {
    if (front.isNotEmpty && back.isEmpty) {
      _showImage(context, 'بطاقة الرقم القومي (الوجه) - ${request.fullName}', front);
      return;
    }
    if (back.isNotEmpty && front.isEmpty) {
      _showImage(context, 'بطاقة الرقم القومي (الظهر) - ${request.fullName}', back);
      return;
    }
    final side = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('صورة البطاقة'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'front'),
            child: const Text('وجه البطاقة'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'back'),
            child: const Text('ظهر البطاقة'),
          ),
        ],
      ),
    );
    if (!context.mounted || side == null) return;
    if (side == 'front') {
      _showImage(context, 'بطاقة الرقم القومي (الوجه) - ${request.fullName}', front);
    } else {
      _showImage(context, 'بطاقة الرقم القومي (الظهر) - ${request.fullName}', back);
    }
  }

  void _showImage(BuildContext context, String title, String url) {
    final wide = MediaQuery.sizeOf(context).width > 768;
    if (!wide) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.8,
            child: _ImageSheet(title: title, url: url),
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _ImageSheet(title: title, url: url),
        ),
      ),
    );
  }
}

class _ImageSheet extends StatefulWidget {
  final String title;
  final String url;

  const _ImageSheet({required this.title, required this.url});

  @override
  State<_ImageSheet> createState() => _ImageSheetState();
}

class _ImageSheetState extends State<_ImageSheet> {
  int _attempt = 0;

  Future<void> _retry() async {
    final url = widget.url.trim();
    if (url.isNotEmpty) {
      await NetworkImage(url).evict();
    }
    if (!mounted) return;
    setState(() => _attempt++);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 38,
          height: 4.5,
          decoration: BoxDecoration(
            color: cs.outlineVariant.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InteractiveViewer(
              child: _photo(cs),
            ),
          ),
        ),
      ],
    );
  }

  // Raw Storage URL. ImageUrlHelper would send the bytes through wsrv.nl;
  // a national ID or this profile photo must not go to a third party.
  // CanvasKit paints the image once the bucket returns CORS headers.
  Widget _photo(ColorScheme cs) {
    final url = widget.url.trim();
    if (url.isEmpty) return _failed(cs);
    return Image.network(
      url,
      key: ValueKey(_attempt),
      height: 320,
      width: double.infinity,
      fit: BoxFit.contain,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _loading();
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _loading();
      },
      errorBuilder: (_, _, _) => _failed(cs),
    );
  }

  Widget _loading() {
    return const SizedBox(
      height: 180,
      width: double.infinity,
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _failed(ColorScheme cs) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 140),
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'فشل تحميل الصورة',
                style: TextStyle(color: cs.error),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _retry,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Null when this role or this request has no قرار to make.
Widget? decisionBarFor(
  DelegateSubscriptionRequest request, {
  required UserRole role,
  required bool deciding,
  required bool compact,
  required VoidCallback onApprove,
  required VoidCallback onReject,
}) {
  if (request.status != SubscriptionRequestStatus.pending) return null;
  if (!subscriptionRequestReviewerCanDecide(role)) return null;
  final showApprove =
      !request.isAwaitingPaymobPayment && !request.isRenewalRequest;
  const showReject = true;
  return _DecisionBar(
    showApprove: showApprove,
    showReject: showReject,
    deciding: deciding,
    compact: compact,
    helper: compact ? null : _noteFor(request, role),
    onApprove: onApprove,
    onReject: onReject,
  );
}

String? _noteFor(DelegateSubscriptionRequest request, UserRole role) {
  if (request.status != SubscriptionRequestStatus.pending) return null;
  if (request.isAwaitingPaymobPayment) {
    return 'بانتظار الدفع الإلكتروني. لا يمكن الاعتماد قبل تأكيد الدفع.';
  }
  if (request.isRenewalRequest) {
    return 'طلب التجديد يُعتمد تلقائياً بعد تأكيد الدفع الإلكتروني.';
  }
  if (!subscriptionRequestReviewerCanDecide(role)) {
    return 'الطلب قيد الانتظار وبانتظار المراجعة والاعتماد.';
  }
  return null;
}

class _DecisionBar extends StatelessWidget {
  final bool showApprove;
  final bool showReject;
  final bool deciding;
  final bool compact;
  final String? helper;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _DecisionBar({
    required this.showApprove,
    required this.showReject,
    required this.deciding,
    required this.compact,
    required this.helper,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final size = compact ? const Size(48, 56) : const Size(120, 48);
    final label = theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);
    // animationDuration zero: the fill and the label read the same scheme.
    // The default 200ms material animation was leaving «اعتماد» on the
    // previous onPrimary (dark #381E72 on light purple) and «رفض» on the
    // previous primary.
    final approve = FilledButton(
      style: ButtonStyle(
        animationDuration: Duration.zero,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return cs.onSurface.withValues(alpha: 0.12);
          }
          return cs.primary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return cs.onSurface.withValues(alpha: 0.38);
          }
          return cs.onPrimary;
        }),
        minimumSize: WidgetStatePropertyAll(size),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStatePropertyAll(label),
      ),
      onPressed: deciding ? null : onApprove,
      child: const Text('اعتماد'),
    );
    final reject = OutlinedButton(
      style: ButtonStyle(
        animationDuration: Duration.zero,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return cs.onSurface.withValues(alpha: 0.38);
          }
          return cs.primary;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          return BorderSide(
            color: states.contains(WidgetState.disabled)
                ? cs.outline.withValues(alpha: 0.38)
                : cs.outline,
          );
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return cs.primary.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return cs.primary.withValues(alpha: 0.08);
          }
          return null;
        }),
        minimumSize: WidgetStatePropertyAll(size),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: WidgetStatePropertyAll(label),
      ),
      onPressed: deciding ? null : onReject,
      child: const Text('رفض'),
    );
    final buttons = <Widget>[
      if (showReject) reject,
      if (showApprove && showReject) const SizedBox(width: 12),
      if (showApprove) approve,
    ];
    if (compact) {
      return Material(
        color: cs.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                if (showApprove)
                  Expanded(child: approve),
                if (showApprove && showReject) const SizedBox(width: 12),
                if (showReject) Expanded(child: reject),
              ],
            ),
          ),
        ),
      );
    }
    final note = helper;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: note == null
                ? const SizedBox.shrink()
                : Text(
                    note,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          ...buttons,
        ],
      ),
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  final DelegateSubscriptionRequest request;
  final ({String before, DateTime? at, String after}) parts;

  const _OutcomeCard({required this.request, required this.parts});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final approved = request.status == SubscriptionRequestStatus.approved;
    final bg = approved ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = approved ? cs.onPrimaryContainer : cs.onSurface;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: fg,
      fontWeight: FontWeight.w600,
    );
    final at = parts.at;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            approved ? Symbols.check_circle_rounded : Icons.block_rounded,
            size: 20,
            color: fg,
            fill: approved ? 1 : 0,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  TextSpan(text: at == null ? parts.before : '${parts.before} '),
                  if (at != null)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: subscriptionLtrText(
                        subscriptionDateTimeLabel(at),
                        style,
                      ),
                    ),
                  if (parts.after.isNotEmpty) TextSpan(text: parts.after),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String text;
  final bool alwaysVisible;

  const _CopyButton({required this.text, required this.alwaysVisible});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = widget.alwaysVisible || _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        width: 32,
        height: 32,
        child: shown
            ? IconButton(
                tooltip: 'نسخ',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.text));
                  if (!context.mounted) return;
                  AppSnackBar.showInfo(context, 'تم النسخ');
                },
                icon: Icon(
                  Icons.content_copy_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: 7,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
    );
  }
}
