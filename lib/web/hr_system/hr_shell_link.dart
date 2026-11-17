import 'package:flutter/foundation.dart';

import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';

/// Web only: lets a full page pushed over the HR shell (for example
/// «إضافة مندوب لمنظمة جديدة») reuse the shell's side navigation and bell.
///
/// [HRMainScreen] registers its handlers while it is mounted on the web. The
/// pushed page pops itself first and then calls them, so the shell switches
/// tab or opens the notifications sheet underneath. Mobile never registers.
class HrShellLink {
  HrShellLink._();

  static ValueChanged<int>? _selectTab;
  static ValueChanged<String>? _selectMenu;
  static HrWebHeaderBridge? _bridge;
  static Object? _owner;

  /// Header bridge of the mounted shell (unread count, notifications).
  static HrWebHeaderBridge? get bridge => _bridge;

  static bool get isAttached => _selectTab != null;

  static void attach({
    required Object owner,
    required ValueChanged<int> selectTab,
    required ValueChanged<String> selectMenu,
    required HrWebHeaderBridge bridge,
  }) {
    _owner = owner;
    _selectTab = selectTab;
    _selectMenu = selectMenu;
    _bridge = bridge;
  }

  /// Only the shell that attached may detach, so a disposing old shell does
  /// not clear a newer one.
  static void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _selectTab = null;
    _selectMenu = null;
    _bridge = null;
  }

  static void selectTab(int index) => _selectTab?.call(index);

  static void selectMenu(String id) => _selectMenu?.call(id);

  static void openNotifications() => _bridge?.openNotifications?.call();

  @visibleForTesting
  static void debugReset() {
    _owner = null;
    _selectTab = null;
    _selectMenu = null;
    _bridge = null;
  }
}
