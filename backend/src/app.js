import { fileURLToPath } from 'node:url';
import express from 'express';
import rateLimit from 'express-rate-limit';
import { authRouter, requireAuth, HttpError, updateProfile } from './auth.js';
import { adminRouter } from './admin.js';
import { teachingRouter } from './teaching.js';
import { faceRouter } from './face.js';
import { spotCheckRouter } from './spotcheck.js';

const PUBLIC_DIR = fileURLToPath(new URL('../public', import.meta.url));
const AUTH_WINDOW_MS = 15 * 60 * 1000;
const AUTH_MAX_REQUESTS = 100;

export function createApp({ sendMail, verifyGoogle, jwtSecret }) {
  const app = express();
  app.set('trust proxy', 1); // Render đứng sau proxy, cần để rate limit lấy đúng IP
  app.use(express.json({ limit: '1mb' }));

  app.get('/health', (_req, res) => res.json({ ok: true }));
  // Trang chủ + chính sách quyền riêng tư (Google đòi khi xuất bản màn hình đồng ý OAuth)
  app.use(express.static(PUBLIC_DIR, { extensions: ['html'] }));
  app.use(
    '/auth',
    rateLimit({ windowMs: AUTH_WINDOW_MS, limit: AUTH_MAX_REQUESTS }),
    authRouter({ sendMail, verifyGoogle, jwtSecret }),
  );
  app.get('/me', requireAuth(jwtSecret), (req, res) => res.json(req.user));
  app.patch('/me', requireAuth(jwtSecret), updateProfile);
  app.use(faceRouter({ jwtSecret })); // trước teachingRouter vì /auth/face không cần token
  app.use('/admin', requireAuth(jwtSecret, 'admin'), adminRouter());
  app.use(requireAuth(jwtSecret), teachingRouter({ qrSecret: jwtSecret }));
  app.use(spotCheckRouter({ jwtSecret }));

  app.use((_req, _res, next) => next(new HttpError(404, 'Không tìm thấy API')));
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    const badId = err.name === 'CastError' && err.kind === 'ObjectId';
    const status =
      err.code === 11000 ? 409
      : badId ? 404
      : err.name === 'CastError' || err.name === 'ValidationError' ? 400
      : err.status ?? 500;
    if (status >= 500) console.error(err);
    const message =
      err instanceof HttpError ? err.message
      : status === 409 ? 'Dữ liệu bị trùng (mã hoặc tên đã tồn tại)'
      : badId ? 'Không tìm thấy dữ liệu'
      : status < 500 ? 'Dữ liệu không hợp lệ'
      : 'Lỗi máy chủ';
    res.status(status).json({ message });
  });
  return app;
}
