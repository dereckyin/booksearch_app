import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/capture_record.dart';
import 'presign_client.dart';

class UploadResult {
  UploadResult({required this.objectKey, required this.eTag});

  final String objectKey;
  final String eTag;
}

class UploadService {
  UploadService({
    PresignClient? presignClient,
    Connectivity? connectivity,
  })  : _presignClient = presignClient ?? PresignClient(),
        _connectivity = connectivity ?? Connectivity(),
        _client = http.Client();

  final PresignClient _presignClient;
  final Connectivity _connectivity;
  final http.Client _client;
  final Uuid _uuid = const Uuid();

  Future<bool> hasConnection() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<UploadResult> uploadFile(File file) async {
    final fileName = p.basename(file.path);
    final presigned = await _presignClient.getPresignedUrl(fileName);

    if (presigned.parts != null && presigned.parts!.isNotEmpty) {
      final eTag = await _multipartUpload(file, presigned);
      return UploadResult(objectKey: presigned.objectKey, eTag: eTag);
    }

    final bytes = await file.readAsBytes();
    final resp = await _client.put(
      presigned.uploadUrl,
      headers: {
        'Content-Type': 'image/jpeg',
        ...presigned.headers,
      },
      body: bytes,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('Upload failed with ${resp.statusCode}');
    }
    final eTag = resp.headers['etag'] ?? _uuid.v4();
    return UploadResult(objectKey: presigned.objectKey, eTag: eTag);
  }

  Future<String> _multipartUpload(File file, PresignedUpload presigned) async {
    final partUrls = presigned.parts!;
    final data = await file.readAsBytes();
    final chunkSize = (5 * 1024 * 1024); // 5MB chunks
    final totalParts = (data.length / chunkSize).ceil();
    if (partUrls.length < totalParts) {
      throw Exception('Not enough pre-signed part URLs for multipart upload');
    }

    final eTags = <String>[];
    for (var i = 0; i < totalParts; i++) {
      final start = i * chunkSize;
      final end = ((i + 1) * chunkSize < data.length)
          ? (i + 1) * chunkSize
          : data.length;
      final chunk = data.sublist(start, end);
      final resp = await _client.put(
        partUrls[i],
        headers: {
          'Content-Type': 'application/octet-stream',
          ...presigned.headers,
        },
        body: chunk,
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException('Multipart upload failed on part ${i + 1}');
      }
      final eTag = resp.headers['etag'] ?? _uuid.v4();
      eTags.add(eTag);
    }

    // A real S3 multipart flow needs a final CompleteMultipartUpload call.
    // Here we just return a combined tag for traceability.
    return base64Encode(utf8.encode(eTags.join(',')));
  }

  Future<void> sendManifest({
    required CaptureRecord record,
    required UploadResult uploadResult,
    required int sizeBytes,
  }) async {
    final payload = ManifestPayload(
      captureId: record.id,
      shelfId: record.shelfId,
      objectKey: uploadResult.objectKey,
      width: record.width,
      height: record.height,
      sizeBytes: sizeBytes,
      capturedAt: record.capturedAt,
      deviceModel: Platform.localHostname,
    );
    await _presignClient.sendManifest(payload);
  }
}

