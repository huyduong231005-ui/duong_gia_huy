import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { createApp } from '../src/app.js';
import { User } from '../src/models.js';

const sentCodes = []; // [{ to, code, purpose }]
let mongo, server, base;

const googleUsers = {
  'tok-ok': { sub: 'g-1', email: 'gg@gmail.com', email_verified: true, name: 'Google User' },
  'tok-unverified': { sub: 'g-2', email: 'x@gmail.com', email_verified: false },
};

before(async () => {
  mongo = await MongoMemoryServer.create();
  await mongoose.connect(mongo.getUri());
  const app = createApp({
    jwtSecret: 'test-secret',
    sendMail: async (to, code, purpose) => sentCodes.push({ to, code, purpose }),
    verifyGoogle: async (t) => {
      if (!googleUsers[t]) throw new Error('bad token');
      return googleUsers[t];
    },
  });
  server = app.listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.close();
  await mongoose.disconnect();
  await mongo.stop();
});

beforeEach(async () => {
  sentCodes.length = 0;
  await mongoose.connection.db.dropDatabase();
  await Promise.all(Object.values(mongoose.models).map((m) => m.syncIndexes()));
});

async function call(method, path, body, token) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

const NEW_USER = { email: 'huy@gmail.com', username: 'duonggiahuy', password: '123456', fullName: 'Dương Gia Huy' };

async function registerAndVerify(user = NEW_USER) {
  await call('POST', '/auth/register', user);
  const { code } = sentCodes.at(-1);
  return call('POST', '/auth/register/verify', { email: user.email, code });
}

test('đăng ký email → OTP → kích hoạt, mặc định là sinh viên', async () => {
  const reg = await call('POST', '/auth/register', NEW_USER);
  assert.equal(reg.status, 201);
  assert.equal(reg.body.email, 'h***@gmail.com');
  assert.equal(sentCodes[0].purpose, 'register');
  assert.match(sentCodes[0].code, /^\d{6}$/);

  const ver = await call('POST', '/auth/register/verify', { email: NEW_USER.email, code: sentCodes[0].code });
  assert.equal(ver.status, 200);
  assert.equal(ver.body.user.role, 'student');
  assert.equal(ver.body.user.passwordHash, undefined, 'không được lộ mật khẩu băm');

  const me = await call('GET', '/me', null, ver.body.token);
  assert.equal(me.body.username, 'duonggiahuy');
});

test('đăng ký kiểm tra dữ liệu và chặn trùng', async () => {
  assert.equal((await call('POST', '/auth/register', { ...NEW_USER, email: 'sai' })).status, 400);
  assert.equal((await call('POST', '/auth/register', { ...NEW_USER, username: 'A B' })).status, 400);
  assert.equal((await call('POST', '/auth/register', { ...NEW_USER, password: '123' })).status, 400);
  await registerAndVerify();
  assert.equal((await call('POST', '/auth/register', { ...NEW_USER, email: 'khac@gmail.com' })).status, 409);
});

test('chưa xác minh thì đăng ký lại được để nhận mã mới', async () => {
  await call('POST', '/auth/register', NEW_USER);
  const again = await call('POST', '/auth/register', NEW_USER);
  assert.equal(again.status, 201);
  assert.equal(sentCodes.length, 2);
});

test('đăng nhập = mật khẩu + OTP email', async () => {
  await registerAndVerify();
  assert.equal((await call('POST', '/auth/login', { username: 'duonggiahuy', password: 'sai-mk' })).status, 401);

  const login = await call('POST', '/auth/login', { username: 'DuongGiaHuy', password: '123456' });
  assert.equal(login.status, 200);
  const { code, purpose } = sentCodes.at(-1);
  assert.equal(purpose, 'login');

  const ok = await call('POST', '/auth/login/verify', { username: 'duonggiahuy', code });
  assert.equal(ok.status, 200);
  assert.ok(ok.body.token);
  // Mã chỉ dùng 1 lần
  assert.equal((await call('POST', '/auth/login/verify', { username: 'duonggiahuy', code })).status, 400);
});

test('OTP sai 5 lần thì mã bị huỷ', async () => {
  await registerAndVerify();
  await call('POST', '/auth/login', { username: 'duonggiahuy', password: '123456' });
  const { code } = sentCodes.at(-1);
  const wrong = code === '000000' ? '111111' : '000000';
  for (let i = 0; i < 5; i++) await call('POST', '/auth/login/verify', { username: 'duonggiahuy', code: wrong });
  assert.equal((await call('POST', '/auth/login/verify', { username: 'duonggiahuy', code })).status, 400);
});

test('chưa xác minh email thì không đăng nhập được', async () => {
  await call('POST', '/auth/register', NEW_USER);
  assert.equal((await call('POST', '/auth/login', { username: 'duonggiahuy', password: '123456' })).status, 403);
});

test('Google OAuth2: tạo tài khoản, lần sau đăng nhập lại cùng tài khoản', async () => {
  const first = await call('POST', '/auth/google', { idToken: 'tok-ok' });
  assert.equal(first.status, 200);
  assert.equal(first.body.user.username, 'gg0', 'tên ngắn được đệm đủ 3 ký tự');
  assert.equal(first.body.user.fullName, 'Google User');
  const second = await call('POST', '/auth/google', { idToken: 'tok-ok' });
  assert.equal(second.body.user.id, first.body.user.id);

  assert.equal((await call('POST', '/auth/google', { idToken: 'gia' })).status, 401);
  assert.equal((await call('POST', '/auth/google', { idToken: 'tok-unverified' })).status, 400);
});

test('Google gắn vào tài khoản email đã có', async () => {
  await registerAndVerify({ ...NEW_USER, email: 'gg@gmail.com' });
  const g = await call('POST', '/auth/google', { idToken: 'tok-ok' });
  assert.equal(g.body.user.username, 'duonggiahuy');
});

test('/me cần token hợp lệ', async () => {
  assert.equal((await call('GET', '/me')).status, 401);
  assert.equal((await call('GET', '/me', null, 'rac')).status, 401);
  const { body } = await registerAndVerify();
  await User.updateOne({ username: 'duonggiahuy' }, { active: false });
  assert.equal((await call('GET', '/me', null, body.token)).status, 401);
});

test('JSON hỏng và API lạ trả lỗi gọn', async () => {
  const bad = await fetch(`${base}/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{' });
  assert.equal(bad.status, 400);
  assert.equal((await call('GET', '/khong-co')).status, 404);
});
