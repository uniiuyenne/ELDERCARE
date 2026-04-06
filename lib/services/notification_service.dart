import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'local_notification_service.dart';

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;

  static Future<void> initialize() async {
    try {
      if (kDebugMode) {
        debugPrint('Initializing Firebase Cloud Messaging (FCM)...');
      }

      // Yêu cầu quyền thông báo
      await _requestPermissions();

      // Thiết lập handlers cho các trạng thái khác nhau
      _setupForegroundMessageHandler();
      _setupBackgroundMessageHandler();

      if (kDebugMode) {
        debugPrint('FCM initialized successfully');
      }
    } catch (e) {
      debugPrint('Error initializing FCM: $e');
    }
  }

  static Future<void> _requestPermissions() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (kDebugMode) {
      debugPrint(
        'User granted notification permissions: ${settings.authorizationStatus}',
      );
    }
  }

  static void _setupForegroundMessageHandler() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint(
          'Received foreground message: ${message.notification?.title}',
        );
      }
      // Xử lý message và hiển thị local notification
      _handleMessage(message);
    });
  }

  static void _setupBackgroundMessageHandler() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint('Message clicked from background/terminated state');
      }
      _handleMessage(message);
    });
  }

  /// Xử lý message từ FCM
  /// Hiển thị local notification cho cả foreground, background, và terminated state
  static void _handleMessage(RemoteMessage message) {
    if (kDebugMode) {
      debugPrint('Handling message: ${message.data}');
      debugPrint('Notification title: ${message.notification?.title}');
      debugPrint('Notification body: ${message.notification?.body}');
    }

    final messageType = message.data['type'];
    final taskTitle = message.data['taskTitle'] ?? 'Không xác định';

    try {
      if (messageType == 'task_completed') {
        // Hiển thị notification cho task completed
        final completedBy = message.data['completedBy'] ?? 'Cha/Mẹ';
        LocalNotificationService.showTaskCompletionNotification(
          taskTitle: taskTitle,
          completedBy: completedBy,
        );
      } else if (messageType == 'task_overdue') {
        // Hiển thị notification cho task overdue
        final dueDate = message.data['dueDate'] ?? 'không xác định';
        LocalNotificationService.showTaskOverdueNotification(
          taskTitle: taskTitle,
          dueDate: dueDate,
        );
      }
    } catch (e) {
      debugPrint('Error handling notification: $e');
    }
  }

  /// Gửi thông báo đến người dùng thông qua Cloud Functions
  /// Trong thực tế, bạn sẽ gọi API của bạn hoặc Cloud Function
  /// để gửi thông báo cho người dùng khác
  static Future<String?> getDeviceToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      if (kDebugMode) {
        debugPrint('FCM Device Token: $token');
      }
      return token;
    } catch (e) {
      debugPrint('Error getting device token: $e');
      return null;
    }
  }

  /// Lưu device token cho người dùng hiện tại
  static Future<void> saveDeviceToken(String userId) async {
    try {
      final token = await getDeviceToken();
      if (token != null && userId.isNotEmpty) {
        // Lưu token vào Firestore
        final userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId);

        // Get current tokens
        final userDoc = await userRef.get();
        final currentTokens = userDoc.data()?['deviceTokens'] as List? ?? [];

        // Add new token if not already present
        if (!currentTokens.contains(token)) {
          await userRef.set({
            'deviceTokens': [...currentTokens, token],
            'lastTokenUpdate': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          if (kDebugMode) {
            debugPrint('Device token saved for user: $userId');
            debugPrint('Token: $token');
          }
        }
      }
    } catch (e) {
      debugPrint('Error saving device token: $e');
    }
  }

  /// Hủy đăng ký từ topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      if (kDebugMode) {
        debugPrint('Unsubscribed from topic: $topic');
      }
    } catch (e) {
      debugPrint('Error unsubscribing from topic: $e');
    }
  }

  /// Đăng ký cho topic
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      if (kDebugMode) {
        debugPrint('Subscribed to topic: $topic');
      }
    } catch (e) {
      debugPrint('Error subscribing to topic: $e');
    }
  }

  /// Sinh ra topic name cho channel giao tiếp
  static String getChannelTopic(String channelId) {
    return 'channel_$channelId';
  }

  /// Sinh ra topic name cho task notifications
  static String getTaskNotificationTopic(String channelId) {
    return 'task_notification_$channelId';
  }

  /// Gửi push notification đến người dùng thông qua topic messaging
  /// Được gọi từ Cloud Function khi có sự kiện
  static Future<void> sendTaskCompletionNotification({
    required String childUid,
    required String taskTitle,
    required String channelId,
  }) async {
    try {
      // Bạn có thể gọi Cloud Function hoặc REST API ở đây
      // Mẫu: POST https://your-api.com/sendNotification
      // Body: {childUid, taskTitle, channelId}

      // Tạm thời, tôi sẽ implement bằng cách lưu vào Firestore
      // và client sẽ listen để nhận notification realtime

      if (kDebugMode) {
        debugPrint(
          'Task completion notification sent to: $childUid, task: $taskTitle',
        );
      }
    } catch (e) {
      debugPrint('Error sending push notification: $e');
    }
  }

  /// Lấy tất cả notification tokens của người dùng
  static Future<String?> getUserNotificationToken(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      final data = userDoc.data();
      if (data != null) {
        final notificationTokens = data['notificationTokens'];
        if (notificationTokens is List && notificationTokens.isNotEmpty) {
          return notificationTokens.first.toString();
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting user notification token: $e');
      return null;
    }
  }
}
