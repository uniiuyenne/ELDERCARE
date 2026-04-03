import 'dart:typed_data';

import 'package:dio/dio.dart';

class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
    required this.resourceType,
    required this.bytes,
  });

  final String secureUrl;
  final String publicId;
  final String resourceType;
  final int bytes;
}

class CloudinaryService {
  const CloudinaryService._();

  static final Dio _dio = Dio();

  static const String _cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'dggbnsm78',
  );
  static const String _uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'eldercare_unsigned',
  );

  static bool get isConfigured =>
      _cloudName.trim().isNotEmpty && _uploadPreset.trim().isNotEmpty;

  static String get configHint =>
      'Thiếu cấu hình Cloudinary. Chạy app với --dart-define=CLOUDINARY_CLOUD_NAME=<ten_cloud> --dart-define=CLOUDINARY_UPLOAD_PRESET=<upload_preset_unsigned>.';

  static Future<CloudinaryUploadResult> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String folder,
    required String resourceType,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!isConfigured) {
      throw StateError(configHint);
    }

    final normalizedResourceType =
        resourceType.toLowerCase() == 'video' ? 'video' : 'image';

    final uri =
      'https://api.cloudinary.com/v1_1/$_cloudName/$normalizedResourceType/upload';
    final formData = FormData.fromMap({
      'upload_preset': _uploadPreset,
      'folder': folder,
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      uri,
      data: formData,
      cancelToken: cancelToken,
      onSendProgress: onProgress,
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );

    final decoded = response.data;

    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw Exception(
        'Cloudinary upload failed (${response.statusCode}): ${decoded ?? response.statusMessage}',
      );
    }

    if (decoded == null) {
      throw Exception('Cloudinary response invalid.');
    }

    final secureUrl = (decoded['secure_url'] ?? '').toString();
    if (secureUrl.isEmpty) {
      throw Exception('Cloudinary response missing secure_url.');
    }

    return CloudinaryUploadResult(
      secureUrl: secureUrl,
      publicId: (decoded['public_id'] ?? '').toString(),
      resourceType: (decoded['resource_type'] ?? normalizedResourceType)
          .toString(),
      bytes: (decoded['bytes'] is num) ? (decoded['bytes'] as num).toInt() : 0,
    );
  }
}
