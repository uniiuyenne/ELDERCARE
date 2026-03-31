# CONTRIBUTING

Tai lieu nay quy dinh quy trinh lam viec chung de team phat trien tren cac nhanh rieng, giam xung dot va de review.

## 1) Nhanh

- Nhanh on dinh: `main`
- Nhanh chuc nang: `feature/<ten-chuc-nang>`
- Nhanh sua loi: `fix/<ten-loi>`
- Nhanh cap nhat tai lieu: `docs/<ten-noi-dung>`

Vi du:

- `feature/auth-phone`
- `feature/medicine-reminder`
- `fix/otp-timeout`

## 2) Quy trinh lam viec

1. Dong bo nhanh `main` moi nhat.
2. Tao nhanh moi tu `main`.
3. Code + test trong nhanh rieng.
4. Commit theo tung buoc nho, message ro nghia.
5. Push nhanh len remote.
6. Tao Pull Request vao `main`.
7. Sau khi duoc review va pass test, moi merge.

## 3) Quy uoc commit

Su dung Conventional Commits don gian:

- `feat: ...` cho tinh nang moi
- `fix: ...` cho sua loi
- `refactor: ...` cho toi uu cau truc code
- `docs: ...` cho tai lieu
- `test: ...` cho test
- `chore: ...` cho viec phu tro

Vi du:

- `feat: add role selection after login`
- `fix: prevent duplicate pair code`

## 4) Dong bo voi main

- Truoc khi mo PR, cap nhat nhanh voi `main`:
  - `git fetch origin`
  - `git rebase origin/main` hoac `git merge origin/main`

Neu team uu tien lich su sach, khuyen khich dung `rebase`.

## 5) Quy tac review

- Moi PR nen nho gon (uu tien < 400 dong thay doi).
- Mo ta ro muc tieu, pham vi, anh huong.
- Dinh kem anh/chup man hinh neu co thay doi UI.
- It nhat 1 thanh vien khac review truoc merge.

## 6) Thu muc khong duoc commit

Du an da co `.gitignore` cho Flutter. Khong commit:

- Thu muc build/cache (`build/`, `.dart_tool/`, ...)
- File tam IDE
- Secrets/keys ngoai quy trinh duoc phe duyet

## 7) Lenh nhanh co ban

```bash
git checkout main
git pull origin main
git checkout -b feature/<ten-chuc-nang>
# code...
git add .
git commit -m "feat: mo ta thay doi"
git push -u origin feature/<ten-chuc-nang>
```

Khi hoan thanh, tao Pull Request tu nhanh cua ban vao `main`.
