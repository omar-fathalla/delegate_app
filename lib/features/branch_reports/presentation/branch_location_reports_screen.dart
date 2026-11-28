import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart' hide Bidi, TextDirection;
import 'package:material_ui/material_ui.dart';

import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/features/branch_reports/data/branch_location_report_repository.dart';
import 'package:delegate_app/features/branch_reports/domain/branch_location_report.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Texts of the reviewer screen (TAS-397).
abstract final class BranchReportsScreenTexts {
  static const String title = 'بلاغات أماكن الفروع';
  static const String subtitle = 'بلاغات المناديب إن مكان الفرع غلط';
  static const String forward = 'يتصحح';
  static const String reject = 'رفض';
  static const String fixed = 'اتصحح';
  static const String showMap = 'شوف على الخريطة';
  static const String emptySupervisor = 'مفيش بلاغات عن أماكن الفروع';
  static const String emptyAdmin = 'مفيش بلاغات محتاجة تصحيح';
  static const String emptyMessage =
      'لما مندوب يقول إن مكان فرع غلط، البلاغ هيظهر هنا.';
  static const String forwardTitle = 'تحوّل البلاغ للتصحيح؟';
  static const String forwardBody =
      'البلاغ هيروح لأدمن السلسلة علشان يعدّل مكان الفرع. مكان الفرع مش '
      'بيتغير لوحده.';
  static const String fixedTitle = 'الفرع اتصحح؟';
  static const String fixedBody =
      'عدّل مكان الفرع من شاشة الفروع الأول، وبعدين اقفل البلاغ. المندوب '
      'هياخد إشعار إن الفرع اتصحح.';
  static const String rejectTitle = 'ترفض البلاغ؟';
  static const String rejectReason = 'سبب الرفض';
  static const String rejectHint = 'مثلاً: مكان الفرع صح، وإنت كنت بعيد عنه';
  static const String rejectReasonRequired = 'اكتب سبب الرفض';
  static const String cancel = 'إلغاء';
  static const String failed = 'التعديل ماتحفظش. جرّب تاني.';
  static const String mocked = 'الموقع جاي من برنامج تغيير مكان';
  static const String branchOnSystem = 'مكان الفرع على السيستم';
  static const String reportedAt = 'مكان المندوب';
  static const String noPermission = 'الشاشة دي لمشرف الشركة وأدمن السلسلة بس.';
}

/// Reports a staff member works on: the company supervisor decides open
/// ones (forward / reject), the chain admin and global staff close
/// forwarded ones after editing the branch by hand. HR and delegates with
/// position supervisor see nothing here (user decision 28 Nov).
class BranchLocationReportsScreen extends StatelessWidget {
  const BranchLocationReportsScreen({
    super.key,
    required this.viewer,
    this.showAppBar = true,
    this.repository,
  });

  final Delegate viewer;
  final bool showAppBar;
  final BranchLocationReportRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? BranchLocationReportRepository();
    final kind = BranchReportViewer.of(viewer);
    final body = kind == BranchReportViewer.none
        ? const Center(
            child: EmptyState(
              icon: Icons.lock_outline_rounded,
              title: BranchReportsScreenTexts.noPermission,
            ),
          )
        : StreamBuilder<List<BranchLocationReport>>(
            stream: repo.watch(viewer),
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(
                  child: EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: BranchReportsScreenTexts.failed,
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = [...snap.data!]
                ..sort((a, b) {
                  int rank(BranchLocationReport r) =>
                      r.status == BranchReportStatus.open ||
                          r.status == BranchReportStatus.forwarded
                      ? 0
                      : 1;
                  return rank(a).compareTo(rank(b));
                });
              if (list.isEmpty) {
                return Center(
                  child: EmptyState(
                    icon: Icons.wrong_location_outlined,
                    title: kind == BranchReportViewer.companySupervisor
                        ? BranchReportsScreenTexts.emptySupervisor
                        : BranchReportsScreenTexts.emptyAdmin,
                    message: BranchReportsScreenTexts.emptyMessage,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(TashilSpacing.page),
                itemCount: list.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: TashilSpacing.md),
                itemBuilder: (context, i) => _ReportCard(
                  report: list[i],
                  viewer: viewer,
                  kind: kind,
                  repository: repo,
                ),
              );
            },
          );
    if (!showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text(BranchReportsScreenTexts.title)),
      body: body,
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.viewer,
    required this.kind,
    required this.repository,
  });

  final BranchLocationReport report;
  final Delegate viewer;
  final BranchReportViewer kind;
  final BranchLocationReportRepository repository;

  bool get _canDecide =>
      kind == BranchReportViewer.companySupervisor &&
      report.status == BranchReportStatus.open;

  bool get _canClose =>
      (kind == BranchReportViewer.chainAdmin ||
          kind == BranchReportViewer.globalStaff) &&
      report.status == BranchReportStatus.forwarded;

  static String _meters(double m) => m >= 1000
      ? Bidi.ltr('${(m / 1000).toStringAsFixed(1)} كم')
      : Bidi.ltr('${m.round()} متر');

  Future<void> _run(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      if (context.mounted) {
        showTashilSnackBar(context, BranchReportsScreenTexts.failed);
      }
    }
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body,
    String confirm,
  ) async {
    final ok = await showTashilDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(BranchReportsScreenTexts.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _reject(BuildContext context) async {
    final reason = await showTashilDialog<String>(
      context: context,
      builder: (c) => const _RejectDialog(),
    );
    if (reason == null || reason.trim().isEmpty || !context.mounted) return;
    await _run(context, () => repository.reject(report, viewer, reason));
  }

  void _openMap(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BranchReportMapPage(report: report),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final created = report.createdAt;
    final details = <String>[
      if (report.distanceMeters != null)
        'على بُعد ${_meters(report.distanceMeters!)} من مكانه على السيستم',
      if (report.accuracy != null) 'دقة الموقع ${_meters(report.accuracy!)}',
      if (created != null)
        Bidi.ltr(DateFormat('d/M/yyyy HH:mm').format(created.toLocal())),
    ];
    return Card.filled(
      key: ValueKey('branch_report_${report.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(report.branchName, style: text.titleMedium),
                ),
                const SizedBox(width: TashilSpacing.sm),
                Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: TashilSpacing.xs),
                Text(
                  report.status.label,
                  style: text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: TashilSpacing.xs),
            Text(report.delegateName, style: text.bodyMedium),
            if (details.isNotEmpty) ...[
              const SizedBox(height: TashilSpacing.xs),
              Text(
                details.join(' · '),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (report.isMocked) ...[
              const SizedBox(height: TashilSpacing.xs),
              Text(
                BranchReportsScreenTexts.mocked,
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            if (report.note.isNotEmpty) ...[
              const SizedBox(height: TashilSpacing.sm),
              Text('«${report.note}»', style: text.bodyMedium),
            ],
            if (report.status == BranchReportStatus.rejected &&
                report.rejectReason.isNotEmpty) ...[
              const SizedBox(height: TashilSpacing.sm),
              Text(
                'سبب الرفض: ${report.rejectReason}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: TashilSpacing.md),
            Wrap(
              spacing: TashilSpacing.sm,
              runSpacing: TashilSpacing.sm,
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _openMap(context),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text(BranchReportsScreenTexts.showMap),
                ),
                if (_canDecide || _canClose)
                  TextButton(
                    key: ValueKey('branch_report_reject_${report.id}'),
                    onPressed: () => _reject(context),
                    child: const Text(BranchReportsScreenTexts.reject),
                  ),
                if (_canDecide)
                  FilledButton.tonal(
                    key: ValueKey('branch_report_forward_${report.id}'),
                    onPressed: () async {
                      if (await _confirm(
                            context,
                            BranchReportsScreenTexts.forwardTitle,
                            BranchReportsScreenTexts.forwardBody,
                            BranchReportsScreenTexts.forward,
                          ) &&
                          context.mounted) {
                        await _run(
                          context,
                          () => repository.forward(report.id, viewer),
                        );
                      }
                    },
                    child: const Text(BranchReportsScreenTexts.forward),
                  ),
                if (_canClose)
                  FilledButton.tonal(
                    key: ValueKey('branch_report_fixed_${report.id}'),
                    onPressed: () async {
                      if (await _confirm(
                            context,
                            BranchReportsScreenTexts.fixedTitle,
                            BranchReportsScreenTexts.fixedBody,
                            BranchReportsScreenTexts.fixed,
                          ) &&
                          context.mounted) {
                        await _run(
                          context,
                          () => repository.markFixed(report.id, viewer),
                        );
                      }
                    },
                    child: const Text(BranchReportsScreenTexts.fixed),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(BranchReportsScreenTexts.rejectTitle),
      content: TextField(
        key: const ValueKey('branch_report_reject_reason'),
        controller: _c,
        maxLength: 500,
        minLines: 1,
        maxLines: 3,
        autofocus: true,
        decoration: InputDecoration(
          labelText: BranchReportsScreenTexts.rejectReason,
          hintText: BranchReportsScreenTexts.rejectHint,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(BranchReportsScreenTexts.cancel),
        ),
        TextButton(
          key: const ValueKey('branch_report_reject_confirm'),
          onPressed: () {
            if (_c.text.trim().isEmpty) {
              setState(
                () => _error = BranchReportsScreenTexts.rejectReasonRequired,
              );
              return;
            }
            Navigator.pop(context, _c.text.trim());
          },
          child: const Text(BranchReportsScreenTexts.reject),
        ),
      ],
    );
  }
}

/// The branch's position on the system and where the delegate stood.
class BranchReportMapPage extends StatelessWidget {
  const BranchReportMapPage({super.key, required this.report});

  final BranchLocationReport report;

  @override
  Widget build(BuildContext context) {
    final reported = LatLng(report.lat, report.lng);
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('reported'),
        position: reported,
        infoWindow: InfoWindow(
          title: BranchReportsScreenTexts.reportedAt,
          snippet: report.delegateName,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      if (report.hasBranchPosition)
        Marker(
          markerId: const MarkerId('branch'),
          position: LatLng(report.branchLat!, report.branchLng!),
          infoWindow: InfoWindow(
            title: BranchReportsScreenTexts.branchOnSystem,
            snippet: report.branchName,
          ),
        ),
    };
    final circles = <Circle>{
      if (report.hasBranchPosition && report.branchRadius != null)
        Circle(
          circleId: const CircleId('fence'),
          center: LatLng(report.branchLat!, report.branchLng!),
          radius: report.branchRadius!,
          strokeWidth: 2,
          strokeColor: Theme.of(context).colorScheme.primary,
          fillColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.12),
        ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(report.branchName)),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: reported, zoom: 15),
        markers: markers,
        circles: circles,
        myLocationButtonEnabled: false,
        onMapCreated: (c) {
          if (!report.hasBranchPosition) return;
          final b = LatLng(report.branchLat!, report.branchLng!);
          final bounds = LatLngBounds(
            southwest: LatLng(
              b.latitude < reported.latitude ? b.latitude : reported.latitude,
              b.longitude < reported.longitude
                  ? b.longitude
                  : reported.longitude,
            ),
            northeast: LatLng(
              b.latitude > reported.latitude ? b.latitude : reported.latitude,
              b.longitude > reported.longitude
                  ? b.longitude
                  : reported.longitude,
            ),
          );
          Future<void>.delayed(const Duration(milliseconds: 300), () {
            c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
          });
        },
      ),
    );
  }
}
