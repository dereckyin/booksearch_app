import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 書籍只讀 EAN-13：書上常有多個條碼或 QR Code，限定格式避免讀錯。
/// 相機辨識不支援 +2／+5 附加碼，只回傳 13 碼，後端以前綴比對物流條碼。
const kBookBarcodeFormats = [BarcodeFormat.ean13];

/// 儲位標籤、單號（FC／CA／CB）用一維碼
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
  );

  bool get _isBook => identical(widget.formats, kBookBarcodeFormats);

  bool _handled = false;
  bool _restarting = false;

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

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(raw);
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
              _isBook ? '將書籍 EAN-13 條碼對準框內' : '將儲位或單號條碼對準框內',
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
