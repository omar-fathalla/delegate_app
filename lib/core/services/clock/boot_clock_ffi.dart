import 'dart:ffi';
import 'dart:io' show Platform;

import 'boot_clock.dart';

final class _Timespec extends Struct {
  @Long()
  external int tvSec;
  @Long()
  external int tvNsec;
}

typedef _ClockGettimeC = Int32 Function(Int32, Pointer<_Timespec>);
typedef _ClockGettimeDart = int Function(int, Pointer<_Timespec>);
typedef _MallocC = Pointer<Void> Function(IntPtr);
typedef _MallocDart = Pointer<Void> Function(int);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

/// `clock_gettime` from libc through dart:ffi (no plugin, no native code,
/// no extra package: malloc/free come from libc too).
class _FfiBootClock implements BootClock {
  _FfiBootClock(this._clockId, this._fn, this._malloc, this._free);

  final int _clockId;
  final _ClockGettimeDart _fn;
  final _MallocDart _malloc;
  final _FreeDart _free;

  @override
  int? elapsedMs() {
    final raw = _malloc(sizeOf<_Timespec>());
    if (raw == nullptr) return null;
    final ts = raw.cast<_Timespec>();
    try {
      if (_fn(_clockId, ts) != 0) return null;
      return ts.ref.tvSec * 1000 + ts.ref.tvNsec ~/ 1000000;
    } catch (_) {
      return null;
    } finally {
      _free(raw);
    }
  }
}

class _NoBootClock implements BootClock {
  @override
  int? elapsedMs() => null;
}

// Linux/Android CLOCK_BOOTTIME = 7; Darwin CLOCK_MONOTONIC = 6.
const int _linuxBootTime = 7;
const int _darwinMonotonic = 6;

BootClock createSystemBootClock() {
  try {
    final int id;
    if (Platform.isAndroid || Platform.isLinux) {
      id = _linuxBootTime;
    } else if (Platform.isIOS || Platform.isMacOS) {
      id = _darwinMonotonic;
    } else {
      return _NoBootClock();
    }
    final libc = DynamicLibrary.process();
    return _FfiBootClock(
      id,
      libc.lookupFunction<_ClockGettimeC, _ClockGettimeDart>('clock_gettime'),
      libc.lookupFunction<_MallocC, _MallocDart>('malloc'),
      libc.lookupFunction<_FreeC, _FreeDart>('free'),
    );
  } catch (_) {
    return _NoBootClock();
  }
}
