import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int _maxImageSide = 16384;
const int _maxImagePixels = 40000000;

Future<Uint8List> prepareMapImage(Uint8List raw) async {
  _inspectImageDimensions(raw);
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw const FormatException(
      'Could not read that image. Please choose a PNG, JPEG, or WEBP map image.',
    );
  }

  img.Image working = decoded;
  final longestSide = working.width > working.height ? working.width : working.height;
  if (longestSide > 2048) {
    if (working.width >= working.height) {
      working = img.copyResize(working, width: 2048);
    } else {
      working = img.copyResize(working, height: 2048);
    }
  }

  for (var quality = 90; quality >= 25; quality -= 5) {
    final encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    if (encoded.lengthInBytes <= 600000) {
      return encoded;
    }
  }

  throw const FormatException(
    'That image is too large after compression. Try a smaller or simpler image.',
  );
}

({int width, int height}) imageSize(Uint8List raw) {
  return _inspectImageDimensions(raw);
}

({int width, int height}) _inspectImageDimensions(Uint8List raw) {
  final decoder = img.findDecoderForData(raw);
  final info = decoder?.startDecode(raw);
  if (info == null) {
    throw const FormatException(
      'Could not read that image. Please choose a PNG, JPEG, or WEBP map image.',
    );
  }
  final width = info.width;
  final height = info.height;
  if (width < 1 || height < 1) {
    throw const FormatException(
      'That image has invalid dimensions.',
    );
  }
  if (width > _maxImageSide || height > _maxImageSide) {
    throw const FormatException(
      'That image is too large. Maximum width or height is 16384 pixels.',
    );
  }
  if (width * height > _maxImagePixels) {
    throw const FormatException(
      'That image is too large. Maximum total size is 40 million pixels.',
    );
  }
  return (width: width, height: height);
}
