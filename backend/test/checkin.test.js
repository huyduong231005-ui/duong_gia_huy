import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { createApp } from '../src/app.js';
import { User, Session } from '../src/models.js';
import { signToken } from '../src/auth.js';
import { qrToken, qrWindow, verifyQr, distanceM, QR_WINDOW_MS } from '../src/checkin.js';

const SECRET = 'test-secret';
// Sân trường (toạ độ ví dụ) và 1 điểm cách ~1 km
const CLASSROOM = { lat: 10.8506, lng: 106.7719 };
const FAR = { lat: 10.8596, lng: 106.7719 };

let mongo, server, base;
let admin, lecturer, student, outsider, sessionId;

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
  const u = await User.create({ username, email: `${username}@x.vn`, role, active: true });
  return { id: u.id, token: signToken(u, SECRET) };
}

async function call(who, method, path, body) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', authorization: `Bearer ${who.token}` },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

beforeEach(async () => {
  await mongoose.connection.db.dropDatabase();
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
  admin = await makeUser('admin', 'admin');
  lecturer = await makeUser('gv1', 'lecturer');
  student = await makeUser('sv1', 'student');
  outsider = await makeUser('sv2', 'student');
  const subject = (await call(admin, 'POST', '/admin/subjects', { code: 'IT001', name: 'Di động' })).body;
  const cls = (await call(admin, 'POST', '/admin/classes', { code: 'L1', subject: subject.id, lecturer: lecturer.id })).body;
  await call(admin, 'POST', `/admin/classes/${cls.id}/students`, { studentId: student.id });
  sessionId = (await call(lecturer, 'POST', `/classes/${cls.id}/sessions`, { date: '2026-11-02' })).body.id;
  // GV bật chiếu QR tại lớp, bán kính 100 m
  await call(lecturer, 'PATCH', `/sessions/${sessionId}`, { ...CLASSROOM, radius: 100 });
});

const qr = async () => (await call(lecturer, 'GET', `/sessions/${sessionId}/qr`)).body.token;

test('haversine: 0,009 độ vĩ ≈ 1 km', () => {
  assert.equal(Math.round(distanceM(CLASSROOM.lat, CLASSROOM.lng, FAR.lat, FAR.lng) / 10) * 10, 1000);
  assert.equal(distanceM(1, 2, 1, 2), 0);
});

test('mã QR: đúng chữ ký, hết hạn sau 2 cửa sổ, sửa 1 ký tự là hỏng', () => {
  const now = Date.now();
  const token = qrToken('abc', qrWindow(now), SECRET);
  assert.equal(verifyQr(token, SECRET, now), 'abc');
  assert.equal(verifyQr(token, SECRET, now + QR_WINDOW_MS), 'abc', 'cho trễ 1 cửa sổ');
  assert.throws(() => verifyQr(token, SECRET, now + 2 * QR_WINDOW_MS), /hết hạn/);
  assert.throws(() => verifyQr(token.slice(0, -1) + (token.endsWith('A') ? 'B' : 'A'), SECRET, now), /không hợp lệ/);
  assert.throws(() => verifyQr(token, 'khoa-khac', now), /không hợp lệ/);
  assert.throws(() => verifyQr(undefined, SECRET, now), /không hợp lệ/);
});

test('SV quét QR đúng chỗ → có mặt, GV thấy vị trí trên bản đồ', async () => {
  const res = await call(student, 'POST', '/checkin', { token: await qr(), lat: 10.8507, lng: 106.7720 });
  assert.equal(res.status, 200);
  assert.equal(res.body.classCode, 'L1');
  assert.ok(res.body.distance < 20);

  const session = (await call(lecturer, 'GET', `/sessions/${sessionId}`)).body;
  assert.equal(session.records[0].status, 'present');
  assert.equal(session.records[0].lat, 10.8507);

  assert.equal((await call(student, 'POST', '/checkin', { token: await qr(), ...CLASSROOM })).status, 409);
});

test('quét QR sau 15 phút kể từ lúc mở buổi thì ghi "đi muộn"', async () => {
  // Giả lập buổi đã mở được 20 phút (sửa thẳng createdAt, Mongoose không cho đổi qua model)
  await Session.collection.updateOne(
    { _id: new mongoose.Types.ObjectId(sessionId) },
    { $set: { createdAt: new Date(Date.now() - 20 * 60 * 1000) } },
  );
  const res = await call(student, 'POST', '/checkin', { token: await qr(), ...CLASSROOM });
  assert.equal(res.body.status, 'late');
  assert.equal((await call(lecturer, 'GET', `/sessions/${sessionId}`)).body.records[0].status, 'late');
});

test('SV ghi danh sau khi buổi đã mở vẫn quét QR được', async () => {
  const sessions = (await call(lecturer, 'GET', '/classes')).body;
  await call(admin, 'POST', `/admin/classes/${sessions[0].id}/students`, { studentId: outsider.id });
  const res = await call(outsider, 'POST', '/checkin', { token: await qr(), ...CLASSROOM });
  assert.equal(res.status, 200);
});

test('chặn: ở xa, fake GPS, thiếu vị trí, mã cũ, không có tên trong lớp, buổi đã đóng', async () => {
  const far = await call(student, 'POST', '/checkin', { token: await qr(), ...FAR });
  assert.equal(far.status, 400);
  assert.match(far.body.message, /cách lớp khoảng 10\d\d m/);

  assert.match((await call(student, 'POST', '/checkin', { token: await qr(), ...CLASSROOM, mocked: true })).body.message, /giả lập/);
  assert.equal((await call(student, 'POST', '/checkin', { token: await qr() })).status, 400);

  const old = qrToken(sessionId, qrWindow() - 5, SECRET);
  assert.match((await call(student, 'POST', '/checkin', { token: old, ...CLASSROOM })).body.message, /hết hạn/);

  assert.equal((await call(outsider, 'POST', '/checkin', { token: await qr(), ...CLASSROOM })).status, 403);
  assert.equal((await call(lecturer, 'POST', '/checkin', { token: await qr(), ...CLASSROOM })).status, 403);
  assert.equal((await call(student, 'GET', `/sessions/${sessionId}/qr`)).status, 403);

  const token = await qr();
  await call(lecturer, 'PATCH', `/sessions/${sessionId}`, { open: false });
  assert.match((await call(student, 'POST', '/checkin', { token, ...CLASSROOM })).body.message, /đã đóng/);
  assert.equal((await call(lecturer, 'GET', `/sessions/${sessionId}/qr`)).status, 400);
});
