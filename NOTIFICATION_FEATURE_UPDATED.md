# Hướng dẫn Tính năng Thông báo Đẩy (Push Notification)

## 📱 Tổng quan
Ứng dụng ElderCare đã được cOBAP nhật để hỗ trợ thông báo đẩy (Push Notification) cho tài khoản con (càng) trong 2 trường hợp:

1. **✅ Công việc đã hoàn thành** - Khi cha/mẹ check hoàn thành công việc
2. **⏰ Công việc quá hạn** - Khi cha/mẹ không hoàn thành công việc và đã vượt quá thời hạn

## 🏗️ Kiến trúc

### Luồng hoạt động

```
┌─────────────────┐
│   Cha/Mẹ        │
│  Mark Task      │
│  Complete/      │
│  Overdue        │
└────────┬────────┘
         │
         ▼
┌──────────────────────────┐
│  Firestore writes to     │
│  channels/{id}/          │
│  notifications           │
└────────┬─────────────────┘
         │
         ▼
┌──────────────────────────────────────┐
│  Cloud Function Trigger              │
│  sendTaskNotification                │
│  (functions/src/index.ts)            │
└────────┬─────────────────────────────┘
         │
    ┌────┴────┐
    │          │
    ▼          ▼
┌─────────────┐ Send via
│   FCM API   │ Firebase Cloud
│             │ Messaging
└────┬────────┘
     │
     ▼
┌─────────────────────────────────────────┐
│  Con's Device nhận FCM message          │
│  Notification hiển thị trên Lock Screen │
│  • Foreground: Local notification       │
│  • Background: FCM tự động              │
│  • Terminated: FCM tự động              │
└─────────────────────────────────────────┘
```

## 📂 Cấu trúc File

### 1. **Cloud Functions** (`functions/src/index.ts`)
```typescript
// Exported function: sendTaskNotification
// Triggered by: Firestore onCreate event
// - channels/{channelId}/notifications/{notificationId}
// 
// Hỗ trợ 2 loại:
//   - type: "task_completed" → ✅ Công việc đã hoàn thành
//   - type: "task_overdue"   → ⏰ Công việc quá hạn
//
// Gửi FCM message với payload đầy đủ
// Xóa invalid device tokens đương
```

**Thay đổi chính:**
- Đổi tên function: `sendTaskCompletionNotification` → `sendTaskNotification`
- Hỗ trợ cả `task_completed` và `task_overdue`
- Thêm emoji và tiêu đề khác nhau cho 2 loại
- Thêm xử lý `dueDate` parameter

### 2. **Flutter Services**

#### a. `lib/services/notification_service.dart` (FCM)
```dart
// Quản lý Firebase Cloud Messaging
NotificationService.initialize()
  • Yêu cầu quyền notification
  • Setup foreground message handler
  • Setup background message open handler
  
Xử lý cả 2 loại notification:
  • task_completed → LocalNotificationService.showTaskCompletionNotification()
  • task_overdue → LocalNotificationService.showTaskOverdueNotification()
```

**Thay đổi:**
- Import `LocalNotificationService`
- Cập nhật `_handleMessage()` để xử lý 2 loại notification
- Gọi các method hiển thị local notification tương ứng

#### b. `lib/services/local_notification_service.dart`
```dart
// Hiển thị notification trên màn hình

// Initialize: Tạo 2 notification channels
// - task_completed_channel (xanh)
// - task_overdue_channel (đỏ)

// Thêm 2 method mới:
showTaskCompletionNotification() → ✅
showTaskOverdueNotification()    → ⏰

// Cấu hình cho cả Android & iOS:
// - Importance: MAX
// - Priority: MAX
// - Full screen intent: true (hiển thị trên lock screen)
// - Vibrate, Sound: enabled
// - Visibility: PUBLIC (hiển thị trên lock screen)
```

**Cấu hình Notification Channels:**

| Tham số | Giá trị | Mục đích |
|--------|--------|---------|
| `importance` | `max` | Ưu tiên cao nhất |
| `priority` | `max` | Hiển thị ngay lập tức |
| `fullScreenIntent` | `true` | Hiển thị full screen/lock screen |
| `enableVibration` | `true` | Rung điện thoại |
| `playSound` | `true` | Phát âm thanh thông báo |
| `visibility` | `public` | Hiển thị nội dung trên lock screen |

### 3. **main.dart** (Background Handler)
```dart
@pragma('vm:entry-point')
firebaseMessagingBackgroundHandler()
  • Handler cho trường hợp app bị terminate
  • FCM sẽ tự động hiển thị notification từ payload
  • Có thể trigger việc cập nhật dữ liệu nếu cần

firebaseMessaging.onBackgroundMessage()
  • Register background handler trước runApp()
```

## 🔄 Dòng sự kiện chi tiết

### Sự kiện: Cha/Mẹ Mark Task Hoàn thành

1. **Ứng dụng Cha/Mẹ ghi vào Firestore:**
```dart
await FirebaseFirestore.instance
  .collection('channels')
  .doc(channelId)
  .collection('notifications')
  .add({
    'type': 'task_completed',
    'taskTitle': 'Rửa tay',
    'recipientUid': childUid,
    'completedBy': parentName,
    'completedByUid': parentUid,
    'timestamp': FieldValue.serverTimestamp(),
  });
```

2. **Cloud Function triggered:**
```typescript
// Lấy device tokens của con
// Tạo FCM payload
// Gửi qua Firebase Cloud Messaging
// Update notification status
```

3. **Firebase Cloud Messaging gửi message:**
```json
{
  "notification": {
    "title": "✅ Công việc đã hoàn thành",
    "body": "Cha/Mẹ đã hoàn thành: Rửa tay"
  },
  "data": {
    "type": "task_completed",
    "taskTitle": "Rửa tay",
    "completedBy": "Mẹ",
    "channelId": "channel_123"
  }
}
```

4. **Con's device nhận notification:**
   - **LockScreen:** Notification hiển thị ngay (fullScreenIntent=true)
   - **App đang chạy (Foreground):** Local notification được trigger
   - **App background:** Notification hiển thị tự động bởi FCM
   - **App closed (Terminated):** Notification hiển thị, tap để mở app

5. **Hiển thị local notification:**
```
┌─────────────────────────────────────────┐
│  ✅ Công việc đã hoàn thành              │
│  Cha/Mẹ (Mẹ) đã hoàn thành: Rửa tay   │
│  ————————────————————────————————————   │
│                                         │
│     [Open]                 [Dismiss]    │
└─────────────────────────────────────────┘
```

### Sự kiện: Task Overdue (Cha/Mẹ không hoàn thành và quá hạn)

Tương tự, nhưng:
- `type` = `'task_overdue'`
- Tiêu đề: `'⏰ Công việc quá hạn'`
- Body: `'Cha/Mẹ chưa hoàn thành: [taskTitle] (Hạn: [dueDate])'`

## 📊 Các trạng thái Notification

### Android

| Trạng thái | Hiển thị |
|-----------|---------|
| **App chạy foreground** | Local notification popup + sound + vibrate |
| **App background** | FCM notification trên notification tray |
| **App terminated** | FCM notification trên lock screen |
| **Phone sleep** | Notification hiển thị ngay trên lock screen (fullScreenIntent) |

### iOS

| Trạng thái | Hiển thị |
|-----------|---------|
| **App chạy foreground** | Local notification banner + sound |
| **App background** | Notification trên lock screen |
| **App terminated** | Notification trên lock screen |

## 🧪 Testing

### Local Testing (Emulator/Device)

1. **Setup:**
   ```bash
   cd functions
   npm run build
   firebase emulators:start
   ```

2. **Manual Trigger via Cloud Function:**
   ```dart
   // Gọi test function
   final result = await FirebaseFunctions.instance
     .httpsCallable('testSendNotification')
     .call({
       'recipientUid': 'child_user_id',
       'taskTitle': 'Rửa tay',
       'channelId': 'channel_123',
     });
   ```

3. **Check Device Logs:**
   ```bash
   adb logcat | grep firebase
   flutter logs
   ```

### Production Deployment

1. **Deploy Cloud Functions:**
   ```bash
   cd functions
   npm run build
   firebase deploy --only functions
   ```

2. **Configure Android Manifest (nếu cần):**
   ```xml
   <!-- android/app/src/AndroidManifest.xml -->
   <permission android:name="android.permission.POST_NOTIFICATIONS" />
   ```

3. **iOS - entitlements (nếu cần):**
   ```xml
   <!-- Runner.entitlements -->
   <key>aps-environment</key>
   <string>production</string>
   ```

## ⚙️ Cấu hình

### Firestore Security Rules
```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Cha/Mẹ có thể ghi notification
    match /channels/{channelId}/notifications/{notificationId} {
      allow create: if request.auth != null;
      allow read: if request.auth.uid in resource.data.get('allowedUsers', []);
    }
  }
}
```

### Firebase Cloud Messaging

- **Topic:** `channel_{channelId}` (nếu sử dụng topic-based)
- **Token Management:** Device tokens được lưu tại `users/{uid}/deviceTokens[]`
- **Retry:** FCM tự động retry 3 lần khi gửi thất bại

## 🐛 Troubleshooting

### Notification không hiển thị

1. **Kiểm tra permission:**
   - Android: Kiểm tra `POST_NOTIFICATIONS` permission
   - iOS: Kiểm tra notification settings

2. **Kiểm tra device token:**
   ```dart
   final token = await FirebaseMessaging.instance.getToken();
   print('Device Token: $token');
   ```

3. **Kiểm tra Cloud Function logs:**
   ```bash
   firebase functions:log
   ```

4. **Kiểm tra FCM:**
   - Đảm bảo google-services.json/GoogleService-Info.plist được config đúng
   - Kiểm tra Firebase Projects settings

### Notification không hiển thị trên Lock Screen

- Đảm bảo `fullScreenIntent: true` được set
- Đảm bảo `importance: Importance.max` được set
- Trên Android, kiểm tra notification channel settings trong System Settings

## 📝 Ghi chú quan trọng

1. **Device Token Management:**
   - Tokens được lưu tự động khi `NotificationService.saveDeviceToken(userId)` được gọi
   - Invalid tokens bị xóa tự động khi gửi thất bại

2. **Notification Deduplication:**
   - Notification ID dùng `hashCode` của task title + offset
   - Cùng task title sẽ update notification cũ thay vì tạo mới

3. **Battery & Data:**
   - Notification được gửi qua FCM (tối ưu pin & data)
   - Local notification chỉ trigger khi app running hoặc mở từ background

4. **Privacy:**
   - Notification body hiển thị trên lock screen (considerecurity)
   - Sensitive data nên được encode hoặc ẩn

## 🔗 Tài liệu tham khảo

- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging)
- [Flutter Local Notifications](https://pub.dev/packages/flutter_local_notifications)
- [Firebase Cloud Functions](https://firebase.google.com/docs/functions)

## 📞 Liên hệ hỗ trợ

Nếu có vấn đề, vui lòng kiểm tra lại:
1. Cloud Function logs
2. Device notification settings
3. Firebase console - Cloud Messaging
4. Flutter debug output
