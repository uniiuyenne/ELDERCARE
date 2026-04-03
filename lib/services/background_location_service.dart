import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

import '../firebase_options.dart';
import 'location_service.dart';

@pragma('vm:entry-point')
class BackgroundLocationService {
  const BackgroundLocationService._();

  static const String _channelId = 'eldercare_bg_silent';
  static const int _notificationId = 7261;

  static Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final service = FlutterBackgroundService();
    try {
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          notificationChannelId: _channelId,
          initialNotificationTitle: 'ElderCare',
          initialNotificationContent: '',
          foregroundServiceNotificationId: _notificationId,
          foregroundServiceTypes: [AndroidForegroundType.location],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onStart,
        ),
      );
    } catch (e, st) {
      debugPrint('BackgroundLocationService.configure failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  static Future<void> start() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (!isRunning) {
      await service.startService();
    }
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();

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
    } catch (_) {
      // Ignore duplicate-app and transient init errors in background isolate.
    }

    if (service is AndroidServiceInstance) {
      service.on('stopService').listen((_) {
        service.stopSelf();
      });

      // Android requires a visible foreground service notification for
      // continuous background location updates.
      service.setForegroundNotificationInfo(
        title: 'ElderCare',
        content: '',
      );
    }

    Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (service is AndroidServiceInstance) {
        final inForeground = await service.isForegroundService();
        if (!inForeground) {
          service.setAsForegroundService();
        }
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      late final Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (_) {
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      String address = '';
      try {
        address = await LocationService.getAddressFromLatLng(
          pos.latitude,
          pos.longitude,
        );
      } catch (_) {
        // Ignore reverse-geocoding failures and keep syncing coordinates.
      }

      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'location': {
            'lat': pos.latitude,
            'lng': pos.longitude,
            'address': address,
            'updatedAt': FieldValue.serverTimestamp(),
            'source': 'background-service',
          },
        }, SetOptions(merge: true));
      } catch (_) {
        // Keep service running and try again on next tick.
      }
    });
  }
}
