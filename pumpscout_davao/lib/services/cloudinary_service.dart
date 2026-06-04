part of '../main.dart';

class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.secureUrl,
    required this.publicId,
  });

  final String secureUrl;
  final String publicId;
}

Future<CloudinaryUploadResult?> uploadPriceReportImageToCloudinary({
  required picker.XFile image,
  required String stationId,
  required DateTime createdAt,
}) async {
  if (!isCloudinaryConfigured) {
    debugPrint(
      'Cloudinary is not configured. Set cloudinaryCloudName and '
      'cloudinaryUploadPreset in main.dart.',
    );
    return null;
  }

  try {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.https(
              'api.cloudinary.com',
              '/v1_1/$cloudinaryCloudName/image/upload',
            ),
          )
          ..fields['upload_preset'] = cloudinaryUploadPreset
          ..fields['folder'] = 'pumpscout/price_reports/$stationId'
          ..fields['public_id'] = createdAt.millisecondsSinceEpoch.toString()
          ..fields['tags'] = 'pumpscout,price_report'
          ..files.add(await http.MultipartFile.fromPath('file', image.path));

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        'Cloudinary upload failed: HTTP ${response.statusCode} '
        '${response.body}',
      );
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    final secureUrl = decoded['secure_url'];
    final publicId = decoded['public_id'];

    if (secureUrl is! String || secureUrl.isEmpty) return null;

    return CloudinaryUploadResult(
      secureUrl: secureUrl,
      publicId: publicId is String ? publicId : '',
    );
  } catch (error) {
    debugPrint('Cloudinary upload request failed: $error');
    return null;
  }
}
