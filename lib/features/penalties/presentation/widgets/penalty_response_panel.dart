import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

/// TAS-365: the dispute flow on a penalty card.
///
/// * The delegate (its own penalty): «اطلعت عليه» on ISSUED, «اعتراض» on
///   ISSUED / ACKNOWLEDGED within [PenaltyEntity.disputeWindowDays] days,
///   once; then the dispute's state and the decision (messages 8.2-8.4 in
///   USER-SCENARIOS/01-delegate-messages.md).
/// * A super admin or chain admin (user decision 2026-11-27) on a DISPUTED
///   penalty: the delegate's reason and «الجزاء يفضل» / «إلغاء الجزاء», each
///   with a required reason.
///
/// Everything goes through [RespondToPenaltyEvent] (respondToPenalty
/// callable); the server checks the same rules again.
class PenaltyResponsePanel extends StatelessWidget {
  final PenaltyEntity penalty;
  final Delegate? currentDelegate;

  /// Test seam for "now".
  final DateTime Function() now;

  const PenaltyResponsePanel({
    super.key,
    required this.penalty,
    required this.currentDelegate,
    this.now = DateTime.now,
  });

  static bool isDecider(Delegate? d) =>
      d != null &&
      (d.role == UserRole.superAdmin || d.role == UserRole.organizationAdmin);

  static bool isPenaltyDelegate(Delegate? d) =>
      d != null && d.role == UserRole.delegate;

  /// Whether the panel has anything to show for this person and penalty.
  static bool hasContent(PenaltyEntity p, Delegate? d) {
    if (isPenaltyDelegate(d)) {
      return p.status == PenaltyStatus.issued ||
          p.status == PenaltyStatus.acknowledged ||
          p.status == PenaltyStatus.disputed ||
          (p.disputeResolution ?? '').isNotEmpty;
    }
    if (isDecider(d)) {
      return p.status == PenaltyStatus.disputed ||
          (p.disputeResolution ?? '').isNotEmpty;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!hasContent(penalty, currentDelegate)) return const SizedBox.shrink();
    final children = <Widget>[];
    final note = _statusNote();
    if (note != null) children.add(_Note(text: note));
    if (isPenaltyDelegate(currentDelegate)) {
      children.addAll(_delegateActions(context));
    } else if (isDecider(currentDelegate) &&
        penalty.status == PenaltyStatus.disputed) {
      children.add(_deciderActions(context));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: TashilSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(height: TashilSpacing.sm),
            c,
          ],
        ],
      ),
    );
  }

  String? _statusNote() {
    final reason = penalty.disputeReason ?? '';
    final decisionReason = penalty.disputeResolutionReason ?? '';
    final delegateView = isPenaltyDelegate(currentDelegate);
    if (penalty.status == PenaltyStatus.disputed) {
      return delegateView
          ? 'اعترضت على الجزاء ده: $reason. مستنيين رد الإدارة، ومش هيتخصم لحد ما ترد.'
          : 'المندوب اعترض على الجزاء: $reason';
    }
    switch (penalty.disputeResolution) {
      case 'upheld':
        final month = penalty.deductionMonth;
        final monthText = month == null ? '' : ' (${Bidi.ltr(month)})';
        return delegateView
            ? 'اعتراضك اترفض، السبب: $decisionReason. هيتخصم في مرتب شهر القرار$monthText.'
            : 'الاعتراض اترفض: $decisionReason. هيتخصم في شهر القرار$monthText.';
      case 'cancelled':
        return delegateView
            ? 'اعتراضك اتقبل والجزاء اتلغى. السبب: $decisionReason'
            : 'الاعتراض اتقبل والجزاء اتلغى: $decisionReason';
    }
    return null;
  }

  List<Widget> _delegateActions(BuildContext context) {
    final at = now();
    final canAck = penalty.status == PenaltyStatus.issued;
    final canDispute = penalty.canDisputeAt(at);
    if (!canAck && !canDispute) return const [];
    final until = penalty.disputeWindowStart
        .add(const Duration(days: PenaltyEntity.disputeWindowDays));
    return [
      if (canDispute)
        Text(
          'لو شايف إن الجزاء غلط تقدر تعترض لحد ${Bidi.ltr(DateFormat('yyyy/MM/dd HH:mm').format(until))}.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      Wrap(
        spacing: TashilSpacing.sm,
        runSpacing: TashilSpacing.sm,
        children: [
          if (canAck)
            FilledButton.tonalIcon(
              key: const ValueKey('penalty-acknowledge'),
              onPressed: () => context.read<PenaltyBloc>().add(
                    RespondToPenaltyEvent(
                      penaltyId: penalty.penaltyId,
                      action: PenaltyResponseAction.acknowledge,
                    ),
                  ),
              icon: const Icon(Icons.done_rounded),
              label: const Text('اطلعت عليه'),
            ),
          if (canDispute)
            OutlinedButton.icon(
              key: const ValueKey('penalty-dispute'),
              onPressed: () => _askReason(
                context,
                title: 'اعتراض على الجزاء',
                hint: 'اكتب ليه شايف إن الجزاء غلط',
                confirm: 'ابعت الاعتراض',
                action: PenaltyResponseAction.dispute,
              ),
              icon: const Icon(Icons.report_outlined),
              label: const Text('اعتراض'),
            ),
        ],
      ),
    ];
  }

  Widget _deciderActions(BuildContext context) {
    return Wrap(
      spacing: TashilSpacing.sm,
      runSpacing: TashilSpacing.sm,
      children: [
        FilledButton.tonalIcon(
          key: const ValueKey('penalty-uphold'),
          onPressed: () => _askReason(
            context,
            title: 'الجزاء يفضل',
            hint: 'سبب رفض الاعتراض (هيوصل للمندوب)',
            confirm: 'رفض الاعتراض',
            action: PenaltyResponseAction.upholdDispute,
          ),
          icon: const Icon(Icons.gavel_rounded),
          label: const Text('الجزاء يفضل'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('penalty-cancel'),
          onPressed: () => _askReason(
            context,
            title: 'إلغاء الجزاء',
            hint: 'سبب قبول الاعتراض (هيوصل للمندوب)',
            confirm: 'إلغاء الجزاء',
            action: PenaltyResponseAction.cancelPenalty,
          ),
          icon: const Icon(Icons.undo_rounded),
          label: const Text('إلغاء الجزاء'),
        ),
      ],
    );
  }

  Future<void> _askReason(
    BuildContext context, {
    required String title,
    required String hint,
    required String confirm,
    required PenaltyResponseAction action,
  }) async {
    final reason = await showTashilDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title, hint: hint, confirm: confirm),
    );
    if (reason == null || !context.mounted) return;
    context.read<PenaltyBloc>().add(
          RespondToPenaltyEvent(
            penaltyId: penalty.penaltyId,
            action: action,
            reason: reason,
          ),
        );
  }
}

class _Note extends StatelessWidget {
  final String text;

  const _Note({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: TashilSpacing.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

/// Required reason (3 to 500 characters); confirm stays disabled until then.
class _ReasonDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String confirm;

  const _ReasonDialog({
    required this.title,
    required this.hint,
    required this.confirm,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _ok => _controller.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('penalty-reason-field'),
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        maxLength: 500,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('رجوع'),
        ),
        TextButton(
          key: const ValueKey('penalty-reason-confirm'),
          onPressed:
              _ok ? () => Navigator.pop(context, _controller.text.trim()) : null,
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
