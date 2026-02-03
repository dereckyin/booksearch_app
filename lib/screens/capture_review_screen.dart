import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

/// Returns the selected image path (original or cropped) when user confirms.
/// Returns null when user discards.
class CaptureReviewScreen extends StatefulWidget {
  const CaptureReviewScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<CaptureReviewScreen> createState() => _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends State<CaptureReviewScreen> {
  late String _currentPath = widget.imagePath;
  bool _busy = false;

  Future<void> _crop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await ImageCropper().cropImage(
        sourcePath: _currentPath,
        compressFormat: ImageCompressFormat.jpg,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁切',
            toolbarWidgetColor: Colors.white,
            toolbarColor: Colors.black,
            activeControlsWidgetColor: Colors.blueGrey,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: '裁切',
            rotateButtonsHidden: false,
            resetButtonHidden: false,
            aspectRatioLockEnabled: false,
          ),
        ],
      );
      if (!mounted) return;
      if (result != null) {
        setState(() => _currentPath = result.path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('裁切失敗: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _use() {
    Navigator.of(context).pop<String>(_currentPath);
  }

  void _discard() {
    Navigator.of(context).pop<String?>(null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('預覽'),
        leading: IconButton(
          tooltip: '捨棄',
          onPressed: _busy ? null : _discard,
          icon: const Icon(Icons.close),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _use,
            child: const Text('使用'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(
                child: Image.file(
                  File(_currentPath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Text('無法顯示圖片'),
                  ),
                ),
              ),
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _crop,
                  icon: const Icon(Icons.crop),
                  label: const Text('裁切'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _use,
                  icon: const Icon(Icons.check),
                  label: const Text('使用'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

