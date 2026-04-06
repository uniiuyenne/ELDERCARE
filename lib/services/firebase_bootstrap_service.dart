import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'notification_service.dart';
import 'local_notification_service.dart';

class FirebaseBootstrapService {
  const FirebaseBootstrapService._();

  static Future<void> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        } else {
          await Firebase.initializeApp();
        }
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!msg.contains('duplicate-app')) {
        rethrow;
      }
    }

    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: true,
      );
      debugPrint(
        'Firebase Auth test mode enabled (no real SMS, using test phone numbers only)',
      );
    }

    // Khởi tạo Firebase Cloud Messaging
    try {
      await NotificationService.initialize();
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }

    // Khởi tạo Local Notifications
    try {
      await LocalNotificationService.initialize();
    } catch (e) {
      debugPrint('Error initializing LocalNotificationService: $e');
    }
  }
}
