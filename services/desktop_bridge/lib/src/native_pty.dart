import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

// ignore_for_file: constant_identifier_names

import 'package:ffi/ffi.dart';

/// A real Unix pseudo-terminal backed by `posix_spawn` and a PTY master fd.
///
/// This intentionally avoids `fork()` in the Dart VM. The child is created by
/// `posix_spawn` with its stdio opened on the PTY slave, which also gives it a
/// controlling terminal. All reads are non-blocking and polled by a timer.
final class NativePty {
  NativePty._({
    required int pid,
    required int master,
    required int columns,
    required int rows,
  }) : _pid = pid,
       _master = master,
       _columns = columns,
       _rows = rows {
    _setNonBlocking(master);
    _poll = Timer.periodic(const Duration(milliseconds: 12), (_) => _tick());
  }

  final int _pid;
  final int _master;
  final int _columns;
  final int _rows;
  final _output = StreamController<List<int>>.broadcast();
  final _exit = Completer<int>();
  final _writeQueue = <int>[];
  Timer? _poll;
  Timer? _writeRetry;
  bool _closed = false;
  int _columnsNow = 0;
  int _rowsNow = 0;

  int get pid => _pid;
  int get columns => _columnsNow == 0 ? _columns : _columnsNow;
  int get rows => _rowsNow == 0 ? _rows : _rowsNow;
  Stream<List<int>> get output => _output.stream;
  Future<int> get exitCode => _exit.future;
  bool get isClosed => _closed;

  static NativePty start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    int columns = 100,
    int rows = 32,
  }) {
    if (Platform.isWindows) {
      throw UnsupportedError(
        'NativePty is only available on Unix. Use the Windows fallback.',
      );
    }
    final libc = DynamicLibrary.process();

    final open = libc.lookupFunction<
      Int32 Function(Pointer<Utf8>, Int32),
      int Function(Pointer<Utf8>, int)
    >('open');
    final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
      'close',
    );
    final grantpt = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
      'grantpt',
    );
    final unlockpt = libc.lookupFunction<
      Int32 Function(Int32),
      int Function(int)
    >('unlockpt');
    final ptsname = libc.lookupFunction<
      Pointer<Utf8> Function(Int32),
      Pointer<Utf8> Function(int)
    >('ptsname');
    final ioctl = libc.lookupFunction<
      Int32 Function(Int32, Uint64, Pointer<Void>),
      int Function(int, int, Pointer<Void>)
    >('ioctl');

    final spawn = libc.lookupFunction<
      Int32 Function(
        Pointer<Int32>,
        Pointer<Utf8>,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      ),
      int Function(
        Pointer<Int32>,
        Pointer<Utf8>,
        Pointer<Void>,
        Pointer<Void>,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
      )
    >('posix_spawn');
    final actionsInit = libc.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('posix_spawn_file_actions_init');
    final actionsDestroy = libc.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('posix_spawn_file_actions_destroy');
    final actionsAddOpen = libc.lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>, Int32, Uint32),
      int Function(Pointer<Void>, int, Pointer<Utf8>, int, int)
    >('posix_spawn_file_actions_addopen');
    final actionsAddClose = libc.lookupFunction<
      Int32 Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)
    >('posix_spawn_file_actions_addclose');
    final actionsAddChdir = libc.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Utf8>),
      int Function(Pointer<Void>, Pointer<Utf8>)
    >('posix_spawn_file_actions_addchdir_np');
    final attrInit = libc.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('posix_spawnattr_init');
    final attrDestroy = libc.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)
    >('posix_spawnattr_destroy');
    final attrSetFlags = libc.lookupFunction<
      Int32 Function(Pointer<Void>, Int16),
      int Function(Pointer<Void>, int)
    >('posix_spawnattr_setflags');

    final ptmx = '/dev/ptmx'.toNativeUtf8();
    final master = open(ptmx, O_RDWR | O_NOCTTY);
    malloc.free(ptmx);
    if (master < 0) {
      throw const ProcessException('open', ['/dev/ptmx'], 'Could not open PTY');
    }

    var ok = false;
    try {
      if (grantpt(master) != 0 || unlockpt(master) != 0) {
        throw const ProcessException(
          'grantpt',
          [],
          'Could not initialize PTY',
        );
      }
      final slaveNamePtr = ptsname(master);
      if (slaveNamePtr == nullptr) {
        throw const ProcessException('ptsname', [], 'Could not name PTY');
      }
      final slaveName = slaveNamePtr.toDartString();

      final winsize = calloc<Uint16>(4);
      winsize[0] = rows;
      winsize[1] = columns;
      ioctl(master, TIOCSWINSZ, winsize.cast<Void>());
      calloc.free(winsize);

      final actions = calloc<Uint8>(1024).cast<Void>();
      final attr = calloc<Uint8>(1024).cast<Void>();
      actionsInit(actions);
      attrInit(attr);
      final flags = Platform.isMacOS ? POSIX_SPAWN_SETSID_MACOS : 0x80;
      attrSetFlags(attr, flags);

      final slaveC = slaveName.toNativeUtf8();
      actionsAddOpen(actions, 0, slaveC, O_RDWR, 0);
      actionsAddOpen(actions, 1, slaveC, O_RDWR, 0);
      actionsAddOpen(actions, 2, slaveC, O_RDWR, 0);
      actionsAddClose(actions, master);
      malloc.free(slaveC);

      Pointer<Utf8>? workdirC;
      if (workingDirectory != null && workingDirectory.isNotEmpty) {
        workdirC = workingDirectory.toNativeUtf8();
        actionsAddChdir(actions, workdirC);
      }

      final argv = calloc<Pointer<Utf8>>(arguments.length + 2);
      final argvAllocated = <Pointer<Utf8>>[];
      final exeC = executable.toNativeUtf8();
      argv[0] = exeC;
      argvAllocated.add(exeC);
      for (var i = 0; i < arguments.length; i++) {
        final value = arguments[i].toNativeUtf8();
        argv[i + 1] = value;
        argvAllocated.add(value);
      }
      argv[arguments.length + 1] = nullptr;

      final env = environment ?? Platform.environment;
      final envp = calloc<Pointer<Utf8>>(env.length + 1);
      final envAllocated = <Pointer<Utf8>>[];
      var envIndex = 0;
      for (final entry in env.entries) {
        final value = '${entry.key}=${entry.value}'.toNativeUtf8();
        envp[envIndex++] = value;
        envAllocated.add(value);
      }
      envp[env.length] = nullptr;

      final pidPtr = calloc<Int32>();
      final result = spawn(
        pidPtr,
        exeC,
        actions,
        attr,
        argv,
        envp,
      );

      actionsDestroy(actions);
      attrDestroy(attr);
      calloc.free(actions);
      calloc.free(attr);

      for (final value in argvAllocated) {
        malloc.free(value);
      }
      calloc.free(argv);
      for (final value in envAllocated) {
        malloc.free(value);
      }
      calloc.free(envp);
      if (workdirC != null) malloc.free(workdirC);

      if (result != 0) {
        calloc.free(pidPtr);
        throw ProcessException(
          executable,
          arguments,
          'posix_spawn failed with error $result',
          result,
        );
      }
      final pid = pidPtr.value;
      calloc.free(pidPtr);
      if (pid <= 0) {
        throw ProcessException(executable, arguments, 'posix_spawn failed');
      }

      ok = true;
      return NativePty._(
        pid: pid,
        master: master,
        columns: columns,
        rows: rows,
      );
    } finally {
      if (!ok) close(master);
    }
  }

  void _tick() {
    if (_closed) return;
    try {
      _tickInner();
    } on Object {
      // A transient FFI failure must not stop the polling timer.
    }
  }

  void _tickInner() {
    final libc = DynamicLibrary.process();
    final read = libc.lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
      int Function(int, Pointer<Uint8>, int)
    >('read');
    final waitpid = libc.lookupFunction<
      Int32 Function(Int32, Pointer<Int32>, Int32),
      int Function(int, Pointer<Int32>, int)
    >('waitpid');
    final kill = libc.lookupFunction<
      Int32 Function(Int32, Int32),
      int Function(int, int)
    >('kill');
    final status = calloc<Int32>();
    final waited = waitpid(_pid, status, 1);
    if (waited == _pid) {
      final raw = status.value;
      calloc.free(status);
      _readAll(read);
      _finish(_exitCodeFromStatus(raw));
      return;
    }
    calloc.free(status);
    if (waited == -1) {
      // The Dart VM reaps child processes of the host application on some
      // platforms, which makes our waitpid return ECHILD. Fall back to
      // checking whether the pid still exists so the session can finish.
      if (kill(_pid, 0) != 0) {
        _readAll(read);
        _finish(-1);
        return;
      }
    }
    _readAll(read);
    _flushWrites();
  }

  void _readAll(
    int Function(int, Pointer<Uint8>, int) read,
  ) {
    final buffer = calloc<Uint8>(8192);
    try {
      while (true) {
        final count = read(_master, buffer, 8192);
        if (count <= 0) break;
        _output.add(Uint8List.fromList(buffer.asTypedList(count)));
      }
    } finally {
      calloc.free(buffer);
    }
  }

  int _exitCodeFromStatus(int raw) {
    final signal = raw & 0x7f;
    if (signal == 0) return (raw >> 8) & 0xff;
    return 128 + signal;
  }

  void _finish(int code) {
    if (_closed) return;
    _closed = true;
    _poll?.cancel();
    _writeRetry?.cancel();
    DynamicLibrary.process().lookupFunction<
      Int32 Function(Int32),
      int Function(int)
    >('close')(_master);
    if (!_exit.isCompleted) _exit.complete(code);
    _output.close();
  }

  void _setNonBlocking(int fd) {
    final libc = DynamicLibrary.process();
    final fcntl = libc.lookupFunction<
      Int32 Function(Int32, Int32, Int32),
      int Function(int, int, int)
    >('fcntl');
    final flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  }

  void _flushWrites() {
    if (_writeQueue.isEmpty || _closed) return;
    final libc = DynamicLibrary.process();
    final write = libc.lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
      int Function(int, Pointer<Uint8>, int)
    >('write');
    final bytes = Uint8List.fromList(_writeQueue);
    final buffer = calloc<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    var offset = 0;
    var failed = false;
    try {
      while (offset < bytes.length) {
        final count = write(_master, buffer + offset, bytes.length - offset);
        if (count <= 0) {
          failed = true;
          break;
        }
        offset += count;
      }
    } finally {
      calloc.free(buffer);
    }
    _writeQueue.removeRange(0, offset);
    if (_writeQueue.isNotEmpty || failed) {
      _writeRetry ??= Timer(const Duration(milliseconds: 15), () {
        _writeRetry = null;
        _flushWrites();
      });
    }
  }

  void write(List<int> data) {
    if (_closed || data.isEmpty) return;
    if (_writeQueue.length + data.length > 1024 * 1024) return;
    _writeQueue.addAll(data);
    _flushWrites();
  }

  void resize(int columns, int rows) {
    if (_closed) return;
    _columnsNow = columns.clamp(1, 500);
    _rowsNow = rows.clamp(1, 300);
    final libc = DynamicLibrary.process();
    final ioctl = libc.lookupFunction<
      Int32 Function(Int32, Uint64, Pointer<Void>),
      int Function(int, int, Pointer<Void>)
    >('ioctl');
    final winsize = calloc<Uint16>(4);
    winsize[0] = _rowsNow;
    winsize[1] = _columnsNow;
    ioctl(_master, TIOCSWINSZ, winsize.cast<Void>());
    calloc.free(winsize);
  }

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_closed) return false;
    final libc = DynamicLibrary.process();
    final kill = libc.lookupFunction<
      Int32 Function(Int32, Int32),
      int Function(int, int)
    >('kill');
    final sig = signal == ProcessSignal.sigkill
        ? 9
        : signal == ProcessSignal.sigint
        ? 2
        : 15;
    var result = kill(-_pid, sig);
    if (result != 0) result = kill(_pid, sig);
    return result == 0;
  }

  void dispose() {
    if (_closed) {
      _output.close();
      return;
    }
    kill(ProcessSignal.sigkill);
    _finish(-1);
  }
}

const int O_RDWR = 2;
const int O_NOCTTY = 0x100;
const int O_NONBLOCK = 0x800;
const int F_GETFL = 3;
const int F_SETFL = 4;
const int TIOCSWINSZ = 0x5414;
const int POSIX_SPAWN_SETSID_MACOS = 0x0400;
