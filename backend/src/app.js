import express from 'express';
import rateLimit from 'express-rate-limit';
import { authRouter, requireAuth, HttpError } from './auth.js';

const AUTH_WINDOW_MS = 15 * 60 * 1000;
const AUTH_MAX_REQUESTS = 100;

export function createApp({ sendMail, verifyGoogle, jwtSecret }) {
  const app = express();
  app.set('trust proxy', 1); // Render đứng sau proxy, cần để rate limit lấy đúng IP
  app.use(express.json({ limit: '1mb' }));

  app.get('/health', (_req, res) => res.json({ ok: true }));
  app.use(
    '/auth',
    rateLimit({ windowMs: AUTH_WINDOW_MS, limit: AUTH_MAX_REQUESTS }),
    authRouter({ sendMail, verifyGoogle, jwtSecret }),
  );
  app.get('/me', requireAuth(jwtSecret), (req, res) => res.json(req.user));

  app.use((_req, _res, next) => next(new HttpError(404, 'Không tìm thấy API')));
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    const status = err.code === 11000 ? 409 : err.status ?? 500;
    if (status >= 500) console.error(err);
    const message =
      err instanceof HttpError ? err.message
      : status === 409 ? 'Dữ liệu bị trùng'
      : status < 500 ? 'Yêu cầu không hợp lệ'
      : 'Lỗi máy chủ';
    res.status(status).json({ message });
  });
  return app;
}
