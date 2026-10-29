// Nhập thời khoá biểu + danh sách sinh viên từ file Excel (.xlsx) do phòng đào tạo / giảng viên cung cấp.
// Sheet "ThoiKhoaBieu": mỗi dòng là 1 buổi học trong tuần của 1 lớp học phần.
// Sheet "SinhVien": mỗi dòng là 1 sinh viên thuộc 1 lớp học phần.
// Nhập lại cùng file không tạo trùng: môn tìm theo mã, GV theo email, SV theo MSSV, lớp theo mã lớp.
import ExcelJS from 'exceljs';
import bcrypt from 'bcryptjs';
import { User, Subject, ClassSection, Session, DATE_RE } from './models.js';
import { HttpError, EMAIL_RE, USERNAME_RE } from './auth.js';

const TKB_COLUMNS = ['malop', 'mamon', 'tenmon', 'emailgv', 'tengv', 'thu', 'giobatdau', 'gioketthuc', 'tungay', 'denngay'];
const SV_COLUMNS = ['malop', 'mssv', 'hoten', 'email'];
const MAX_ERRORS = 50;

/** "Giờ bắt đầu" → "giobatdau", "Thứ 2" → "thu2": bỏ dấu, khoảng trắng, chữ hoa. */
const norm = (s) =>
  String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/gi, 'd').toLowerCase().replace(/[^a-z0-9]/g, '');

/** Giá trị ô Excel → chuỗi (ô có thể là hyperlink, công thức, rich text…). */
function text(v) {
  if (v == null) return '';
  if (v instanceof Date) return v.toISOString();
  if (typeof v === 'object') return text(v.text ?? v.result ?? v.richText?.map((r) => r.text).join('') ?? '');
  return String(v).trim();
}

const pad = (n) => String(n).padStart(2, '0');

/** Ô ngày: Date của Excel, "2026-09-01" hoặc "1/9/2026". */
function dateCell(v) {
  if (v instanceof Date) return v.toISOString().slice(0, 10);
  const s = text(v);
  if (DATE_RE.test(s)) return s;
  const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  return m ? `${m[3]}-${pad(m[2])}-${pad(m[1])}` : null;
}

/** Ô giờ: Date (giờ Excel), phân số của ngày (0.3125), "7:30", "07:30" hoặc "7h30". */
function timeCell(v) {
  if (v instanceof Date) return `${pad(v.getUTCHours())}:${pad(v.getUTCMinutes())}`;
  if (typeof v === 'number' && v >= 0 && v < 1) {
    const mins = Math.round(v * 1440) % 1440;
    return `${pad(Math.floor(mins / 60))}:${pad(mins % 60)}`;
  }
  const m = text(v).match(/^(\d{1,2})\s*[:hH]\s*(\d{2})?$/);
  if (!m || Number(m[1]) > 23 || Number(m[2] ?? 0) > 59) return null;
  return `${pad(m[1])}:${pad(m[2] ?? 0)}`;
}

/** Ô thứ: 2…7, "Thứ 2", "CN", "Chủ nhật", 8 → 1 (Thứ 2) … 7 (Chủ nhật). */
function weekdayCell(v) {
  const s = norm(text(v)).replace(/^thu/, '');
  if (s === 'cn' || s === 'chunhat' || s === '8') return 7;
  const n = Number(s);
  return Number.isInteger(n) && n >= 2 && n <= 7 ? n - 1 : null;
}

/** Đọc 1 sheet theo tên cột ở dòng 1 (không phụ thuộc thứ tự cột). */
function readSheet(workbook, name, required) {
  const sheet = workbook.worksheets.find((ws) => norm(ws.name) === norm(name));
  if (!sheet) throw new HttpError(400, `File thiếu sheet "${name}" (xem file mẫu)`);
  const header = new Map();
  sheet.getRow(1).eachCell((cell, col) => header.set(norm(text(cell.value)), col));
  const missing = required.filter((c) => !header.has(c));
  if (missing.length) throw new HttpError(400, `Sheet "${name}" thiếu cột: ${missing.join(', ')}`);
  const rows = [];
  sheet.eachRow({ includeEmpty: false }, (row, line) => {
    if (line === 1) return;
    const get = (col) => (header.has(col) ? row.getCell(header.get(col)).value : null);
    if (required.some((c) => text(get(c)))) rows.push({ line, get });
  });
  return rows;
}

async function freeUsername(base) {
  const clean = base.toLowerCase().replace(/[^a-z0-9_.]/g, '').slice(0, 24).padEnd(3, '0');
  let name = clean;
  for (let i = 2; await User.exists({ username: name }); i++) name = `${clean}${i}`;
  return name;
}

/** Tài khoản do nhập file: kích hoạt sẵn, mật khẩu mặc định = tên đăng nhập (đăng nhập vẫn cần OTP email). */
async function createUser({ username, email, fullName, role }) {
  return User.create({ username, email, fullName, role, active: true, passwordHash: await bcrypt.hash(username, 10) });
}

/** Ghi danh SV vào lớp; buổi đang mở cũng thêm tên để quét QR được ngay. */
export async function enrollStudent(classId, studentId) {
  const cls = await ClassSection.findByIdAndUpdate(classId, { $addToSet: { students: studentId } }, { new: true });
  if (!cls) return null;
  await Session.updateMany(
    { classSection: cls._id, open: true, 'records.student': { $ne: studentId } },
    { $push: { records: { student: studentId } } },
  );
  return cls;
}

export async function importWorkbook(buffer) {
  const workbook = new ExcelJS.Workbook();
  try {
    await workbook.xlsx.load(buffer);
  } catch {
    throw new HttpError(400, 'File không phải Excel .xlsx hợp lệ');
  }
  const tkbRows = readSheet(workbook, 'ThoiKhoaBieu', TKB_COLUMNS);
  const svRows = readSheet(workbook, 'SinhVien', SV_COLUMNS);

  const errors = [];
  const fail = (sheet, line, msg) => errors.length < MAX_ERRORS && errors.push(`${sheet} dòng ${line}: ${msg}`);
  const result = { subjects: 0, lecturers: 0, classes: 0, students: 0, newAccounts: 0, enrollments: 0 };

  // 1. Gom các dòng TKB theo lớp
  const classes = new Map();
  for (const { line, get } of tkbRows) {
    const code = text(get('malop')).toUpperCase();
    const subjectCode = text(get('mamon')).toUpperCase();
    const email = text(get('emailgv')).toLowerCase();
    const weekday = weekdayCell(get('thu'));
    const start = timeCell(get('giobatdau'));
    const end = timeCell(get('gioketthuc'));
    const startDate = dateCell(get('tungay'));
    const endDate = dateCell(get('denngay'));
    if (!code || !subjectCode || !text(get('tenmon'))) { fail('ThoiKhoaBieu', line, 'thiếu mã lớp / mã môn / tên môn'); continue; }
    if (!EMAIL_RE.test(email)) { fail('ThoiKhoaBieu', line, 'email giảng viên không hợp lệ'); continue; }
    if (!weekday) { fail('ThoiKhoaBieu', line, 'cột Thứ phải là 2…7 hoặc CN'); continue; }
    if (!start || !end || start >= end) { fail('ThoiKhoaBieu', line, 'giờ bắt đầu/kết thúc không hợp lệ'); continue; }
    if (!startDate || !endDate || startDate > endDate) { fail('ThoiKhoaBieu', line, 'từ ngày/đến ngày không hợp lệ'); continue; }

    const entry = classes.get(code) ?? {
      code, meetings: [], startDate, endDate,
      subject: { code: subjectCode, name: text(get('tenmon')), credits: Number(text(get('sotinchi'))) || 3 },
      lecturer: { email, fullName: text(get('tengv')) },
      planned: Number(text(get('sobuoi'))) || undefined,
    };
    entry.meetings.push({ weekday, start, end, room: text(get('phong')) });
    entry.startDate = entry.startDate < startDate ? entry.startDate : startDate;
    entry.endDate = entry.endDate > endDate ? entry.endDate : endDate;
    classes.set(code, entry);
  }

  // 2. Môn, giảng viên, lớp
  const subjectIds = new Map();
  const lecturerIds = new Map();
  for (const c of classes.values()) {
    if (!subjectIds.has(c.subject.code)) {
      const s = await Subject.findOneAndUpdate(
        { code: c.subject.code },
        { name: c.subject.name, credits: c.subject.credits },
        { upsert: true, new: true, runValidators: true, setDefaultsOnInsert: true },
      );
      subjectIds.set(c.subject.code, s._id);
      result.subjects++;
    }
    if (!lecturerIds.has(c.lecturer.email)) {
      let gv = await User.findOne({ email: c.lecturer.email });
      if (!gv) {
        gv = await createUser({
          username: await freeUsername(c.lecturer.email.split('@')[0]),
          email: c.lecturer.email, fullName: c.lecturer.fullName, role: 'lecturer',
        });
        result.newAccounts++;
      } else if (gv.role === 'student') {
        gv.role = 'lecturer';
        await gv.save();
      }
      lecturerIds.set(c.lecturer.email, gv._id);
      result.lecturers++;
    }
    await ClassSection.findOneAndUpdate(
      { code: c.code },
      {
        subject: subjectIds.get(c.subject.code),
        lecturer: lecturerIds.get(c.lecturer.email),
        meetings: c.meetings,
        room: c.meetings[0].room,
        schedule: '', // lịch dạng chữ cũ, giờ đã có TKB
        startDate: c.startDate,
        endDate: c.endDate,
        ...(c.planned && { plannedSessions: c.planned }),
      },
      { upsert: true, new: true, runValidators: true, setDefaultsOnInsert: true },
    );
    result.classes++;
  }

  // 3. Sinh viên + ghi danh
  const seenStudents = new Set();
  for (const { line, get } of svRows) {
    const code = text(get('malop')).toUpperCase();
    const mssv = text(get('mssv')).toLowerCase();
    const email = text(get('email')).toLowerCase();
    if (!USERNAME_RE.test(mssv)) { fail('SinhVien', line, 'MSSV không hợp lệ (3–30 chữ/số)'); continue; }
    if (!EMAIL_RE.test(email)) { fail('SinhVien', line, 'email không hợp lệ'); continue; }
    const cls = await ClassSection.findOne({ code }, '_id');
    if (!cls) { fail('SinhVien', line, `chưa có lớp ${code} trong sheet ThoiKhoaBieu`); continue; }

    let sv = await User.findOne({ $or: [{ username: mssv }, { email }] });
    if (!sv) {
      sv = await createUser({ username: mssv, email, fullName: text(get('hoten')), role: 'student' });
      result.newAccounts++;
    }
    if (sv.role !== 'student') { fail('SinhVien', line, `${email} đang là tài khoản ${sv.role}, bỏ qua`); continue; }
    await enrollStudent(cls._id, sv._id);
    result.enrollments++;
    if (!seenStudents.has(sv.id)) { seenStudents.add(sv.id); result.students++; }
  }

  return { ...result, errors };
}
