import 'dart:typed_data';

import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as imglib;
import 'package:mobile_scanner/mobile_scanner.dart';

final _digitsOnly = RegExp(r'^[0-9]+$');

/// EAN／UPC、純數字 Code 128，以及純數字 Code 39 用 ML Kit 的結果。
/// Code 39 若被讀成字母（8880632997502 → BBBGJFRSD7502）不採用，
/// 改把同一張畫面交給 ZXing。數字讀對的 Code 39 直接收，
/// 例如商品標 55667100549，否則物流掃描會一直等重解、畫面沒有反應。
String? trustedMlKitBookBarcode(List<Barcode> barcodes) {
  String? code39Digits;
  for (final barcode in barcodes) {
    final value = barcode.rawValue?.trim() ?? '';
    if (!_digitsOnly.hasMatch(value)) continue;
    switch (barcode.format) {
      case BarcodeFormat.ean13:
        if (value.length == 13) return value;
        break;
      case BarcodeFormat.ean8:
        if (value.length == 8) return value;
        break;
      case BarcodeFormat.upcA:
        if (value.length == 12 || value.length == 13) return value;
        break;
      case BarcodeFormat.upcE:
        if (value.length >= 6 && value.length <= 8) return value;
        break;
      case BarcodeFormat.code128:
        if (value.length >= 6) return value;
        break;
      case BarcodeFormat.code39:
        if (value.length >= 6) code39Digits ??= value;
        break;
      default:
        break;
    }
  }
  return code39Digits;
}

const _bookZxingFormats =
    Format.code39 |
    Format.code128 |
    Format.ean13 |
    Format.ean8 |
    Format.upca |
    Format.upce;

/// 快速重解。只看畫面中間約一半、找到一個就停。
/// 對準框內的 Code 39 走這裡，不要每次都把整張圖掃完。
String? decodeBookBarcodeJpeg(Uint8List encoded) {
  final image = _prepareBookBarcodeImage(encoded);
  if (image == null) return null;
  return _readBookBarcode(image, tryHarder: false);
}

/// 快速那輪失敗才用。tryHarder 會把整張圖逐列掃過，
/// 所以只找 Code 39（ML Kit 讀成字母的那種商品標），找到一個就停。
String? decodeBookBarcodeJpegThorough(Uint8List encoded) {
  final image = _prepareBookBarcodeImage(encoded);
  if (image == null) return null;
  return _readBookBarcode(image, tryHarder: true, formats: Format.code39);
}

imglib.Image? _prepareBookBarcodeImage(Uint8List encoded) {
  final decoded = imglib.decodeImage(encoded);
  if (decoded == null) return null;
  return resizeToMaxSize(decoded, 1200);
}

String? _readBookBarcode(
  imglib.Image image, {
  required bool tryHarder,
  int formats = _bookZxingFormats,
}) {
  final params = DecodeParams(
    imageFormat: ImageFormat.rgb,
    format: formats,
    width: image.width,
    height: image.height,
    tryHarder: tryHarder,
    tryRotate: true,
    tryInverted: false,
    maxNumberOfSymbols: 1,
  );
  final codes = zx.readBarcodes(rgbBytes(image), params);
  return _pickZxing(codes.codes);
}

String? _pickZxing(List<Code> codes) {
  final valid = <Code>[];
  for (final code in codes) {
    final text = code.text?.trim() ?? '';
    if (!code.isValid || text.isEmpty) continue;
    valid.add(code);
  }
  if (valid.isEmpty) return null;

  for (final code in valid) {
    final text = code.text!.trim();
    final format = code.format;
    if (!_digitsOnly.hasMatch(text) || format == null) continue;
    if (format == Format.ean13 && text.length == 13) return text;
    if (format == Format.ean8 && text.length == 8) return text;
    if (format == Format.upca && (text.length == 12 || text.length == 13)) {
      return text;
    }
    if (format == Format.upce && text.length >= 6 && text.length <= 8) {
      return text;
    }
  }
  for (final code in valid) {
    final text = code.text!.trim();
    if (_digitsOnly.hasMatch(text)) return text;
  }
  return valid.first.text!.trim();
}
