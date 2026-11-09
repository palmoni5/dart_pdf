import 'dart:io';

void reportPrintingFootprint(int processRssBefore) {
  try {
    var privateMapping = false;
    var privateRssKiB = 0;
    String? privatePath;
    for (final line in File('/proc/self/smaps').readAsLinesSync()) {
      if (RegExp(r'^[0-9a-f]+-[0-9a-f]+ ').hasMatch(line)) {
        privateMapping = line.endsWith('/libpdfium_printing.so');
        if (privateMapping) {
          privatePath = line.substring(line.indexOf('/'));
        }
      } else if (privateMapping && line.startsWith('Rss:')) {
        privateRssKiB += int.parse(line.split(RegExp(r'\s+'))[1]);
      }
    }
    final diskBytes =
        privatePath == null ? null : File(privatePath).lengthSync();
    // Process RSS includes worker, raster and Dart buffers; mapped RSS is PDFium only.
    // ignore: avoid_print
    print('Printing footprint: privateDiskBytes=$diskBytes '
        'privateMappedRssKiB=$privateRssKiB '
        'processRssBefore=$processRssBefore processRssAfter=${ProcessInfo.currentRss}');
  } on FileSystemException catch (error) {
    // Diagnostics must not turn an unavailable procfs into a raster test failure.
    // ignore: avoid_print
    print('Printing footprint unavailable: $error');
  }
}
