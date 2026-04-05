# Notification Daemon (không dùng Cloud Functions)

Mục tiêu: chạy 1 tiến trình trên PC/laptop (miễn phí) để:
- Lắng nghe Firestore `chatMessages` và `tasks`
- Tự gửi FCM push cho người nhận
- Đồng thời ghi inbox `users/<uid>/notifications/<id>` để icon/badge trong app đồng bộ với push

## 1) Yêu cầu
- Node.js >= 18
- Firebase Admin service account JSON (giữ bí mật)

## 2) Tạo Service Account Key
Firebase Console → Project Settings → Service accounts → **Generate new private key**.
- Tải file JSON về (VD: `serviceAccount-careelder.json`)
- KHÔNG commit file này lên Git

## 3) Cấu hình env
Tạo file `.env` trong thư mục `notification-daemon/`:

```
SERVICE_ACCOUNT_PATH=../secrets/serviceAccount-careelder.json
ENABLE_USER_MIRROR=true
```

Bạn có thể đặt file JSON ở bất kỳ đâu, miễn path đúng.

`ENABLE_USER_MIRROR` (mặc định: bật) dùng để đồng bộ số điện thoại giữa tài khoản Con ↔ Cha/Mẹ mà không cần Cloud Functions (không cần Blaze).
- Khi user `role == child` cập nhật `phone/parentPhone/parentUid`, daemon sẽ ghi sang `users/<parentUid>`:
  - `childUid`, `childPhone`
  - `linkedChildUids` (arrayUnion)
  - `linkedChildPhones` (arrayUnion)
  - và `phone = parentPhone` (nếu `parentPhone` có giá trị)
- Tắt tính năng này nếu không cần: `ENABLE_USER_MIRROR=false`.

## 4) Cài và chạy
Tại project root:

```
cd notification-daemon
npm install
npm run dev
```

Hoặc build + start:

```
npm run build
npm start
```

## 5) Cách kiểm tra hoạt động
1) Chạy app trên 2 máy/2 tài khoản (parent/child), đăng nhập.
2) Đảm bảo token đã lên Firestore: `users/<uid>/fcmTokens/<token>`.
3) Gửi 1 tin nhắn → máy còn lại sẽ nhận push + có doc mới ở `users/<receiverUid>/notifications/*`.

Kiểm tra đồng bộ số điện thoại (khi bật `ENABLE_USER_MIRROR`):
1) Đăng nhập tài khoản Con → Quản lý tài khoản → sửa/lưu số điện thoại.
2) Xem log daemon có dòng: `mirror child -> parent { uid, parentUid, childPhone, parentPhone }`.
3) Kiểm tra Firestore: `users/<parentUid>.phone` và các field `childPhone/linkedChildPhones` được cập nhật.

## 6) Quản lý chạy nền (gợi ý)
### A) PM2 (dễ nhất)
Cài pm2:

```
npm i -g pm2
```

Chạy daemon (khuyến nghị chạy bản build `dist/`):

```
cd notification-daemon
npm run build
pm2 start ecosystem.config.cjs
pm2 logs eldercare-daemon
```

Hoặc dùng npm scripts:

```
cd notification-daemon
npm run build
npm run pm2:start
npm run pm2:logs
```

Lưu config để phục hồi sau reboot:

```
pm2 save
```

Auto-start trên Windows (khuyến nghị): tạo Task Scheduler chạy lệnh `pm2 resurrect` khi đăng nhập.

- Mở **Task Scheduler** → Create Task...
- Triggers: **At log on**
- Actions → Start a program:
  - Program/script: `pm2`
  - Add arguments: `resurrect`
  - Start in: thư mục chứa pm2 (thường đã có trong PATH; nếu không có thì dùng đường dẫn đầy đủ tới `pm2.cmd`)

Ghi chú: trên Windows, `pm2 startup` không ổn định như Linux; cách Task Scheduler + `pm2 save/resurrect` thường dễ kiểm soát hơn.

### B) Windows Task Scheduler
Tạo task chạy khi startup → Action chạy:
- Program: `node`
- Arguments: `dist/index.js`
- Start in: `<path>\notification-daemon`

## 7) Lưu ý quan trọng
- Daemon dùng **admin quyền cao nhất**: ai có file service account sẽ có quyền đọc/ghi DB.
- Nên:
  - Chỉ chạy trên máy bạn tin cậy
  - Không share key
  - Nếu lộ key: thu hồi key ngay trong Firebase Console

## Giới hạn
- Nếu daemon tắt (PC tắt/mạng mất) thì sẽ không gửi push trong thời gian đó.
- Đây là giải pháp phù hợp demo/sinh viên: miễn phí nhưng cần 1 máy luôn bật.
