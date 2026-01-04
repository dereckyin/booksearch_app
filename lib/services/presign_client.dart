import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

const _defaultPresignEndpoint =
    String.fromEnvironment('PRESIGN_ENDPOINT', defaultValue: '');
const _defaultManifestEndpoint =
    String.fromEnvironment('MANIFEST_ENDPOINT', defaultValue: '');

class PresignedUpload {
  PresignedUpload({
    required this.objectKey,
    required this.uploadUrl,
    this.headers = const {},
    this.parts,
  });

  final String objectKey;
  final Uri uploadUrl;
  final Map<String, String> headers;
  final List<Uri>? parts;
}

class ManifestPayload {
  ManifestPayload({
    required this.captureId,
    required this.shelfId,
    required this.objectKey,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.capturedAt,
    required this.deviceModel,
    this.geo,
  });

  final String captureId;
  final String shelfId;
  final String objectKey;
  final int width;
  final int height;
  final int sizeBytes;
  final DateTime capturedAt;
  final String deviceModel;
  final Map<String, dynamic>? geo;

  Map<String, dynamic> toJson() => {
        'captureId': captureId,
        'shelfId': shelfId,
        'objectKey': objectKey,
        'width': width,
        'height': height,
        'sizeBytes': sizeBytes,
        'capturedAt': capturedAt.toIso8601String(),
        'deviceModel': deviceModel,
        if (geo != null) 'geo': geo,
      };
}

class PresignClient {
  PresignClient({
    String? presignEndpoint,
    String? manifestEndpoint,
    http.Client? httpClient,
  })  : _presignEndpoint = presignEndpoint ?? _defaultPresignEndpoint,
        _manifestEndpoint = manifestEndpoint ?? _defaultManifestEndpoint,
        _client = httpClient ?? http.Client();

  final String _presignEndpoint;
  final String _manifestEndpoint;
  final http.Client _client;
  final Uuid _uuid = const Uuid();

  bool get _hasPresignApi => _presignEndpoint.isNotEmpty;
  bool get _hasManifestApi => _manifestEndpoint.isNotEmpty;
  bool get hasPresignApi => _hasPresignApi;
  bool get hasManifestApi => _hasManifestApi;

  Future<PresignedUpload> getPresignedUrl(String filename) async {
    if (_hasPresignApi) {
      final resp = await _client.post(
        Uri.parse(_presignEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'filename': filename}),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        return PresignedUpload(
          objectKey: json['objectKey'] as String,
          uploadUrl: Uri.parse(json['uploadUrl'] as String),
          headers: (json['headers'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, v.toString())) ??
              {},
          parts: (json['parts'] as List<dynamic>?)
              ?.map((e) => Uri.parse(e as String))
              .toList(),
        );
      }
      throw HttpException(
        'Failed to fetch presigned url: ${resp.statusCode}',
      );
    }

    // Fallback for local/demo: send to httpbin PUT endpoint.
    final demoKey = 'captures/${_uuid.v4()}-$filename';
    return PresignedUpload(
      objectKey: demoKey,
      uploadUrl: Uri.parse('https://httpbin.org/put'),
      headers: {'Content-Type': 'image/jpeg'},
    );
  }

  Future<void> sendManifest(ManifestPayload payload) async {
    if (!_hasManifestApi) return;
    final resp = await _client.post(
      Uri.parse(_manifestEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload.toJson()),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException('Failed to send manifest: ${resp.statusCode}');
    }
  }
}




