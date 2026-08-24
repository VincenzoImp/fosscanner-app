import 'dart:typed_data';
import 'dart:ui' as ui;

/// Bound source decoding as well as perspective-corrected output. OpenCV
/// decodes compressed inputs into multi-byte native Mats, so compressed file
/// size alone is not a safe allocation limit.
const maxSourceImagePixels = 20000000;
const maxSourceImageEdge = 8192;
const maxEncodedImageBytes = 32 * 1024 * 1024;

Future<Uint8List> readBoundedBytes(
  Stream<List<int>> stream, {
  int maxBytes = maxEncodedImageBytes,
}) async {
  if (maxBytes < 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must not be negative');
  }

  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (chunk.length > maxBytes - bytes.length) {
      throw UnsupportedError(
        'Encoded image exceeds the supported $maxBytes byte limit',
      );
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

Future<ui.Size> readEncodedImageSize(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return ui.Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

void validateSourceImageSize(ui.Size size) {
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    throw const FormatException('Image dimensions must be finite and positive');
  }

  if (size.width > maxSourceImageEdge ||
      size.height > maxSourceImageEdge ||
      size.width * size.height > maxSourceImagePixels) {
    throw UnsupportedError(
      'Image dimensions exceed the supported ${maxSourceImageEdge}px edge '
      'or $maxSourceImagePixels pixel limit',
    );
  }
}
