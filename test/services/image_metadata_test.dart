import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:fosscanner/services/image_metadata.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('reads encoded dimensions without decoding the full image', () async {
    final bytes = File('assets/icon/icon.png').readAsBytesSync();

    final size = await readEncodedImageSize(bytes);

    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    expect(() => validateSourceImageSize(size), returnsNormally);
  });

  test('reads an XFile stream bounded to its declared length', () async {
    final file = XFile('assets/icon/icon.png');
    final length = await file.length();

    final bytes = await readBoundedBytes(file.openRead(0, length));
    final size = await readEncodedImageSize(bytes);

    expect(bytes, isNotEmpty);
    expect(size.width, greaterThan(0));
  });

  test('stops accumulating encoded data at the byte limit', () async {
    final stream = Stream.fromIterable([
      Uint8List.fromList(const [1, 2]),
      Uint8List.fromList(const [3, 4]),
    ]);

    await expectLater(
      readBoundedBytes(stream, maxBytes: 3),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('rejects source images whose decoded allocation is too large', () {
    expect(
      () => validateSourceImageSize(
        const Size(maxSourceImageEdge + 1, maxSourceImageEdge + 1),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('rejects malformed source dimensions', () {
    for (final size in [
      Size.zero,
      const Size(double.infinity, 100),
      const Size(double.nan, 100),
    ]) {
      expect(
        () => validateSourceImageSize(size),
        throwsA(isA<FormatException>()),
        reason: '$size',
      );
    }
  });
}
