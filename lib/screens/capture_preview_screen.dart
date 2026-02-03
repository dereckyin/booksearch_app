import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:uuid/uuid.dart';

import '../models/capture_record.dart';
import '../services/capture_queue.dart';
import '../services/preprocessor.dart';

/// 拍照後的預覽畫面：可裁切、上傳或捨棄。
class CapturePreviewScreen extends StatefulWidget {
  const CapturePreviewScreen({
    super.key,
    required this.photoPath,
    this.shelfId = 'shelf-demo',
  });

  final String photoPath;
  final String shelfId;

  @override
  State<CapturePreviewScreen> createState() => _CapturePreviewScreenState();
}

class _CapturePreviewScreenState extends State<CapturePreviewScreen> {
  String _currentPath = '';
  bool _busy = false;
  String? _error;
  final _uuid = const Uuid();
  final _queue = CaptureQueue.instance;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.photoPath;
  }

  Future<void> _crop() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 原生裁切畫面：調整框選後，點擊工具列右上角 ✓（Android）或 Done（iOS）即確認並回傳
      final cropped = await ImageCropper().cropImage(
        sourcePath: _currentPath,
        aspectRatio: const CropAspectRatio(ratioX: 4, ratioY: 3),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁切（完成請按右上角 ✓）',
            toolbarColor: Colors.black87,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
          ),
          IOSUiSettings(
            title: '裁切（完成請按 Done）',
          ),
        ],
      );
      if (!mounted) return;
      if (cropped != null && cropped.path.isNotEmpty) {
        setState(() => _currentPath = cropped.path);
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _error = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('此裝置不支援裁切功能，請使用原圖上傳或捨棄'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '裁切失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = _uuid.v4();
      final processed = await Preprocessor.process(_currentPath, id);
      final record = CaptureRecord(
        id: id,
        shelfId: widget.shelfId,
        localPath: processed.processedPath,
        thumbnailPath: processed.thumbnailPath,
        width: processed.width,
        height: processed.height,
        capturedAt: DateTime.now(),
      );
      await _queue.upsert(record);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '處理失敗: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _discard() {
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('預覽'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _currentPath.isEmpty
                ? const Center(child: Text('無圖片'))
                : InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Center(
                      child: Image.file(
                        File(_currentPath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: _busy ? null : _crop,
                  child: const Text('裁切'),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _busy ? null : _upload,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('上傳'),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: _busy ? null : _discard,
                  child: const Text('捨棄'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
