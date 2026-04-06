import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/app_shell.dart';
import 'services/background_location_service.dart';
import 'services/firebase_bootstrap_service.dart';

/// Background message handler cho trường hợp app bị terminate hoặc background
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data.isNotEmpty) {
    final messageType = message.data['type'];
    debugPrint('Background message received: type=$messageType');
    // FCM sẽ hiển thị notification tự động từ cloud function payload
    // Local handler sẽ được gọi khi người dùng tap vào notification
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FirebaseBootstrapService.initialize();
  } catch (e, st) {
    debugPrint('Firebase bootstrap failed: $e');
    debugPrintStack(stackTrace: st);
  }

  try {
    // Thiết lập background message handler cho FCM
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e, st) {
    debugPrint('Background message handler setup failed: $e');
    debugPrintStack(stackTrace: st);
  }

  try {
    await BackgroundLocationService.initialize();
  } catch (e, st) {
    debugPrint('Background service init failed: $e');
    debugPrintStack(stackTrace: st);
  }

  runApp(const MyApp());
}
