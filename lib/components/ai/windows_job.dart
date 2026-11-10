import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// kernel32 bindings (Windows only; nothing here runs on Android).
typedef _CreateJobC = IntPtr Function(Pointer<Void>, Pointer<Utf16>);
typedef _CreateJobD = int Function(Pointer<Void>, Pointer<Utf16>);
typedef _SetInfoC = Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32);
typedef _SetInfoD = int Function(int, int, Pointer<Void>, int);
typedef _OpenProcC = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenProcD = int Function(int, int, int);
typedef _AssignC = Int32 Function(IntPtr, IntPtr);
typedef _AssignD = int Function(int, int);
typedef _CloseC = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);

/// Makes Windows kill child processes when this app's process ends,
/// however it ends (X button, End Task, crash, debugger stop).
abstract final class WindowsJob {
  static int _job = 0;
  static bool _failed = false;

  /// Puts the process with [pid] into the app's kill-on-close job.
  static void adopt(int pid) {
    if (!Platform.isWindows || _failed) return;
    try {
      final k32 = DynamicLibrary.open('kernel32.dll');
      if (_job == 0) {
        final create = k32.lookupFunction<_CreateJobC, _CreateJobD>(
          'CreateJobObjectW',
        );
        final setInfo = k32.lookupFunction<_SetInfoC, _SetInfoD>(
          'SetInformationJobObject',
        );
        _job = create(nullptr, nullptr);
        if (_job == 0) throw StateError('CreateJobObject failed');

        // JOBOBJECT_EXTENDED_LIMIT_INFORMATION is 144 bytes on 64-bit.
        // LimitFlags sits at offset 16; 0x2000 = KILL_ON_JOB_CLOSE.
        final info = calloc<Uint8>(144);
        try {
          (info.cast<Uint32>() + 4).value = 0x2000;
          // 9 = JobObjectExtendedLimitInformation
          if (setInfo(_job, 9, info.cast(), 144) == 0) {
            throw StateError('SetInformationJobObject failed');
          }
        } finally {
          calloc.free(info);
        }
      }
      final open = k32.lookupFunction<_OpenProcC, _OpenProcD>('OpenProcess');
      final assign = k32.lookupFunction<_AssignC, _AssignD>(
        'AssignProcessToJobObject',
      );
      final close = k32.lookupFunction<_CloseC, _CloseD>('CloseHandle');

      // PROCESS_SET_QUOTA (0x100) | PROCESS_TERMINATE (0x1)
      final h = open(0x0101, 0, pid);
      if (h != 0) {
        assign(_job, h);
        close(h);
      }
      // _job is deliberately never closed: it must live as long as the app.
    } catch (_) {
      _failed =
          true; // best effort; the normal exit path still tries to stop it
    }
  }
}
