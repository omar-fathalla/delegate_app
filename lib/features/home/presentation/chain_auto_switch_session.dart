/// App-session state for automatic chain switching (TAS-245).
///
/// `/home` keys MainScreen by uid + org + company, so every chain switch
/// builds a NEW MainScreen state. What must survive a switch lives here.
class ChainAutoSwitchSession {
  ChainAutoSwitchSession._();

  /// Tab the next MainScreen opens on (consumed once).
  static int? _pendingTab;

  /// Delegate uid for which automatic switching is paused (after a manual
  /// chain pick or an undo). Tied to the uid so another login starts fresh.
  static String? _pausedForUid;

  static void openTabAfterSwitch(int tab) => _pendingTab = tab;

  static int? takePendingTab() {
    final t = _pendingTab;
    _pendingTab = null;
    return t;
  }

  static void pause(String uid) => _pausedForUid = uid;

  static bool isPaused(String uid) => _pausedForUid == uid;
}
