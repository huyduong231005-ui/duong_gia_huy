// Tạo file mẫu nhập Excel: node scripts/make-sample.js → public/mau-import.xlsx
// (cũng tải được ở https://<api>/mau-import.xlsx). Email dùng dạng huyduong455+xxx@gmail.com:
// Gmail bỏ phần sau dấu "+" nên mọi mã OTP về chung 1 hộp thư → demo đăng nhập được mọi tài khoản.
import { fileURLToPath } from 'node:url';
import ExcelJS from 'exceljs';

const OUT = fileURLToPath(new URL('../public/mau-import.xlsx', import.meta.url));
const MAIL = (tag) => `huyduong455+${tag}@gmail.com`;
const day = (iso) => new Date(`${iso}T00:00:00Z`);

const GV1 = { email: MAIL('gv'), name: 'Nguyễn Văn Giảng' };
const GV2 = { email: MAIL('gv2'), name: 'Trần Thị Hướng' };
const IT008 = ['IT008', 'Lập trình thiết bị di động', 3];
const SE104 = ['SE104', 'Nhập môn Công nghệ phần mềm', 4];
const TERM = ['2026-09-01', '2027-06-30'];
const ALL_DAYS = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];

// [mã lớp, môn, GV, thứ, bắt đầu, kết thúc, phòng, số buổi]
const TKB = [
  // Lớp demo: học mọi ngày, cả ngày → lúc nào cũng mở được buổi chính thức
  ...ALL_DAYS.map((thu) => ['IT008.DEMO', IT008, GV1, thu, '00:00', '23:59', 'B1.14', 15]),
  // Lớp theo lịch thật → mở ngoài giờ sẽ thành "buổi bù"
  ['IT008.Q11', IT008, GV1, 'Thứ 2', '07:30', '09:45', 'A2.03', 15],
  ['IT008.Q11', IT008, GV1, 'Thứ 5', '13:00', '15:15', 'A2.03', 15],
  ['SE104.Q12', SE104, GV2, 'Thứ 3', '07:30', '10:30', 'C1.02', 15],
  ['SE104.Q12', SE104, GV2, 'Thứ 6', '13:00', '16:00', 'C1.02', 15],
];

const NAMES = [
  'Nguyễn Minh Anh', 'Trần Quốc Bảo', 'Lê Thị Cúc', 'Phạm Đức Duy', 'Hoàng Gia Hân',
  'Võ Thành Đạt', 'Đặng Ngọc Hà', 'Bùi Văn Hiếu', 'Đỗ Thu Hương', 'Ngô Tuấn Khang',
  'Dương Mỹ Linh', 'Lý Hoàng Long', 'Phan Thị Mai', 'Vũ Đình Nam', 'Trịnh Bảo Ngọc',
  'Mai Văn Phúc', 'Hồ Thị Quỳnh', 'Tạ Minh Sơn', 'Châu Thanh Tâm', 'Lâm Nhật Vy',
];
const STUDENTS = NAMES.map((name, i) => ({
  mssv: `23806001${String(i + 1).padStart(2, '0')}`,
  name,
  email: MAIL(`sv${String(i + 1).padStart(2, '0')}`),
}));
// Cả 20 SV học lớp DEMO; SV 1–12 học thêm IT008.Q11; SV 9–20 học thêm SE104.Q12
const ENROLL = [
  ...STUDENTS.map((s) => ['IT008.DEMO', s]),
  ...STUDENTS.slice(0, 12).map((s) => ['IT008.Q11', s]),
  ...STUDENTS.slice(8).map((s) => ['SE104.Q12', s]),
];

const wb = new ExcelJS.Workbook();
wb.creator = 'Nhóm 4 con tuất';

function sheet(name, columns, rows) {
  const ws = wb.addWorksheet(name, { views: [{ state: 'frozen', ySplit: 1 }] });
  ws.columns = columns.map(([header, width, numFmt]) => ({ header, width, style: numFmt ? { numFmt } : {} }));
  ws.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } };
  ws.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0F766E' } };
  rows.forEach((r) => ws.addRow(r));
  return ws;
}

sheet(
  'ThoiKhoaBieu',
  [
    ['Mã lớp', 14], ['Mã môn', 10], ['Tên môn', 32], ['Số tín chỉ', 11], ['Email GV', 30], ['Tên GV', 22],
    ['Thứ', 9], ['Giờ bắt đầu', 13], ['Giờ kết thúc', 13], ['Phòng', 9],
    ['Từ ngày', 13, 'dd/mm/yyyy'], ['Đến ngày', 13, 'dd/mm/yyyy'], ['Số buổi', 9],
  ],
  TKB.map(([lop, [mm, ten, tc], gv, thu, bd, kt, phong, sb]) =>
    [lop, mm, ten, tc, gv.email, gv.name, thu, bd, kt, phong, day(TERM[0]), day(TERM[1]), sb]),
);

sheet(
  'SinhVien',
  [['Mã lớp', 14], ['MSSV', 14], ['Họ tên', 24], ['Email', 32]],
  ENROLL.map(([lop, s]) => [lop, s.mssv, s.name, s.email]),
);

const guide = wb.addWorksheet('HuongDan');
guide.getColumn(1).width = 110;
[
  'HƯỚNG DẪN NHẬP FILE (Admin → Nhập Excel)',
  '',
  'Sheet ThoiKhoaBieu: mỗi dòng là 1 buổi học trong tuần của 1 lớp. Lớp học nhiều buổi/tuần thì ghi nhiều dòng cùng mã lớp.',
  '  • Thứ: 2…7 hoặc CN (ghi "Thứ 2" cũng được). Giờ: HH:mm. Ngày: dd/mm/yyyy.',
  '  • Giảng viên chưa có tài khoản sẽ được tạo: tên đăng nhập = phần trước @ của email (bỏ ký tự đặc biệt).',
  'Sheet SinhVien: mỗi dòng là 1 SV trong 1 lớp. SV học nhiều lớp thì ghi nhiều dòng.',
  '  • SV chưa có tài khoản sẽ được tạo: tên đăng nhập = MSSV, mật khẩu mặc định = MSSV.',
  '  • Đăng nhập bằng mật khẩu luôn cần mã OTP gửi về email → email phải nhận được thư.',
  '',
  'Nhập lại cùng file không tạo trùng (môn theo mã, GV theo email, SV theo MSSV, lớp theo mã lớp).',
  'Lớp IT008.DEMO học mọi ngày 00:00–23:59 để demo bất cứ lúc nào; IT008.Q11, SE104.Q12 theo lịch thật',
  '(mở buổi ngoài giờ học → hệ thống ghi là "Buổi bù").',
  'Email mẫu dạng huyduong455+sv01@gmail.com: Gmail bỏ phần sau dấu + nên mọi OTP về chung hộp thư huyduong455@gmail.com.',
].forEach((line, i) => {
  guide.getCell(`A${i + 1}`).value = line;
  if (i === 0) guide.getCell('A1').font = { bold: true, size: 14 };
});

await wb.xlsx.writeFile(OUT);
console.log(`Đã tạo ${OUT}: ${TKB.length} dòng TKB, ${STUDENTS.length} SV, ${ENROLL.length} lượt ghi danh`);
