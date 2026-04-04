import 'package:url_launcher/url_launcher.dart';

enum EmergencyActionResult {
  callStarted,
  smsOpened,
  failed,
}

class EmergencyContactService {
  static String normalizePhone(String phone) {
    var value = phone.trim();
    if (value.isEmpty) return '';

    value = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (value.startsWith('00')) {
      value = '+${value.substring(2)}';
    }

    return value;
  }

  static Future<EmergencyActionResult> startSosToChild({
    required String phone,
    required String smsBody,
  }) async {
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) {
      return EmergencyActionResult.failed;
    }

    final telUri = Uri(scheme: 'tel', path: normalized);
    if (await canLaunchUrl(telUri) &&
        await launchUrl(telUri, mode: LaunchMode.externalApplication)) {
      return EmergencyActionResult.callStarted;
    }

    final smsUri = Uri(
      scheme: 'sms',
      path: normalized,
      queryParameters: <String, String>{'body': smsBody},
    );

    if (await canLaunchUrl(smsUri) &&
        await launchUrl(smsUri, mode: LaunchMode.externalApplication)) {
      return EmergencyActionResult.smsOpened;
    }

    return EmergencyActionResult.failed;
  }
}
