# 🎯 Hướng Dẫn Tính Năng: Thông Báo Khi Hoàn Thành Ghi Chú

## 📋 Tổng Quan
Tính năng này cho phép **cha/mẹ** đánh dấu ghi chú (công việc) là hoàn thành, và **người con** sẽ nhận được **thông báo push** trên điện thoại của họ.

## 🔧 Các Thành Phần Được Triển Khai

### 1. **Firebase Cloud Messaging (FCM)** ✅
- Package: `firebase_messaging: ^14.8.0`
- Cho phép gửi push notification về các device

### 2. **NotificationService** (`lib/services/notification_service.dart`) ✅  
- Khởi tạo FCM và xử lý permission
- Quản lý topic subscription
- Lưu device token của người dùng
- Xử lý foreground/background messages

### 3. **Cập Nhật Business Logic** ✅
- Khi cha/mẹ ấn checkbox hoàn thành ghi chú
- Hệ thống ghi lại event vào Firestore collection `notifications`  
- Gửi push notification cho người con

### 4. **Cấu Hình Android** ✅
- Thêm permission `POST_NOTIFICATIONS` cho Android 13+
- Cấu hình Google Services plugin (version 4.4.4)

## 🚀 Cách Hoạt Động

### Flow Khi Cha/Mẹ Hoàn Thành Ghi Chú:

```
1. Cha/Mẹ mở ứng dụng
   ↓
2. Trong tab "Công việc", ấn checkbox để đánh dấu ghi chú hoàn thành
   ↓
3. Ứng dụng gọi _toggleTask(scope, task, completed=true)
   ↓
4. Cập nhật trạng thái trong Firestore:
   - completed: true
   - checkedAt: timestamp
   - checkedByRole: 'parent'
   ↓
5. Ghi event vào collection `channels/{channelId}/notifications`
   ↓
6. Gửi push notification qua Firebase Cloud Messaging
   ↓
7. Người con nhận được notification với tiêu đề:
   "Cha/Mẹ đã hoàn thành '[Tên Ghi Chú]'"
```

## 📱 Để Test Tính Năng:

### **Trên Emulator:**

1. **Mở ứng dụng trên 2 instance (hoặc 2 thiết bị)**
   - Instance 1 (Cha/Mẹ): Đăng nhập với tài khoản cha/mẹ
   - Instance 2 (Con): Đăng nhập với tài khoản con

2. **Người Con: Tạo Ghi Chú**
   - Ấn nút "Thêm công việc"
   - Nhập tên ghi chú: "Ăn cơm"
   - Nhập mô tả: "Ăn cơm lúc 12h"
   - Chọn thời hạn
   - Ấn "Thêm"

3. **Kiểm Tra Logs**
   - Xem console output từ `flutter run`
   - Tìm dòng: `Subscribed to topic: task_notification_...`
   - Tìm dòng: `Device token saved for user: ...`

4. **Cha/Mẹ: Hoàn Thành Ghi Chú**
   - Mở ứng dụng cha/mẹ
   - Tìm ghi chú "Ăn cơm"
   - Ấn checkbox để đánh dấu hoàn thành ✓

5. **Người Con: Nhận Thông Báo**
   - Trên instance con, sẽ thấy thông báo:
     ```
     Cha/Mẹ đã hoàn thành "ĂN CƠM"
     ```
   - Hoặc kiểm tra trong phần "Thông báo"

## 🔍 Debugging

### Xem FCM Logs:
```bash
# Chạy lệnh này để xem logs FCM
flutter run -d emulator-5554

# Tìm các dòng có chứa:
# - "Initializing Firebase Cloud Messaging"
# - "FCM initialized successfully"
# - "Subscribed to topic"
# - "Device token saved"
```

### Kiểm Tra Topic Subscription:
Logs sẽ hiển thị:
```
I/flutter: Subscribed to topic: task_notification_[channelId]
```

### Kiểm Tra Device Token:
Logs sẽ hiển thị:
```
I/flutter: FCM Device Token: [long-token-string]
```

## 📝 Các File Được Sửa Đổi

1. **pubspec.yaml** - Thêm `firebase_messaging: ^14.8.0`
2. **lib/services/notification_service.dart** - File mới, quản lý FCM
3. **lib/services/firebase_bootstrap_service.dart** - Cập nhật để khởi tạo FCM
4. **lib/screens/care_elder_screen.dart** - Cập nhật logic gửi notification
5. **android/build.gradle.kts** - Thêm Google Services plugin
6. **android/app/src/main/AndroidManifest.xml** - Thêm permission POST_NOTIFICATIONS

## 🎨 UI Các Thành Phần:

### Khi Người Con Nhận Được Notification:
```
┌─────────────────────────────┐
│  Cha/Mẹ đã hoàn thành       │ ← Notification popup
│  "ĂN CƠM"                   │
└─────────────────────────────┘
```

### Trong Danh Sách Thông Báo:
```
┌──────────────────────────────────┐
│ 📌 Cha/Mẹ đã hoàn thành "ĂN CƠM" │
│                            [Đọc]│
└──────────────────────────────────┘
```

## 🔐 Quyền Cần Cấp

- **Android 13+**: `POST_NOTIFICATIONS`
- **Location** (đã có sẵn): `ACCESS_FINE_LOCATION`

## ⚠️ Lưu Ý:

1. **Emulator:** Notification hoạt động tốt trên emulator Android 13+
2. **FCM Token:** Mỗi device/emulator có token khác nhau
3. **Connection:** Cần kết nối Internet để nhận notification
4. **Background:** Notification hoạt động cả khi app đang mở hoặc ở background

## 🌐 Để Deploy Lên Production:

Bạn sẽ cần:
1. **Cloud Function** hoặc **Python Backend** để gửi notification qua FCM API
2. **Server Endpoint** để nhận yêu cầu từ Flutter app
3. Ví dụ:
   ```
   POST /api/send-notification
   Body: {
     "recipientUid": "uid-cua-con",
     "taskTitle": "Ăn cơm",
     "channelId": "123_456"
   }
   ```

## 📚 Resources:

- [Firebase Cloud Messaging Docs](https://firebase.google.com/docs/cloud-messaging)
- [Flutter Firebase Messaging Plugin](https://pub.dev/packages/firebase_messaging)
- [Android Notification Guide](https://developer.android.com/guide/topics/ui/notifiers/notifications)

---

**Hoàn thành ngày:** 3/4/2026  
**Status:** ✅ Đã triển khai thành công
