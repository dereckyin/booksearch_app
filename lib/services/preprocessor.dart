import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PreprocessResult {
  PreprocessResult({
    required this.processedPath,
    required this.thumbnailPath,
    required this.width,
    required this.height,
  });

  final String processedPath;
  final String thumbnailPath;
  final int width;
  final int height;
}

class Preprocessor {
  static const int longEdge = 2048;
  static const int quality = 85;
  static const int thumbEdge = 320;

  static Future<PreprocessResult> process(String inputPath, String id) async {
    final inputBytes = await File(inputPath).readAsBytes();
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw Exception('Unable to decode captured image');
    }

    final resized = _resize(decoded, longEdge);
    final processedBytes = Uint8List.fromList(
      img.encodeJpg(resized, quality: quality),
    );

    final dir = await getApplicationDocumentsDirectory();
    final captureDir = Directory(p.join(dir.path, 'captures'));
    if (!await captureDir.exists()) {
      await captureDir.create(recursive: true);
    }
    final processedPath = p.join(captureDir.path, '$id.jpg');
    await File(processedPath).writeAsBytes(processedBytes, flush: true);

    final thumb = _resize(resized, thumbEdge);
    final thumbBytes = Uint8List.fromList(img.encodeJpg(thumb, quality: 70));
    final thumbPath = p.join(captureDir.path, '${id}_thumb.jpg');
    await File(thumbPath).writeAsBytes(thumbBytes, flush: true);

    return PreprocessResult(
      processedPath: processedPath,
      thumbnailPath: thumbPath,
      width: resized.width,
      height: resized.height,
    );
  }

  static img.Image _resize(img.Image image, int targetLongEdge) {
    final longSide = image.width > image.height ? image.width : image.height;
    if (longSide <= targetLongEdge) return image;
    final scale = targetLongEdge / longSide;
    final targetWidth = (image.width * scale).round();
    final targetHeight = (image.height * scale).round();
    return img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic,
    );
  }
}

