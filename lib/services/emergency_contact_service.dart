import 'package:url_launcher/url_launcher.dart';

enum EmergencyActionResult { callStarted, smsOpened, failed }

class EmergencyContactService {
  static String normalizePhone(String rawPhone) {
    return rawPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  }

  static Future<EmergencyActionResult> startSosToChild({
    required String phone,
    required String smsBody,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isEmpty) {
      return EmergencyActionResult.failed;
    }

    final callStarted = await _launchExternal(
      Uri(scheme: 'tel', path: normalizedPhone),
    );
    if (callStarted) {
      return EmergencyActionResult.callStarted;
    }

    final smsOpened = await _launchExternal(
      Uri(
        scheme: 'sms',
        path: normalizedPhone,
        queryParameters: smsBody.isEmpty ? null : {'body': smsBody},
      ),
    );
    if (smsOpened) {
      return EmergencyActionResult.smsOpened;
    }

    return EmergencyActionResult.failed;
  }

  static Future<bool> _launchExternal(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
