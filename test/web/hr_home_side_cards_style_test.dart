// TAS-141: the three home side cards share one style, the chain chip grows
// to its name with a full-name tooltip, the web never goes below 12, and the
// account menu stands out from the page in light mode. Fake data only.
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/web/hr_system/hr_home_overview_web.dart';
import 'package:delegate_app/web/hr_system/hr_home_side_cards_web.dart';
import 'package:delegate_app/web/hr_system/hr_web_account_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

const _longChain = 'Fake Test Organization';

Delegate _supervisor() => Delegate(
  uid: 'seed-fake-supervisor',
  firstName: 'مشرف',
  middleName: '',
  lastName: 'تجريبي',
  fullName: 'مشرف تجريبي',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: 'seed-fake-org',
  organizationName: 'Fake Org',
  companyUID: 'seed-fake-co',
  companyName: 'شركة ألفا التجريبية',
  status: DelegateStatus.approved,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'test',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: UserRole.admin,
);

ThemeData _theme(Brightness b) => b == Brightness.light
    ? AppTheme.lightTheme(const Color(0xFF6750A4))
    : AppTheme.darkTheme(const Color(0xFF6750A4));

Future<void> _pumpSideColumn(WidgetTester t) async {
  t.view.physicalSize = const Size(1440, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: _theme(Brightness.light),
      locale: const Locale('ar'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              // The side column of the 1440 overview.
              child: SizedBox(
                width: kHrOverviewSideColumnWidth,
                child: Column(
                  children: [
                    HrHomeChainsCard(
                      chains: const ['كارفور', _longChain, 'زهران'],
                      selected: null,
                      onSelected: (_) {},
                      onAddChain: () {},
                    ),
                    const SizedBox(height: 16),
                    HrHomeFeatureCard(
                      isFreePromotion: true,
                      onAddDelegate: () {},
                      onHowToLink: () {},
                    ),
                    const SizedBox(height: 16),
                    HrHomeDutiesCard(
                      duties: adminHomeDuties(_supervisor(), isArabic: true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

const _cardKeys = [
  ValueKey('hr_home_chains_card'),
  ValueKey('hr_home_feature_card'),
  ValueKey('hr_home_duties_card'),
];

void main() {
  setUp(WebRuntimePolicy.debugReset);
  tearDown(WebRuntimePolicy.debugReset);

  testWidgets('the three side cards share one Card style', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pumpSideColumn(t);
    final theme = Theme.of(t.element(find.byKey(_cardKeys.first)));
    final titleSize = theme.textTheme.titleMedium!.fontSize;
    expect(titleSize, HrFont.titleMedium);
    final titles = {
      'hr_home_chains_card': kHrHomeChainsTitle,
      'hr_home_feature_card': 'ميزة حصرية للشركات',
      'hr_home_duties_card': 'دليل المهام والمسؤوليات',
    };
    for (final key in _cardKeys) {
      final cardWidget = find.byKey(key);
      expect(t.widget(cardWidget), isA<HrSideCard>(), reason: key.value);
      final card = t.widget<Card>(
        find.descendant(of: cardWidget, matching: find.byType(Card)).first,
      );
      final shape = card.shape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(HrRadius.card),
        reason: key.value,
      );
      expect(card.color, theme.colorScheme.surfaceContainerLow);
      final title = t.widget<Text>(
        find.descendant(of: cardWidget, matching: find.text(titles[key.value]!)),
      );
      expect(title.style?.fontSize, titleSize, reason: key.value);
    }
  });

  testWidgets('a long chain name takes the room it needs, with a tooltip', (
    t,
  ) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pumpSideColumn(t);
    final label = find.byKey(const ValueKey('hr_home_chain_chip_label_$_longChain'));
    final paragraph = t.renderObject<RenderParagraph>(label);
    expect(paragraph.didExceedMaxLines, isFalse, reason: 'not cut');

    final chip = find.byKey(const ValueKey('hr_home_chain_chip_$_longChain'));
    final short = find.byKey(const ValueKey('hr_home_chain_chip_كارفور'));
    expect(t.getSize(chip).width, greaterThan(t.getSize(short).width));

    final tooltip = t.widget<Tooltip>(
      find.ancestor(of: chip, matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, _longChain);
  });

  testWidgets('no text below 12 in the side cards (web)', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pumpSideColumn(t);
    await t.tap(find.byKey(const ValueKey('hr_home_duty_0')));
    await t.pumpAndSettle();
    for (final key in _cardKeys) {
      final paragraphs = find
          .descendant(of: find.byKey(key), matching: find.byType(RichText))
          .evaluate()
          .map((e) => e.renderObject! as RenderParagraph);
      for (final p in paragraphs) {
        p.text.visitChildren((span) {
          final size = span.style?.fontSize;
          if (size != null) {
            expect(
              size,
              greaterThanOrEqualTo(12),
              reason: '${key.value}: "${span.toPlainText()}"',
            );
          }
          return true;
        });
      }
    }
  });

  Future<Container> openAccountPanel(WidgetTester t, Brightness b) async {
    SharedPreferences.setMockInitialValues({});
    final cubit = ThemeCubit(await SharedPreferences.getInstance());
    addTearDown(cubit.close);
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          theme: _theme(b),
          locale: const Locale('ar'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Align(
                alignment: AlignmentDirectional.topEnd,
                child: HrWebAccountButton(
                  delegate: _supervisor(),
                  showName: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const ValueKey('hr_web_header_account')));
    await t.pumpAndSettle();
    return t.widget<Container>(
      find.byKey(const ValueKey('hr_web_profile_panel')),
    );
  }

  testWidgets('account menu: outline and level-3 shadow in light mode', (
    t,
  ) async {
    final panel = await openAccountPanel(t, Brightness.light);
    final deco = panel.decoration! as BoxDecoration;
    final cs = _theme(Brightness.light).colorScheme;
    expect(deco.border, Border.all(color: cs.outlineVariant));
    expect(deco.boxShadow, hasLength(2));
  });

  testWidgets('account menu: dark mode keeps the soft lift', (t) async {
    final panel = await openAccountPanel(t, Brightness.dark);
    final deco = panel.decoration! as BoxDecoration;
    expect(deco.border, isNull);
    expect(deco.boxShadow, hasLength(1));
  });
}
