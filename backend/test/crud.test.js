import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { createApp } from '../src/app.js';
import { User } from '../src/models.js';
import { signToken } from '../src/auth.js';

const SECRET = 'test-secret';
let mongo, server, base;
let admin, lecturer, lecturer2, student, student2; // { id, token }

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

async function makeUser(username, role) {
  const u = await User.create({ username, email: `${username}@x.vn`, fullName: username, role, active: true });
  return { id: u.id, token: signToken(u, SECRET) };
}

beforeEach(async () => {
  await mongoose.connection.db.dropDatabase();
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
  admin = await makeUser('admin', 'admin');
  lecturer = await makeUser('gv1', 'lecturer');
  lecturer2 = await makeUser('gv2', 'lecturer');
  student = await makeUser('sv1', 'student');
  student2 = await makeUser('sv2', 'student');
});

async function call(who, method, path, body) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${who.token}` },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: res.status === 204 ? null : await res.json() };
}

/** Môn + lớp do gv1 dạy, có sv1 ghi danh. */
async function setupClass() {
  const subject = (await call(admin, 'POST', '/admin/subjects', { code: 'it001', name: 'Lập trình di động', credits: 3 })).body;
  const cls = (await call(admin, 'POST', '/admin/classes', {
    code: 'it001.1', subject: subject.id, lecturer: lecturer.id, room: 'A1', plannedSessions: 10,
  })).body;
  await call(admin, 'POST', `/admin/classes/${cls.id}/students`, { studentId: student.id });
  return { subject, cls };
}

test('admin: CRUD tài khoản', async () => {
  const created = await call(admin, 'POST', '/admin/users', {
    username: 'gv3', email: 'gv3@x.vn', password: '123456', fullName: 'Thầy Ba', role: 'lecturer',
  });
  assert.equal(created.status, 201);
  assert.equal(created.body.active, true);
  assert.equal(created.body.passwordHash, undefined);

  const list = await call(admin, 'GET', '/admin/users?role=lecturer&q=ba');
  assert.deepEqual(list.body.map((u) => u.username), ['gv3']);

  const edited = await call(admin, 'PATCH', `/admin/users/${created.body.id}`, { fullName: 'Thầy Ba 2', active: false });
  assert.equal(edited.body.fullName, 'Thầy Ba 2');
  assert.equal(edited.body.active, false);

  // Admin không tự hạ quyền / tự xoá mình
  const self = await call(admin, 'PATCH', `/admin/users/${admin.id}`, { role: 'student' });
  assert.equal(self.body.role, 'admin');
  assert.equal((await call(admin, 'DELETE', `/admin/users/${admin.id}`)).status, 400);

  assert.equal((await call(admin, 'DELETE', `/admin/users/${created.body.id}`)).status, 204);
  assert.equal((await call(admin, 'PATCH', `/admin/users/${created.body.id}`, { fullName: 'x' })).status, 404);
});

test('chỉ admin vào được /admin', async () => {
  assert.equal((await call(lecturer, 'GET', '/admin/users')).status, 403);
  assert.equal((await call(student, 'POST', '/admin/subjects', { code: 'X', name: 'X' })).status, 403);
});

test('admin: CRUD môn học, chặn trùng mã và xoá môn đang có lớp', async () => {
  const { subject } = await setupClass();
  assert.equal((await call(admin, 'POST', '/admin/subjects', { code: 'IT001', name: 'Trùng' })).status, 409);
  assert.equal((await call(admin, 'POST', '/admin/subjects', { name: 'Thiếu mã' })).status, 400);
  const edited = await call(admin, 'PATCH', `/admin/subjects/${subject.id}`, { name: 'Di động nâng cao' });
  assert.equal(edited.body.name, 'Di động nâng cao');
  assert.equal(edited.body.code, 'IT001');
  assert.equal((await call(admin, 'DELETE', `/admin/subjects/${subject.id}`)).status, 409);
  assert.equal((await call(admin, 'GET', '/admin/subjects/khong-phai-id')).status, 404);
});

test('admin: lớp học phần + ghi danh, mỗi vai trò chỉ thấy lớp của mình', async () => {
  const { cls } = await setupClass();
  assert.equal((await call(admin, 'POST', '/admin/classes', { code: 'X1', subject: cls.subject, lecturer: student.id })).status, 400);

  assert.equal((await call(admin, 'GET', '/classes')).body.length, 1);
  assert.equal((await call(lecturer, 'GET', '/classes')).body.length, 1);
  assert.equal((await call(lecturer2, 'GET', '/classes')).body.length, 0);
  assert.equal((await call(student, 'GET', '/classes')).body.length, 1);
  assert.equal((await call(student2, 'GET', '/classes')).body.length, 0);
  assert.equal((await call(student2, 'GET', `/classes/${cls.id}`)).status, 404);

  const detail = await call(lecturer, 'GET', `/classes/${cls.id}`);
  assert.equal(detail.body.subject.name, 'Lập trình di động');
  assert.deepEqual(detail.body.students.map((s) => s.username), ['sv1']);

  await call(admin, 'DELETE', `/admin/classes/${cls.id}/students/${student.id}`);
  assert.equal((await call(student, 'GET', '/classes')).body.length, 0);

  assert.equal((await call(admin, 'PATCH', `/admin/classes/${cls.id}`, { room: 'B2' })).body.room, 'B2');
  assert.equal((await call(admin, 'DELETE', `/admin/classes/${cls.id}`)).status, 204);
});

test('giảng viên: mở buổi, điểm danh từng SV, đóng buổi, xoá buổi', async () => {
  const { cls } = await setupClass();
  assert.equal((await call(student, 'POST', `/classes/${cls.id}/sessions`, { date: '2026-11-02' })).status, 403);
  assert.equal((await call(lecturer2, 'POST', `/classes/${cls.id}/sessions`, { date: '2026-11-02' })).status, 404);
  assert.equal((await call(lecturer, 'POST', `/classes/${cls.id}/sessions`, { date: '2/11' })).status, 400);

  const s = (await call(lecturer, 'POST', `/classes/${cls.id}/sessions`, { date: '2026-11-02', topic: 'Buổi 1' })).body;
  assert.deepEqual(s.records.map((r) => r.status), ['absent']);

  const marked = await call(lecturer, 'PATCH', `/sessions/${s.id}/records/${student.id}`, { status: 'late' });
  assert.equal(marked.body.records[0].status, 'late');
  assert.ok(marked.body.records[0].checkedAt);
  assert.equal((await call(lecturer, 'PATCH', `/sessions/${s.id}/records/${student2.id}`, { status: 'present' })).status, 404);
  assert.equal((await call(lecturer, 'PATCH', `/sessions/${s.id}/records/${student.id}`, { status: 'ngu' })).status, 400);

  assert.equal((await call(lecturer, 'PATCH', `/sessions/${s.id}`, { open: false })).body.open, false);

  const mine = await call(student, 'GET', `/classes/${cls.id}/sessions`);
  assert.deepEqual(mine.body.map((x) => x.myStatus), ['late']);
  assert.equal(mine.body[0].records, undefined, 'SV không thấy điểm danh của bạn khác');

  assert.equal((await call(lecturer, 'DELETE', `/sessions/${s.id}`)).status, 204);
  assert.equal((await call(lecturer, 'GET', `/sessions/${s.id}`)).status, 404);
});

test('sinh viên: lịch sử chuyên cần và số buổi còn được vắng', async () => {
  const { cls } = await setupClass(); // plannedSessions = 10 → được vắng 2
  for (const date of ['2026-11-02', '2026-11-09', '2026-11-16']) {
    await call(lecturer, 'POST', `/classes/${cls.id}/sessions`, { date });
  }
  const s = (await call(lecturer, 'GET', `/classes/${cls.id}/sessions`)).body[0];
  await call(lecturer, 'PATCH', `/sessions/${s.id}/records/${student.id}`, { status: 'present' });

  const [row] = (await call(student, 'GET', '/me/attendance')).body;
  assert.equal(row.classSection.code, 'IT001.1');
  assert.deepEqual(
    { total: row.summary.total, present: row.summary.present, absent: row.summary.absent, remaining: row.summary.remainingAbsences },
    { total: 3, present: 1, absent: 2, remaining: 0 },
  );
});

test('đơn xin nghỉ: SV gửi/sửa/rút, GV duyệt → buổi học thành "có phép"', async () => {
  const { cls } = await setupClass();
  const session = (await call(lecturer, 'POST', `/classes/${cls.id}/sessions`, { date: '2026-11-02' })).body;

  assert.equal((await call(student2, 'POST', '/leaves', { classId: cls.id, date: '2026-11-02', reason: 'Ốm' })).status, 404);
  assert.equal((await call(student, 'POST', '/leaves', { date: '2026-11-02', reason: 'Ốm' })).status, 400);
  const leave = (await call(student, 'POST', '/leaves', { classId: cls.id, date: '2026-11-02', reason: 'Ốm' })).body;
  assert.equal(leave.status, 'pending');

  assert.equal((await call(student, 'PATCH', `/leaves/${leave.id}`, { reason: 'Sốt cao' })).body.reason, 'Sốt cao');
  assert.equal((await call(student, 'PATCH', `/leaves/${leave.id}`, { status: 'approved' })).body.status, 'pending');
  assert.equal((await call(lecturer2, 'PATCH', `/leaves/${leave.id}`, { status: 'approved' })).status, 404);

  assert.equal((await call(lecturer, 'GET', '/leaves')).body.length, 1);
  assert.equal((await call(lecturer2, 'GET', '/leaves')).body.length, 0);

  assert.equal((await call(lecturer, 'PATCH', `/leaves/${leave.id}`, { status: 'approved' })).body.status, 'approved');
  const after = await call(lecturer, 'GET', `/sessions/${session.id}`);
  assert.equal(after.body.records[0].status, 'excused');

  // Buổi mở sau khi đã duyệt đơn cùng ngày cũng vào sẵn "có phép"
  const again = (await call(lecturer, 'POST', `/classes/${cls.id}/sessions`, { date: '2026-11-02', topic: 'Bù' })).body;
  assert.equal(again.records[0].status, 'excused');

  assert.equal((await call(student, 'PATCH', `/leaves/${leave.id}`, { reason: 'x' })).status, 400);
  assert.equal((await call(student, 'DELETE', `/leaves/${leave.id}`)).status, 400);

  const pending = (await call(student, 'POST', '/leaves', { classId: cls.id, date: '2026-11-09', reason: 'Việc nhà' })).body;
  assert.equal((await call(student, 'DELETE', `/leaves/${pending.id}`)).status, 204);
});

test('xoá SV khỏi hệ thống thì gỡ khỏi lớp, buổi học và xoá đơn', async () => {
  const { cls } = await setupClass();
  await call(lecturer, 'POST', `/classes/${cls.id}/sessions`, { date: '2026-11-02' });
  await call(student, 'POST', '/leaves', { classId: cls.id, date: '2026-11-02', reason: 'Ốm' });
  assert.equal((await call(admin, 'DELETE', `/admin/users/${lecturer.id}`)).status, 409);

  assert.equal((await call(admin, 'DELETE', `/admin/users/${student.id}`)).status, 204);
  assert.equal((await call(admin, 'GET', `/classes/${cls.id}`)).body.students.length, 0);
  assert.equal((await call(admin, 'GET', `/classes/${cls.id}/sessions`)).body[0].records.length, 0);
  assert.equal((await call(admin, 'GET', '/leaves')).body.length, 0);
});
