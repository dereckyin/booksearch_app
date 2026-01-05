enum CaptureStatus { pending, uploading, done, failed }

class CaptureRecord {
  CaptureRecord({
    required this.id,
    required this.shelfId,
    required this.localPath,
    required this.thumbnailPath,
    required this.width,
    required this.height,
    required this.capturedAt,
    this.objectKey,
    this.status = CaptureStatus.pending,
    this.retries = 0,
    this.error,
  });

  final String id;
  final String shelfId;
  final String localPath;
  final String thumbnailPath;
  final int width;
  final int height;
  final DateTime capturedAt;
  final String? objectKey;
  final CaptureStatus status;
  final int retries;
  final String? error;

  CaptureRecord copyWith({
    String? id,
    String? shelfId,
    String? localPath,
    String? thumbnailPath,
    int? width,
    int? height,
    DateTime? capturedAt,
    String? objectKey,
    CaptureStatus? status,
    int? retries,
    String? error,
  }) {
    return CaptureRecord(
      id: id ?? this.id,
      shelfId: shelfId ?? this.shelfId,
      localPath: localPath ?? this.localPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      width: width ?? this.width,
      height: height ?? this.height,
      capturedAt: capturedAt ?? this.capturedAt,
      objectKey: objectKey ?? this.objectKey,
      status: status ?? this.status,
      retries: retries ?? this.retries,
      error: error,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'shelfId': shelfId,
      'localPath': localPath,
      'thumbnailPath': thumbnailPath,
      'width': width,
      'height': height,
      'capturedAt': capturedAt.toIso8601String(),
      'objectKey': objectKey,
      'status': status.name,
      'retries': retries,
      'error': error,
    };
  }

  factory CaptureRecord.fromMap(Map<String, dynamic> map) {
    return CaptureRecord(
      id: map['id'] as String,
      shelfId: map['shelfId'] as String? ?? 'unknown',
      localPath: map['localPath'] as String,
      thumbnailPath: map['thumbnailPath'] as String,
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      capturedAt: DateTime.tryParse(map['capturedAt'] as String? ?? '') ??
          DateTime.now(),
      objectKey: map['objectKey'] as String?,
      status: CaptureStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => CaptureStatus.pending,
      ),
      retries: map['retries'] as int? ?? 0,
      error: map['error'] as String?,
    );
  }
}






