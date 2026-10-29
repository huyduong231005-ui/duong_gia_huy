# Kịch bản quay video demo – App điểm danh sinh viên (nhóm 4 con tuất)

## Chuẩn bị

Trên màn hình máy tính đặt hai "điện thoại" cạnh nhau: bên trái là máy ảo Pixel 7, đóng vai **phòng đào tạo rồi giảng viên**; bên phải là cửa sổ scrcpy chiếu điện thoại thật, đóng vai **sinh viên**. OBS quay toàn bộ màn hình. Mở sẵn Gmail `huyduong455@gmail.com` trong một tab trình duyệt, vì mọi mã OTP trong video đều gửi về hộp thư này. Trước khi quay, cả hai máy để ở màn đăng nhập, điện thoại bật Không làm phiền, và **chưa nhập file Excel**.

Video bắt đầu từ con số 0 – hệ thống chưa có lớp, chưa có sinh viên – để người xem thấy trọn một vòng: đăng ký, đăng nhập, phân quyền, nhập dữ liệu rồi mới đến điểm danh. Cả video chỉ có **5 lần đăng nhập**, mỗi lần chứng minh một yêu cầu của đề: đăng ký bằng email (yêu cầu 1), đăng nhập mật khẩu + OTP vào trang quản trị (yêu cầu 2 và 3), đăng nhập giảng viên để thấy trang khác (yêu cầu 3), sinh viên đăng nhập lần đầu để bật khuôn mặt, và đăng nhập bằng khuôn mặt (chức năng a).

## Phần 1 – Đăng ký, đăng nhập và phân quyền (khoảng 2 phút)

Trên máy ảo, bấm "Chưa có tài khoản? Đăng ký bằng email", điền họ tên Sinh Viên Demo, email `huyduong455+demo@gmail.com`, tên đăng nhập `demo_sv`, mật khẩu `123456` rồi bấm Đăng ký. Mở Gmail lấy mã 6 số, nhập vào, app vào thẳng trang Sinh viên. Vừa làm vừa nói: *"Người dùng đăng ký bằng email, hệ thống gửi mã OTP hết hạn sau 5 phút, nhập sai 5 lần là huỷ mã. Tài khoản tự đăng ký luôn là sinh viên, không ai tự cho mình quyền admin được."* Sau đó bấm đăng xuất.

Vẫn trên máy ảo, đăng nhập bằng tài khoản quản trị `huyduong455` và mật khẩu của bạn. App báo đã gửi OTP, lấy mã trong Gmail nhập vào, và app mở Trang quản trị. Nói: *"Đăng nhập gồm tên, mật khẩu và mã OTP qua email. Backend biết vai trò của tài khoản nên đưa admin vào trang quản trị, giảng viên và sinh viên sẽ vào trang khác."*

## Phần 2 – Phòng đào tạo nhập dữ liệu và quản lý (khoảng 2,5 phút)

Ở Trang quản trị, bấm "Nhập Excel TKB + sinh viên", chọn file `mau-import.xlsx` trong thư mục Download. Vài giây sau màn hình báo đã nhập 2 môn, 2 giảng viên, 3 lớp, 20 sinh viên, 44 lượt ghi danh. Nói: *"Phòng đào tạo chỉ cần nhập một file Excel gồm thời khoá biểu và danh sách sinh viên, hệ thống tự tạo môn, giảng viên, lớp học phần và tài khoản sinh viên theo mã số sinh viên."*

Tiếp theo trình diễn thêm – sửa – xoá: vào Môn học, thêm môn `IT999 – Môn thử`, sửa tên rồi xoá nó đi. Vào Tài khoản, bấm chip Giảng viên để lọc, rồi gõ `2380600101` để tìm sinh viên. Cuối cùng vào Lớp học phần, mở lớp `IT008.DEMO` để thấy thời khoá biểu học cả 7 ngày và tab Sinh viên có đủ 20 người. Xong bấm đăng xuất.

## Phần 3 – Giảng viên và sinh viên vào việc (khoảng 2,5 phút)

Trên máy ảo, đăng nhập giảng viên `huyduong455gv`, mật khẩu cũng là `huyduong455gv`, nhập OTP. Người xem thấy ngay Dashboard giảng viên khác hẳn Trang quản trị – đó là phân quyền.

Chuyển sang điện thoại: đăng nhập sinh viên `2380600101`, mật khẩu `2380600101`, nhập OTP, vào trang Sinh viên. Bấm Bật ở thẻ "Đăng nhập bằng khuôn mặt", nhìn vào camera, nháy mắt một lần, app chụp 5 ảnh và báo đã bật. Đăng xuất, gõ lại `2380600101` rồi bấm "Đăng nhập bằng khuôn mặt", nháy mắt, app vào thẳng trang Sinh viên mà không cần mật khẩu. Nói: *"Chức năng thứ nhất là đăng nhập bằng khuôn mặt. App kiểm tra người thật bằng cái nháy mắt để chống giơ ảnh, mô hình FaceNet biến khuôn mặt thành 512 con số. Server chỉ lưu dãy số đó chứ không lưu ảnh, và sai 5 lần thì phải quay về mật khẩu."*

## Phần 4 – Điểm danh bằng QR và vị trí (khoảng 2 phút)

Trên máy ảo, giảng viên bấm "Hôm nay". Lớp `IT008.DEMO` hiện nhãn "Đang trong giờ", bấm "Mở buổi & chiếu QR", mã QR hiện lên kèm đồng hồ đếm ngược và dòng "0 / 20 sinh viên đã điểm danh". Trên điện thoại, sinh viên bấm "Hôm nay học gì", thấy lớp đang mở điểm danh, bấm "Quét QR" rồi đưa camera vào mã QR trên màn hình máy tính. Điện thoại báo điểm danh thành công và cách giảng viên vài mét, bên máy ảo con số nhảy lên 1 / 20. Nói: *"Chức năng thứ hai là mã QR động: mã được ký bằng khoá bí mật của server và đổi mỗi 60 giây, nên chụp gửi cho bạn ở nhà sẽ hết hạn. Đi kèm là GPS: sinh viên phải đứng trong bán kính 100 mét quanh giảng viên, dùng app giả lập vị trí cũng bị phát hiện."*

Đóng màn QR để về màn buổi học, bấm biểu tượng bản đồ. Bản đồ hiện vòng tròn 100 mét quanh giảng viên và chấm vị trí của sinh viên vừa điểm danh. Nói: *"Chức năng thứ ba là chia sẻ vị trí: giảng viên thấy ai điểm danh từ đâu ngay trên bản đồ."*

## Phần 5 – Tính năng mới: kiểm tra đột xuất giữa giờ (khoảng 1 phút)

Để điện thoại ở trang chủ sinh viên. Trên máy ảo, ngay màn buổi học, giảng viên bấm "Kiểm tra đột xuất giữa giờ", chọn Tất cả rồi Lưu. Chừng 10 giây sau, điện thoại tự bật màn "Kiểm tra đột xuất!" với đồng hồ đếm ngược 2 phút. Sinh viên bấm "Xác minh ngay", quét khuôn mặt, app gửi kèm vị trí và báo đã xác minh, bên máy ảo tự cập nhật "1/1 sinh viên đã xác minh". Nói: *"Đây là tính năng mới mà các app điểm danh hiện nay chưa có. Các app khác chỉ điểm danh một lần đầu giờ, nên sinh viên điểm danh xong là có thể về. Ở đây giảng viên gọi ngẫu nhiên giữa buổi, sinh viên phải xác minh lại bằng khuôn mặt và vị trí trong 2 phút, không kịp thì bị ghi là rời lớp sớm và tính như vắng."*

## Phần 6 – Đơn xin nghỉ, chuyên cần và buổi bù (khoảng 1,5 phút)

Trên điện thoại, sinh viên vào "Xin nghỉ phép", viết đơn cho lớp `IT008.Q11` vào ngày mai với lý do bị ốm. Trên máy ảo, giảng viên quay ra trang chủ, vào "Duyệt đơn nghỉ" và bấm Duyệt. Sinh viên kéo để tải lại, thấy đơn đã duyệt, rồi mở "Lịch sử chuyên cần" để thấy dòng "còn được vắng N buổi" – vắng quá 20% số buổi sẽ bị cấm thi.

Cuối cùng, trên máy ảo vào "Lớp của tôi", mở lớp `IT008.Q11` (lớp này chỉ học Thứ 2 và Thứ 5) và bấm Mở buổi điểm danh. Vì đang ngoài giờ trong thời khoá biểu, app báo đây là buổi bù và danh sách ghi rõ "Buổi bù". Nói: *"Mỗi lớp chỉ được điểm danh chính thức đúng thứ, đúng giờ trong thời khoá biểu; mở ngoài giờ thì hệ thống tự ghi là buổi bù."*

## Kết thúc (khoảng 20 giây)

Quay lại trang chủ và nói: *"Ứng dụng viết bằng Flutter, backend Node.js chạy trên Render, dữ liệu lưu ở MongoDB Atlas. Cảm ơn thầy cô và các bạn đã theo dõi."*

Quay thô khoảng 11 phút; khi dựng, cắt các đoạn chờ mã OTP và tua nhanh lúc chụp khuôn mặt thì còn 7–8 phút.

---

**Nếu gặp sự cố khi quay:** mã OTP không tới thì xem thư mục Spam hoặc chờ 30 giây rồi gửi lại. QR báo hết hạn thì quét mã mới đang hiện. Điện thoại báo cách lớp quá xa thì đứng gần cửa sổ cho GPS bắt tốt hơn. Quét mặt báo không khớp thì ra chỗ đủ sáng và giữ mặt trong khung oval. Nếu đã lỡ tạo tài khoản giảng viên `gv_huy` với email `huyduong455+gv@gmail.com` từ trước, hệ thống sẽ dùng lại tài khoản đó, nên ở Phần 3 hãy đăng nhập bằng `gv_huy` và mật khẩu cũ của bạn.
