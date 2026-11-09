import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'linux_printing_footprint.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux raster keeps the Dart event loop responsive',
      (tester) async {
    final document = pw.Document();
    for (var page = 0; page < 60; page++) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(
            child: pw.Text('Raster worker page $page'),
          ),
        ),
      );
    }
    final bytes = await document.save();

    var timerTicks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => timerTicks++,
    );

    final rssBefore = ProcessInfo.currentRss;
    var rasterized = 0;
    final stopwatch = Stopwatch()..start();
    await for (final _ in Printing.raster(bytes, dpi: 144)) {
      rasterized++;
    }
    stopwatch.stop();
    timer.cancel();

    reportPrintingFootprint(rssBefore);
    expect(rasterized, 60);
    // Rastering dozens of A4 pages is deliberately long enough that a
    // synchronous native method handler starves this timer completely.
    expect(
      timerTicks,
      greaterThan(2),
      reason: 'Dart timer did not run while native rastering took '
          '${stopwatch.elapsedMilliseconds} ms',
    );
  });
  testWidgets('Malformed PDF fails promptly and native state can be reused',
      (tester) async {
    final malformed = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    await expectLater(
      Printing.raster(Uint8List(0))
          .toList()
          .timeout(const Duration(seconds: 15)),
      throwsA(isNot(isA<TimeoutException>())),
    );
    for (var attempt = 0; attempt < 3; attempt++) {
      await expectLater(
        Printing.raster(malformed)
            .toList()
            .timeout(const Duration(seconds: 15)),
        throwsA(isNot(isA<TimeoutException>())),
      );
    }

    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (_) => pw.Center(child: pw.Text('Recovery')),
      ),
    );
    final valid = await document.save();
    for (var attempt = 0; attempt < 3; attempt++) {
      expect(
        await Printing.raster(valid)
            .length
            .timeout(const Duration(seconds: 15)),
        1,
      );
    }
  });

  testWidgets(
      'Cancelling a Dart raster subscription does not poison later jobs',
      (tester) async {
    final document = pw.Document();
    for (var i = 0; i < 12; i++) {
      document.addPage(
        pw.Page(
          build: (_) => pw.Center(child: pw.Text('Cancellation $i')),
        ),
      );
    }
    final bytes = await document.save();
    final first = await Printing.raster(bytes, dpi: 144)
        .take(1)
        .toList()
        .timeout(const Duration(seconds: 20));
    expect(first, hasLength(1));

    // The native raster task is allowed to finish; the next task must still
    // complete normally even if Dart cancelled its page subscription.
    final pages = await Printing.raster(bytes)
        .toList()
        .timeout(const Duration(seconds: 30));
    expect(pages, hasLength(12));
  });

  testWidgets('PDFium 8125 remains live through isolated printing 5200 jobs',
      (tester) async {
    final publicPath = Platform.environment['PRINTING_PUBLIC_PDFIUM'];
    expect(
      publicPath,
      isNotNull,
      reason: 'A real Chromium/8125 Linux binary must be supplied by CI.',
    );
    final publicLibrary = DynamicLibrary.open(publicPath!);
    final init = publicLibrary.lookupFunction<Void Function(), void Function()>(
      'FPDF_InitLibrary',
    );
    final destroy =
        publicLibrary.lookupFunction<Void Function(), void Function()>(
      'FPDF_DestroyLibrary',
    );
    final load = publicLibrary.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, IntPtr, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, int, Pointer<Void>)>(
      'FPDF_LoadMemDocument64',
    );
    final pageCount = publicLibrary.lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('FPDF_GetPageCount');
    final close = publicLibrary.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>(
      'FPDF_CloseDocument',
    );

    final document = pw.Document();
    for (var i = 0; i < 24; i++) {
      document.addPage(
        pw.Page(
          build: (_) => pw.Center(child: pw.Text('PDFium coexistence $i')),
        ),
      );
    }
    final bytes = await document.save();
    final ownedBytes = calloc<Uint8>(bytes.length);
    ownedBytes.asTypedList(bytes.length).setAll(0, bytes);

    Pointer<Void> publicDocument = nullptr;
    Timer? publicPoller;
    var publicChecks = 0;
    init();
    try {
      publicDocument = load(ownedBytes.cast<Void>(), bytes.length, nullptr);
      expect(publicDocument, isNot(nullptr));
      expect(pageCount(publicDocument), 24);

      // The 8125 document is kept open in the ELF base namespace while the
      // printing plugin repeatedly initializes/renders/destroys its private
      // 5200 instance in a distinct dlmopen namespace.
      publicPoller = Timer.periodic(const Duration(milliseconds: 5), (_) {
        expect(pageCount(publicDocument), 24);
        publicChecks++;
      });
      for (var attempt = 0; attempt < 3; attempt++) {
        final result = await Printing.raster(bytes, dpi: 108)
            .length
            .timeout(const Duration(seconds: 30));
        expect(result, 24);
        expect(pageCount(publicDocument), 24);
      }
      expect(publicChecks, greaterThan(2));
    } finally {
      publicPoller?.cancel();
      if (publicDocument != nullptr) {
        close(publicDocument);
      }
      destroy();
      calloc.free(ownedBytes);
    }
  });
}
