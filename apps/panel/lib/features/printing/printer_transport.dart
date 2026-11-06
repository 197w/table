import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:table_core/table_core.dart';

// Wysyłanie gotowych poleceń do drukarki bez sterownika rysującego strony („RAW”): drukarka systemowa
// (Windows: bufor wydruku przez winspool, macOS: CUPS przez `lp -o raw`) albo drukarka w sieci (port 9100).

/// Błąd drukowania z polskim komunikatem dla obsługi (powiadomienie pokazuje go jak inne błędy panelu).
class PrinterException extends AppFailure {
  const PrinterException(super.message);
}

/// Drukarka systemowa (nazwa kolejki) albo sieciowa (adres i port).
typedef PrinterTarget = ({bool network, String name, String host, int port});

abstract final class PrinterTransport {
  /// Drukarki systemowe są tylko na komputerze; na tablecie zostaje drukarka sieciowa.
  static bool get supportsSystem => Platform.isWindows || Platform.isMacOS;

  /// Nazwy drukarek zainstalowanych w systemie.
  static Future<List<String>> systemPrinters() async {
    if (Platform.isWindows) return _WinSpool.printers();
    if (Platform.isMacOS) {
      final result = await Process.run('lpstat', ['-e']);
      if (result.exitCode != 0) return const [];
      return [
        for (final line in (result.stdout as String).split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
    }
    return const [];
  }

  static Future<void> send(PrinterTarget target, Uint8List data, {String job = 'Table: etykiety'}) async {
    if (target.network) return _sendNetwork(target.host, target.port, data);
    if (target.name.isEmpty) throw const PrinterException('Wybierz drukarkę etykiet.');
    if (Platform.isWindows) {
      _WinSpool.send(target.name, data, job);
      return;
    }
    if (Platform.isMacOS) return _sendCups(target.name, data, job);
    throw const PrinterException('Na tym urządzeniu działa tylko drukarka sieciowa.');
  }

  static Future<void> _sendNetwork(String host, int port, Uint8List data) async {
    if (host.trim().isEmpty) throw const PrinterException('Wpisz adres IP drukarki.');
    Socket socket;
    try {
      socket = await Socket.connect(host.trim(), port, timeout: const Duration(seconds: 5));
    } on SocketException {
      throw PrinterException('Drukarka $host:$port nie odpowiada. Sprawdź, czy jest włączona i w tej samej sieci.');
    }
    try {
      socket.add(data);
      await socket.flush();
    } on SocketException {
      throw PrinterException('Połączenie z drukarką $host:$port zerwało się w trakcie wydruku.');
    } finally {
      await socket.close();
      socket.destroy();
    }
  }

  static Future<void> _sendCups(String name, Uint8List data, String job) async {
    final dir = await Directory.systemTemp.createTemp('table_etykiety');
    try {
      final file = File('${dir.path}/etykiety.prn');
      await file.writeAsBytes(data, flush: true);
      final result = await Process.run('lp', ['-d', name, '-t', job, '-o', 'raw', file.path]);
      if (result.exitCode != 0) {
        final reason = (result.stderr as String).trim();
        throw PrinterException('Drukarka „$name” nie przyjęła wydruku${reason.isEmpty ? '' : ': $reason'}.');
      }
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }
}

// Windows: winspool.drv przez FFI. Zadanie z typem danych „RAW” trafia do drukarki bez zmian, jak w programach
// do etykiet (sterownik Xprinter ma domyślnie RAW).

final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

final class _PrinterInfo4 extends Struct {
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pServerName;
  @Uint32()
  external int attributes;
}

abstract final class _WinSpool {
  static final _lib = DynamicLibrary.open('winspool.drv');

  static final _enumPrinters = _lib.lookupFunction<
    Int32 Function(Uint32, Pointer<Utf16>, Uint32, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint32>),
    int Function(int, Pointer<Utf16>, int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint32>)
  >('EnumPrintersW');
  static final _openPrinter = _lib.lookupFunction<
    Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
    int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)
  >('OpenPrinterW');
  static final _startDoc = _lib.lookupFunction<
    Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo1>),
    int Function(int, int, Pointer<_DocInfo1>)
  >('StartDocPrinterW');
  static final _startPage = _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('StartPagePrinter');
  static final _write = _lib.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
  >('WritePrinter');
  static final _endPage = _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndPagePrinter');
  static final _endDoc = _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndDocPrinter');
  static final _close = _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('ClosePrinter');

  static final _lastError = DynamicLibrary.open('kernel32.dll').lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
    isLeaf: true,
  );

  /// Kod błędu Windows do komunikatu (np. „kod 5”), żeby dało się sprawdzić przyczynę.
  static String _code() => ' (kod Windows ${_lastError()})';

  static const _enumLocal = 0x2;
  static const _enumConnections = 0x4;

  static List<String> printers() {
    final needed = calloc<Uint32>();
    final returned = calloc<Uint32>();
    try {
      const flags = _enumLocal | _enumConnections;
      _enumPrinters(flags, nullptr, 4, nullptr, 0, needed, returned);
      if (needed.value == 0) return const [];
      final buffer = calloc<Uint8>(needed.value);
      try {
        if (_enumPrinters(flags, nullptr, 4, buffer, needed.value, needed, returned) == 0) return const [];
        final infos = buffer.cast<_PrinterInfo4>();
        return [
          for (var i = 0; i < returned.value; i++)
            if (infos[i].pPrinterName != nullptr) infos[i].pPrinterName.toDartString(),
        ];
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc
        ..free(needed)
        ..free(returned);
    }
  }

  static void send(String printer, Uint8List data, String job) {
    final name = printer.toNativeUtf16();
    final handle = calloc<IntPtr>();
    final doc = calloc<_DocInfo1>();
    final docName = job.toNativeUtf16();
    final dataType = 'RAW'.toNativeUtf16();
    final bytes = calloc<Uint8>(data.length);
    final written = calloc<Uint32>();
    try {
      if (_openPrinter(name, handle, nullptr) == 0) {
        throw PrinterException('Nie ma drukarki „$printer” w systemie. Wybierz ją jeszcze raz w „Drukarki”.');
      }
      final h = handle.value;
      try {
        doc.ref
          ..pDocName = docName
          ..pOutputFile = nullptr
          ..pDatatype = dataType;
        if (_startDoc(h, 1, doc) == 0) {
          throw PrinterException('Drukarka „$printer” nie przyjęła wydruku${_code()}.');
        }
        try {
          _startPage(h);
          bytes.asTypedList(data.length).setAll(0, data);
          final ok = _write(h, bytes, data.length, written);
          _endPage(h);
          if (ok == 0 || written.value != data.length) {
            throw PrinterException('Wydruk do „$printer” przerwał się w trakcie wysyłania${_code()}.');
          }
        } finally {
          _endDoc(h);
        }
      } finally {
        _close(h);
      }
    } finally {
      calloc
        ..free(name)
        ..free(handle)
        ..free(doc)
        ..free(docName)
        ..free(dataType)
        ..free(bytes)
        ..free(written);
    }
  }
}
