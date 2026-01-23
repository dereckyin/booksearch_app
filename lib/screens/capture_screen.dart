import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../models/capture_record.dart';
import '../services/capture_queue.dart';
import '../services/preprocessor.dart';
import '../services/upload_service.dart';
import '../widgets/capture_overlay.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.showUi,
    required this.onToggleUi,
  });

  final bool showUi;
  final VoidCallback onToggleUi;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _initializing = true;
  bool _busy = false;
  String _status = '準備就緒';
  // Default photo quality: "佳" -> use a higher resolution preset.
  final ResolutionPreset _resolutionPreset = ResolutionPreset.high;
  FlashMode _flashMode = FlashMode.auto;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  static const double _zoomStep = 0.2;
  final _uuid = const Uuid();
  final _queue = CaptureQueue.instance;
  final _uploadService = UploadService();
  List<CaptureRecord> _captures = [];
  final String _shelfId = 'shelf-demo';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFlow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initFlow() async {
    await _ensurePermissions();
    await _loadQueue();
    await _initCamera();
    setState(() {
      _initializing = false;
    });
    _processPendingUploads();
  }

  Future<void> _ensurePermissions() async {
    final camStatus = await Permission.camera.request();
    if (!camStatus.isGranted) {
      setState(() => _status = '需要相機權限');
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        // iOS Simulator (and some environments) may not have a usable camera device.
        setState(() {
          _cameraController = null;
          _status = '此裝置/模擬器無可用相機（iOS 模擬器常見），請改用實機';
        });
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        _resolutionPreset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final initialZoom = minZoom.clamp(minZoom, maxZoom).toDouble();
      await controller.setZoomLevel(initialZoom);
      await controller.setFlashMode(_flashMode);
      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        _status = '相機已就緒';
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _currentZoom = initialZoom;
      });
    } catch (e) {
      setState(() => _status = '相機初始化失敗: $e');
    }
  }

  Future<void> _loadQueue() async {
    final items = await _queue.listAll();
    setState(() => _captures = items);
  }

  Future<void> _capture() async {
    if (_busy) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      _busy = true;
      _status = '拍攝中…';
    });
    try {
      final file = await controller.takePicture();
      final id = _uuid.v4();
      final processed = await Preprocessor.process(file.path, id);
      final record = CaptureRecord(
        id: id,
        shelfId: _shelfId,
        localPath: processed.processedPath,
        thumbnailPath: processed.thumbnailPath,
        width: processed.width,
        height: processed.height,
        capturedAt: DateTime.now(),
      );
      await _queue.upsert(record);
      await _loadQueue();
      setState(() => _status = '已拍攝，等待上傳');
      _processPendingUploads();
    } catch (e) {
      setState(() => _status = '拍攝失敗: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _processPendingUploads() async {
    final hasNet = await _uploadService.hasConnection();
    if (!hasNet) {
      setState(() => _status = '離線中，暫停上傳');
      return;
    }

    final pending = await _queue.pending();
    for (final record in pending) {
      await _queue.updateStatus(record.id, CaptureStatus.uploading);
      await _loadQueue();
      try {
        final file = File(record.localPath);
        final upload = await _uploadService.uploadFile(
          file,
          folder: 'user_photos',
        );
        await _uploadService.sendManifest(
          record: record,
          uploadResult: upload,
          sizeBytes: await file.length(),
        );
        await _queue.updateStatus(
          record.id,
          CaptureStatus.done,
          objectKey: upload.objectKey,
          error: null,
        );
        setState(() => _status = '已上傳 ${record.id}');
      } catch (e) {
        final retries = record.retries + 1;
        await _queue.updateStatus(
          record.id,
          CaptureStatus.failed,
          error: e.toString(),
          retries: retries,
        );
        setState(() => _status = '上傳失敗: $e');
      }
      await _loadQueue();
    }
  }

  Future<void> _setFlash(FlashMode mode) async {
    if (_cameraController == null) return;
    await _cameraController!.setFlashMode(mode);
    setState(() => _flashMode = mode);
  }

  Future<void> _setZoom(double zoom) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom).toDouble();
    try {
      await controller.setZoomLevel(clamped);
      setState(() => _currentZoom = clamped);
    } catch (e) {
      setState(() => _status = '縮放設定失敗: $e');
    }
  }

  void _stepZoom(double delta) {
    _setZoom(_currentZoom + delta);
  }

  String _flashLabel(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return '關閉';
      case FlashMode.auto:
        return '自動';
      case FlashMode.always:
        return '常亮';
      case FlashMode.torch:
        return '手電筒';
    }
  }

  String _statusLabel(CaptureStatus status) {
    switch (status) {
      case CaptureStatus.pending:
        return '待上傳';
      case CaptureStatus.uploading:
        return '上傳中';
      case CaptureStatus.done:
        return '已完成';
      case CaptureStatus.failed:
        return '失敗';
    }
  }

  Widget _AspectCameraPreview(CameraController controller) {
    final aspect = controller.value.aspectRatio;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspect,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    return Scaffold(
      appBar: widget.showUi
          ? AppBar(
              title: const Text('讀冊撿貨單'),
              actions: [
                IconButton(
                  tooltip: '重新嘗試上傳',
                  onPressed: _processPendingUploads,
                  icon: const Icon(Icons.sync),
                ),
              ],
            )
          : null,
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: widget.onToggleUi,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AspectRatio(
                    aspectRatio:
                        controller?.value.aspectRatio ?? (4 / 3),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (controller != null &&
                            controller.value.isInitialized)
                          _AspectCameraPreview(controller)
                        else
                          Container(color: Colors.black12),
                        CaptureOverlay(showGrid: false, label: _status),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.large(
        heroTag: 'capture-fab',
        onPressed: _busy ? null : _capture,
        child: _busy
            ? const CircularProgressIndicator()
            : const Icon(Icons.camera),
      ),
    );
  }

}
