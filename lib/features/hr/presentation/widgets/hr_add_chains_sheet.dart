import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:delegate_app/features/admin/data/company_chains.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Kept for the delegates table: suspended delegates never get chains
/// (Mohamed, 17 Nov 2026). Chains now come from the company (see
/// company_chains.dart), so this only documents the rule.
const bool kHrAllowAddChainsForSuspended = false;

const String kHrAddChainsSuspendedTooltip =
    'المندوب متوقف، لا يمكن إضافة سلاسل له';

/// HR web «إضافة سلاسل للشركة» side sheet: a company-level «طلب ضم سلسلة».
///
/// Sections: «سلاسل الشركة» (already joined, shown disabled) and
/// «سلاسل أخرى (تحتاج موافقة)» (selectable). No chain cap, «اختيار الكل»
/// picks every visible chain, alphabetical, search. After approval every
/// active delegate with a paid subscription of the company is linked to the
/// chain automatically (Cloud Function), so no delegate is picked here.
///
/// Fast: the chain catalog is cached per company and prefetched when the
/// page opens; the pending-request check is one query and runs alongside.
class HrAddChainsSheet extends StatefulWidget {
  const HrAddChainsSheet({
    super.key,
    required this.supervisor,
    required this.companyUID,
    required this.companyName,
    required this.fullScreen,
  });

  final Delegate supervisor;
  final String companyUID;
  final String companyName;
  final bool fullScreen;

  static const double fullScreenBelow = 840;
  static const double sheetWidth = 480;

  static const titleKey = Key('hr_add_chains_title');
  static const counterKey = Key('hr_add_chains_counter');
  static const submitKey = Key('hr_add_chains_submit');
  static const searchKey = Key('hr_add_chains_search');
  static const selectAllKey = Key('hr_add_chains_select_all');
  static const skeletonKey = Key('hr_add_chains_skeleton');
  static const joinedSectionKey = Key('hr_add_chains_joined');
  static const otherSectionKey = Key('hr_add_chains_other');
  static Key chipKey(String uid) => Key('hr_add_chains_chip_$uid');

  /// Tests and fake-data screenshots only.
  @visibleForTesting
  static FirebaseFirestore Function()? debugFirestore;
  @visibleForTesting
  static Future<List<CompanyChainOption>> Function()? debugCatalog;
  @visibleForTesting
  static Future<Set<String>> Function()? debugPending;
  @visibleForTesting
  static Future<void> Function(List<CompanyChainOption> selected)? debugSubmit;

  static void debugReset() {
    debugFirestore = null;
    debugCatalog = null;
    debugPending = null;
    debugSubmit = null;
  }

  /// Returns the names of the requested chains, or null.
  static Future<List<String>?> show(
    BuildContext context, {
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
        supervisor: supervisor,
        companyUID: supervisor.companyUID,
        companyName: supervisor.companyName,
        fullScreen: fullScreen,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final rtl = Directionality.of(ctx) == TextDirection.rtl;
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: fullScreen ? const Offset(0, 0.05) : Offset(rtl ? -1 : 1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  /// Warms the cache when the delegates page opens (web only).
  static void prefetch(Delegate supervisor) {
    if (debugCatalog != null || supervisor.companyUID.trim().isEmpty) return;
    CompanyChainCatalog.fetch(
      firestore: debugFirestore?.call() ?? FirebaseFirestore.instance,
      companyUID: supervisor.companyUID,
    ).ignore();
  }

  @override
  State<HrAddChainsSheet> createState() => _HrAddChainsSheetState();
}

class _HrAddChainsSheetState extends State<HrAddChainsSheet> {
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  bool _checkingPending = true;
  bool _pendingUnavailable = false;
  String? _loadError;
  String? _submitError;
  bool _submitting = false;

  List<CompanyChainOption> _chains = const [];
  Set<String> _pending = const {};
  final Set<String> _selected = {};

  FirebaseFirestore get _firestore =>
      HrAddChainsSheet.debugFirestore?.call() ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _checkingPending = true;
      _loadError = null;
    });
    final pendingFuture = (HrAddChainsSheet.debugPending?.call() ??
            fetchPendingCompanyChainUids(
              firestore: _firestore,
              companyUID: widget.companyUID,
            ))
        .then<Set<String>?>((v) => v)
        .catchError((Object _) => null);
    try {
      final chains = await (HrAddChainsSheet.debugCatalog?.call() ??
          CompanyChainCatalog.fetch(
            firestore: _firestore,
            companyUID: widget.companyUID,
            forceRefresh: force,
          ));
      if (!mounted) return;
      // Show the chains right away; the pending check fills in after.
      setState(() {
        _chains = chains;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _checkingPending = false;
        _loadError = 'تعذر تحميل السلاسل الآن. تحقق من الاتصال وحاول مرة أخرى.';
      });
      return;
    }
    final pending = await pendingFuture;
    if (!mounted) return;
    setState(() {
      _checkingPending = false;
      _pendingUnavailable = pending == null;
      _pending = pending ?? const {};
      _selected.removeAll(_pending);
    });
  }

  List<CompanyChainOption> get _joined => [
        for (final c in _chains)
          if (c.joined) c,
      ];

  List<CompanyChainOption> get _others => [
        for (final c in _chains)
          if (!c.joined) c,
      ];

  bool _matches(CompanyChainOption c) {
    final q = _search.text.trim().toLowerCase();
    return q.isEmpty || c.name.toLowerCase().contains(q);
  }

  bool _selectable(CompanyChainOption c) => !c.joined && !_pending.contains(c.uid);

  List<CompanyChainOption> get _selectedChains => [
        for (final c in _chains)
          if (_selected.contains(c.uid) && _selectable(c)) c,
      ];

  Future<void> _submit() async {
    final picked = _selectedChains;
    if (picked.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final hook = HrAddChainsSheet.debugSubmit;
      if (hook != null) {
        await hook(picked);
      } else {
        await submitCompanyChainRequests(
          firestore: _firestore,
          supervisor: widget.supervisor,
          companyUID: widget.companyUID,
          companyName: widget.companyName,
          chains: picked,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop([for (final c in picked) c.name]);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = 'تعذر إرسال الطلب الآن، حاول مرة أخرى.';
      });
    }
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
        if (!_loading && _checkingPending)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCompanyCard(cs),
                const SizedBox(height: 16),
                if (_loadError != null)
                  _buildLoadError(cs)
                else ...[
                  _buildSearch(cs),
                  const SizedBox(height: 20),
                  if (_loading) _buildSkeleton(cs) else ..._buildSections(cs),
                ],
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
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 8, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Symbols.add_business_rounded, color: cs.onPrimaryContainer, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إضافة سلاسل للشركة',
                  key: HrAddChainsSheet.titleKey,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                Text(
                  'طلب ضم سلسلة',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'إغلاق',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Symbols.close_rounded),
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyCard(ColorScheme cs) {
    final joined = _loading ? null : _joined.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Symbols.domain_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.companyName.trim().isEmpty ? 'الشركة' : widget.companyName.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  joined == null ? 'جاري تحميل السلاسل…' : 'مسجلة في $joined سلسلة',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch(ColorScheme cs) {
    return SearchBar(
      key: HrAddChainsSheet.searchKey,
      controller: _search,
      hintText: 'ابحث باسم السلسلة',
      elevation: const WidgetStatePropertyAll(0),
      constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
      backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
      leading: Icon(Symbols.search_rounded, color: cs.onSurfaceVariant),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _sectionHeader(
    ColorScheme cs, {
    Key? key,
    required String title,
    required int count,
    String? subtitle,
    Widget? trailing,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title ($count)',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: cs.onSurface),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// Evenly sized tiles, 2 per row in the sheet, 1 on very narrow screens.
  Widget _grid(List<Widget> tiles) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 8.0;
      final cols = c.maxWidth >= 340 ? 2 : 1;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }

  Widget _tile(
    ColorScheme cs, {
    required CompanyChainOption chain,
    required bool selected,
    required bool enabled,
    IconData? stateIcon,
    String? stateLabel,
    String? tooltip,
  }) {
    final bg = selected ? cs.primaryContainer : cs.surface;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;
    final tile = Material(
      key: HrAddChainsSheet.chipKey(chain.uid),
      color: enabled ? bg : cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled && !_submitting
            ? () => setState(() {
                  selected ? _selected.remove(chain.uid) : _selected.add(chain.uid);
                  _submitError = null;
                })
            : null,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, end: 12),
            child: Row(
              children: [
                if (stateIcon != null)
                  SizedBox(
                    width: 40,
                    child: Icon(stateIcon, size: 20, color: cs.onSurfaceVariant),
                  )
                else
                  Checkbox(
                    value: selected,
                    onChanged: enabled && !_submitting
                        ? (v) => setState(() {
                              v == true ? _selected.add(chain.uid) : _selected.remove(chain.uid);
                              _submitError = null;
                            })
                        : null,
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chain.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: enabled ? fg : cs.onSurfaceVariant,
                        ),
                      ),
                      if (stateLabel != null)
                        Text(
                          stateLabel,
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: tooltip ?? chain.name, child: tile);
  }

  List<Widget> _buildSections(ColorScheme cs) {
    final joined = _joined.where(_matches).toList();
    final others = _others.where(_matches).toList();
    final visibleSelectable = others.where(_selectable).toList();
    final count = _selectedChains.length;
    final allVisibleSelected = visibleSelectable.isNotEmpty &&
        visibleSelectable.every((c) => _selected.contains(c.uid));
    return [
      _sectionHeader(
        cs,
        key: HrAddChainsSheet.joinedSectionKey,
        title: 'سلاسل الشركة',
        count: _joined.length,
        subtitle: 'الشركة مسجلة فيها بالفعل.',
      ),
      if (joined.isEmpty)
        Text(
          _joined.isEmpty ? 'لا توجد سلاسل مسجلة بعد.' : 'لا توجد نتائج.',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
        )
      else
        _grid([
          for (final c in joined)
            _tile(
              cs,
              chain: c,
              selected: false,
              enabled: false,
              stateIcon: Symbols.check_circle_rounded,
              stateLabel: 'مسجلة',
            ),
        ]),
      const SizedBox(height: 24),
      _sectionHeader(
        cs,
        key: HrAddChainsSheet.otherSectionKey,
        title: 'سلاسل أخرى (تحتاج موافقة)',
        count: _others.length,
        subtitle: 'تُسجَّل الشركة فيها بعد موافقة مسؤول السلسلة.',
        trailing: Container(
          key: HrAddChainsSheet.counterKey,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count مختارة',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSecondaryContainer),
          ),
        ),
      ),
      if (others.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: HrAddChainsSheet.selectAllKey,
            style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
            onPressed: _submitting || visibleSelectable.isEmpty
                ? null
                : () => setState(() {
                      if (allVisibleSelected) {
                        _selected.removeAll(visibleSelectable.map((c) => c.uid));
                      } else {
                        _selected.addAll(visibleSelectable.map((c) => c.uid));
                      }
                      _submitError = null;
                    }),
            icon: Icon(
              allVisibleSelected ? Symbols.deselect_rounded : Symbols.select_all_rounded,
              size: 18,
            ),
            label: Text(allVisibleSelected ? 'إلغاء الكل' : 'اختيار الكل'),
          ),
        ),
      const SizedBox(height: 4),
      if (_others.isEmpty)
        Text('الشركة مسجلة في كل السلاسل المتاحة.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))
      else if (others.isEmpty)
        Text('لا توجد سلاسل مطابقة للبحث', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))
      else
        _grid([
          for (final c in others)
            if (_pending.contains(c.uid))
              _tile(
                cs,
                chain: c,
                selected: false,
                enabled: false,
                stateIcon: Symbols.schedule_rounded,
                stateLabel: 'طلب قيد المراجعة',
              )
            else
              _tile(
                cs,
                chain: c,
                selected: _selected.contains(c.uid),
                enabled: true,
              ),
        ]),
      if (_pendingUnavailable) ...[
        const SizedBox(height: 12),
        _note(cs, Symbols.info_rounded,
            'تعذر التحقق من الطلبات السابقة الآن. يمكنك الإرسال، وسيراجع المسؤول أي طلب مكرر.'),
      ],
      if (_submitError != null) ...[
        const SizedBox(height: 12),
        Text(_submitError!, style: TextStyle(fontSize: 12.5, color: cs.error)),
      ],
    ];
  }

  Widget _buildSkeleton(ColorScheme cs) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return Column(
      key: HrAddChainsSheet.skeletonKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(140, 16),
        const SizedBox(height: 12),
        _grid([for (var i = 0; i < 4; i++) bar(double.infinity, 52)]),
        const SizedBox(height: 24),
        bar(200, 16),
        const SizedBox(height: 12),
        _grid([for (var i = 0; i < 10; i++) bar(double.infinity, 52)]),
      ],
    );
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
            child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.5, color: cs.onSurfaceVariant)),
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
            onPressed: () => _load(force: true),
            icon: const Icon(Symbols.refresh_rounded, size: 18),
            label: const Text('إعادة المحاولة'),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(ColorScheme cs) {
    final count = _selectedChains.length;
    final canSubmit = !_loading && !_checkingPending && _loadError == null && count > 0 && !_submitting;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
                  'بعد الموافقة تظهر فروع السلسلة تلقائياً لكل مناديب الشركة النشطين '
                  'والمدفوع اشتراكهم. لا رسوم إضافية لكل سلسلة.',
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
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Symbols.send_rounded, size: 20),
                  label: Text(
                    _submitting ? 'جاري إرسال الطلب...' : 'إرسال طلب الضم ($count)',
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
