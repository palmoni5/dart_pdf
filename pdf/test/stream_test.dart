/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:test/test.dart';

void main() {
  group('PdfStream', () {
    test('putStream copies written bytes, not spare capacity', () {
      final source = PdfStream()..putBytes([1, 2, 3]);
      final target = PdfStream()
        ..putByte(9)
        ..putStream(source)
        ..putByte(8);

      expect(target.offset, 5);
      expect(target.output(), [9, 1, 2, 3, 8]);
    });

    test('putStream also supports appending the stream to itself', () {
      final stream = PdfStream()..putBytes([1, 2, 3]);
      stream.putStream(stream);

      expect(stream.offset, 6);
      expect(stream.output(), [1, 2, 3, 1, 2, 3]);
    });

    test('grows across several capacity boundaries without losing bytes', () {
      final stream = PdfStream();
      final chunk = Uint8List.fromList(
        List<int>.generate(4096, (index) => index % 251),
      );
      for (var i = 0; i < 160; i++) {
        stream.putBytes(chunk);
      }

      expect(stream.offset, chunk.length * 160);
      final output = stream.output();
      expect(output.length, chunk.length * 160);
      for (var i = 0; i < 160; i++) {
        expect(
          Uint8List.sublistView(
            output,
            i * chunk.length,
            (i + 1) * chunk.length,
          ),
          chunk,
        );
      }
    });
  });
}
