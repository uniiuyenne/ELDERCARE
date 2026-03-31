# CareElder App

Ứng dụng hỗ trợ chăm sóc người cao tuổi với màn hình đăng nhập, phân quyền và ghép cặp.

## Cài Đặt

1. Cài đặt Flutter SDK.
2. Clone repo và chạy `flutter pub get`.
3. Cấu hình Firebase:
   - Tạo project trên Firebase Console.
   - Thêm firebase_core, firebase_auth, cloud_firestore.
   - Cấu hình Authentication với Phone.
   - Thêm google-services.json (Android) và GoogleService-Info.plist (iOS).

## Chạy App

`flutter run`

## Chức Năng

- Đăng nhập bằng SĐT + OTP.
- Chọn vai trò: Người con hoặc Cha/Mẹ.
- Ghép cặp tài khoản giữa con và cha/mẹ.

## Quy Trình Làm Việc Nhóm

- Nhánh mặc định: `main` (giữ ổn định, luôn chạy được).
- Mỗi thành viên tạo nhánh chức năng từ `main`:
   - `feature/<ten-chuc-nang>`
   - `fix/<ten-loi>`
- Commit nhỏ, rõ nghĩa theo mẫu:
   - `feat: them man hinh nhac thuoc`
   - `fix: sua loi dang nhap otp`
- Mở Pull Request về `main` khi hoàn thành chức năng.
- Luôn `git pull origin main` trước khi rebase/merge để tránh xung đột.
- Không commit file build, cache, hay thông tin nhay cam.

Xem thêm chi tiết trong file `CONTRIBUTING.md`.
