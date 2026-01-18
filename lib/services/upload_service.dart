import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/capture_record.dart';
import '../config/api_config.dart';
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
  final ApiConfig _apiConfig = ApiConfig();

  Future<bool> hasConnection() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<UploadResult> uploadFile(
    File file, {
    String folder = 'user_photos',
  }) async {
    // If no presign API is configured, fall back to direct Taaze upload API.
    if (!_presignClient.hasPresignApi) {
      return _uploadDirectToTaaze(file, folder: folder);
    }

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

  Future<UploadResult> _uploadDirectToTaaze(
    File file, {
    required String folder,
  }) async {
    final uri = Uri.parse(_apiConfig.uploadPhotoUrl);
    final fileLen = await file.length();
    if (fileLen == 0) {
      throw HttpException('Upload aborted: file is empty');
    }

    // Debug info to help backend diagnose 422.
    // ignore: avoid_print
    print('Uploading file ${file.path} size=$fileLen bytes');

    final multipart = await http.MultipartFile.fromPath(
      'photoFile', // matches backend example
      file.path,
      filename: p.basename(file.path),
      contentType: MediaType('image', 'jpeg'),
    );

    final request = http.MultipartRequest('POST', uri)
      ..files.add(multipart)
      ..fields['folder'] = folder;

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    // Debug info for all responses to help diagnose backend parsing.
    // ignore: avoid_print
    print('Upload response status=${streamed.statusCode} body=$body');

    if (streamed.statusCode == 422) {
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final detail = json['detail'] as Map<String, dynamic>? ?? {};
        final fields = detail['received_fields'];
        final fieldTypes = detail['field_types'];
        final fieldDetails = detail['field_details'];
        // Logging to help backend debug field parsing.
        // ignore: avoid_print
        print(
          '422 upload response - fields: $fields; types: $fieldTypes; details: $fieldDetails',
        );
        throw HttpException(
          'Upload 422: fields=$fields types=$fieldTypes details=$fieldDetails',
        );
      } catch (_) {
        throw HttpException('Upload failed with 422: $body');
      }
    }

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw HttpException('Upload failed with ${streamed.statusCode}: $body');
    }

    String objectKey = _uuid.v4();
    String eTag = streamed.headers['etag'] ?? _uuid.v4();
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      objectKey = (json['objectKey'] ??
              json['url'] ??
              (json['data'] is Map ? (json['data'] as Map)['url'] : null) ??
              objectKey)
          .toString();
      eTag = (json['etag'] ??
              (json['data'] is Map ? (json['data'] as Map)['etag'] : null) ??
              eTag)
          .toString();
    } catch (_) {
      // Best-effort parse; keep generated IDs.
    }

    return UploadResult(objectKey: objectKey, eTag: eTag);
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

