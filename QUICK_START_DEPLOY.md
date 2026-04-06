# ⚡ Quick Start: Deploy Cloud Function (5 Phút)

## 🏃 Super Quick Setup

### 1️⃣ Cài Đặt Firebase CLI (Lần Đầu)
```bash
npm install -g firebase-tools
firebase login
```

### 2️⃣ Build & Deploy Functions
```bash
cd E:\Thong\Flutter\ELDERCARE
cd functions
npm install
npm run build
cd ..
firebase use --add          # Chọn careelder-e475b
firebase deploy --only firestore:rules
firebase deploy --only functions
```

### 3️⃣ Xác Nhận Deploy Thành Công
```bash
firebase functions:log
```

**Tìm:**
```
✓ functions[sendTaskCompletionNotification]: Successful
✓ functions[testSendNotification]: Successful
```

### 4️⃣ Cập Nhật Flutter App
```bash
flutter pub get
flutter run
```

### 5️⃣ Test Trên 2 Máy
- Máy 1 (Cha/Mẹ): App trên laptop khác
- Máy 2 (Con): App trên máy hiện tại
- Con tạo ghi chú
- Cha/Mẹ ấn ✓
- Con nhận notification (1-2 giây)

---

## ✅ Xong! 🎉

**Notification hoạt động cả khi app đóng!**

---

**Lỗi?** → Xem `DEPLOY_CLOUD_FUNCTIONS.md`  
**Chi tiết?** → Xem `TEST_TWO_DEVICES.md`
