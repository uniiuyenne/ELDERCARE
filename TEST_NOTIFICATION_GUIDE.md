# 📱 Hướng Dẫn Test: Tính Năng Thông Báo Hoàn Thành Ghi Chú (Cách 1 - Firestore Listener)

## ✨ Tính Năng Hoàn Thành

Khi **cha/mẹ** ấn checkbox ✓ để đánh dấu ghi chú là **hoàn thành**, **người con** sẽ **nhận được local notification** ngay lập tức trên thiết bị của họ.

---

## 🛠️ Cách Hoạt Động

```
┌─────────────────────────────────────────────────────────────┐
│  Cha/Mẹ ấn ✓ checkbox hoàn thành ghi chú                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
         ┌────────────────────────────────┐
         │ Cập nhật Firestore             │
         │ - completed: true              │
         │ - checkedAt: timestamp         │
         │ - checkedByRole: 'parent'      │
         └────────────────┬───────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │ Ghi event vào notifications        │
         │ collection:                        │
         │ - type: 'task_completed'           │
         │ - taskTitle: '[Tên Ghi Chú]'       │
         │ - recipientUid: '[UID Con]'        │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │ App Con Listen Notifications       │
         │ Collection (Firestore Listener)    │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │ Nhận Event Ngay Lập Tức            │
         │ (Realtime từ Firestore)            │
         └────────────────┬───────────────────┘
                          │
                          ▼
         ┌────────────────────────────────────┐
         │ Hiển Thị Local Notification        │
         │ "Cha/Mẹ đã hoàn thành '[Ghi Chú]'"│
         └────────────────────────────────────┘
```

---

## 📖 Hướng Dẫn Test Chi Tiết

### **Bước 1: Chuẩn Bị 2 Instances/Devices**

**Option A: Dùng 1 Emulator (Kiểm Tra Logs)**
- Đăng nhập 2 tài khoản khác nhau
- Kiểm tra logs để xem notification được ghi

**Option B: Dùng 2 Emulators (Tốt Nhất)**
- Mở 2 emulator khác nhau
- Instance 1: Cha/Mẹ
- Instance 2: Con

### **Bước 2: Cha/Mẹ - Setup**
1. Mở ứng dụng
2. Đăng nhập tài khoản cha/mẹ
3. Liên kết với tài khoản con
4. Vào trang chính cha/mẹ

### **Bước 3: Con - Setup**
1. Mở ứng dụng
2. Đăng nhập tài khoản con
3. Liên kết với tài khoản cha/mẹ
4. Vào trang chính con

### **Bước 4: Con - Tạo Ghi Chú**
1. Ấn nút "+ Thêm công việc"
2. Nhập thông tin:
   - **Tên**: "Ăn cơm"
   - **Mô tả**: "Ăn cơm lúc 12h"
   - **Thời hạn**: Chọn ngày hôm nay
3. Ấn "Thêm"

### **Bước 5: Kiểm Tra Firestore (Tuỳ Chọn)**
- Vào Firebase Console
- Chọn Firestore Database
- Điều hướng: `channels` → `{channelId}` → `tasks`
- Nên thấy ghi chú vừa tạo

### **Bước 6: Cha/Mẹ - Hoàn Thành Ghi Chú** ⭐
1. Trên app cha/mẹ, tìm ghi chú "Ăn cơm"
2. Ấn **checkbox ✓** để đánh dấu hoàn thành
3. **Đợi 1-2 giây**

### **Bước 7: Con - Nhận Notification** 🎉
**Kích hoạt:**
- Local notification sẽ xuất hiện trên thiết bị con:
  ```
  ┌─────────────────────────────────┐
  │ 🔔 Cha/Mẹ đã hoàn thành công việc│
  │                                  │
  │    ĂN CƠM                        │
  └─────────────────────────────────┘
  ```

---

## 🔍 Kiểm Tra Logs (Debug)

### **Trên Cha/Mẹ (Khi Ấn ✓):**
```
I/flutter: Task completion notification sent for task: ĂN CƠM
```

### **Trên Con (Khi Nhận Event):**
```
I/flutter: Task completion notification displayed: ĂN CƠM
```

---

## 📊 Kết Cấu Firestore Sau Khi Hoàn Thành

**Collection Path:** `channels/{channelId}/notifications`

**Document:**
```json
{
  "type": "task_completed",
  "taskId": "task_abc123",
  "taskTitle": "ĂN CƠM",
  "completedBy": "parent",
  "completedByUid": "uid_parent_123",
  "recipientUid": "uid_child_456",
  "createdAt": "2026-04-03T10:30:00Z",
  "read": false
}
```

---

## ⚙️ Implementation Details

### **Người Con App - Listener:**
```dart
// File: care_elder_screen.dart
void _listenForTaskCompletionNotifications(_FamilyScope scope) {
  _notificationsSub = FirebaseFirestore.instance
      .collection('channels')
      .doc(scope.channelId)
      .collection('notifications')
      .snapshots()
      .listen((snapshot) {
        for (final doc in snapshot.docs) {
          final type = doc.data()['type'];
          if (type == 'task_completed' && 
              doc.data()['recipientUid'] == currentUserUid) {
            // Hiển thị local notification
            LocalNotificationService.showTaskCompletionNotification(...);
          }
        }
      });
}
```

### **Cha/Mẹ Khi Ấn ✓:**
```dart
// File: care_elder_screen.dart
Future<void> _toggleTask(...) {
  // Cập nhật task
  await _taskCollection(scope).doc(task.id).set({...});
  
  // Nếu đánh dấu hoàn thành
  if (completed && scope.selfRole == 'parent') {
    await _sendTaskCompletionNotification(scope, task);
  }
}

Future<void> _sendTaskCompletionNotification(...) {
  // Ghi event vào Firestore
  await FirebaseFirestore.instance
      .collection('channels')
      .doc(scope.channelId)
      .collection('notifications')
      .add({
        'type': 'task_completed',
        'taskTitle': task.title,
        'recipientUid': scope.partnerUid,
        ...
      });
}
```

---

## 🎯 Điểm Mạnh của Cách 1:

✅ **Realtime:** Notification hiển thị trong 1-2 giây  
✅ **Không cần Backend:** Chỉ dùng Firestore  
✅ **Đơn giản:** Dễ triển khai  
✅ **Tiết kiệm:** Không tốn chi phí Cloud Function  
✅ **An toàn:** Sử dụng Firestore Security Rules  

---

## ⚠️ Giới Hạn:

❌ Chỉ hiển thị khi **app mở**  
❌ Notification không persistent (offline)  
❌ Không hiển thị khi app đóng hoặc background

---

## 🚀 Nếu Muốn Notification Cả Khi App Đóng:

Bạn cần **Cách 2 (Cloud Function)** để gửi push notification thực sự.

---

## ✅ Checklist Test:

- [ ] Cha/Mẹ đăng nhập thành công
- [ ] Con đăng nhập thành công
- [ ] Liên kết tài khoản thành công
- [ ] Con tạo ghi chú thành công
- [ ] Cha/Mẹ nhìn thấy ghi chú
- [ ] Cha/Mẹ ấn ✓ hoàn thành
- [ ] Con nhận được local notification
- [ ] Notification hiển thị đúng tiêu đề
- [ ] Notification có tiếng/rung (nếu bật)

---

**Trạng Thái:** ✅ Đã Triển Khai Xong  
**Ngày:** 3/4/2026  
**Cách:** Firestore Listener + Local Notification
