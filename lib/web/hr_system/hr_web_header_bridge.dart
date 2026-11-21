import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// Web shell bridge between «الرئيسية» and the desktop header.
///
/// The overview publishes the unread count and the reload / notifications
/// actions the greeting row used to own. The header reads them. Mobile never
/// shows those header controls.
class HrWebHeaderBridge extends ChangeNotifier {
  int unread = 0;
  Future<void> Function()? reloadHome;
  VoidCallback? openNotifications;

  /// Bell focus, restored when the notifications sheet closes.
  FocusNode? notificationsFocus;

  /// While the sheet is open the bell badge hides, so the unread count is
  /// shown once — inside the sheet.
  bool sheetOpen = false;

  void attach({
    required int unread,
    required Future<void> Function() reloadHome,
    required VoidCallback openNotifications,
  }) {
    final changed =
        this.unread != unread ||
        this.reloadHome != reloadHome ||
        this.openNotifications != openNotifications;
    this.reloadHome = reloadHome;
    this.openNotifications = openNotifications;
    this.unread = unread;
    // The header builds before the overview attaches. Skipping the notify
    // when the count is unchanged left the bell disabled (onPressed null).
    if (changed) notifyListeners();
  }

  void setSheetOpen(bool open) {
    if (sheetOpen == open) return;
    sheetOpen = open;
    notifyListeners();
  }

  /// Per-page reloads run by the shell's top-bar refresh, keyed by the
  /// shell tab. A page with its own data (for example «الخريطة الحية»)
  /// registers here instead of drawing its own refresh button (TAS-148).
  final Map<Object, Future<void> Function()> _pageReloads = {};

  void attachPageReload(Object page, Future<void> Function() reload) {
    _pageReloads[page] = reload;
  }

  /// Removes [reload] only if it is still the one registered for [page].
  void releasePageReload(Object page, Future<void> Function() reload) {
    if (_pageReloads[page] == reload) _pageReloads.remove(page);
  }

  Future<void> Function()? pageReload(Object page) => _pageReloads[page];

  /// Drops the callbacks when the overview leaves the tree. The count stays
  /// so a disposing child does not rebuild the header mid-unmount.
  void release() {
    reloadHome = null;
    openNotifications = null;
  }
}

class HrWebHeaderBridgeScope extends InheritedNotifier<HrWebHeaderBridge> {
  const HrWebHeaderBridgeScope({
    super.key,
    required HrWebHeaderBridge bridge,
    required super.child,
  }) : super(notifier: bridge);
}

/// Notifications control moved out of the home greeting row.
class HrWebHeaderBell extends StatefulWidget {
  final int unread;
  final VoidCallback? onPressed;

  /// Matches the desktop header's filled icon buttons. The narrow app bar
  /// uses a plain toolbar button.
  final bool toolbar;

  const HrWebHeaderBell({
    super.key,
    required this.unread,
    required this.onPressed,
    this.toolbar = true,
  });

  @override
  State<HrWebHeaderBell> createState() => _HrWebHeaderBellState();
}

class _HrWebHeaderBellState extends State<HrWebHeaderBell> {
  final FocusNode _focus = FocusNode(debugLabel: 'hr_notifications_bell');
  HrWebHeaderBridge? _bridge;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context
        .getInheritedWidgetOfExactType<HrWebHeaderBridgeScope>()
        ?.notifier;
    if (identical(_bridge, next)) return;
    if (_bridge?.notificationsFocus == _focus) {
      _bridge!.notificationsFocus = null;
    }
    _bridge = next;
    _bridge?.notificationsFocus = _focus;
  }

  @override
  void dispose() {
    if (_bridge?.notificationsFocus == _focus) {
      _bridge!.notificationsFocus = null;
    }
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = _bridge;
    if (bridge == null) return _button(context, hideCount: false);
    return ListenableBuilder(
      listenable: bridge,
      builder: (context, _) => _button(context, hideCount: bridge.sheetOpen),
    );
  }

  Widget _button(BuildContext context, {required bool hideCount}) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = cs.onSurfaceVariant;
    final unread = widget.unread;
    return Badge(
      key: const ValueKey('hr_web_header_notifications_badge'),
      isLabelVisible: unread > 0 && !hideCount,
      label: Text('$unread'),
      child: IconButton(
        key: const ValueKey('hr_web_header_notifications'),
        focusNode: _focus,
        tooltip: 'الإشعارات',
        onPressed: widget.onPressed,
        icon: Icon(
          Symbols.notifications_rounded,
          size: widget.toolbar ? 20 : 24,
          color: iconColor,
        ),
        style: widget.toolbar
            ? IconButton.styleFrom(
                foregroundColor: iconColor,
                backgroundColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
              )
            : IconButton.styleFrom(foregroundColor: iconColor),
      ),
    );
  }
}
