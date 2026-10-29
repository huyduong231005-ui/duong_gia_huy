import crypto from 'node:crypto';
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { User, Otp } from './models.js';

const OTP_TTL_MS = 5 * 60 * 1000;
const OTP_MAX_ATTEMPTS = 5;
const TOKEN_TTL = '7d';
export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export const USERNAME_RE = /^[a-z0-9_.]{3,30}$/;
export const MIN_PASSWORD = 6;

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
const maskEmail = (email) => email.replace(/^(.).*(@.*)$/, '$1***$2');
export const str = (v) => (typeof v === 'string' ? v.trim() : '');

export function signToken(user, jwtSecret) {
  return jwt.sign({ sub: user.id, role: user.role }, jwtSecret, { expiresIn: TOKEN_TTL });
}

/** Kiểm JWT, nạp user từ DB (để đổi role/khoá có hiệu lực ngay) và kiểm role nếu có truyền. */
export function requireAuth(jwtSecret, ...roles) {
  return async (req, _res, next) => {
    const token = req.get('authorization')?.replace(/^Bearer /, '');
    let payload;
    try {
      payload = jwt.verify(token ?? '', jwtSecret);
    } catch {
      throw new HttpError(401, 'Phiên đăng nhập không hợp lệ hoặc đã hết hạn');
    }
    const user = await User.findById(payload.sub);
    if (!user?.active) throw new HttpError(401, 'Tài khoản không còn hoạt động');
    if (roles.length && !roles.includes(user.role)) throw new HttpError(403, 'Bạn không có quyền làm việc này');
    req.user = user;
    next();
  };
}

export function authRouter({ sendMail, verifyGoogle, jwtSecret }) {
  const router = Router();
  const session = (user) => ({ token: signToken(user, jwtSecret), user });

  async function issueOtp(user, purpose) {
    const code = crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
    await Otp.findOneAndUpdate(
      { userId: user._id, purpose },
      { codeHash: sha256(code), attempts: 0, expiresAt: new Date(Date.now() + OTP_TTL_MS) },
      { upsert: true },
    );
    try {
      await sendMail(user.email, code, purpose);
    } catch (err) {
      console.error('Gửi email OTP lỗi:', err);
      throw new HttpError(502, 'Không gửi được email OTP, hãy thử lại');
    }
  }

  async function consumeOtp(user, purpose, code) {
    const otp = await Otp.findOne({ userId: user._id, purpose });
    if (!otp || otp.expiresAt < new Date()) throw new HttpError(400, 'Mã OTP đã hết hạn, hãy gửi lại mã mới');
    if (otp.codeHash !== sha256(str(code))) {
      otp.attempts += 1;
      if (otp.attempts >= OTP_MAX_ATTEMPTS) {
        await otp.deleteOne();
        throw new HttpError(400, 'Nhập sai quá nhiều lần, hãy gửi lại mã mới');
      }
      await otp.save();
      throw new HttpError(400, 'Mã OTP không đúng');
    }
    await otp.deleteOne();
  }

  router.post('/register', async (req, res) => {
    const email = str(req.body?.email).toLowerCase();
    const username = str(req.body?.username).toLowerCase();
    const fullName = str(req.body?.fullName);
    const password = typeof req.body?.password === 'string' ? req.body.password : '';
    if (!EMAIL_RE.test(email)) throw new HttpError(400, 'Email không hợp lệ');
    if (!USERNAME_RE.test(username)) throw new HttpError(400, 'Tên đăng nhập 3–30 ký tự: chữ thường, số, dấu _ hoặc .');
    if (password.length < MIN_PASSWORD) throw new HttpError(400, `Mật khẩu tối thiểu ${MIN_PASSWORD} ký tự`);

    let user = await User.findOne({ $or: [{ email }, { username }] });
    // Đăng ký lại khi chưa xác minh (VD: mất mã OTP) thì cho cập nhật và gửi mã mới.
    const isRetry = user && !user.active && user.email === email && user.username === username;
    if (user && !isRetry) throw new HttpError(409, 'Tên đăng nhập hoặc email đã được dùng');

    user ??= new User({ email, username });
    user.fullName = fullName;
    user.passwordHash = await bcrypt.hash(password, 10);
    await user.save();
    await issueOtp(user, 'register');
    res.status(201).json({ message: 'Đã gửi mã OTP tới email', email: maskEmail(email) });
  });

  router.post('/register/verify', async (req, res) => {
    const user = await User.findOne({ email: str(req.body?.email).toLowerCase() });
    if (!user || user.active) throw new HttpError(400, 'Không có tài khoản nào đang chờ xác minh với email này');
    await consumeOtp(user, 'register', req.body?.code);
    user.active = true;
    await user.save();
    res.json(session(user));
  });

  router.post('/login', async (req, res) => {
    const user = await User.findOne({ username: str(req.body?.username).toLowerCase() });
    const password = typeof req.body?.password === 'string' ? req.body.password : '';
    const ok = user?.passwordHash && (await bcrypt.compare(password, user.passwordHash));
    if (!ok) throw new HttpError(401, 'Sai tên đăng nhập hoặc mật khẩu');
    if (!user.active) throw new HttpError(403, 'Tài khoản chưa xác minh email');
    await issueOtp(user, 'login');
    res.json({ message: 'Đã gửi mã OTP tới email', email: maskEmail(user.email) });
  });

  router.post('/login/verify', async (req, res) => {
    const user = await User.findOne({ username: str(req.body?.username).toLowerCase() });
    if (!user?.active) throw new HttpError(400, 'Tài khoản không hợp lệ');
    await consumeOtp(user, 'login', req.body?.code);
    if (user.faceFails) {
      user.faceFails = 0; // đăng nhập mật khẩu + OTP thành công thì mở lại đăng nhập bằng mặt
      await user.save();
    }
    res.json(session(user));
  });

  // OAuth2: app gửi idToken lấy từ Google Sign-In, backend tự xác thực với Google.
  router.post('/google', async (req, res) => {
    let payload;
    try {
      payload = await verifyGoogle(str(req.body?.idToken));
    } catch {
      throw new HttpError(401, 'Token Google không hợp lệ');
    }
    if (!payload?.email_verified) throw new HttpError(400, 'Email Google chưa được xác minh');
    const email = payload.email.toLowerCase();

    let user = await User.findOne({ $or: [{ googleId: payload.sub }, { email }] });
    if (!user) {
      const base = email.split('@')[0].toLowerCase().replace(/[^a-z0-9_.]/g, '').slice(0, 24).padEnd(3, '0');
      const taken = await User.exists({ username: base });
      user = new User({ email, username: taken ? `${base}_${crypto.randomInt(1000, 10000)}` : base });
    }
    user.googleId = payload.sub;
    user.fullName ||= payload.name ?? '';
    user.active = true; // Google đã xác minh email
    await user.save();
    res.json(session(user));
  });

  return router;
}
