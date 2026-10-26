class VideoItem {
  VideoItem({
    required this.id,
    required this.filename,
    required this.status,
    this.error,
    this.durationSeconds,
    this.uploadedAt,
    this.violations,
  });

  final int id;
  final String filename;
  final String status; // processing | done | failed
  final String? error;
  final double? durationSeconds;
  final DateTime? uploadedAt;
  final int? violations; // people without a helmet (only known once done)

  bool get isProcessing => status == 'processing';
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';

  factory VideoItem.fromJson(Map<String, dynamic> j) => VideoItem(
        id: j['id'] as int,
        filename: j['filename'] as String,
        status: j['status'] as String,
        error: j['error'] as String?,
        durationSeconds: (j['duration_seconds'] as num?)?.toDouble(),
        uploadedAt: j['uploaded_at'] == null ? null : DateTime.tryParse(j['uploaded_at'] as String),
        violations: (j['violations'] as num?)?.toInt(),
      );
}

class Detection {
  Detection({
    required this.id,
    required this.label,
    required this.confidence,
    required this.timestampSeconds,
    this.imageUrl,
  });

  final int id;
  final String label; // helmet | no_helmet
  final double confidence;
  final double timestampSeconds;
  final String? imageUrl;

  bool get isViolation => label == 'no_helmet';

  factory Detection.fromJson(Map<String, dynamic> j) => Detection(
        id: j['id'] as int,
        label: j['label'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        timestampSeconds: (j['timestamp_seconds'] as num).toDouble(),
        imageUrl: j['image_url'] as String?,
      );
}

class VideoResults {
  VideoResults({
    required this.video,
    required this.violations,
    required this.peopleChecked,
    required this.detections,
    this.warnings = const [],
  });

  final VideoItem video;
  final int violations;
  final int peopleChecked;
  final List<Detection> detections;
  final List<String> warnings;

  factory VideoResults.fromJson(Map<String, dynamic> j) => VideoResults(
        video: VideoItem.fromJson(j),
        violations: (j['violations'] as num?)?.toInt() ?? 0,
        peopleChecked: (j['people_checked'] as num?)?.toInt() ?? 0,
        detections: ((j['detections'] as List?) ?? [])
            .map((e) => Detection.fromJson(e as Map<String, dynamic>))
            .toList(),
        warnings: ((j['warnings'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
}

/// One alert raised by the CCTV worker (a photo and the number of the camera that saw it).
class CctvEvent {
  CctvEvent({
    required this.id,
    required this.cameraName,
    required this.confidence,
    required this.createdAt,
    this.photoUrl,
    this.isFalsePositive = false,
  });

  final int id;
  final String cameraName;
  final double confidence;
  final DateTime? createdAt; // server time, shown as it is
  final String? photoUrl; // server path, needs the login header
  bool isFalsePositive;

  factory CctvEvent.fromJson(Map<String, dynamic> j) => CctvEvent(
        id: j['id'] as int,
        cameraName: j['camera_name'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        createdAt: j['created_at'] == null ? null : DateTime.tryParse(j['created_at'] as String),
        photoUrl: j['photo_url'] as String?,
        isFalsePositive: j['is_false_positive'] as bool? ?? false,
      );
}

/// Is the CCTV worker alive, and which cameras exist.
class CctvStatus {
  CctvStatus({required this.workerOnline, this.secondsSinceHeartbeat, this.cameraCount = 0});

  final bool workerOnline;
  final int? secondsSinceHeartbeat; // null = the worker has never reported
  final int cameraCount;

  factory CctvStatus.fromJson(Map<String, dynamic> j) => CctvStatus(
        workerOnline: j['worker_online'] as bool? ?? false,
        secondsSinceHeartbeat: (j['worker_seconds_since_heartbeat'] as num?)?.toInt(),
        cameraCount: (j['cameras'] as List?)?.length ?? 0,
      );
}
