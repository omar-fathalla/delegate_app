import 'package:flutter/material.dart';

/// Web shell bridge between «الرئيسية» and the desktop header.
///
/// The overview publishes the unread count and the reload / notifications
/// actions the greeting row used to own. The header reads them. Mobile never
/// shows those header controls.
class HrWebHeaderBridge extends ChangeNotifier {
  int unread = 0;
  Future<void> Function()? reloadHome;
  VoidCallback? openNotifications;

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
class HrWebHeaderBell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = cs.onSurfaceVariant;
    return Badge(
      key: const ValueKey('hr_web_header_notifications_badge'),
      isLabelVisible: unread > 0,
      label: Text('$unread'),
      child: IconButton(
        key: const ValueKey('hr_web_header_notifications'),
        tooltip: 'الإشعارات',
        onPressed: onPressed,
        icon: Icon(
          Icons.notifications_outlined,
          size: toolbar ? 20 : 24,
          color: iconColor,
        ),
        style: toolbar
            ? IconButton.styleFrom(
                foregroundColor: iconColor,
                backgroundColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              )
            : IconButton.styleFrom(foregroundColor: iconColor),
      ),
    );
  }
}
