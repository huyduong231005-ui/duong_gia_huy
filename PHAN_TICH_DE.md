# Phân tích đề kiểm tra (40%) – Nhóm "4 con tuất"

**Đề của nhóm:** Đề 3 – **App điểm danh cho sinh viên**
**Project cá nhân:** `duong_gia_huy` (Flutter) – folder `D:\duong_gia_huy`

---

## 1. Ràng buộc "chết" (sai là 0đ / rớt môn)

| # | Ràng buộc | Cách tuân thủ |
|---|---|---|
| 1 | Tên project **bắt buộc là tên cá nhân** | `flutter create --org com.duonggiahuy duong_gia_huy` → package `duong_gia_huy`, applicationId `com.duonggiahuy.duong_gia_huy`. Mỗi thành viên một tên riêng. |
| 2 | **Hai frontend giống nhau = rớt** | Mỗi người tự viết UI của mình (theme, bố cục, cách chia màn hình khác nhau). Chỉ dùng chung **backend + tài liệu API**. Mỗi người một repo git riêng để có lịch sử commit chứng minh tự làm. |
| 3 | **Chỉ Flutter** cho di động | Không dùng React Native / Kotlin thuần cho UI (MethodChannel Java nhỏ cho vân tay vẫn là Flutter app). |
| 4 | **API không được localhost** | Backend deploy lên cloud (Render / Railway – như bài 6) hoặc VPS, app gọi qua `https://…`. |
| 5 | Backend được dùng chung cả nhóm | → 1 backend chung, deploy 1 lần, cả nhóm cùng gọi. |

## 2. Bóc tách yêu cầu và điểm

| Mục | Yêu cầu | Điểm | Ghi chú |
|---|---|---|---|
| 1 | Đăng ký qua **email** hoặc **bên thứ 3 (OAuth2.0 ở backend)** | (nền) | Làm cả hai: email + Google. |
| 2 | Đăng nhập **tên đăng nhập + mật khẩu + OTP** (SMS hoặc Email) | (nền) | Chọn **Email OTP** (miễn phí). SMS tốn tiền. |
| 3 | **Phân quyền** 3 vai trò, mỗi vai trò vào màn hình riêng | (nền) | Admin / Nhân viên / Khách hàng ↔ xem mục 3.2. |
| 4 | **CRUD** | **4,5** | Phần nặng điểm nhất – phải đủ Thêm/Xem/Sửa/Xoá thấy rõ trên UI. |
| 5 | Chọn **3/6 chức năng nâng cao** để thuyết trình | **3,5** | Chọn cái **khớp với điểm danh** và **chắc chạy được**. |
| 6 | **Tính năng mới** app hiện tại chưa có | **1** | Tự đề xuất, phải demo được. |
| 7 | **Giao diện đẹp, dễ dùng, cả nhóm chạy được** | **1** | Mỗi người build được APK, gọi được API thật. |

> Mục 1–3 không có điểm riêng nhưng là **điều kiện nền**: thiếu thì không vào được CRUD để chấm.

---

## 3. Phương án đề xuất (khả quan nhất)

### 3.1. Kiến trúc

```
 ┌─────────── Flutter app (mỗi người 1 bản, tên riêng) ───────────┐
 │  Đăng nhập / OTP / Google · Admin · Giảng viên · Sinh viên     │
 │  camera+ML Kit+TFLite (mặt) · mobile_scanner (QR) · geolocator │
 └──────────────────────────────┬─────────────────────────────────┘
                                │ HTTPS + JWT
 ┌──────────────────────────────▼─────────────────────────────────┐
 │  Backend chung: Node.js + Express (deploy Render/Railway/VPS)  │
 │  Auth (bcrypt, JWT, Email OTP, Google OAuth2) · CRUD · QR ký   │
 └───────┬──────────────────┬──────────────────┬──────────────────┘
   MongoDB Atlas (free)   Brevo (gửi email OTP)   FCM (push spot-check)
```

| Phần | Chọn | Lý do |
|---|---|---|
| Backend | **Node.js + Express** | Nhanh, nhiều tài liệu; nếu bài 6 thầy dạy ngôn ngữ khác thì theo bài 6. |
| CSDL | **MongoDB Atlas M0** (miễn phí) | Không cần tự host DB. |
| Deploy | **Render free** (hoặc cách bài 6 / VPS) | Free tier ngủ sau 15 phút → mở API trước khi demo 1–2 phút. |
| Email OTP | **Brevo HTTP API** (300 mail/ngày free) | Render free **chặn cổng SMTP** → Gmail SMTP không chạy được trên Render; trên VPS thì Gmail SMTP + App Password vẫn được. |
| OAuth2 | **Google Sign-In** | App lấy `idToken` → backend `POST /auth/google` xác thực bằng `google-auth-library` → cấp JWT của mình. |
| Bản đồ | **flutter_map + OpenStreetMap** | Không cần API key / thẻ tín dụng như Google Maps. |

### 3.2. Phân quyền (map đề → điểm danh)

| Đề gọi là | Trong app | Vào màn hình |
|---|---|---|
| Admin | **Admin / Phòng đào tạo** | Trang quản trị: quản lý tài khoản, môn học, lớp học phần, ghi danh SV, cấu hình |
| Nhân viên | **Giảng viên** | Dashboard GV: lớp mình dạy, mở buổi điểm danh (QR), xem/sửa điểm danh, duyệt đơn nghỉ, thống kê |
| Khách hàng | **Sinh viên** | Trang SV: lịch học, quét QR điểm danh, lịch sử chuyên cần, gửi đơn xin nghỉ |

Luồng: đăng nhập → backend trả JWT có `role` → app điều hướng theo `role`. Backend **cũng phải kiểm role** ở từng API (không chỉ ẩn nút trên app).

### 3.3. Luồng xác thực

- **Đăng ký email:** nhập email, tên đăng nhập, mật khẩu → backend gửi OTP 6 số (hạn 5 phút) → nhập đúng mới kích hoạt. Mặc định role = Sinh viên; Admin tạo/đổi role Giảng viên.
- **Đăng ký Google:** nút "Tiếp tục với Google" → backend verify `idToken` → tạo tài khoản nếu chưa có.
- **Đăng nhập:** tên đăng nhập + mật khẩu → đúng thì gửi Email OTP → nhập OTP → nhận JWT → vào trang theo role.
- Mật khẩu băm **bcrypt**, OTP lưu dạng băm + hạn dùng + giới hạn 5 lần nhập sai.

> Google Sign-In: mỗi thành viên có package khác nhau → mỗi người tạo **1 Android OAuth client** (package + SHA-1 của máy mình) trong cùng project Google Cloud; tất cả dùng chung **1 Web client ID** làm `serverClientId` để backend kiểm `audience`.

### 3.4. CRUD (4,5đ) – 6 nhóm dữ liệu

| Đối tượng | Ai thao tác | C | R | U | D |
|---|---|---|---|---|---|
| Tài khoản người dùng | Admin | tạo GV/SV | danh sách, tìm kiếm, lọc theo role | sửa thông tin, đổi role, khoá | xoá |
| Môn học | Admin | ✓ | ✓ | ✓ | ✓ |
| Lớp học phần (môn + GV + lịch + phòng) | Admin | ✓ | ✓ | ✓ | ✓ |
| Ghi danh SV vào lớp | Admin | thêm SV | danh sách lớp | chuyển lớp | xoá khỏi lớp |
| Buổi học / phiên điểm danh | Giảng viên | mở buổi | xem buổi + ai đã có mặt | sửa trạng thái từng SV (có mặt/muộn/vắng/có phép) | huỷ buổi |
| Đơn xin nghỉ phép (kèm ảnh minh chứng) | SV tạo – GV duyệt | SV gửi | cả hai xem | SV sửa khi đang chờ; GV duyệt/từ chối | SV rút đơn |

→ Mỗi vai trò đều có CRUD riêng để demo, không dồn hết vào Admin.

### 3.5. Chọn 3/6 chức năng nâng cao (3,5đ)

| Chọn | Chức năng của đề | Dùng vào điểm danh thế nào | Gói Flutter | Độ khó |
|---|---|---|---|---|
| ✅ **a** | Đăng nhập bằng khuôn mặt | Đăng nhập bằng mặt **và** xác minh mặt lúc điểm danh → chống điểm danh hộ | `camera`, `google_mlkit_face_detection`, `tflite_flutter` | Trung bình – **tận dụng được `D:\faceid`** (mục 4) |
| ✅ **e** | QR (+ vân tay) | GV chiếu **QR động đổi mỗi 10 giây** (backend ký HMAC, hết hạn nhanh) → SV quét; chụp QR gửi bạn sẽ hết hạn. Vân tay để mở app nhanh. | `qr_flutter`, `mobile_scanner`, `local_auth` | Dễ |
| ✅ **b** | Chia sẻ vị trí | SV gửi vị trí khi điểm danh, backend kiểm **trong bán kính ~100 m** của GV; GV xem **bản đồ vị trí các SV** đã điểm danh | `geolocator`, `flutter_map` | Dễ |
| dự phòng **f** | Ảnh chụp / OCR | Chụp **thẻ sinh viên** → tự điền MSSV, họ tên khi đăng ký | `google_mlkit_text_recognition` | Dễ |

Ba cái a + e + b gộp lại thành **một quy trình điểm danh 3 lớp**: QR đúng buổi + đúng chỗ + đúng người — câu chuyện thuyết trình liền mạch, không phải 3 tính năng rời rạc.

### 3.6. Tính năng mới (1đ) – đề xuất

**"Điểm danh đột xuất giữa giờ" (Spot-check ngẫu nhiên)**

- Vấn đề: các app điểm danh hiện tại (QR, Google Classroom, MS Teams…) chỉ kiểm **một lần đầu giờ** → SV điểm danh xong rồi về.
- Cách làm: giữa buổi, GV bấm (hoặc hệ thống hẹn giờ ngẫu nhiên) → backend gửi **push (FCM)** đến một nhóm SV ngẫu nhiên đã điểm danh → trong **60 giây** phải xác minh **mặt + vị trí** ngay trên thông báo → ai không phản hồi bị đánh dấu **"rời lớp sớm"**.
- Demo dễ: 2 điện thoại, 1 người "bỏ về" → GV thấy ngay trên dashboard.

Thêm nhỏ (gần như miễn phí vì có sẵn dữ liệu): **đồng hồ "còn được vắng N buổi"** – cảnh báo SV và GV khi sắp chạm ngưỡng cấm thi (20% số buổi).

---

## 4. Tận dụng project có sẵn `D:\faceid`

Project `faceid` đã có **đăng nhập bằng khuôn mặt** (ML Kit + FaceNet-512, kiểm tra nháy mắt, ~90% đúng trên LFW) và **vân tay** (BiometricPrompt + Keystore) chạy trên điện thoại thật.

| Lấy lại | Phải đổi |
|---|---|
| Pipeline mặt: `face/` (căn thẳng, cắt, embedding), kiểm tra nháy mắt, model `facenet_512.tflite` | Lưu vector mặt lên **backend mới** thay vì Firestore; so khớp ở backend để cấp JWT |
| Khoá vân tay (MethodChannel `BiometricLock.java`) | Đổi tên channel/package theo `duong_gia_huy` |
| Kinh nghiệm cấu hình Android (minSdk 24, FlutterFragmentActivity) | Giao diện viết lại theo app điểm danh (không bê nguyên UI) |

> Chỉ **phần frontend của Huy** dùng code này. Các thành viên khác **không copy** sang app của họ (dính luật "2 frontend giống nhau").

---

## 5. Chia việc nhóm (gợi ý)

| Phần | Ai |
|---|---|
| Backend chung (auth, OTP, OAuth2, CRUD, QR ký, FCM) + deploy | 1–2 người, cả nhóm review |
| Tài liệu API (Postman collection) | Người làm backend – để mọi người gọi theo |
| Frontend Flutter | **Mỗi người 1 app riêng, tên riêng, UI riêng** |
| Slide thuyết trình a / e / b + tính năng mới | Chia mỗi người 1 phần |

---

## 6. Rủi ro và cách né

| Rủi ro | Cách né |
|---|---|
| Render free ngủ → demo chờ 50 giây | Gọi `/health` trước khi lên trình bày, hoặc dùng VPS |
| Email OTP vào Spam / không gửi được | Brevo + xác minh email người gửi; có tài khoản demo sẵn |
| Google Sign-In lỗi `ApiException: 10` | Sai SHA-1/package → mỗi người tự đăng ký SHA-1 máy mình |
| Nhận diện mặt sai khi thiếu sáng | Ngưỡng điều chỉnh được (đã có 3 mức trong faceid); luôn có đường lùi bằng mật khẩu |
| GPS trong phòng kín lệch xa | Bán kính 100 m; GV lấy toạ độ ngay tại lớp khi mở buổi |
| Frontend các thành viên na ná nhau | Thống nhất từ đầu: khác theme, khác bố cục, khác cách điều hướng; không chia sẻ file `lib/` |

---

## 7. Thứ tự làm

1. **Backend nền:** auth (đăng ký email + OTP, đăng nhập + OTP, Google), JWT + role → **deploy ngay** để cả nhóm gọi.
2. **App nền:** đăng ký / đăng nhập / OTP / điều hướng theo role (mục 1–3).
3. **CRUD** (4,5đ) – làm chắc trước khi sang tính năng nâng cao.
4. **QR động + GPS** (dễ, làm trước) → **khuôn mặt** (lấy từ faceid).
5. **Spot-check** (FCM) + đồng hồ "còn được vắng".
6. Làm đẹp UI, build APK, chạy thử trên máy từng người, chuẩn bị slide.

## 8. Cần chốt với nhóm

- [ ] **Bài 6** thầy dạy deploy bằng gì (Render? Railway? ngrok?) và backend ngôn ngữ gì → backend theo đúng cách đó.
- [ ] Nhóm mấy người, ai làm backend.
- [ ] Hạn nộp / ngày thuyết trình.
