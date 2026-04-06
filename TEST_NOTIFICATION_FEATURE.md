# 🧪 Hướng dẫn Test Tính năng Thông báo

## ⚡ Quick Start - Test trong 3 bước

### 1️⃣ Build & Run App

```bash
cd e:\Thong\Flutter\ELDERCARE

# Clean & Get dependencies
flutter clean
flutter pub get

# Build APK/App
flutter run

# Hoặc build release
flutter build apk --release
```

### 2️⃣ Deploy Cloud Functions

```bash
cd functions

# Install dependencies
npm install

# Build TypeScript
npm run build

# Deploy functions
firebase deploy --only functions
```

### 3️⃣ Test Notification

#### Test Case 1: Task Completed Notification

**Setup:**
- Có 2 device/emulator: 1 cho cha/mẹ, 1 cho con
- Login tài khoản cha/mẹ trên device 1
- Login tài khoản con trên device 2

**Steps:**
1. Tại cha/mẹ device: Vào app → Select con → Chọn công việc
2. Click "Mark as Completed" / "✅ Hoàn thành"
3. Quan sát device con:
   - ✅ Notification hiển thị ngay lập tức
   - Tiêu đề: "✅ Công việc đã hoàn thành"
   - Nội dung: "Cha/Mẹ (tên) đã hoàn thành: [tên công việc]"

**Expected:**
- Khi app foreground: Popup notification
- Khi app background: Notification tray
- Khi app closed: Lock screen notification
- Khi phone sleep: Hiển thị ngay trên màn hình

---

#### Test Case 2: Task Overdue Notification

**Setup:**
- Có công việc hết hạn đã qua

**Steps (Method A - Manual via Firestore Console):**

1. Vào [Firebase Console](https://console.firebase.google.com)
2. Chọn project → Firestore Database
3. Navigate tới: `channels/{anyChannelId}/notifications`
4. Thêm document mới:

```json
{
  "type": "task_overdue",
  "taskTitle": "Lau bàn",
  "recipientUid": "uid_của_con",
  "dueDate": "2024-04-02",
  "completedBy": "Mẹ",
  "completedByUid": "uid_của_cha_mẹ"
}
```

5. Cloud Function tự động trigger & gửi notification
6. Quan sát con's device:
   - ⏰ Notification hiển thị
   - Tiêu đề: "⏰ Công việc quá hạn"
   - Nội dung: "Cha/Mẹ chưa hoàn thành: [tên] (Hạn: [ngày])"

**Expected:** Tương tự Test Case 1 nhưng với icon ⏰

---

#### Test Case 3: Multiple Notifications

**Steps:**
1. Tạo 3-4 tasks khác nhau
2. Mark each as completed
3. Quan sát:
   - Mỗi notification có ID khác nhau
   - Notification tray hiển thị tất cả
   - Tap vào mỗi notification có thể vào task đó

---

## 🔍 Verification Checklist

### Device notifications:
- [ ] Notification hiển thị trên lock screen
- [ ] Notification hiển thị trong notification tray
- [ ] Notification có sound/vibrate
- [ ] Tap notification mở app (hoặc navigate tới task)
- [ ] Dismiss notification hoạt động

### Content:
- [ ] Emoji ✅/⏰ hiển thị đúng
- [ ] Task title hiển thị đúng
- [ ] Cha/mẹ name hiển thị đúng
- [ ] Tiêu đề tiếng Việt hiển thị đúng

### Platforms:
- [ ] **Android**: Đặc biệt kiểm tra lock screen notification
- [ ] **iOS**: Kiểm tra banner notification
- [ ] **Web**: (N/A - nếu có PWA feature)

---

## 🐛 Debug - Kiểm tra Logs

### Android - View Device Logs

```bash
# Real-time logs
adb logcat | grep -i notification

# Firebase logs
adb logcat | grep -i firebase

# Flutter logs
flutter logs
```

### Check FCM Token

```dart
// Thêm vào app (development only)
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final token = await FirebaseMessaging.instance.getToken();
  print('🔑 FCM Token: $token');
  runApp(MyApp());
}
```

**Output:**
```
🔑 FCM Token: eS3WqaJiR0e:APA91b...
```

### Cloud Function Logs

```bash
firebase functions:log
# Hoặc
firebase functions:log --only sendTaskNotification
```

Expected output khi notification sent:
```
✓ Sending task_completed notification to user_123 with 1 device(s)
✓ Successfully sent 1 notification(s)
```

### Firestore Notification Status

1. Vào Firebase Console → Firestore
2. Navigate tới notification document vừa tạo
3. Check fields:
   - `sent: true` - Gửi thành công
   - `sentAt: [timestamp]` - Thời gian gửi
   - `sentToDevices: 1` - Số device nhận được
   - `error: null` - Không có lỗi

---

## 🚨 Common Issues & Solutions

### Issue 1: Notification không hiển thị

**Causes:**
- Device token không được save
- Notification permission bị deny
- Cloud function không trigger

**Solutions:**
```bash
# 1. Check permission trên device
# Settings → Apps → ElderCare → Notifications → Allow

# 2. Check token saved
# Vào Firebase Console → Firestore
# Check users/{uid}/deviceTokens[] có token không

# 3. Check Cloud Function
firebase functions:log

# 4. Manual test Cloud Function
firebase functions:call sendTaskNotification \
  --data='{
    "recipientUid":"user_id",
    "taskTitle":"Test",
    "channelId":"ch_123"
  }'
```

### Issue 2: Notification không hiển thị trên Lock Screen

**Android causes:**
- `fullScreenIntent` not set
- `importance` not max
- Notification permission level

**Solutions:**
```dart
// Verify settings in local_notification_service.dart
const androidDetails = AndroidNotificationDetails(
  'channel_id',
  'Channel Name',
  importance: Importance.max,      // ✅ MUST BE MAX
  priority: Priority.max,            // ✅ MUST BE MAX
  fullScreenIntent: true,            // ✅ MUST BE TRUE
  visibility: NotificationVisibility.public,  // ✅ PUBLIC
);
```

**iOS causes:**
- Permission not granted
- Critical alert not enabled for app

**Solutions:**
```dart
// In notification_service.dart
await _firebaseMessaging.requestPermission(
  alert: true,           // ✅
  badge: true,           // ✅
  sound: true,           // ✅
  criticalAlert: true,   // For iOS critical alerts
);
```

### Issue 3: Cloud Function Error

**Common Errors:**

```
"recipientUid not found in notification"
→ Firestore document missing 'recipientUid' field

"No valid device tokens found"
→ users/{uid}/deviceTokens array is empty

"Failed to send: InvalidRegistrationToken"
→ Device token expired or invalid (will be auto-removed)
```

**Fix:**
1. Check notification document structure
2. Ensure token is saved: `NotificationService.saveDeviceToken(userId)`
3. Check user document exists in `users` collection

---

## 📊 Performance Testing

### Task (Để đo hiệu suất)

```bash
# Test gửi 10 notifications liên tiếp
for i in {1..10}; do
  firebase firestore:import - <<EOF
{
  "channels": {
    "test_channel": {
      "notifications": {
        "notif_$i": {
          "type": "task_completed",
          "taskTitle": "Task $i",
          "recipientUid": "test_user_id",
          "completedBy": "Test Parent",
          "completedByUid": "parent_id"
        }
      }
    }
  }
}
EOF
  sleep 0.5
done
```

**Measure:**
- Cloud Function execution time
- Average latency từ write → notification
- Device notification display time

---

## 📱 Multi-Device Testing Setup

### Using Emulator + Physical Device

```bash
# Terminal 1: Physical device
adb devices  # Verify device connected
flutter run -d <device_id>

# Terminal 2: Android emulator
emulator -avd <emulator_name>
adb devices  # Verify emulator
flutter run -d emulator-5554

# Terminal 3: Monitor both
adb logcat -e "notification|firebase" -s "flutter" -s "Firebase"
```

### Firebase Test Lab (Cloud Testing)

```bash
# Build APK
flutter build apk --debug

# Upload to Firebase Test Lab
gcloud firebase test android run \
  --app=build/app/outputs/apk/debug/app-debug.apk \
  --test=build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk
```

---

## ✅ QA Checklist

- [ ] Notification hiển thị trong 5 giây
- [ ] Notification title/body Unicode (tiếng Việt) hiển thị đúng
- [ ] Emoji ✅ ⏰ hiển thị đúng
- [ ] Sound/vibrate hoạt động
- [ ] Tap notification không crash app
- [ ] Multiple notifications không overlap
- [ ] App background state xử lý đúng
- [ ] App terminated state xử lý đúng
- [ ] Network disconnect xử lý đúng
- [ ] Token refresh xử lý đúng
- [ ] Battery saver mode không block notification
- [ ] DND (Do Not Disturb) mode không block notification

---

## 📝 Test Report Template

```markdown
# Test Report - Push Notification Feature

**Date:** [ngày test]
**Devices:** [device list]
**App Version:** [version]

## Test Cases
- [ ] Task Completed - Lock Screen
- [ ] Task Completed - Foreground
- [ ] Task Completed - Background
- [ ] Task Overdue - Lock Screen
- [ ] Task Overdue - Foreground
- [ ] Task Overdue - Background
- [ ] Multiple Notifications
- [ ] Invalid Token Removal

## Issues Found
1. [Issue 1]
2. [Issue 2]

## Performance
- Latency: [time] ms
- Success Rate: [rate] %

## Sign-off
- QA: ___________
- Date: _________
```

---

## 🎯 Next Steps

1. ✅ Fix all compilation errors
2. ✅ Deploy Cloud Functions
3. ⬜ Test on emulator/device
4. ⬜ Test on multiple devices
5. ⬜ QA review
6. ⬜ Deploy to production

---

**Need help?** Check Firebase docs or run:
```bash
firebase functions:log
flutter logs
adb logcat
```
