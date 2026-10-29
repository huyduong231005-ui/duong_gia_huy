import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import mongoose from 'mongoose';
import ExcelJS from 'exceljs';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { createApp } from '../src/app.js';
import { User } from '../src/models.js';
import { signToken } from '../src/auth.js';
import { vnNow, isMakeup } from '../src/schedule.js';

const SECRET = 'test-secret';
const SAMPLE = await readFile(new URL('../public/mau-import.xlsx', import.meta.url));
let mongo, server, base, admin;

before(async () => {
  mongo = await MongoMemoryServer.create();
  await mongoose.connect(mongo.getUri());
  server = createApp({ jwtSecret: SECRET, sendMail: async () => {}, verifyGoogle: async () => null }).listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.close();
  await mongoose.disconnect();
  await mongo.stop();
});

beforeEach(async () => {
  await mongoose.connection.db.dropDatabase();
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
  const u = await User.create({ username: 'admin', email: 'admin@x.vn', role: 'admin', active: true });
  admin = { token: signToken(u, SECRET) };
});

const tokenOf = async (username) => ({ token: signToken(await User.findOne({ username }), SECRET) });

async function call(who, method, path, body) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${who.token}` },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

async function upload(bytes) {
  const res = await fetch(`${base}/admin/import`, {
    method: 'POST',
    headers: { 'content-type': 'application/octet-stream', authorization: `Bearer ${admin.token}` },
    body: bytes,
  });
  return { status: res.status, body: await res.json() };
}

test('giờ Việt Nam: 17:30 UTC ngày 29/10 là 00:30 Thứ 6 ngày 30/10', () => {
  assert.deepEqual(vnNow(Date.parse('2026-10-29T17:30:00Z')), { date: '2026-10-30', weekday: 5, minutes: 30 });
});

test('nhập file mẫu: tạo môn, GV, lớp có TKB, 20 SV và ghi danh; nhập lại không tạo trùng', async () => {
  const first = await upload(SAMPLE);
  assert.equal(first.status, 200);
  assert.deepEqual(first.body, {
    subjects: 2, lecturers: 2, classes: 3, students: 20, newAccounts: 22, enrollments: 44, errors: [],
  });

  const classes = (await call(admin, 'GET', '/classes')).body;
  const demo = classes.find((c) => c.code === 'IT008.DEMO');
  assert.equal(demo.meetings.length, 7);
  assert.equal(demo.students.length, 20);
  assert.equal(demo.startDate, '2026-09-01');
  assert.equal(demo.lecturer.email, 'huyduong455+gv@gmail.com');
  const q11 = classes.find((c) => c.code === 'IT008.Q11');
  assert.deepEqual(q11.meetings.map((m) => [m.weekday, m.start, m.end]), [[1, '07:30', '09:45'], [4, '13:00', '15:15']]);

  const sv = await User.findOne({ username: '2380600101' });
  assert.equal(sv.fullName, 'Nguyễn Minh Anh');
  assert.equal(sv.role, 'student');

  const again = await upload(SAMPLE);
  assert.equal(again.body.newAccounts, 0);
  assert.equal(await User.countDocuments(), 23, 'admin + 2 GV + 20 SV');
  assert.equal((await call(admin, 'GET', '/classes')).body.find((c) => c.code === 'IT008.DEMO').students.length, 20);
});

test('Hôm nay: lớp DEMO luôn có lịch, mở buổi đúng giờ là buổi chính thức, ngoài giờ là buổi bù', async () => {
  await upload(SAMPLE);
  const gv = await tokenOf('huyduong455gv');
  const sv = await tokenOf('2380600120'); // SV 20: học DEMO + SE104.Q12, không học IT008.Q11

  const today = (await call(gv, 'GET', '/me/today')).body;
  const demoRow = today.classes.find((c) => c.classSection.code === 'IT008.DEMO');
  assert.ok(demoRow.inProgress);
  assert.equal(demoRow.session, undefined);

  const opened = await call(gv, 'POST', `/classes/${demoRow.classSection.id}/sessions`, {}); // không gửi ngày → hôm nay
  assert.equal(opened.body.date, vnNow().date);
  assert.equal(opened.body.makeup, false);
  assert.equal(opened.body.records.length, 20);

  const mine = (await call(sv, 'GET', '/me/today')).body.classes;
  assert.ok(mine.every((c) => c.classSection.code !== 'IT008.Q11'), 'chỉ thấy lớp mình học');
  assert.equal(mine.find((c) => c.classSection.code === 'IT008.DEMO').session.myStatus, 'absent');

  // Mở buổi cho ngày khác ngày hôm nay → luôn là buổi bù
  const other = await call(gv, 'POST', `/classes/${demoRow.classSection.id}/sessions`, { date: '2026-12-31' });
  assert.equal(other.body.makeup, true);
});

test('isMakeup: lớp chưa có TKB không xét, có TKB thì đúng thứ + giờ mới là buổi chính thức', () => {
  const now = Date.parse('2026-11-02T01:00:00Z'); // 08:00 Thứ 2 giờ VN
  const q11 = { meetings: [{ weekday: 1, start: '07:30', end: '09:45' }], startDate: '2026-09-01', endDate: '2027-06-30' };
  assert.equal(isMakeup({ meetings: [] }, '2026-11-02', now), false);
  assert.equal(isMakeup(q11, '2026-11-02', now), false);
  assert.equal(isMakeup(q11, '2026-11-02', Date.parse('2026-11-02T00:20:00Z')), false, '07:20: được mở sớm 15 phút');
  assert.equal(isMakeup(q11, '2026-11-02', Date.parse('2026-11-02T00:10:00Z')), true, '07:10: quá sớm');
  assert.equal(isMakeup(q11, '2026-11-02', Date.parse('2026-11-02T03:00:00Z')), true, '10:00: đã hết giờ');
  assert.equal(isMakeup({ ...q11, endDate: '2026-10-31' }, '2026-11-02', now), true, 'hết học kỳ');
});

test('file lỗi: không phải Excel, thiếu sheet, dòng sai thì bỏ qua và báo đúng dòng', async () => {
  assert.match((await upload(Buffer.from('khong phai excel'))).body.message, /không phải Excel/);

  const wb = new ExcelJS.Workbook();
  wb.addWorksheet('ThoiKhoaBieu').addRows([
    ['Mã lớp', 'Mã môn', 'Tên môn', 'Email GV', 'Tên GV', 'Thứ', 'Giờ bắt đầu', 'Giờ kết thúc', 'Từ ngày', 'Đến ngày'],
    ['L1', 'M1', 'Môn 1', 'gv@x.vn', 'GV', 'Thứ 9', '07:30', '09:00', '1/9/2026', '30/12/2026'],
    ['L1', 'M1', 'Môn 1', 'gv@x.vn', 'GV', 'CN', '7h30', '9h', '1/9/2026', '30/12/2026'],
  ]);
  assert.match((await upload(Buffer.from(await wb.xlsx.writeBuffer()))).body.message, /thiếu sheet "SinhVien"/);

  wb.addWorksheet('SinhVien').addRows([
    ['Mã lớp', 'MSSV', 'Họ tên', 'Email'],
    ['L1', '111', 'SV Một', 'sv1@x.vn'],
    ['L9', '222', 'SV Hai', 'sv2@x.vn'],
    ['L1', '333', 'SV Ba', 'khong-phai-email'],
  ]);
  const res = await upload(Buffer.from(await wb.xlsx.writeBuffer()));
  assert.equal(res.status, 200);
  assert.equal(res.body.classes, 1);
  assert.equal(res.body.students, 1);
  assert.deepEqual(res.body.errors, [
    'ThoiKhoaBieu dòng 2: cột Thứ phải là 2…7 hoặc CN',
    'SinhVien dòng 3: chưa có lớp L9 trong sheet ThoiKhoaBieu',
    'SinhVien dòng 4: email không hợp lệ',
  ]);
  const l1 = (await call(admin, 'GET', '/classes')).body[0];
  assert.deepEqual(l1.meetings, [{ weekday: 7, start: '07:30', end: '09:00', room: '' }]);
  assert.equal(l1.endDate, '2026-12-30');
});
