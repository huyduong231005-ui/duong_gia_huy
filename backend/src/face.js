// Đăng nhập bằng khuôn mặt. App tự chạy ML Kit + FaceNet-512 trên máy (kèm kiểm tra nháy mắt),
// chỉ gửi vector 512 số đã chuẩn hoá L2; server lưu vector mẫu và tự so khớp.
import { Router } from 'express';
import { User } from './models.js';
import { HttpError, requireAuth, signToken, str } from './auth.js';

export const EMBEDDING_LENGTH = 512;
// Ngưỡng khoảng cách Euclid (mức "Cao" đo trên LFW ở project faceid: chính chủ ~83%, người lạ 0%)
export const FACE_THRESHOLD = 0.65;
export const MAX_FACE_FAILS = 5;
const MAX_SAMPLES = 3;

export function isEmbedding(v) {
  if (!Array.isArray(v) || v.length !== EMBEDDING_LENGTH || !v.every(Number.isFinite)) return false;
  const norm = Math.sqrt(v.reduce((s, x) => s + x * x, 0));
  return Math.abs(norm - 1) < 0.05; // phải là vector đã chuẩn hoá
}

export function euclidean(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) sum += (a[i] - b[i]) ** 2;
  return Math.sqrt(sum);
}

export function faceRouter({ jwtSecret }) {
  const r = Router();

  // Lưu / thay mẫu khuôn mặt của chính mình (app gửi trung bình 5 ảnh)
  r.put('/me/face', requireAuth(jwtSecret), async (req, res) => {
    const embedding = req.body?.embedding;
    if (!isEmbedding(embedding)) throw new HttpError(400, 'Dữ liệu khuôn mặt không hợp lệ');
    req.user.set({ faceEmbedding: embedding, faceUpdatedAt: new Date(), faceFails: 0 });
    res.json(await req.user.save());
  });

  r.delete('/me/face', requireAuth(jwtSecret), async (req, res) => {
    req.user.set({ faceEmbedding: undefined, faceUpdatedAt: undefined, faceFails: 0 });
    res.json(await req.user.save());
  });

  // App chụp 2 ảnh lúc đăng nhập, lấy ảnh khớp nhất (1 ảnh mờ không làm hỏng lần đăng nhập)
  r.post('/auth/face', async (req, res) => {
    const samples = req.body?.embeddings;
    if (!Array.isArray(samples) || samples.length === 0 || samples.length > MAX_SAMPLES || !samples.every(isEmbedding)) {
      throw new HttpError(400, 'Dữ liệu khuôn mặt không hợp lệ');
    }
    const user = await User.findOne({ username: str(req.body?.username).toLowerCase() }).select('+faceEmbedding');
    if (!user?.active || !user.faceEmbedding?.length) {
      throw new HttpError(400, 'Tài khoản này chưa bật đăng nhập bằng khuôn mặt');
    }
    if (user.faceFails >= MAX_FACE_FAILS) {
      throw new HttpError(403, 'Sai khuôn mặt quá nhiều lần, hãy đăng nhập bằng mật khẩu + OTP');
    }
    const distance = Math.min(...samples.map((s) => euclidean(user.faceEmbedding, s)));
    if (distance > FACE_THRESHOLD) {
      user.faceFails += 1;
      await user.save();
      const left = MAX_FACE_FAILS - user.faceFails;
      throw new HttpError(401, left > 0 ? `Khuôn mặt không khớp, còn ${left} lần thử` : 'Khuôn mặt không khớp. Hãy đăng nhập bằng mật khẩu + OTP');
    }
    user.faceFails = 0;
    await user.save();
    res.json({ token: signToken(user, jwtSecret), user });
  });

  return r;
}
