import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { createApp } from '../src/app.js';
import { User, Session } from '../src/models.js';
import { signToken } from '../src/auth.js';

const SECRET = 'test-secret';
const CLASSROOM = { lat: 10.8506, lng: 106.7719 };
const FAR = { lat: 10.8596, lng: 106.7719 };

let mongo, server, base;
let admin, lecturer, sv1, sv2, sv3, sessionId;

const unit = (i) => Array.from({ length: 512 }, (_, k) => (k === i ? 1 : 0)); // vector mặt giả, đã chuẩn hoá

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

const statusOf = async (who) =>
  (await call(lecturer, 'GET', `/sessions/${sessionId}`)).body.records.find((r) => r.student.id === who.id).status;

beforeEach(async () => {
  await mongoose.connection.db.dropDatabase();
  admin = await makeUser('admin', 'admin');
  lecturer = await makeUser('gv1', 'lecturer');
  [sv1, sv2, sv3] = [await makeUser('sv1', 'student'), await makeUser('sv2', 'student'), await makeUser('sv3', 'student')];
  const subject = (await call(admin, 'POST', '/admin/subjects', { code: 'IT001', name: 'Di động' })).body;
  const cls = (await call(admin, 'POST', '/admin/classes', { code: 'L1', subject: subject.id, lecturer: lecturer.id })).body;
  for (const s of [sv1, sv2, sv3]) await call(admin, 'POST', `/admin/classes/${cls.id}/students`, { studentId: s.id });
  sessionId = (await call(lecturer, 'POST', `/classes/${cls.id}/sessions`, { date: '2026-11-02' })).body.id;
  await call(lecturer, 'PATCH', `/sessions/${sessionId}`, { ...CLASSROOM, radius: 100 });
  // sv1, sv2 có mặt (sv2 đi muộn), sv3 vắng
  await call(lecturer, 'PATCH', `/sessions/${sessionId}/records/${sv1.id}`, { status: 'present' });
  await call(lecturer, 'PATCH', `/sessions/${sessionId}/records/${sv2.id}`, { status: 'late' });
});

test('kiểm tra 100%: chỉ gọi SV đang có mặt, ai xác minh kịp thì giữ trạng thái cũ, ai không thì "rời lớp sớm"', async () => {
  const created = await call(lecturer, 'POST', `/sessions/${sessionId}/spot-checks`, { percent: 100 });
  assert.equal(created.status, 201);
  assert.deepEqual(created.body.targets.map((t) => t.student).sort(), [sv1.id, sv2.id].sort());
  assert.equal(await statusOf(sv1), 'left');

  assert.equal((await call(sv3, 'GET', '/me/spot-check')).body, null, 'SV vắng không bị gọi');
  const pending = (await call(sv2, 'GET', '/me/spot-check')).body;
  assert.equal(pending.sessionId, sessionId);
  assert.equal(pending.classCode, 'L1');
  assert.equal(pending.requireFace, false);

  const ok = await call(sv2, 'POST', '/spot-checks/respond', { sessionId, ...CLASSROOM });
  assert.equal(ok.status, 200);
  assert.equal(await statusOf(sv2), 'late', 'trả lại đúng trạng thái trước đó');
  assert.equal((await call(sv2, 'GET', '/me/spot-check')).body, null);
  assert.equal((await call(sv2, 'POST', '/spot-checks/respond', { sessionId, ...CLASSROOM })).status, 404);

  // sv1 không phản hồi, hết giờ
  await Session.updateOne({ _id: sessionId }, { $set: { 'spotChecks.0.expiresAt': new Date(Date.now() - 1000) } });
  assert.equal((await call(sv1, 'GET', '/me/spot-check')).body, null);
  assert.match((await call(sv1, 'POST', '/spot-checks/respond', { sessionId, ...CLASSROOM })).body.message, /hết giờ/);
  assert.equal(await statusOf(sv1), 'left');

  // "rời lớp sớm" bị tính như vắng khi đếm số buổi còn được vắng
  const [row] = (await call(sv1, 'GET', '/me/attendance')).body;
  assert.equal(row.summary.left, 1);
  assert.equal(row.summary.remainingAbsences, row.summary.allowedAbsences - 1);
});

test('chọn ngẫu nhiên theo %, không cho tạo chồng lượt, chặn ở xa / thiếu GPS / SV không bị gọi', async () => {
  const created = await call(lecturer, 'POST', `/sessions/${sessionId}/spot-checks`, { percent: 50 });
  assert.equal(created.body.targets.length, 1, '50% của 2 SV có mặt');
  assert.equal((await call(lecturer, 'POST', `/sessions/${sessionId}/spot-checks`, {})).status, 409);
  assert.equal((await call(sv1, 'POST', `/sessions/${sessionId}/spot-checks`, {})).status, 403);

  const target = [sv1, sv2].find((s) => s.id === created.body.targets[0].student);
  const other = target === sv1 ? sv2 : sv1;
  assert.match((await call(target, 'POST', '/spot-checks/respond', { sessionId, ...FAR })).body.message, /cách lớp/);
  assert.equal((await call(target, 'POST', '/spot-checks/respond', { sessionId })).status, 400);
  assert.equal((await call(other, 'POST', '/spot-checks/respond', { sessionId, ...CLASSROOM })).status, 404);
  assert.equal((await call(target, 'POST', '/spot-checks/respond', { sessionId, ...CLASSROOM })).status, 200);
});

test('SV đã đăng ký mặt thì bắt buộc quét mặt đúng người', async () => {
  await call(sv1, 'PUT', '/me/face', { embedding: unit(0) });
  await call(lecturer, 'PATCH', `/sessions/${sessionId}/records/${sv2.id}`, { status: 'absent' });
  await call(lecturer, 'POST', `/sessions/${sessionId}/spot-checks`, { percent: 100 });

  assert.equal((await call(sv1, 'GET', '/me/spot-check')).body.requireFace, true);
  assert.match((await call(sv1, 'POST', '/spot-checks/respond', { sessionId, ...CLASSROOM })).body.message, /quét khuôn mặt/);
  const wrong = await call(sv1, 'POST', '/spot-checks/respond', { sessionId, ...CLASSROOM, embeddings: [unit(1)] });
  assert.equal(wrong.status, 400, 'không dùng 401 để app không tưởng hết phiên');
  assert.match(wrong.body.message, /không khớp/);
  const right = await call(sv1, 'POST', '/spot-checks/respond', { sessionId, ...CLASSROOM, embeddings: [unit(0)] });
  assert.equal(right.status, 200);
  assert.equal(await statusOf(sv1), 'present');
});

test('không kiểm tra khi buổi đã đóng hoặc chưa ai có mặt', async () => {
  await call(lecturer, 'PATCH', `/sessions/${sessionId}/records/${sv1.id}`, { status: 'absent' });
  await call(lecturer, 'PATCH', `/sessions/${sessionId}/records/${sv2.id}`, { status: 'absent' });
  assert.match((await call(lecturer, 'POST', `/sessions/${sessionId}/spot-checks`, {})).body.message, /Chưa có sinh viên/);
  await call(lecturer, 'PATCH', `/sessions/${sessionId}`, { open: false });
  assert.match((await call(lecturer, 'POST', `/sessions/${sessionId}/spot-checks`, {})).body.message, /đã đóng/);
});
