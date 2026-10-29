# duong_gia_huy – App điểm danh sinh viên

Đề 3 – nhóm **4 con tuất**. App Flutter (Android) + backend Node.js dùng chung cả nhóm.
Phân tích đề và phương án: [PHAN_TICH_DE.md](PHAN_TICH_DE.md).

```
duong_gia_huy/
├── lib/                 App Flutter (frontend riêng của Huy)
│   ├── api.dart         Gọi API, lưu token (flutter_secure_storage)
│   ├── main.dart        Theme, điều hướng theo vai trò
│   └── screens/         Đăng nhập, đăng ký, OTP, trang chủ 3 vai trò
├── backend/             API chung (Express + MongoDB) – deploy Render
└── render.yaml          Cấu hình deploy Render
```

## Đã có

| Yêu cầu đề | API | Màn hình |
|---|---|---|
| Đăng ký qua email (xác minh OTP) | `POST /auth/register`, `/auth/register/verify` | `RegisterScreen` → `OtpScreen` |
| Đăng ký/đăng nhập bằng Google (OAuth2 ở backend) | `POST /auth/google` | nút "Tiếp tục với Google" |
| Đăng nhập tên + mật khẩu + Email OTP | `POST /auth/login`, `/auth/login/verify` | `LoginScreen` → `OtpScreen` |
| Phân quyền admin / giảng viên / sinh viên | JWT + `requireAuth(secret, ...roles)` | `homeFor(user)` |

## Chuẩn bị tài khoản (làm 1 lần, cả nhóm dùng chung)

1. **MongoDB Atlas** (miễn phí, M0): tạo cluster → Database Access: tạo user → Network Access: `0.0.0.0/0`
   (Render free không có IP cố định) → Connect → Drivers → copy chuỗi `mongodb+srv://...`, thêm tên DB `/diemdanh`.
2. **Brevo**: Senders → thêm và xác minh email người gửi → SMTP & API → API Keys → tạo key.
3. **Google Cloud Console** → APIs & Services → Credentials:
   - Tạo **OAuth client ID loại Web** → đây là `GOOGLE_CLIENT_ID` (backend) và `GOOGLE_SERVER_CLIENT_ID` (app).
   - Mỗi thành viên tạo thêm **OAuth client ID loại Android** với package của mình
     (của Huy: `com.duonggiahuy.duong_gia_huy`) và SHA-1 máy mình:
     `cd android; ./gradlew signingReport` (lấy dòng SHA1 của `debug`).
   - OAuth consent screen: thêm email các thành viên vào **Test users**.

## Deploy backend lên Render

1. Đẩy repo này lên GitHub.
2. Render → **New → Blueprint** → chọn repo → Render đọc `render.yaml`.
3. Điền `MONGODB_URI`, `GOOGLE_CLIENT_ID`, `BREVO_API_KEY`, `MAIL_FROM` (`JWT_SECRET` Render tự sinh).
4. Mở `https://<ten-service>.onrender.com/health` → thấy `{"ok":true}` là xong.
5. Cấp quyền admin cho tài khoản đầu tiên (chạy trên máy, có file `backend/.env` trỏ tới Atlas):

```bash
npm --prefix backend run make-admin -- duonggiahuy
```

> Render free ngủ sau 15 phút không dùng; lần gọi đầu mất ~50 giây. Mở `/health` trước khi demo.

## Chạy app

```bash
flutter run
```

`API_URL` và `GOOGLE_SERVER_CLIENT_ID` đã có giá trị mặc định trong `lib/api.dart`; đổi khi cần bằng `--dart-define=API_URL=...`.

## Kiểm thử

```bash
npm --prefix backend test
```

```bash
flutter test
```

Backend test dùng MongoDB trong bộ nhớ (`mongodb-memory-server`), không cần cài MongoDB.
