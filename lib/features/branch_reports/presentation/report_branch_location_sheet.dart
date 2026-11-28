import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';

import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/branch_reports/data/branch_location_report_repository.dart';
import 'package:delegate_app/features/branch_reports/domain/branch_location_report.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Texts of the «الفرع مكانه غلط؟» flow (TAS-397). The button label is the
/// agreed one in USER-SCENARIOS/01-delegate-messages.md (3.1).
abstract final class BranchReportTexts {
  static const String action = 'الفرع مكانه غلط؟';
  static const String sheetTitle = 'الفرع مكانه غلط؟';
  static const String sheetIntro =
      'اختار الفرع اللي إنت واقف فيه دلوقتي. المشرف هيراجع البلاغ، '
      'ومكان الفرع مش هيتغير غير بعد ما يتراجع.';
  static const String nearest = 'الأقرب ليك';
  static const String noteLabel = 'ملاحظة (اختياري)';
  static const String noteHint = 'مثلاً: أنا واقف قدام باب الفرع';
  static const String send = 'ابعت البلاغ';
  static const String chooseBranch = 'اختار الفرع الأول';
  static const String sent = 'البلاغ اتبعت للمشرف';
  static const String mockedWarning =
      'موقعك جاي من برنامج تغيير مكان، والمشرف هيشوف ده.';
}

/// The «outside the branch» refusal: with [onReport] the snackbar carries
/// «الفرع مكانه غلط؟» (it then stays until used or closed, M3); without it,
/// the plain message as before. Both refusal paths of the attendance screen
/// (its own check and the repository / server) go through here.
void showGeofenceRefusalSnackBar(
  BuildContext context,
  String message, {
  VoidCallback? onReport,
}) {
  if (onReport == null) {
    AppSnackBar.showError(context, message);
    return;
  }
  showTashilSnackBar(
    context,
    message,
    actionLabel: BranchReportTexts.action,
    onAction: onReport,
  );
}

/// Where the delegate stood when attendance was refused.
class ReportPosition {
  const ReportPosition({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.isMocked = false,
  });

  factory ReportPosition.fromPosition(Position p) => ReportPosition(
    lat: p.latitude,
    lng: p.longitude,
    accuracy: p.accuracy,
    isMocked: p.isMocked,
  );

  final double lat;
  final double lng;
  final double? accuracy;
  final bool isMocked;
}

/// Branches in the order the sheet lists them: the suggestion first, then
/// by distance. Branches without a position stay (their position is what
/// may be wrong) and go last.
List<Branch> orderBranchesForReport(
  List<Branch> branches,
  ReportPosition at, {
  String? suggestedBranchId,
}) {
  double d(Branch b) => (b.latitude == 0 && b.longitude == 0)
      ? double.infinity
      : Geolocator.distanceBetween(at.lat, at.lng, b.latitude, b.longitude);
  final seen = <String>{};
  final unique = [
    for (final b in branches)
      if (b.id.isNotEmpty && seen.add(b.id)) b,
  ];
  unique.sort((a, b) {
    if (a.id == suggestedBranchId) return -1;
    if (b.id == suggestedBranchId) return 1;
    return d(a).compareTo(d(b));
  });
  return unique;
}

/// The report the delegate sends for [branch].
NewBranchLocationReport buildBranchReport({
  required Delegate delegate,
  required Branch branch,
  required ReportPosition at,
  String note = '',
}) {
  final hasPos = !(branch.latitude == 0 && branch.longitude == 0);
  return NewBranchLocationReport(
    delegateId: delegate.uid,
    delegateName: delegate.fullName,
    companyUID: delegate.companyUID,
    // The branch's chain, or the delegate's when the branch does not say.
    organizationUID: (branch.organizationUID ?? '').trim().isNotEmpty
        ? branch.organizationUID!.trim()
        : delegate.organizationUID,
    branchId: branch.id,
    branchName: BranchDisplayCache.instance.displayName(branch.branchName),
    branchLat: hasPos ? branch.latitude : null,
    branchLng: hasPos ? branch.longitude : null,
    branchRadius: branch.geofenceRadius,
    lat: at.lat,
    lng: at.lng,
    accuracy: at.accuracy,
    isMocked: at.isMocked,
    distanceMeters: hasPos
        ? Geolocator.distanceBetween(
            at.lat,
            at.lng,
            branch.latitude,
            branch.longitude,
          )
        : null,
    note: note,
  );
}

/// Opens the sheet. Returns true when a report was sent.
Future<bool> showReportBranchLocationSheet({
  required BuildContext context,
  required Delegate delegate,
  required List<Branch> branches,
  required ReportPosition at,
  String? suggestedBranchId,
  BranchLocationReportRepository? repository,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 1,
      snap: true,
      builder: (c, scroll) => ReportBranchLocationSheet(
        delegate: delegate,
        branches: branches,
        at: at,
        suggestedBranchId: suggestedBranchId,
        repository: repository,
        scrollController: scroll,
      ),
    ),
  );
  if (sent == true && context.mounted) {
    showTashilSnackBar(context, BranchReportTexts.sent);
  }
  return sent == true;
}

class ReportBranchLocationSheet extends StatefulWidget {
  const ReportBranchLocationSheet({
    super.key,
    required this.delegate,
    required this.branches,
    required this.at,
    this.suggestedBranchId,
    this.repository,
    this.scrollController,
  });

  final Delegate delegate;
  final List<Branch> branches;
  final ReportPosition at;

  /// The nearest branch by the stored positions. Only a suggestion: when
  /// the positions are wrong the branch the delegate stands in may be far
  /// from it (TAS-343), so the delegate picks.
  final String? suggestedBranchId;
  final BranchLocationReportRepository? repository;
  final ScrollController? scrollController;

  @override
  State<ReportBranchLocationSheet> createState() =>
      _ReportBranchLocationSheetState();
}

class _ReportBranchLocationSheetState extends State<ReportBranchLocationSheet> {
  late final List<Branch> _ordered = orderBranchesForReport(
    widget.branches,
    widget.at,
    suggestedBranchId: widget.suggestedBranchId,
  );
  final _note = TextEditingController();
  String? _chosen;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final id = _chosen;
    if (id == null) {
      setState(() => _error = BranchReportTexts.chooseBranch);
      return;
    }
    final branch = _ordered.firstWhere((b) => b.id == id);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await (widget.repository ?? BranchLocationReportRepository()).submit(
        buildBranchReport(
          delegate: widget.delegate,
          branch: branch,
          at: widget.at,
          note: _note.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on BranchReportException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.message;
        });
      }
    }
  }

  String _distanceLabel(Branch b) {
    if (b.latitude == 0 && b.longitude == 0) return '';
    final m = Geolocator.distanceBetween(
      widget.at.lat,
      widget.at.lng,
      b.latitude,
      b.longitude,
    );
    final text = m >= 1000
        ? '${(m / 1000).toStringAsFixed(1)} كم'
        : '${m.round()} متر';
    return 'على بُعد ${Bidi.ltr(text)} حسب السيستم';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.page,
        0,
        TashilSpacing.page,
        TashilSpacing.xl,
      ),
      children: [
        Text(BranchReportTexts.sheetTitle, style: text.titleLarge),
        const SizedBox(height: TashilSpacing.sm),
        Text(
          BranchReportTexts.sheetIntro,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (widget.at.isMocked) ...[
          const SizedBox(height: TashilSpacing.sm),
          Text(
            BranchReportTexts.mockedWarning,
            style: text.bodyMedium?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: TashilSpacing.md),
        RadioGroup<String>(
          groupValue: _chosen,
          onChanged: (v) => setState(() {
            _chosen = v;
            _error = null;
          }),
          child: Column(
            children: [
              for (final b in _ordered)
                RadioListTile<String>(
                  key: ValueKey('branch_report_option_${b.id}'),
                  value: b.id,
                  contentPadding: EdgeInsetsDirectional.zero,
                  title: Text(
                    BranchDisplayCache.instance.displayName(b.branchName),
                  ),
                  subtitle: Text(
                    [
                      if (b.id == widget.suggestedBranchId)
                        BranchReportTexts.nearest,
                      _distanceLabel(b),
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: TashilSpacing.md),
        TextField(
          controller: _note,
          maxLength: 500,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: BranchReportTexts.noteLabel,
            hintText: BranchReportTexts.noteHint,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: TashilSpacing.sm),
          Text(
            _error!,
            key: const ValueKey('branch_report_error'),
            style: text.bodyMedium?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: TashilSpacing.lg),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const ValueKey('branch_report_send'),
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(BranchReportTexts.send),
          ),
        ),
      ],
    );
  }
}
