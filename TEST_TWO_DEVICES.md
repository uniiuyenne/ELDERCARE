# 📱 Hướng Dẫn Test: Notification Giữa 2 Máy Laptop (Cách 2 - Cloud Function)

## 🎯 Mục Tiêu

Kiểm Tra: 
- ✅ Máy Cha/Mẹ ấn ✓ hoàn thành
- ✅ Máy Con nhận FCM push notification
- ✅ Notification hoạt động **cả khi app đóng/background**

---

## 🛠️ Chuẩn Bị

### Trước Khi Bắt Đầu:
1. ✅ Cloud Functions đã deploy (xem `DEPLOY_CLOUD_FUNCTIONS.md`)
2. ✅ Flutter app chạy trên 2 máy/emulator
3. ✅ 2 tài khoản Firebase (cha/mẹ + con)
4. ✅ Tài khoản đã liên kết

---

## 📝 Setup Chi Tiết

### **Máy 1 - Cha/Mẹ (Laptop Khác)**

#### Step 1: Download & Cài App
1. Clone project hoặc pull code mới nhất
2. Mở terminal:
```bash
cd path/to/ELDERCARE
flutter pub get
flutter run
```

#### Step 2: Đăng Nhập
- Email: `parent@example.com` (hoặc tài khoản cha/mẹ)
- Mật khẩu: `Password123`

#### Step 3: Setup Hồ Sơ
- **Bước 1 (Login):** Chọn "Đăng nhập Google"
- **Bước 2 (Phone):** Nhập số điện thoại cha/mẹ (VD: 0912345678)
- **Bước 3 (Role):** Chọn "Cha/Mẹ"
- **Bước 4 (Link):** Liên kết với số điện thoại con

#### Step 4: Vào Trang Chính
- Nếu lần đầu: Bật quyền vị trí "Luôn cho phép"
- Chờ load xong

#### Step 5: Kiểm Tra Điều Kiện
- App đang chạy trên máy 1
- Có thể thấy ghi chú từ con (nếu có)

---

### **Máy 2 - Con (Laptop Hiện Tại)**

#### Step 1: Chuẩn Bị Ứng Dụng
1. Đảm bảo code là latest (có cloud function support)
2. Build & run:
```bash
cd ELDERCARE
flutter pub get
flutter run -d <device_id>  # hoặc emulator
```

#### Step 2: Đăng Nhập
- Email: `child@example.com` (hoặc tài khoản con)
- Mật khẩu: `Password123`

#### Step 3: Setup Hồ Sơ
- **Bước 1:** "Đăng nhập Google"
- **Bước 2:** Nhập số điện thoại con (VD: 0987654321)
- **Bước 3:** Chọn "Con"
- **Bước 4:** Liên kết với số điện thoại cha/mẹ

#### Step 4: Vào Trang Chính
- App đang chạy
- Bật thông báo nếu được hỏi

---

## 🧪 Test Scenario 1: Notification Khi App Mở

### **Máy 2 (Con): Tạo Ghi Chú**
```
Bước 1: Tìm tab "Công Việc" hoặc "Tasks"
Bước 2: Ấn nút "+ Thêm công việc"
Bước 3: Điền thông tin:
  - Tên: "Ăn cơm"
  - Mô tả: "Ăn cơm lúc 12h trưa"
  - Thời hạn: Hôm nay, 12:00
Bước 4: Ấn "Thêm"

✅ Kiểm Tra: Ghi chú xuất hiện trong danh sách
```

### **Máy 1 (Cha/Mẹ): Hoàn Thành Ghi Chú**
```
Bước 1: Làm mới (Pull-to-refresh) hoặc chờ
Bước 2: Tìm ghi chú "Ăn cơm"
Bước 3: Ấn checkbox ✓ bên cạnh ghi chú

⏱️ Đợi 1-2 giây...

✅ Kiểm Tra: Ghi chú có dấu ✓ hoàn thành
```

### **Máy 2 (Con): Nhận Notification**
```
🔔 NGAY LẬP TỨC, máy 2 sẽ hiển thị:

┌────────────────────────────────────┐
│ ✅ Công việc đã hoàn thành          │
│                                    │
│ Cha/Mẹ đã hoàn thành: ĂN CƠM       │
│                                    │
│ [Ấn để xem]                        │
└────────────────────────────────────┘

✅ Kiểm Tra:
- [ ] Notification hiển thị
- [ ] Tiêu đề đúng
- [ ] Có tiếng/rung (nếu bật)
```

---

## 🧪 Test Scenario 2: Notification Khi App Đóng

### **Máy 2 (Con): Chuẩn Bị**
```
Bước 1: Tạo ghi chú mới:
  - Tên: "Làm bài tập"
  - Mô tả: "Làm bài toán"
  - Thời hạn: Hôm nay, 15:00
Bước 2: Ấn "Thêm"
Bước 3: ĐÓNG ỨNG DỤNG HOÀN TOÀN
  - Ấn Home button hoặc Swipe up để close app
  - Xác nhận app không còn chạy
```

### **Máy 1 (Cha/Mẹ): Hoàn Thành**
```
Bước 1: Làm mới danh sách ghi chú
Bước 2: Tìm ghi chú "Làm bài tập"
Bước 3: Ấn checkbox ✓

⏱️ Đợi 1-2 giây...
```

### **Máy 2 (Con): Nhận Notification Khi App Đóng**
```
🔔 NOTIFICATION XUẤT HIỆN TRÊ
N LOCK SCREEN HOẶC SYSTEM TRAY:

📱 Lock Screen (nếu điện thoại khóa):
┌────────────────────────────────┐
│ ✅ Công việc đã hoàn thành      │
│ Cha/Mẹ đã hoàn thành: LÀM BÀI TP│
└────────────────────────────────┘

🔔 Notification Tray (Swipe down):
📱 Notification Center
├─ ✅ Công việc đã hoàn thành
│   Cha/Mẹ đã hoàn thành: LÀM BÀI TẬP
└─ [Earlier notifications...]

✅ Điểm Quan Trọng:
- [✓] Notification xuất hiện cả khi app đóng
- [✓] Notification có tiếng/rung mạnh
- [✓] Ấn notification mở app (Deep Link tùy chọn)
```

---

## 📊 Monitoring & Debugging

### **Kiểm Tra Cloud Function Logs**
```bash
# Terminal trên máy phát triển
firebase functions:log
```

**Log thành công sẽ như:**
```
4:05:23 PM  sendTaskCompletionNotification
      Successfully sent 1 notification(s)
```

### **Kiểm Tra Device Token**
1. Vào Firebase Console
2. Firestore Database
3. Collection `users`
4. Mở document của con (child user)
5. Xem field `deviceTokens`

**Phải có array tokens:**
```
deviceTokens: [
  "dWSZNp1UTiW...APA91bFRmvXt...",
]
```

### **Kiểm Tra Notification Event**
1. Vào Firebase Console
2. Firestore Database
3. `channels` → `{channelId}` → `notifications`
4. Mở document vừa tạo

**Phải có:**
```json
{
  "type": "task_completed",
  "taskTitle": "Ăn cơm",
  "sent": true,
  "sentAt": "2026-04-03T10:30:00Z",
  "sentToDevices": 1
}
```

---

## 🔍 Troubleshooting

### ❌ Notification Không Hiển Thị

**Nguyên Nhân 1: Device Token Chưa Được Lưu**
```bash
✅ Giải Pháp:
1. Mở app con lần nữa
2. Chờ 2-3 giây
3. Kiểm tra Firestore xem token có chưa
4. Nếu còn là [], tôi cần cập nhật code
```

**Nguyên Nhân 2: Cloud Function Chưa Deploy**
```bash
✅ Giải Pháp:
firebase deploy --only functions
firebase functions:log  # Check  deployed
```

**Nguyên Nhân 3: Notification Permission Chưa Bật**
```bash
✅ Giải Pháp (Android):
1. Mở Settings
2. Apps → App name → Notifications
3. Bật "Allow notifications"
```

### ⚠️ Notification Hiển Thị Muộn (>5 giây)

**Nguyên Nhân:** Network chậm hoặc Cloud Function lag
```bash
✅ Giải Pháp:
- Thử lại hoặc kiểm tra internet
- Xem Cloud Function logs
```

### ⚠️ Notification Hiển Thị Nhiều Lần

**Nguyên Nhân:** Device token bị lưu duplicate
```bash
✅ Giải Pháp:
firebase firestore:delete users/{userId}/deviceTokens
# Rồi mở app lại
```

---

## ✅ Checklist Test

| # | Kiểm Tra | Kết Quả | Ghi Chú |
|---|----------|---------|--------|
| 1 | 2 máy kết nối Firebase | ✓ |  |
| 2 | Mỗi máy có device token | ✓ |  |
| 3 | Mailbox hoàn thành ghi chú | ✓ |  |
| 4 | Cloud Function trigger | ✓ | Xem logs |
| 5 | Notification hiển thị (app mở) | ✓ |  |
| 6 | Notification hiển thị (app đóng) | ✓ |  |
| 7 | Notification có tiếng | ✓ |  |
| 8 | Notification có rung | ✓ |  |
| 9 | Notification persistent | ✓ | Không tự mất |
| 10 | Connection stabil 2 máy | ✓ |  |

---

## 🎯 Expected Results

```
Test Pass Criteria:

✅ Máy Cha/Mẹ ấn checkbox
   ↓ (1-2 giây sau)
✅ Máy Con nhận notification ngay lập tức
   
✅ Notification hiển thị:
   - Tiêu đề: "✅ Công việc đã hoàn thành"
   - Thân: "Cha/Mẹ đã hoàn thành: [Tên ghi chú]"
   - Có tiếng/rung
   
✅ Hoạt động cả khi:
   - App mở (foreground)
   - App background
   - App đóng hoàn toàn
```

---

## 📸 Screenshots Mong Đợi

```
EXPECTED STATES:

Screen 1 - Máy Cha/Mẹ:
┌─────────────────────────────┐
│ Công Việc                   │
├─────────────────────────────┤
│ ☐ Giặt quần áo      [Edit]  │
│ ☐ Rửa chén           [Edit]  │
│ ☑ Ăn cơm             [Edit]  ← Just checked!
└─────────────────────────────┘

Screen 2 - Máy Con (Lock):
┌──────────────────────────┐
│ 2:30 PM   Tuesday        │
│                          │
│ 🔔                       │
│ ✅ Công việc đã hoàn thành│
│ Cha/Mẹ đã hoàn thành:    │
│ ĂN CƠM                   │
│                          │
│ [Swipe để mở]            │
└──────────────────────────┘
```

---

## 🚀 Kết Luận

**Nếu tất cả kiểm tra ✅ → Notification System HOÀN THÀNH!**

---

**Version:** v2.0 (Cloud Function)  
**Ngày:** 3/4/2026  
**Support:** Xem logs: `firebase functions:log`
