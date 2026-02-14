import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/capture_record.dart';
import '../services/capture_queue.dart';
import '../services/upload_service.dart';
import '../widgets/capture_overlay.dart';
import 'capture_preview_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.showUi,
    required this.onToggleUi,
    required this.isActive,
  });

  final bool showUi;
  final VoidCallback onToggleUi;
  final bool isActive;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _permissionsReady = false;
  bool _initializing = true;
  bool _busy = false;
  String _status = '準備就緒';
  // Default photo quality: "佳" -> use a higher resolution preset.
  final ResolutionPreset _resolutionPreset = ResolutionPreset.high;
  final FlashMode _flashMode = FlashMode.auto;
  final _queue = CaptureQueue.instance;
  final _uploadService = UploadService();
  final String _shelfId = 'shelf-demo';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initFlow();
  }

  @override
  void didUpdateWidget(covariant CaptureScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (widget.isActive) {
      _resumeCameraFlow();
    } else {
      _disposeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.isActive) return;
    if (state == AppLifecycleState.inactive) {
      if (_cameraController != null) {
        _disposeCamera();
      }
    } else if (state == AppLifecycleState.resumed) {
      // Returning from native pages (e.g. cropper) may leave controller null.
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        _resumeCameraFlow();
      }
    }
  }

  Future<void> _initFlow() async {
    if (widget.isActive) {
      await _ensurePermissions();
      await _initCamera();
    } else {
      setState(() => _status = '切換到拍照頁後啟動相機');
    }
    if (!mounted) return;
    setState(() => _initializing = false);
    _processPendingUploads();
  }

  Future<void> _resumeCameraFlow() async {
    setState(() => _initializing = true);
    if (!_permissionsReady) {
      await _ensurePermissions();
    }
    await _initCamera();
    if (!mounted) return;
    setState(() => _initializing = false);
  }

  void _disposeCamera() {
    _cameraController?.dispose();
    _cameraController = null;
  }

  Future<void> _ensurePermissions() async {
    if (_permissionsReady) return;
    final camStatus = await Permission.camera.request();
    if (!camStatus.isGranted) {
      if (!mounted) return;
      if (camStatus.isPermanentlyDenied || camStatus.isRestricted) {
        setState(() => _status = '相機權限被停用，請到「設定」開啟相機權限');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('相機權限被停用，請到設定開啟'),
            action: SnackBarAction(
              label: '前往設定',
              onPressed: () {
                openAppSettings();
              },
            ),
          ),
        );
      } else {
        setState(() => _status = '需要相機權限');
      }
      return;
    }
    _permissionsReady = true;
  }

  Future<void> _initCamera() async {
    if (!widget.isActive) return;
    if (!_permissionsReady) return;
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
      await controller.setFlashMode(_flashMode);
      if (!mounted || !widget.isActive) {
        await controller.dispose();
        return;
      }
      _disposeCamera();
      setState(() {
        _cameraController = controller;
        _status = '相機已就緒';
      });
    } catch (e) {
      setState(() => _status = '相機初始化失敗: $e');
    }
  }

  Future<void> _capture() async {
    if (_busy) return;
    var controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _resumeCameraFlow();
      controller = _cameraController;
    }
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      _busy = true;
      _status = '拍攝中…';
    });
    try {
      final file = await controller.takePicture();
      final photoPath = file.path;
      if (!mounted) return;
      if (photoPath.isEmpty) {
        setState(() => _status = '拍照路徑無效');
        return;
      }
      setState(() => _busy = false);
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      final uploaded = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CapturePreviewScreen(
            photoPath: photoPath,
            shelfId: _shelfId,
          ),
        ),
      );
      if (!mounted) return;
      if (uploaded == true) {
        setState(() => _status = '已上傳，等待同步');
        _processPendingUploads();
      } else {
        setState(() => _status = '已捨棄');
      }
    } catch (e) {
      if (mounted) setState(() => _status = '拍攝失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
    }
  }

  Widget _aspectCameraPreview(CameraController controller) {
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
                          _aspectCameraPreview(controller)
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
