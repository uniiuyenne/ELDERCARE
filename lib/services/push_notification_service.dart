import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

int _fnv1a31(String input) {
  // 32-bit FNV-1a, then clamp to a positive 31-bit int.
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

int _stableNotificationId(RemoteMessage message) {
  final inboxId = message.data['inboxId']?.toString().trim() ?? '';
  if (inboxId.isNotEmpty) return _fnv1a31('inbox:$inboxId');

  final messageId = message.data['messageId']?.toString().trim() ?? '';
  if (messageId.isNotEmpty) return _fnv1a31('msg:$messageId');

  final fcmMessageId = message.messageId?.trim() ?? '';
  if (fcmMessageId.isNotEmpty) return _fnv1a31('fcm:$fcmMessageId');

  final channelId = message.data['channelId']?.toString().trim() ?? '';
  final type = message.data['type']?.toString().trim() ?? '';
  return _fnv1a31('fallback:$channelId:$type:${message.sentTime?.millisecondsSinceEpoch ?? 0}');
}

bool _shouldShowLocalInForeground(RemoteMessage message) {
  // Android: FCM does not display notification UI while foreground.
  // iOS: if message contains a notification payload and foreground presentation
  // is enabled, the system can already show it; avoid double alerts.
  if (defaultTargetPlatform == TargetPlatform.android) return true;
  return message.notification == null;
}

String _extractString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final v = data[key];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

({String title, String body}) _extractTitleBody(RemoteMessage message) {
  final n = message.notification;
  final title = (n?.title ?? '').trim();
  final body = (n?.body ?? '').trim();
  if (title.isNotEmpty || body.isNotEmpty) {
    return (title: title.isEmpty ? 'Thông báo' : title, body: body);
  }

  final dataTitle = _extractString(message.data, const [
    'title',
    'notification_title',
    'subject',
    'name',
  ]);
  final dataBody = _extractString(message.data, const [
    'body',
    'notification_body',
    'message',
    'content',
    'text',
  ]);

  return (
    title: dataTitle.isEmpty ? 'Thông báo' : dataTitle,
    body: dataBody,
  );
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (kDebugMode) {
      debugPrint('[push] background handler invoked; dataKeys=${message.data.keys.toList()} hasNotification=${message.notification != null}');
    }
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
    // ignore
  }

  // If the backend sends a data-only payload, Android won't show anything by
  // default. We display a local notification as a fallback.
  // IMPORTANT: If the payload contains a `notification` object, Android can
  // show it automatically while the app is background/terminated. In that case
  // we must NOT also show a local notification, otherwise the user sees
  // duplicates.
  try {
    if (kIsWeb) return;

    if (message.notification != null) {
      if (kDebugMode) {
        debugPrint('[push] background: skip local (notification payload present)');
      }
      return;
    }

    const channelId = 'chat_and_tasks_v4';
    const channelName = 'Chat & Công việc';

    final local = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await local.initialize(initSettings);

    final androidPlugin = local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'Thông báo chat và công việc',
          importance: Importance.high,
        ),
      );
    }

    final (:title, :body) = _extractTitleBody(message);
    if (title.trim().isEmpty && body.trim().isEmpty) return;

    if (kDebugMode) {
      debugPrint('[push] background show local notification title="$title" bodyLen=${body.length}');
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Thông báo chat và công việc',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final id = _stableNotificationId(message);
    await local.show(
      id,
      title,
      body,
      details,
      payload: message.data.isEmpty ? null : message.data.toString(),
    );
  } catch (_) {
    // ignore
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const String _androidChannelId = 'chat_and_tasks_v4';
  static const String _androidChannelName = 'Chat & Công việc';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;

  // In-memory dedupe guard to protect against accidental double delivery
  // (e.g. multiple listeners, rare platform quirks). Keyed by stable ID.
  final Map<int, int> _recentLocalNotifs = <int, int>{};

  Future<void> unregisterCurrentUserToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;
    await _removeTokenForUser(uid);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // TODO: deep link into ShareBox/task screen via response.payload
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          description: 'Thông báo chat và công việc',
          importance: Importance.high,
        ),
      );

      // Android 13+ runtime permission.
      try {
        await androidPlugin.requestNotificationsPermission();
      } catch (_) {
        // ignore
      }
    }

    // iOS permissions + foreground presentation.
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // ignore
    }

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      // Ensure bell inbox is populated when user opens from a notification.
      unawaited(_maybeCreateInboxFromMessage(message));
      // TODO: navigate based on message.data
    });

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Cold start from notification tap.
      unawaited(_maybeCreateInboxFromMessage(initial));
      // TODO: navigate based on initial.data
    }

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      if (user == null) {
        return;
      }
      await _syncTokenForUser(user.uid);
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => _syncTokenForUser(user.uid),
      );
    });
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
  }

  Future<void> _syncTokenForUser(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;

      if (kDebugMode) {
        debugPrint('[push] sync token for uid=$uid token=${token.substring(0, 12)}...');
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'token': token,
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('FCM token sync failed: $e');
    }
  }

  Future<void> _removeTokenForUser(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;

      if (kDebugMode) {
        debugPrint('[push] remove token for uid=$uid token=${token.substring(0, 12)}...');
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .delete();
    } catch (e) {
      debugPrint('FCM token remove failed: $e');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final (:title, :body) = _extractTitleBody(message);
    if (title.trim().isEmpty && body.trim().isEmpty) return;

    if (kDebugMode) {
      debugPrint('[push] onMessage; dataKeys=${message.data.keys.toList()} hasNotification=${message.notification != null} title="$title" bodyLen=${body.length}');
    }

    // Safety guard: never show a notification for messages sent by self.
    // Normally the server only sends to the receiver, but this prevents
    // edge cases (multiple devices, misrouted payloads) from spamming.
    try {
      final selfUid = FirebaseAuth.instance.currentUser?.uid;
      final senderUid = message.data['senderUid']?.toString();
      if (selfUid != null && senderUid != null && senderUid == selfUid) {
        return;
      }
    } catch (_) {
      // ignore
    }

    // Fallback: ensure the in-app bell inbox also receives an item.
    // This helps when a backend pushes FCM but the inbox write is delayed
    // or temporarily unavailable.
    unawaited(_maybeCreateInboxFromMessage(message));

    if (!_shouldShowLocalInForeground(message)) {
      if (kDebugMode) {
        debugPrint('[push] onMessage: skip local (platform/system will present)');
      }
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: 'Thông báo chat và công việc',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final id = _stableNotificationId(message);
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _recentLocalNotifs[id];
    if (last != null && (now - last) < 1500) {
      if (kDebugMode) {
        debugPrint('[push] onMessage: deduped local show (id=$id)');
      }
      return;
    }
    _recentLocalNotifs[id] = now;
    _recentLocalNotifs.removeWhere((_, ts) => (now - ts) > 15000);

    await _localNotifications.show(
      id,
      title,
      body,
      details,
      payload: message.data.isEmpty ? null : message.data.toString(),
    );

    if (kDebugMode) {
      debugPrint('[push] localNotifications.show done');
    }
  }

  Future<void> _maybeCreateInboxFromMessage(RemoteMessage message) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.trim().isEmpty) return;

      final senderUid = message.data['senderUid']?.toString();
      if (senderUid != null && senderUid == uid) return;

      final channelId = message.data['channelId']?.toString() ?? '';
      if (channelId.trim().isEmpty) return;

      final type = (message.data['type']?.toString() ?? '').trim();
      final effectiveType = type.isEmpty ? 'chat' : type;

      final taskId = message.data['taskId']?.toString() ?? '';
      final messageId = message.data['messageId']?.toString() ?? '';
      final inboxIdFromServer = message.data['inboxId']?.toString() ?? '';

      final nowMillis = DateTime.now().millisecondsSinceEpoch;

      final inboxId = inboxIdFromServer.trim().isNotEmpty
          ? inboxIdFromServer.trim()
          : effectiveType == 'task' && taskId.trim().isNotEmpty
            ? [channelId, 'task', taskId, nowMillis.toString()].join('_')
              : messageId.trim().isNotEmpty
              ? [channelId, 'chat', messageId].join('_')
              : [channelId, effectiveType, nowMillis.toString()].join('_');

      final (:title, :body) = _extractTitleBody(message);

      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .doc(inboxId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) return;

        tx.set(ref, {
          'type': effectiveType,
          'title': title,
          'body': body,
          'channelId': channelId,
          ...?(senderUid == null ? null : {'senderUid': senderUid}),
          ...?(taskId.trim().isEmpty ? null : {'taskId': taskId}),
          ...?(messageId.trim().isEmpty ? null : {'messageId': messageId}),
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('Inbox fallback write failed: $e');
    }
  }
}
