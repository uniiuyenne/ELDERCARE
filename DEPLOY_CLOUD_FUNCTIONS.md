# 🚀 Hướng Dẫn Deploy Cloud Functions (Cách 2)

## 📋 Tổng Quan

**Cloud Function** sẽ:
1. Listen khi cha/mẹ hoàn thành ghi chú (document mới trong `notifications` collection)
2. Lấy device token của người con từ Firestore
3. Gửi FCM push notification về máy con
4. **Hoạt động cả khi app đóng hoặc background**

---

## ⚙️ Bước 1: Chuẩn Bị Environment

### 1.1 Cài Đặt Firebase CLI
```bash
npm install -g firebase-tools
```

### 1.2 Đăng Nhập Firebase
```bash
firebase login
```
- Sẽ mở trình duyệt
- Chọn tài khoản Google (cùng tài khoản tạo Firebase project)
- Cho phép quyền

### 1.3 Kiểm Tra Project
```bash
firebase projects:list
```

Xác nhận project `careelder-e475b` có trong danh sách

---

## 📁 Bước 2: Cấu Trúc Thư Mục (Đã Có Sẵn)

```
ELDERCARE/
├── functions/
│   ├── src/
│   │   └── index.ts          ✅ Cloud Function code
│   ├── package.json          ✅ Dependencies
│   ├── tsconfig.json         ✅ TypeScript config
│   └── lib/                  (Auto-generated)
├── firebase.json             ✅ Firebase config
├── firestore.rules           ✅ Security rules
└── ...
```

---

## 💾 Bước 3: Setup Functions Folder (Lần Đầu)

### 3.1 Mở Terminal Trong Project
```bash
cd E:\Thong\Flutter\ELDERCARE
```

### 3.2 Cài Đặt Dependencies
```bash
cd functions
npm install
cd ..
```

**Output mong đợi:**
```
added 450+ packages
```

### 3.3 Build TypeScript -> JavaScript
```bash
cd functions
npm run build
cd ..
```

**Output mong đợi:**
```
✓ tsc compiled successfully
```

---

## 🔑 Bước 4: Thiết Lập Firebase Project

### 4.1 Set Project Default
```bash
firebase use --add
```

**Chọn:** `careelder-e475b`  
**Alias:** `default`

### 4.2 Cập Nhật Firestore Rules
```bash
firebase deploy --only firestore:rules
```

**Output:**
```
✓ firestore rules deployed successfully
```

---

## ✅ Bước 5: Deploy Cloud Functions

### 5.1 Deploy Hàm Chính
```bash
firebase deploy --only functions
```

**Output mong đợi:**
```
✓ functions[sendTaskCompletionNotification]: Successful
✓ functions[testSendNotification]: Successful
```

### 5.2 Kiểm Tra Logs
```bash
firebase functions:log
```

---

## 🧪 Bước 6: Test Cloud Function

### 6.1 Test Manual (Optional)
```javascript
// Vào Firebase Console → Functions → testSendNotification
// Click "Test the Function"

{
  "recipientUid": "uid_of_child",
  "taskTitle": "Test Task",
  "channelId": "channel_id"
}
```

---

## 📱 Bước 7: Cập Nhật App Flutter

### 7.1 Rebuild & Deploy
```bash
cd E:\Thong\Flutter\ELDERCARE
flutter pub get
flutter run -d emulator-5554
```

---

## 🧪 Bước 8: Full Test (2 Máy Laptop)

### Setup:
- **Máy 1 (Cha/Mẹ):** Laptop khác, đăng nhập tài khoản cha/mẹ
- **Máy 2 (Con):** Laptop hiện tại, đăng nhập tài khoản con

### Test Flow:

#### 8.1 Máy Con: Tạo Ghi Chú
```
1. Mở app
2. Ấn "+ Thêm công việc"
3. Nhập: "Ăn cơm", "Ăn lúc 12h"
4. Ấn "Thêm"
```

#### 8.2 Máy Cha/Mẹ: Hoàn Thành Ghi Chú
```
1. Mở app
2. Tìm ghi chú "Ăn cơm"
3. Ấn ✓ checkbox
```

#### 8.3 Máy Con: Nhận Notification
```
☑️ NGAY LẬP TỨC (1-2 giây):
┌─────────────────────────────┐
│ ✅ Công việc đã hoàn thành   │
│                              │
│  Cha/Mẹ đã hoàn thành:       │
│  ĂN CƠM                      │
└─────────────────────────────┘
```

**Lưu Ý:**
- ✅ Notification hiển thị **cả khi app đóng**
- ✅ Notification có **tiếng/rung**
- ✅ Notification **persistent** (không tự mất)

---

## 🔍 Debugging

### Check Logs
```bash
firebase functions:log
```

**Tìm dòng:**
```
Successfully sent 1 notification(s)
```

### Check Device Token
1. Vào Firebase Console
2. Firestore Database
3. `users` collection
4. Chọn user id
5. Xem field `deviceTokens`

**Nó phải có giá trị token:**
```
"dWSZNp1UTiW1ZXmZ9KXyaO:APA91bFRmvXtegDAHxm4..."
```

### Check Notification Document
```
channels > {channelId} > notifications > {notificationId}
```

**Sau khi hoàn thành, nó sẽ có:**
```
{
  type: "task_completed",
  sent: true,
  sentAt: <timestamp>,
  sentToDevices: 1
}
```

---

## ⚠️ Troubleshooting

### ❌ "sendTaskCompletionNotification not found"
**Giải pháp:**
```bash
firebase deploy --only functions
firebase functions:log  # Check if deployed
```

### ❌ "No device tokens found"
**Nguyên nhân:** App chưa lưu device token
**Giải pháp:**
1. Mở app
2. Chờ 2-3 giây
3. Kiểm tra Firestore `users` collection

### ❌ "Permission denied"
**Giải pháp:**
```bash
firebase deploy --only firestore:rules
```

### ❌ "Function timed out"
**Giải pháp:** Tăng timeout trong Cloud Function config

---

## 📊 Quy Trình Hoạt Động

```
┌────────────────────────────────────────────────────────┐
│ Máy Cha/Mẹ Ấn ✓                                        │
└────────────────────┬─────────────────────────────────┘
                     ↓
         ┌───────────────────────────┐
         │ Firestore Task Updated    │
         │ - completed: true         │
         └────────────┬──────────────┘
                      ↓
         ┌────────────────────────────────────┐
         │ Create Event trong notifications   │
         │ collection                         │
         └────────────┬───────────────────────┘
                      ↓
         ┌────────────────────────────────────┐
         │ ⚡ Cloud Function Trigger          │
         │ sendTaskCompletionNotification     │
         └────────────┬───────────────────────┘
                      ↓
         ┌────────────────────────────────────┐
         │ 1. Lấy device token của con        │
         │ 2. Tạo FCM message                 │
         │ 3. Gửi via Firebase Cloud          │
         │    Messaging                       │
         └────────────┬───────────────────────┘
                      ↓
         ┌────────────────────────────────────┐
         │ Device Con Nhận FCM Message        │
         └────────────┬───────────────────────┘
                      ↓
         ┌────────────────────────────────────┐
         │ 🔔 Push Notification Hiển Thị      │
         │ (Cả khi app đóng/background)       │
         └────────────────────────────────────┘
```

---

## ✨ Features Bổ Sung

### Optional: Callable Function Test
Bạn có thể test bằng HTTP:
```bash
# Gọi từ Flutter:
final result = await FirebaseFunctions.instance
  .httpsCallable('testSendNotification')
  .call({
    'recipientUid': childUid,
    'taskTitle': 'Test',
    'channelId': channelId,
  });
```

---

## 📝 Checklist Deploy

- [ ] Firebase CLI cài đặt
- [ ] Đăng nhập Firebase
- [ ] `firebase use --add` setup
- [ ] `cd functions && npm install`
- [ ] `npm run build`
- [ ] `firebase deploy --only firestore:rules`
- [ ] `firebase deploy --only functions`
- [ ] Kiểm tra `firebase functions:log`
- [ ] Test trên 2 máy laptop
- [ ] Notification hiển thị thành công

---

## 🎯 Kết Quả Mong Đợi

```
✅ Máy Cha/Mẹ ấn ✓
   ↓
✅ Firestore cập nhật
   ↓
✅ Cloud Function trigger (1-2s)
   ↓
✅ FCM message gửi đi
   ↓
✅ Máy Con nhận push notification
   ↓
🔔 Notification popup ngay lập tức
   ✅ Cả khi app đóng
   ✅ Cả khi background
   ✅ Có tiếng/rung
```

---

**Status:** Deploy Ready  
**Ngày:** 3/4/2026  
**Contact:** Nếu có lỗi, kiểm tra logs: `firebase functions:log`
