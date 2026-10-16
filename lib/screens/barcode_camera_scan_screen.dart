import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/book_barcode_decode.dart';

/// 書／商品：EAN-13、UPC、EAN-8、讀冊物流標籤（Code 128）、
/// 以及印成 Code 39 的商品碼（底下數字像 EAN，線條不是 EAN）。不讀 QR、Code 93。
/// 相機辨識不支援 +2／+5 附加碼，只回傳 13 碼，後端以前綴比對物流條碼。
///
/// ML Kit 的 Code 39 會把 8880632997502 讀成 BBBGJFRSD7502，
/// 那種結果不採用，改把同一張畫面交給 ZXing。
const kBookBarcodeFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
];

/// 儲位標籤、揀貨單號（FC／CA／CB）。這些標籤是 Code 128 或 Code 39／93，
/// 不是商品 EAN，所以這裡保留 Code 39／93。
const kCodeBarcodeFormats = [
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
];

/// 相機掃條碼（回傳掃到的字串後關閉）
class BarcodeCameraScanScreen extends StatefulWidget {
  const BarcodeCameraScanScreen({
    super.key,
    this.title = '掃描物流條碼',
    this.formats = kBookBarcodeFormats,
  });

  final String title;
  final List<BarcodeFormat> formats;

  @override
  State<BarcodeCameraScanScreen> createState() =>
      _BarcodeCameraScanScreenState();
}

class _BarcodeCameraScanScreenState extends State<BarcodeCameraScanScreen> {
  /// 上一個掃描畫面釋放相機的進度；連續開關相機時，原生相機尚未釋放就 start
  /// 會得到 controllerAlreadyInitialized（黑屏），所以新畫面要先等它完成。
  static Future<void>? _releasing;

  late final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: widget.formats,
    // Code 39 誤讀時要把這一幀交給 ZXing，所以書／商品掃描要帶回 JPEG。
    returnImage: _isBook,
  );

  bool get _isBook => identical(widget.formats, kBookBarcodeFormats);

  bool _handled = false;
  bool _redecoding = false;
  bool _thorough = false;
  int _fastMisses = 0;
  bool _restarting = false;

  /// 連續幾張快速重解失敗後，才做一次整張圖的 Code 39 慢掃。
  static const _thoroughEvery = 3;

  @override
  void initState() {
    super.initState();
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    _releasing = _release(_controller);
    super.dispose();
  }

  static Future<void> _release(MobileScannerController c) async {
    try {
      await c.stop();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  Future<void> _startCamera() async {
    try {
      await _releasing?.timeout(const Duration(seconds: 3));
    } catch (_) {}
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return;
      try {
        await _controller.start();
      } on MobileScannerException catch (_) {
        // start 途中重入；下一輪再試
      } catch (_) {}
      if (!mounted) return;
      final v = _controller.value;
      if (v.isRunning) return;
      final code = v.error?.errorCode;
      final retryable =
          code == null ||
          code == MobileScannerErrorCode.controllerAlreadyInitialized ||
          code == MobileScannerErrorCode.controllerInitializing ||
          code == MobileScannerErrorCode.genericError;
      if (!retryable) return;
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }

  Future<void> _restart() async {
    if (_restarting) return;
    setState(() => _restarting = true);
    try {
      await _controller.stop();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _startCamera();
    if (mounted) setState(() => _restarting = false);
  }

  void _finish(String raw) {
    _handled = true;
    Navigator.of(context).pop(raw);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (!_isBook) {
      final raw = capture.barcodes
          .map((b) => b.rawValue?.trim() ?? '')
          .firstWhere((v) => v.isNotEmpty, orElse: () => '');
      if (raw.isEmpty) return;
      _finish(raw);
      return;
    }
    final trusted = trustedMlKitBookBarcode(capture.barcodes);
    if (trusted != null) {
      _finish(trusted);
      return;
    }
    if (_redecoding) return;
    final image = capture.image;
    if (image == null || image.isEmpty) return;
    _redecoding = true;
    unawaited(_redecode(image));
  }

  Future<String?> _decodeOffUi(
    String? Function(Uint8List) decode,
    Uint8List image,
  ) async {
    try {
      return await compute(decode, image);
    } catch (_) {
      // 背景 isolate 載入不到原生庫時，退回這條執行緒，至少還解得出來。
      return decode(image);
    }
  }

  Future<void> _redecode(Uint8List image) async {
    try {
      final fast = await _decodeOffUi(decodeBookBarcodeJpeg, image);
      if (!mounted || _handled) return;
      if (fast != null && fast.isNotEmpty) {
        _fastMisses = 0;
        _finish(fast);
        return;
      }
      _fastMisses++;
      if (_fastMisses < _thoroughEvery) return;
      _fastMisses = 0;
      if (mounted) setState(() => _thorough = true);
      final slow = await _decodeOffUi(decodeBookBarcodeJpegThorough, image);
      if (!mounted || _handled) return;
      if (slow != null && slow.isNotEmpty) _finish(slow);
    } catch (_) {
      // 這一幀解不出來就繼續掃，不要把 ML Kit 的字母亂碼送出去。
    } finally {
      _redecoding = false;
      if (mounted && _thorough) setState(() => _thorough = false);
    }
  }

  Widget _buildError(BuildContext context, MobileScannerException error) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off, color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          Text(
            denied ? '沒有相機權限，請到手機設定允許本 App 使用相機' : '相機無法啟動',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (!denied) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _restarting ? null : _restart,
              icon: const Icon(Icons.refresh),
              label: const Text('重新開啟相機'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '手電筒',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: '切換鏡頭',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: _buildError,
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 260,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.amber, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              _thorough
                  ? '這張標比較難讀，請再對準框內停一下'
                  : _isBook
                  ? '將書籍條碼或讀冊物流標籤對準框內'
                  : '將儲位或單號條碼對準框內',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 6, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
