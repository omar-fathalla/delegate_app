# Tashil M3 catalog

Every Material Design 3 item Tashil implements has a fixed ID here. A
review of any m3.material.io page (see "How to review an M3 page" below)
matches the page to these IDs, compares, and records the result.

- **F** = foundations and styles, **C** = M3 components, **P** = Tashil's
  own composites built from M3 parts.
- IDs never change and are never reused. A new item takes the next free
  number in its group. A removed item stays with status `removed`.
- Rules live in `docs/design/design-system.md` (the "Rules" column names the
  section); this file is the index, not a second copy of the rules.
- Playground: `flutter run -t lib/main_playground.dart`, or the live web
  build. "Tab / section" is the tab name, then the section title.
- Spec paths are relative to `https://m3.material.io/`; code paths to
  `lib/core/design/`; tests to `test/design/`.
- **Reviewed** is the date the item was last checked against the page.

## F: foundations and styles

| ID | Item | Spec | Code | Test | Tab / section | Rules | Reviewed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F-01 | Color roles, contrast levels | styles/color/roles | `tokens.dart` (`TashilColors`, `TashilContrast`), `app_theme.dart` | `color_test.dart` | الأساسيات / الألوان | Colour | 2026-11-26 |
| F-02 | Color schemes: static, dynamic, baseline, store colour | styles/color/choosing-a-scheme | `color_schemes.dart` | `color_schemes_test.dart` | الأساسيات / نظام الألوان المصدر | Colour schemes | 2026-11-26 |
| F-03 | Content-based colour | styles/color/dynamic/content-based-source | `color_schemes.dart` (`ContentColorScope`) | `color_schemes_test.dart` | الأساسيات / ألوان من المحتوى | Colour schemes | 2026-11-26 |
| F-04 | Semantic colours (success, warning) | styles/color/roles | `tokens.dart` (`TashilSemanticColors`) | `color_test.dart` | الأساسيات / الألوان | Colour | 2026-11-26 |
| F-05 | Typography: baseline + emphasized scale | styles/typography/applying-type | `typography.dart` | `typography_test.dart` | الأساسيات / الخطوط | Typography | 2026-11-26 |
| F-06 | Shape: corner radius scale | styles/shape/corner-radius-scale | `tokens.dart` (`TashilRadius`) | `playground_test.dart` | الأساسيات / الأشكال | Rules intro | 2026-11-26 |
| F-07 | Breakpoints (width + height) | foundations/layout/breakpoints/overview | `layout.dart` (`TashilBreakpoint`, `TashilHeightBreakpoint`) | `layout_test.dart`, `grid_density_rtl_test.dart` | الأساسيات / التخطيط ونقاط التوقف | Layout: breakpoints | 2026-11-26 |
| F-08 | Panes, split, resizing, reflow | foundations/layout/scaffold/panes | `layout.dart` (`PaneLayout`, `PaneDragHandle`) | `layout_test.dart` | الأساسيات / التخطيط ونقاط التوقف | Layout: breakpoints | 2026-11-26 |
| F-09 | Layout scaffold: bars and rails, floating toolbar | foundations/layout/scaffold/overview | `widgets/navigation.dart`, `widgets/toolbar.dart` | `layout_test.dart`, `navigation_test.dart` | الأساسيات / التخطيط ونقاط التوقف | Layout: breakpoints | 2026-11-26 |
| F-10 | Grid columns and content rulers | foundations/layout/grids-spacing/grids | `layout.dart` (`ColumnGrid`, `ColumnGridOverlay`) | `grid_density_rtl_test.dart` | الأساسيات / التخطيط ونقاط التوقف | Grids and spacing | 2026-11-26 |
| F-11 | Spacing scale, padding vs gaps vs margins | foundations/layout/grids-spacing/spacing | `tokens.dart` (`TashilSpacing`) | `playground_test.dart` | الأساسيات / المسافات | Grids and spacing | 2026-11-26 |
| F-12 | Density (opt-in, 0 to -3) | foundations/layout/grids-spacing/density | `layout.dart` (`TashilDensity`, `DensityScope`) | `grid_density_rtl_test.dart` | الأساسيات / الكثافة | Grids and spacing | 2026-11-26 |
| F-13 | Bidirectionality and RTL | foundations/layout/bidirectionality-rtl | `bidi.dart` (`Bidi`, `MirroredIcon`, `LtrIsland`) | `grid_density_rtl_test.dart` | الأساسيات / من اليمين للشمال | Localisation and direction | 2026-11-26 |
| F-14 | Line length 40 to 60 characters | foundations/layout/layout-overview/overview | `layout.dart` (`ReadingWidth`) | `layout_test.dart` | الأساسيات / التخطيط ونقاط التوقف | Layout: breakpoints | 2026-11-26 |
| F-15 | Motion: springs | styles/motion/overview | `motion.dart` (`TashilSpring`) | `transitions_test.dart` | الأساسيات / الحركة | Motion | 2026-11-26 |
| F-16 | Motion: easing and duration | styles/motion/easing-and-duration | `motion.dart` (`TashilEasing`) | `transitions_test.dart` | الانتقالات / أزواج الـ Easing والمدة | Motion | 2026-11-26 |
| F-17 | Transitions: container transform, forward/backward, lateral, top level, enter/exit, skeleton | styles/motion/transitions/transition-patterns | `motion.dart`, `app_theme.dart` (page transitions) | `transitions_test.dart` | الانتقالات | Motion | 2026-11-26 |
| F-18 | Accessibility, writing, tokens, input, selection | foundations/overview | `docs/design/design-system.md` only | — | — | Foundations: accessibility, writing | 2026-11-26 |
| F-19 | Touch targets 48dp, POS 56dp | foundations/designing/structure | `tokens.dart` (`TashilSizes`) | `playground_test.dart` | — | Layout and touch | 2026-11-26 |
| F-20 | Money and numbers (Western digits, piastres) | — (Tashil) | `money.dart`, `app_localizations.dart` | `money_test.dart`, `date_time_test.dart` | — | Money and numbers | 2026-11-26 |

## C: components

| ID | Item | Spec | Code | Test | Tab / section | Rules | Reviewed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C-01 | Common buttons | components/buttons | `app_theme.dart` | `playground_test.dart` | الأزرار / الأزرار | Components | 2026-11-26 |
| C-02 | Icon buttons | components/icon-buttons | official `IconButton` | `playground_test.dart` | الأزرار / أزرار الأيقونات | Components | 2026-11-26 |
| C-03 | FAB | components/floating-action-button | official, `layout.dart` (`AdaptiveFab`) | `layout_test.dart` | الأزرار / الزر العائم | Components | 2026-11-26 |
| C-04 | Extended FAB (collapses on scroll) | components/extended-fab/guidelines | official `FloatingActionButton.extended` | `playground_test.dart` | الأزرار / الزر العائم الممتد | Components | 2026-11-26 |
| C-05 | FAB menu | components/fab-menu | `widgets/fab_menu.dart` (hand-built) | `fab_menu_test.dart` | الأزرار / قائمة الزر العائم | Expressive table | 2026-11-26 |
| C-06 | Button groups: standard + connected (replaces segmented button) | components/button-groups | `widgets/button_group.dart` (hand-built) | `button_group_test.dart` | الأزرار / مجموعات الأزرار | Components | 2026-11-26 |
| C-07 | Floating toolbar | components/toolbars | `widgets/toolbar.dart` (hand-built) | `layout_test.dart` | الأساسيات / التخطيط ونقاط التوقف | Layout: breakpoints | 2026-11-26 |
| C-08 | Text fields | components/text-fields/guidelines | `widgets/text_fields.dart` (`TashilTextField`, `FormColumn`) | `text_fields_test.dart` | المدخلات / حقول النص | Text fields | 2026-11-26 |
| C-09 | Search | components/search/guidelines | `widgets/search.dart` (`TashilSearch`) | `search_test.dart` | المدخلات / البحث | Search | 2026-11-26 |
| C-10 | Menus (gaps, vibrant, select) | components/menus/guidelines | `widgets/menus.dart` | `menus_test.dart` | المدخلات / القوائم, قائمة اختيار | Menus | 2026-11-26 |
| C-11 | Chips: assist, filter, input, suggestion | components/chips/guidelines | `widgets/chips.dart` | `chips_test.dart` | المدخلات / الشرايح | Chips | 2026-11-26 |
| C-12 | Checkbox, radio, switch | components/checkbox | official | `playground_test.dart` | المدخلات / الاختيارات | Components | 2026-11-26 |
| C-13 | Sliders (sizes XS-XL, centered, range, vertical) | components/sliders/guidelines | `widgets/sliders.dart` | `sliders_test.dart` | المدخلات / المنزلق | Sliders | 2026-11-26 |
| C-14 | Date pickers + date range | components/date-pickers/guidelines | `widgets/date_time_fields.dart` (`DateField`) | `date_time_test.dart` | المدخلات / التاريخ, فترة تاريخ | Dates and times | 2026-11-26 |
| C-15 | Time pickers (scroll, dial) | components/time-pickers/guidelines | `widgets/date_time_fields.dart` (`ScrollTimePicker`, hand-built) | `date_time_test.dart` | المدخلات / الوقت | Dates and times | 2026-11-26 |
| C-16 | Scroll fields | components/scroll-fields/guidelines | `widgets/scroll_field.dart` (hand-built) | `scroll_field_test.dart` | المدخلات / حقول التمرير | Scroll fields | 2026-11-26 |
| C-17 | Navigation bar (hides on scroll) | components/navigation-bar/guidelines | `widgets/navigation.dart` | `navigation_test.dart` | التنقل / شريط التنقل السفلي | Navigation | 2026-11-26 |
| C-18 | Navigation rail: collapsed, expanded, modal (replaces drawer) | components/navigation-rail/guidelines | `widgets/navigation.dart` | `navigation_test.dart` | التنقل / القضيب الجانبي | Navigation | 2026-11-26 |
| C-19 | Adaptive navigation scaffold | components/navigation-rail/guidelines#adaptive-design | `widgets/navigation.dart` (`AdaptiveNavigationScaffold`) | `navigation_test.dart` | التنقل / تنقل متكيف | Navigation | 2026-11-26 |
| C-20 | Tabs | components/tabs | official `TabBar` | `playground_test.dart` | التنقل / التبويبات | Components | 2026-11-26 |
| C-21 | Top app bar | components/top-app-bar | official `AppBar` | `playground_test.dart` | التنقل / شريط التطبيق | Components | 2026-11-26 |
| C-22 | Cards | components/cards | official `Card` | `playground_test.dart` | الحاويات / الكروت | Components | 2026-11-26 |
| C-23 | Lists | components/lists | official `ListTile` | `playground_test.dart` | الحاويات / القوائم | Components | 2026-11-26 |
| C-24 | Data table (reports only) | components/lists | official `DataTable` | `playground_test.dart` | الحاويات / جدول البيانات | Components | 2026-11-26 |
| C-25 | Badges | components/badges | official `Badge` | `grid_density_rtl_test.dart` | الحاويات / الشارات | Components | 2026-11-26 |
| C-26 | Dividers | components/divider/guidelines | `tokens.dart` (`TashilDividerInset`) | `divider_test.dart` | الحاويات / الفواصل | Dividers | 2026-11-26 |
| C-27 | Basic + full-screen dialogs | components/dialogs/guidelines | `widgets/dialogs.dart` | `dialogs_test.dart` | التنبيهات / حوار أساسي, حوار بملء الشاشة | Dialogs | 2026-11-26 |
| C-28 | Bottom sheets | components/bottom-sheets/guidelines | `widgets/sheets.dart` | `sheets_test.dart` | التنبيهات / الورقة السفلية | Bottom sheets | 2026-11-26 |
| C-29 | Side sheets | components/side-sheets/guidelines | `widgets/side_sheets.dart` (hand-built) | `side_sheets_test.dart` | التنبيهات / الورقة الجانبية | Side sheets | 2026-11-26 |
| C-30 | Snackbar | components/snackbar/guidelines | `widgets/snackbars.dart` (`showTashilSnackBar`) | `snackbar_test.dart` | التنبيهات / الإشعار السريع | Snackbars | 2026-11-26 |
| C-31 | Loading indicator + pull to refresh | components/loading-indicator/guidelines | `widgets/loading_indicator.dart` (hand-built shapes) | `loading_indicator_test.dart` | التنبيهات / مؤشر التحميل | Loading and progress | 2026-11-26 |
| C-32 | Progress indicators | components/progress-indicators/guidelines | official | `playground_test.dart` | التنبيهات / مؤشرات التقدم | Loading and progress | 2026-11-26 |
| C-33 | Tooltips: plain + rich | components/tooltips/guidelines | `widgets/tooltips.dart` (`RichTooltip`, hand-built) | `tooltips_test.dart` | التنبيهات / التلميح | Tooltips | 2026-11-26 |
| C-34 | Banner | components/banner | official `MaterialBanner` | `playground_test.dart` | التنبيهات / اللافتة | Components | 2026-11-26 |

## P: Tashil composites

| ID | Item | Built from | Code | Test | Tab / section | Rules | Reviewed |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P-01 | ProductTile | C-23 lists | `widgets/pos_widgets.dart` | `playground_test.dart` | مكونات تسهيل / ProductTile | Components | 2026-11-26 |
| P-02 | StockBadge, SyncStatusLabel (status, not chips) | F-04 colours | `widgets/pos_widgets.dart` | `chips_test.dart` | مكونات تسهيل / StockBadge | Chips | 2026-11-26 |
| P-03 | CartLine + CheckoutBar | C-23, C-01 | `widgets/pos_widgets.dart` | `playground_test.dart` | مكونات تسهيل / CartLine | Components | 2026-11-26 |
| P-07 | SummaryCard + SummaryFact + SummaryLabel (content fills the card: icon, headline, subhead, labels, a prominent value on the end side, label-over-value facts across the width) | C-22 cards, F-05 type roles | `widgets/summary_card.dart` (hand-built composition) | `summary_card_test.dart` | الحاويات / كارت الملخص | Components | 2026-11-27 |
| P-08 | Skeleton, SummaryCardSkeleton, SkeletonSwitcher (skeleton loader: grey shapes where content will be, gentle pulse, fade to content) | motion transition patterns, C-22 | `widgets/skeleton.dart` | `skeleton_and_refresh_test.dart` | الحركة / هيكل التحميل | Motion | 2026-11-27 |
| P-09 | PullToRefresh (official `RefreshIndicator.noSpinner` + contained `LoadingIndicator`) | loading indicator | `widgets/pull_to_refresh.dart` | `skeleton_and_refresh_test.dart` | التنبيهات / السحب للتحديث | Loading and progress | 2026-11-27 |
| P-04 | NumericKeypad (7-8-9 on top) | C-01 | `widgets/pos_widgets.dart` | `playground_test.dart` | مكونات تسهيل / NumericKeypad | Components | 2026-11-26 |
| P-05 | ReceiptPreview 58mm | F-05, F-13 | `widgets/receipt_preview.dart` | `playground_test.dart` | مكونات تسهيل / ReceiptPreview | Money and numbers | 2026-11-26 |
| P-06 | EmptyState (empty list, and a failed load with retry) | foundations | `widgets/empty_state.dart` (app; m3-kit: `widgets/pos_widgets.dart`) | `playground_test.dart` | مكونات تسهيل / EmptyState | Components | 2026-11-26 |

## Open gaps

| ID | Gap |
| --- | --- |
| F-18 | UI overflows at 200% text in 6 of 8 playground tabs. |
| F-12 | Density is not wired to a user setting yet. |
| F-08 | Pane widths are not saved in user settings yet. |
| F-02 | Store colour is not persisted yet. |

## How to review an M3 page

Use this for every m3.material.io link or screenshot, in any session.

1. **Read the whole page**, every tab (Overview, Specs, Guidelines,
   Accessibility). m3.material.io is rendered by JavaScript: plain fetches
   get an empty shell, so use a real browser and read the page text.
2. **List what the page defines**: each component, variant, measurement,
   behaviour, do and don't.
3. **Match each one to an ID** in the tables above (by spec path first,
   then by name).
4. **Compare and act**, one row each:
   - **matches**: change nothing, only update the Reviewed date.
   - **differs**: update the existing item in place (same ID, same file);
     never create a second version. Use the official Flutter or Google
     widget first. Build by hand only when Flutter has none, mark it
     "hand-built" here, and add it to the Expressive table in
     `design-system.md`.
   - **missing**: add it with the next free ID in its group.
   - **does not apply** (platform or product mismatch): note it, change
     nothing.
5. **Prove it**: tests for every behaviour changed, `flutter analyze`
   clean, `dart format` clean, and the playground still passes at 360dp
   in light and dark.
6. **Write it down**: the rule in `design-system.md`, the row here
   (Code, Test, Section, Reviewed), and the playground `SpecSection`
   (spec path + one-line Arabic rule).
7. **Ship it**: rebuild and republish the live playground, then commit
   with the Linear issue reference and push.
8. **Report** a table: ID, item, result (matches / updated / new /
   skipped), and one line on why. State any assumption (a value the page
   did not give) as an assumption.
