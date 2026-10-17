import 'package:booksearch_app/utils/book_barcode_decode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  test('ML Kit retail and numeric Code 128 are trusted', () {
    expect(
      trustedMlKitBookBarcode([
        const Barcode(format: BarcodeFormat.code39, rawValue: 'BBBGJFRSD7502'),
        const Barcode(format: BarcodeFormat.ean13, rawValue: '9789573288881'),
      ]),
      '9789573288881',
    );
    expect(
      trustedMlKitBookBarcode([
        const Barcode(format: BarcodeFormat.code128, rawValue: '888063299750212345'),
      ]),
      '888063299750212345',
    );
  });

  test('ML Kit Code 39 letters are not trusted', () {
    expect(
      trustedMlKitBookBarcode([
        const Barcode(format: BarcodeFormat.code39, rawValue: 'BBBGJFRSD7502'),
      ]),
      isNull,
    );
  });

  test('ML Kit numeric Code 39 is trusted', () {
    expect(
      trustedMlKitBookBarcode([
        const Barcode(format: BarcodeFormat.code39, rawValue: '55667100549'),
      ]),
      '55667100549',
    );
  });

  test('retail code wins over a numeric Code 39 in the same frame', () {
    expect(
      trustedMlKitBookBarcode([
        const Barcode(format: BarcodeFormat.code39, rawValue: '55667100549'),
        const Barcode(format: BarcodeFormat.ean13, rawValue: '9789573288881'),
      ]),
      '9789573288881',
    );
  });
}
