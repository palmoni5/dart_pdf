/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:io';

import 'package:pdf/src/pdf/font/ttf_parser.dart';
import 'package:pdf/src/pdf/font/ttf_writer.dart';
import 'package:test/test.dart';

/// Subsets [chars] and returns, for each char, the outline bytes stored in its
/// subset slot next to the outline bytes of its glyph in the original font.
List<(List<int>, List<int>)> subsetOutlines(String fontFile, List<int> chars) {
  final ttf = TtfParser(File(fontFile).readAsBytesSync().buffer.asByteData());
  final subset = TtfParser(TtfWriter(ttf).withChars(chars).buffer.asByteData());

  return [
    for (var slot = 0; slot < chars.length; slot++)
      (
        subset.readGlyph(slot).data,
        ttf.readGlyph(ttf.charToGlyphIndexMap[chars[slot]] ?? 0).data,
      ),
  ];
}

void main() {
  for (final fontFile in ['noto-sans.ttf', 'genyomintw.ttf']) {
    for (final chars in [
      [0, 0x41, 0x20, 0xA0, 0x42],
      [0, 0x41, 0xA0, 0x20, 0x42],
    ]) {
      test('$fontFile keeps space and no-break space empty in $chars', () {
        final ttf = TtfParser(
          File(fontFile).readAsBytesSync().buffer.asByteData(),
        );
        expect(ttf.charToGlyphIndexMap[0xA0], ttf.charToGlyphIndexMap[0x20]);
        expect(ttf.readGlyph(ttf.charToGlyphIndexMap[0x20]!).data, isEmpty);

        final outlines = subsetOutlines(fontFile, chars);
        for (var slot = 1; slot < chars.length; slot++) {
          final (actual, expected) = outlines[slot];
          expect(
            actual,
            expected,
            reason: 'U+${chars[slot].toRadixString(16)}',
          );
        }
        expect(outlines[chars.indexOf(0x20)].$1, isEmpty);
        expect(outlines[chars.indexOf(0xA0)].$1, isEmpty);
        expect(outlines[chars.indexOf(0x41)].$1, isNotEmpty);
      });
    }
  }

  test('Two chars sharing a visible glyph both get that glyph', () {
    // Roboto maps U+03A9 (Omega) and U+2126 (Ohm sign) to the same glyph.
    final chars = [0, 0x41, 0x3A9, 0x2126, 0x42];
    final outlines = subsetOutlines('roboto.ttf', chars);
    expect(outlines[2].$2, isNotEmpty);
    expect(outlines[2].$1, outlines[2].$2);
    expect(outlines[3].$1, outlines[3].$2);
  });

  test('Chars missing from the font get .notdef, not another glyph', () {
    // Hacen Tunisia has no combining hamza (U+0654, U+0655), which the Arabic
    // reshaper emits for hamza with harakat; U+064D is kasratan.
    final chars = [0, 0x655, 0x654, 0x64D];
    final outlines = subsetOutlines('hacen-tunisia.ttf', chars);
    final notdef = outlines[0].$1;
    expect(notdef, isNotEmpty);
    expect(outlines[1].$1, notdef);
    expect(outlines[2].$1, notdef);
    expect(outlines[3].$1, outlines[3].$2);
    expect(outlines[3].$1, isNot(notdef));
  });
}
