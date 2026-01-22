import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/upload_service.dart';

class UploadGalleryScreen extends StatefulWidget {
  const UploadGalleryScreen({super.key});

  @override
  State<UploadGalleryScreen> createState() => _UploadGalleryScreenState();
}

class _UploadGalleryScreenState extends State<UploadGalleryScreen> {
  final _picker = ImagePicker();
  final _uploadService = UploadService();
  bool _busy = false;
  String _status = '請選擇要上傳的相片';
  List<XFile> _files = [];

  Future<void> _pickImages() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 90);
      if (picked == null || picked.isEmpty) return;
      setState(() {
        _files = picked;
        _status = '已選擇 ${picked.length} 張';
      });
    } catch (e) {
      setState(() => _status = '選取失敗: $e');
    }
  }

  Future<void> _uploadAll() async {
    if (_files.isEmpty) {
      setState(() => _status = '請先選擇相片');
      return;
    }
    setState(() {
      _busy = true;
      _status = '上傳中…';
    });
    try {
      for (final f in _files) {
        final file = File(f.path);
        await _uploadService.uploadFile(file, folder: 'user_photos');
      }
      setState(() {
        _status = '上傳完成 ${_files.length} 張';
        _files = [];
      });
    } catch (e) {
      setState(() => _status = '上傳失敗: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上傳圖檔'),
        actions: [
          IconButton(
            tooltip: '重新選擇',
            onPressed: _busy ? null : _pickImages,
            icon: const Icon(Icons.photo_library),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: Text(
              _status,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: _files.isEmpty
                ? const Center(child: Text('尚未選擇任何相片'))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final f = _files[index];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(f.path),
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                color: Colors.white,
                                icon: const Icon(Icons.close),
                                onPressed: _busy
                                    ? null
                                    : () {
                                        setState(() {
                                          _files.removeAt(index);
                                          _status =
                                              '已選擇 ${_files.length} 張';
                                        });
                                      },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'upload-fab',
        onPressed: _busy ? null : _uploadAll,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_upload),
        label: Text(_busy ? '上傳中…' : '上傳'),
      ),
    );
  }
}
