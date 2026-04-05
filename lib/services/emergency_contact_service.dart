import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum EmergencyActionResult {
  callStarted,
  smsOpened,
  failed,
}

class EmergencyContactService {
  static const MethodChannel _phoneChannel = MethodChannel('eldercare/phone');

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

    // Android: try a true direct call first (no dialer), requesting permission if needed.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final ok = await _phoneChannel.invokeMethod<bool>('directCall', {
          'number': normalized,
        });
        if (ok == true) {
          return EmergencyActionResult.callStarted;
        }
      } catch (_) {
        // Ignore and fall back to tel: launcher.
      }
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
