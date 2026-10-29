import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { createApp } from '../src/app.js';
import { User } from '../src/models.js';
import { signToken } from '../src/auth.js';
import { MAX_FACE_FAILS, euclidean } from '../src/face.js';

const SECRET = 'test-secret';
let mongo, server, base, me;

// Vector giả lập: cùng người = vector gốc + nhiễu nhỏ; người khác = vector ngẫu nhiên khác.
let seed = 42;
const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647) - 0.5;
const normalize = (v) => {
  const n = Math.sqrt(v.reduce((s, x) => s + x * x, 0));
  return v.map((x) => x / n);
};
const randomFace = () => normalize(Array.from({ length: 512 }, rand));
const sameFace = (face, noise = 0.01) => normalize(face.map((x) => x + rand() * noise));

const HUY = randomFace();
const STRANGER = randomFace();

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
  const u = await User.create({ username: 'huy', email: 'huy@x.vn', role: 'student', active: true });
  me = signToken(u, SECRET);
});

async function call(method, path, body, token) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

const faceLogin = (...embeddings) => call('POST', '/auth/face', { username: 'HUY', embeddings });

test('dữ liệu giả lập đúng ý: cùng người gần, người lạ xa', () => {
  assert.ok(euclidean(HUY, sameFace(HUY)) < 0.3);
  assert.ok(euclidean(HUY, STRANGER) > 1.2);
});

test('đăng ký mặt rồi đăng nhập bằng mặt, không lộ vector ra ngoài', async () => {
  assert.equal((await faceLogin(sameFace(HUY))).status, 400, 'chưa đăng ký mặt');

  const saved = await call('PUT', '/me/face', { embedding: HUY }, me);
  assert.equal(saved.status, 200);
  assert.equal(saved.body.hasFace, true);
  assert.equal(saved.body.faceEmbedding, undefined);

  const ok = await faceLogin(STRANGER, sameFace(HUY)); // 1 ảnh hỏng, 1 ảnh tốt vẫn qua
  assert.equal(ok.status, 200);
  assert.ok(ok.body.token);
  assert.equal(ok.body.user.username, 'huy');
  assert.equal(ok.body.user.faceEmbedding, undefined);
});

test('người lạ bị từ chối, sai quá 5 lần thì khoá đăng nhập bằng mặt', async () => {
  await call('PUT', '/me/face', { embedding: HUY }, me);
  for (let i = 1; i <= MAX_FACE_FAILS; i++) {
    const r = await faceLogin(STRANGER);
    assert.equal(r.status, 401);
  }
  const locked = await faceLogin(sameFace(HUY));
  assert.equal(locked.status, 403, 'kể cả đúng mặt cũng phải dùng mật khẩu');

  // Đăng ký lại mặt (đã đăng nhập bằng cách khác) thì mở khoá
  await call('PUT', '/me/face', { embedding: HUY }, me);
  assert.equal((await faceLogin(sameFace(HUY))).status, 200);
});

test('chặn dữ liệu mặt sai định dạng và xoá được mặt đã đăng ký', async () => {
  const bad = [
    HUY.slice(0, 100), // thiếu chiều
    HUY.map((x) => x * 3), // chưa chuẩn hoá
    [...HUY.slice(0, 511), 'x'],
  ];
  for (const embedding of bad) assert.equal((await call('PUT', '/me/face', { embedding }, me)).status, 400);
  assert.equal((await call('PUT', '/me/face', { embedding: HUY })).status, 401, 'cần đăng nhập');
  assert.equal((await call('POST', '/auth/face', { username: 'huy', embeddings: [HUY, HUY, HUY, HUY] })).status, 400);

  await call('PUT', '/me/face', { embedding: HUY }, me);
  const removed = await call('DELETE', '/me/face', null, me);
  assert.equal(removed.body.hasFace, false);
  assert.equal((await faceLogin(sameFace(HUY))).status, 400);
});
