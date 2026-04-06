import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Channel IDs
  static const String _taskCompletedChannelId = 'task_completed_channel';
  static const String _taskOverdueChannelId = 'task_overdue_channel';

  static Future<void> initialize() async {
    try {
      if (kDebugMode) {
        debugPrint('Initializing Local Notifications...');
      }

      // iOS cấu hình
      final iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        notificationCategories: [
          DarwinNotificationCategory(
            'task_completed',
            actions: [
              DarwinNotificationAction.plain('id_1', 'Open'),
              DarwinNotificationAction.plain('id_2', 'Dismiss'),
            ],
          ),
          DarwinNotificationCategory(
            'task_overdue',
            actions: [
              DarwinNotificationAction.plain('id_1', 'Open'),
              DarwinNotificationAction.plain('id_2', 'Dismiss'),
            ],
          ),
        ],
      );

      // Khởi tạo plugin
      await _notificationsPlugin.initialize(
        InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: iosSettings,
        ),
      );

      if (kDebugMode) {
        debugPrint('Local Notifications initialized successfully');
      }
    } catch (e) {
      debugPrint('Error initializing local notifications: $e');
    }
  }

  /// Hiển thị notification khi cha/mẹ hoàn thành công việc
  static Future<void> showTaskCompletionNotification({
    required String taskTitle,
    required String completedBy,
    String? message,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        _taskCompletedChannelId,
        'Task Completion',
        channelDescription: 'Notifications when parent completes a task',
        importance: Importance.max,
        priority: Priority.max,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'task_completed',
        threadIdentifier: 'task_notifications',
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final notificationId = taskTitle.hashCode;
      await _notificationsPlugin.show(
        notificationId,
        '✅ Công việc đã hoàn thành',
        'Cha/Mẹ ($completedBy) đã hoàn thành: $taskTitle',
        notificationDetails,
      );

      if (kDebugMode) {
        debugPrint('Task completion notification shown: $taskTitle');
      }
    } catch (e) {
      debugPrint('Error showing task completion notification: $e');
    }
  }

  /// Hiển thị notification khi công việc quá hạn
  static Future<void> showTaskOverdueNotification({
    required String taskTitle,
    required String dueDate,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        _taskOverdueChannelId,
        'Task Overdue',
        channelDescription: 'Notifications when task is overdue',
        importance: Importance.max,
        priority: Priority.max,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification'),
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        tag: 'overdue_task',
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'task_overdue',
        threadIdentifier: 'task_notifications',
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final notificationId = taskTitle.hashCode + 1000;
      await _notificationsPlugin.show(
        notificationId,
        '⏰ Công việc quá hạn',
        'Cha/Mẹ chưa hoàn thành: $taskTitle (Hạn: $dueDate)',
        notificationDetails,
      );

      if (kDebugMode) {
        debugPrint('Task overdue notification shown: $taskTitle');
      }
    } catch (e) {
      debugPrint('Error showing task overdue notification: $e');
    }
  }

  /// Hủy tất cả notifications
  static Future<void> cancelAll() async {
    try {
      await _notificationsPlugin.cancelAll();
      if (kDebugMode) {
        debugPrint('All notifications cancelled');
      }
    } catch (e) {
      debugPrint('Error cancelling notifications: $e');
    }
  }

  /// Hủy một notification cụ thể
  static Future<void> cancelNotification(int notificationId) async {
    try {
      await _notificationsPlugin.cancel(notificationId);
      if (kDebugMode) {
        debugPrint('Notification $notificationId cancelled');
      }
    } catch (e) {
      debugPrint('Error cancelling notification $notificationId: $e');
    }
  }
}
