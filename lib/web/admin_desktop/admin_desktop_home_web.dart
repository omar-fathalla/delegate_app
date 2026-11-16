// WEB-ONLY: Material 3 desktop grid for the supervisor home tab.
// Reuses AdminHomeScreen (same bloc provider + initial loads) through its
// layoutBuilder hook, and composes the public section widgets into a grid.
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

const double kDesktopHomeGridMinWidth = 1200; // window width for 12 columns
const double _gutter = 24;

class AdminDesktopHomeWeb extends StatelessWidget {
  final Delegate delegate;
  const AdminDesktopHomeWeb({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    return AdminHomeScreen(
      adminDelegate: delegate,
      layoutBuilder: (context, data) => AdminDesktopHomeGridWeb(data: data),
    );
  }
}

/// The grid itself (public for tests / goldens with fake data).
class AdminDesktopHomeGridWeb extends StatelessWidget {
  final AdminHomeSectionsData data;
  const AdminDesktopHomeGridWeb({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final wide = MediaQuery.sizeOf(context).width >= kDesktopHomeGridMinWidth;
    final d = data.delegate;

    final hero = AdminHomeHeroCard(
      adminDelegate: d,
      organizations: data.organizations,
      embedSections: false,
    );
    final overview = _DeskCard(child: AdminHomeTodayOverview(adminDelegate: d));
    final showChips = data.isCompanySupervisor && data.organizations.isNotEmpty;
    final chips = _DeskCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            icon: Symbols.storefront_rounded,
            text: ar ? 'السلاسل التابع لها مناديبك' : 'Your delegates\' chains',
          ),
          const SizedBox(height: 16),
          AdminHomeChainChips(
            organizations: data.organizations,
            foreground: cs.onSurface,
            adminDelegate: d,
            wrap: true,
          ),
        ],
      ),
    );
    final duties = _DeskCard(
      child: AdminHomeDutiesGuide(
        adminDelegate: d,
        foreground: cs.onSurface,
        tileColor: cs.surfaceContainerHigh,
        columns: 2,
      ),
    );
    final promo = data.isCompanySupervisor ? AdminHomePromoCard(adminDelegate: d) : null;
    final quick = AdminHomeQuickActions(adminDelegate: d);

    Widget pair(Widget a, Widget? b, {int fa = 8, int fb = 4}) => b == null
        ? a
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: fa, child: a),
              const SizedBox(width: _gutter),
              Expanded(flex: fb, child: b),
            ],
          );

    final children = wide
        ? <Widget>[
            pair(hero, overview),
            if (showChips) chips,
            pair(duties, promo),
            quick,
          ]
        : <Widget>[
            hero,
            overview,
            if (showChips) chips,
            pair(duties, promo, fa: 1, fb: 1),
            quick,
          ];

    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(_gutter),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: _gutter),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeskCard extends StatelessWidget {
  final Widget child;
  const _DeskCard({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionTitle({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, color: cs.primary, fill: 1),
      const SizedBox(width: 8),
      Text(text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface)),
    ]);
  }
}
