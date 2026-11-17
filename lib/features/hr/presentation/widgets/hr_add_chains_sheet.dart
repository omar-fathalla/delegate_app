import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/admin/data/chain_duplicate_lookup.dart';
import 'package:delegate_app/features/admin/data/link_delegate_chains.dart';
import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

/// Suspended («متوقف») delegates can't get chains from the HR web
/// «مناديب الشركة» page (Mohamed, 17 Nov 2026): the button stays disabled.
const bool kHrAllowAddChainsForSuspended = false;

const String kHrAddChainsSuspendedTooltip =
    'المندوب متوقف، لا يمكن إضافة سلاسل له';

/// HR web «إضافة سلاسل» side sheet (MD3 Model 3). Same data and request as
/// the mobile «ربط بسلاسل إضافية» sheet (see link_delegate_chains.dart):
/// chain search, FilterChip bubbles, a counter and a sticky «إرسال الطلب».
/// About 420 wide on the end side; full screen below 840.
class HrAddChainsSheet extends StatefulWidget {
  const HrAddChainsSheet({
    super.key,
    required this.delegate,
    required this.supervisor,
    required this.fullScreen,
  });

  final Delegate delegate;
  final Delegate supervisor;
  final bool fullScreen;

  /// Below this width the sheet fills the screen.
  static const double fullScreenBelow = 840;
  static const double sheetWidth = 420;

  static const titleKey = Key('hr_add_chains_title');
  static const counterKey = Key('hr_add_chains_counter');
  static const submitKey = Key('hr_add_chains_submit');
  static const searchKey = Key('hr_add_chains_search');
  static const selectAllKey = Key('hr_add_chains_select_all');
  static Key newChainHintKey(String uid) => Key('hr_add_chains_new_$uid');
  static Key chipKey(String uid) => Key('hr_add_chains_chip_$uid');

  /// Tests and fake-data screenshots only.
  @visibleForTesting
  static FirebaseFirestore Function()? debugFirestore;

  /// Tests and fake-data screenshots only: replaces the request write.
  @visibleForTesting
  static Future<Either<Failure, String>> Function(List<ChainOption> selected)?
      debugSubmit;

  @visibleForTesting
  /// Test hook: replaces the linked/pending pre-check.
  @visibleForTesting
  static Future<DuplicateChainLookup> Function(Iterable<String> orgUids)? debugLookup;

  static void debugReset() {
    debugLookup = null;
    debugFirestore = null;
    debugSubmit = null;
  }

  /// Returns the names of the chains in the sent request, or null.
  static Future<List<String>?> show(
    BuildContext context, {
    required Delegate delegate,
    required Delegate supervisor,
  }) {
    final fullScreen = MediaQuery.sizeOf(context).width < fullScreenBelow;
    return showGeneralDialog<List<String>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => HrAddChainsSheet(
        delegate: delegate,
        supervisor: supervisor,
        fullScreen: fullScreen,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final rtl = Directionality.of(ctx) == TextDirection.rtl;
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: fullScreen
                ? const Offset(0, 0.05)
                : Offset(rtl ? -1 : 1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  @override
  State<HrAddChainsSheet> createState() => _HrAddChainsSheetState();
}

enum _ChainState { available, linked, pending }

class _HrAddChainsSheetState extends State<HrAddChainsSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _loading = true;
  String? _loadError;
  String? _submitError;
  String? _notice;
  bool _submitting = false;

  /// The pending/linked pre-check failed; chains are shown anyway.
  bool _checkUnavailable = false;

  List<LinkableChain> _chains = const [];
  final Map<String, _ChainState> _state = {};
  final Set<String> _selected = {};

  FirebaseFirestore get _firestore =>
      HrAddChainsSheet.debugFirestore?.call() ?? FirebaseFirestore.instance;

  String get _companyUID => linkRequestCompanyUID(
        delegate: widget.delegate,
        supervisor: widget.supervisor,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<DuplicateChainLookup> _lookup(Iterable<String> orgUids) =>
      HrAddChainsSheet.debugLookup?.call(orgUids) ??
      lookupLinkChainStates(
        firestore: _firestore,
        companyUID: _companyUID,
        delegateUid: widget.delegate.uid,
        nationalId: widget.delegate.nationalityID,
        phoneNumber: widget.delegate.phoneNumber,
        organizationUIDs: orgUids,
      );

  void _applyLookup(DuplicateChainLookup lookup) {
    for (final uid in lookup.delegateOrgUids) {
      if (_state.containsKey(uid)) _state[uid] = _ChainState.linked;
    }
    for (final uid in lookup.pendingOrgUids) {
      if (_state[uid] == _ChainState.available) {
        _state[uid] = _ChainState.pending;
      }
    }
    _selected.removeWhere((uid) => _state[uid] != _ChainState.available);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final chains = await fetchLinkableChains(
        firestore: _firestore,
        delegate: widget.delegate,
        supervisor: widget.supervisor,
        includeLinked: true,
      );
      _state
        ..clear()
        ..addAll({
          for (final c in chains)
            c.uid: c.alreadyLinked ? _ChainState.linked : _ChainState.available,
        });
      final candidates = [
        for (final c in chains)
          if (!c.alreadyLinked) c.uid,
      ];
      DuplicateChainLookup? lookup;
      try {
        lookup = await _lookup(candidates);
      } on DuplicateChainLookupException {
        // Graceful fallback: still show the chains. On send the request
        // flow re-checks each chain for the delegate's doc and refuses a
        // chain the delegate is already on.
        lookup = null;
      }
      if (!mounted) return;
      setState(() {
        _chains = chains;
        _checkUnavailable = lookup == null;
        if (lookup != null) _applyLookup(lookup);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = const DuplicateChainLookupException().message;
      });
    }
  }

  List<ChainOption> get _availableOptions => [
        for (final c in _chains)
          if (_state[c.uid] == _ChainState.available) c.option,
      ];

  ChainSelectionResult get _selection => partitionSelectedChains(
        all: _availableOptions,
        selectedUids: _selected,
      );

  Future<void> _submit() async {
    if (_submitting) return;
    if (_selected.isEmpty) {
      setState(() => _submitError = kLinkChainsRequiredMessage);
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
      _notice = null;
    });

    // Re-check linked / pending chains right before writing. If the check
    // itself can't run, the request flow still refuses chains the delegate
    // is already on (it reads the delegate's doc in each chain).
    late ChainSelectionResult selection;
    try {
      final lookup = await _lookup(_selection.keptUids);
      selection = partitionSelectedChains(
        all: _availableOptions,
        selectedUids: _selected,
        duplicateUids: lookup.duplicateOrgUids,
      );
      if (!mounted) return;
      if (lookup.duplicateOrgUids.isNotEmpty) {
        setState(() => _applyLookup(lookup));
      }
    } on DuplicateChainLookupException {
      if (!mounted) return;
      selection = _selection;
    }

    if (!selection.canSubmit) {
      setState(() {
        _submitting = false;
        _submitError = selection.warningAr ?? kLinkChainsRequiredMessage;
      });
      return;
    }
    if (selection.warningAr != null) {
      setState(() => _notice = selection.warningAr);
    }

    final submit = HrAddChainsSheet.debugSubmit;
    final result = submit != null
        ? await submit(selection.kept)
        : await submitLinkChainsRequest(
            repo: sl<DelegateSubscriptionRepository>(),
            delegate: widget.delegate,
            supervisor: widget.supervisor,
            selected: selection.kept,
          );
    if (!mounted) return;
    result.fold(
      (failure) => setState(() {
        _submitting = false;
        _submitError = failure.message;
      }),
      (_) => Navigator.of(context).pop(selection.keptNames),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = Material(
      color: cs.surfaceContainerLow,
      child: SafeArea(child: _buildBody(cs)),
    );
    if (widget.fullScreen) return body;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SizedBox(
        width: HrAddChainsSheet.sheetWidth,
        height: double.infinity,
        child: ClipRRect(
          borderRadius: const BorderRadiusDirectional.horizontal(
            start: Radius.circular(16),
          ).resolve(Directionality.of(context)),
          child: body,
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTitle(cs),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDelegateCard(cs),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_loadError != null)
                  _buildLoadError(cs)
                else
                  ..._buildChains(cs),
              ],
            ),
          ),
        ),
        _buildFooter(cs),
      ],
    );
  }

  Widget _buildTitle(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'إضافة سلاسل',
              key: HrAddChainsSheet.titleKey,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: 'إغلاق',
            iconSize: 24,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Symbols.close_rounded),
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildDelegateCard(ColorScheme cs) {
    final d = widget.delegate;
    final subtitle = d.city.trim();
    final active = d.status == DelegateStatus.active;
    final statusColor = active ? const Color(0xFF2E7D32) : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          AppAvatar(
            imageUrl: d.personalPhotoUrl,
            fallbackText: d.fullName,
            radius: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 7, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  active ? 'نشط' : 'متوقف',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, ColorScheme cs, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  List<Widget> _buildChains(ColorScheme cs) {
    final l10n = AppLocalizations.of(context);
    final linked = [
      for (final c in _chains)
        if (_state[c.uid] == _ChainState.linked) c,
    ];
    final query = _search.text.trim().toLowerCase();
    final selectable = [
      for (final c in _chains)
        if (_state[c.uid] != _ChainState.linked &&
            (query.isEmpty || c.name.toLowerCase().contains(query)))
          c,
    ];
    final hasSelectable = _chains.any((c) => _state[c.uid] != _ChainState.linked);
    final available = _availableOptions;
    final selection = _selection;
    final count = selection.kept.length;
    final atCap = count >= kMaxOrganizationsPerRequest;
    final allSelected = available.isNotEmpty &&
        available.every((c) => _selected.contains(c.uid));

    return [
      _sectionLabel('مرتبط حالياً (${linked.length})', cs),
      if (linked.isEmpty)
        Text('—', style: TextStyle(color: cs.onSurfaceVariant))
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in linked)
              FilterChip(
                key: HrAddChainsSheet.chipKey(c.uid),
                avatar: Icon(Symbols.check_circle_rounded, size: 18, color: cs.onSurfaceVariant),
                showCheckmark: false,
                selected: false,
                label: Text('${c.name} · مرتبط'),
                onSelected: null,
              ),
          ],
        ),
      const SizedBox(height: 20),
      _sectionLabel(
        'سلاسل الشركة',
        cs,
        trailing: Container(
          key: HrAddChainsSheet.counterKey,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count/$kMaxOrganizationsPerRequest مختارة',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSecondaryContainer,
            ),
          ),
        ),
      ),
      if (hasSelectable) ...[
        SearchBar(
          key: HrAddChainsSheet.searchKey,
          controller: _search,
          hintText: 'ابحث باسم السلسلة',
          elevation: const WidgetStatePropertyAll(0),
          constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
          backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
          leading: Icon(Symbols.search_rounded, color: cs.onSurfaceVariant),
          onChanged: (_) => setState(() {}),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: HrAddChainsSheet.selectAllKey,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _submitting || available.isEmpty
                ? null
                : () => setState(() {
                      final next = toggleSelectAll(
                        all: available,
                        selectedUids: _selected,
                      );
                      _selected
                        ..clear()
                        ..addAll(next);
                      _submitError = null;
                    }),
            child: Text(
              allSelected
                  ? 'إلغاء الكل'
                  : (l10n?.chainPickerSelectAll ?? 'اختيار الكل'),
            ),
          ),
        ),
      ],
      if (!hasSelectable)
        _note(cs, Symbols.info_rounded, kLinkChainsNoneAvailableMessage)
      else if (selectable.isEmpty)
        Text('لا توجد سلاسل مطابقة للبحث', style: TextStyle(color: cs.onSurfaceVariant))
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in selectable)
              if (_state[c.uid] == _ChainState.pending)
                FilterChip(
                  key: HrAddChainsSheet.chipKey(c.uid),
                  avatar: Icon(Symbols.schedule_rounded, size: 18, color: cs.onSurfaceVariant),
                  showCheckmark: false,
                  selected: false,
                  label: Text('${c.name} · طلب قيد المراجعة'),
                  onSelected: null,
                )
              else
                FilterChip(
                  key: HrAddChainsSheet.chipKey(c.uid),
                  selected: _selected.contains(c.uid),
                  tooltip: c.companyRegistered
                      ? null
                      : 'الشركة غير مسجلة في هذه السلسلة بعد، وتُسجَّل عند اعتماد الطلب',
                  label: c.companyRegistered
                      ? Text(c.name)
                      : Text.rich(
                          TextSpan(
                            text: c.name,
                            children: [
                              TextSpan(
                                text: ' · جديدة',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          key: HrAddChainsSheet.newChainHintKey(c.uid),
                        ),
                  onSelected: _submitting ||
                          (atCap && !_selected.contains(c.uid))
                      ? null
                      : (on) => setState(() {
                            on ? _selected.add(c.uid) : _selected.remove(c.uid);
                            _submitError = null;
                          }),
                ),
          ],
        ),
      const SizedBox(height: 16),
      _note(
        cs,
        Symbols.info_rounded,
        _checkUnavailable
            ? 'تعذر التحقق من الطلبات السابقة الآن. سيتم التحقق من ربط المندوب بكل سلسلة عند الإرسال.'
            : 'السلاسل المرتبطة حالياً أو التي عليها طلب قيد المراجعة غير متاحة للاختيار.',
      ),
      if (_chains.any((c) =>
          _selected.contains(c.uid) && !c.companyRegistered)) ...[
        const SizedBox(height: 8),
        _note(
          cs,
          Symbols.domain_add_rounded,
          'السلاسل المعلّمة «جديدة» ستُسجَّل فيها الشركة تلقائياً عند اعتماد الطلب.',
        ),
      ],
      if (selection.warningAr != null || _notice != null) ...[
        const SizedBox(height: 8),
        _note(cs, Symbols.info_rounded, (_notice ?? selection.warningAr)!),
      ],
      if (_submitError != null) ...[
        const SizedBox(height: 8),
        Text(
          _submitError!,
          style: TextStyle(fontSize: 12.5, height: 1.4, color: cs.error),
        ),
      ],
    ];
  }

  Widget _note(ColorScheme cs, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _note(cs, Symbols.error_rounded, _loadError!),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _load,
            icon: const Icon(Symbols.refresh_rounded, size: 18),
            label: const Text('إعادة المحاولة'),
          ),
        ),
      ],
    );
  }

  /// Sticky footer: the one-request note and the send / cancel buttons.
  Widget _buildFooter(ColorScheme cs) {
    final l10n = AppLocalizations.of(context);
    final count = _loading ? 0 : _selection.kept.length;
    final canSubmit = !_loading && _loadError == null && count > 0 && !_submitting;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.verified_user_rounded, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n?.chainPickerOneSubscriptionNote ?? 'طلب واحد، موافقة واحدة، واشتراك واحد. لا تُحتسب رسوم لكل سلسلة.'} '
                  'الحد الأقصى $kMaxOrganizationsPerRequest سلاسل في الطلب الواحد.',
                  style: TextStyle(fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: HrAddChainsSheet.submitKey,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: canSubmit ? _submit : null,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.send_rounded, size: 20),
                  label: Text(
                    _submitting ? 'جاري إرسال الطلب...' : 'إرسال الطلب ($count)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
