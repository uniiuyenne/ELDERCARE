import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'services/background_location_service.dart';
import 'services/firebase_bootstrap_service.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FirebaseBootstrapService.initialize();
  } catch (e, st) {
    debugPrint('Firebase bootstrap failed: $e');
    debugPrintStack(stackTrace: st);
  }

  try {
    await BackgroundLocationService.initialize();
  } catch (e, st) {
    debugPrint('Background service init failed: $e');
    debugPrintStack(stackTrace: st);
  }

  try {
    await PushNotificationService.instance.initialize();
  } catch (e, st) {
    debugPrint('Push notification init failed: $e');
    debugPrintStack(stackTrace: st);
  }

  runApp(const MyApp());
}
