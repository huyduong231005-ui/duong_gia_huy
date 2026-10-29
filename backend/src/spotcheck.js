// Tính năng mới: KIỂM TRA ĐỘT XUẤT GIỮA GIỜ.
// App điểm danh hiện nay chỉ kiểm 1 lần đầu giờ → SV điểm danh xong rồi về. Giữa buổi GV bấm
// "Kiểm tra đột xuất": hệ thống chọn ngẫu nhiên một phần SV đang có mặt, họ có 2 phút để xác minh
// lại bằng khuôn mặt (nếu đã đăng ký) + GPS trong bán kính lớp; không kịp thì thành "rời lớp sớm".
import crypto from 'node:crypto';
import { Router } from 'express';
import { Session, User } from './models.js';
import { HttpError, requireAuth } from './auth.js';
import { findSession, requireTeacher } from './teaching.js';
import { checkLocation } from './checkin.js';
import { isEmbedding, euclidean, FACE_THRESHOLD } from './face.js';

export const SPOT_WINDOW_MS = 2 * 60 * 1000;
const DEFAULT_PERCENT = 50;

const isHere = (status) => status === 'present' || status === 'late';

/** Xáo trộn Fisher–Yates bằng số ngẫu nhiên mật mã (SV không đoán trước được ai bị gọi). */
function shuffle(list) {
  const a = [...list];
  for (let i = a.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const pendingFor = (spotCheck, userId) =>
  spotCheck.targets.find((t) => t.student?.equals(userId) && !t.respondedAt);

export function spotCheckRouter({ jwtSecret }) {
  const r = Router();
  r.use(requireAuth(jwtSecret));

  // GV tạo lượt kiểm tra
  r.post('/sessions/:id/spot-checks', async (req, res) => {
    requireTeacher(req.user);
    const session = await findSession(req.params.id, req.user);
    const now = Date.now();
    if (!session.open) throw new HttpError(400, 'Buổi học đã đóng');
    if (session.spotChecks.some((sc) => sc.expiresAt > now)) {
      throw new HttpError(409, 'Lượt kiểm tra trước chưa hết giờ');
    }
    const here = session.records.filter((rec) => isHere(rec.status));
    if (here.length === 0) throw new HttpError(400, 'Chưa có sinh viên nào có mặt để kiểm tra');

    const percent = Math.min(100, Math.max(1, Number(req.body?.percent) || DEFAULT_PERCENT));
    const picked = shuffle(here).slice(0, Math.max(1, Math.round((here.length * percent) / 100)));
    session.spotChecks.push({
      expiresAt: new Date(now + SPOT_WINDOW_MS),
      targets: picked.map((rec) => ({ student: rec.student, prevStatus: rec.status })),
    });
    for (const rec of picked) rec.status = 'left'; // xác minh kịp sẽ được trả lại
    await session.save();
    res.status(201).json(session.spotChecks.at(-1));
  });

  // App SV hỏi định kỳ: mình có đang bị gọi kiểm tra không?
  // ponytail: hỏi định kỳ khi app đang mở; muốn báo cả khi app tắt thì thêm push FCM
  r.get('/me/spot-check', async (req, res) => {
    const now = new Date();
    const session = await Session.findOne({
      spotChecks: {
        $elemMatch: {
          expiresAt: { $gt: now },
          targets: { $elemMatch: { student: req.user._id, respondedAt: null } },
        },
      },
    }).populate({ path: 'classSection', select: 'code subject', populate: { path: 'subject', select: 'name' } });
    if (!session) return res.json(null);
    const spotCheck = session.spotChecks.find((sc) => sc.expiresAt > now && pendingFor(sc, req.user._id));
    res.json({
      sessionId: session.id,
      expiresAt: spotCheck.expiresAt,
      classCode: session.classSection?.code ?? '',
      subject: session.classSection?.subject?.name ?? '',
      requireFace: Boolean(req.user.faceUpdatedAt),
    });
  });

  // SV xác minh: GPS bắt buộc, khuôn mặt bắt buộc nếu đã đăng ký mặt
  r.post('/spot-checks/respond', async (req, res) => {
    const session = await Session.findById(req.body?.sessionId);
    const spotCheck = session?.spotChecks.findLast((sc) => pendingFor(sc, req.user._id));
    if (!spotCheck) throw new HttpError(404, 'Bạn không có lượt kiểm tra nào cần xác minh');
    if (spotCheck.expiresAt < new Date()) throw new HttpError(400, 'Đã hết giờ xác minh, bạn bị ghi "rời lớp sớm"');

    const { distance } = checkLocation(session, req.body);

    const me = await User.findById(req.user._id).select('+faceEmbedding');
    if (me.faceEmbedding?.length) {
      const samples = req.body?.embeddings;
      if (!Array.isArray(samples) || samples.length === 0 || samples.length > 3 || !samples.every(isEmbedding)) {
        throw new HttpError(400, 'Cần quét khuôn mặt để xác minh');
      }
      if (Math.min(...samples.map((s) => euclidean(me.faceEmbedding, s))) > FACE_THRESHOLD) {
        throw new HttpError(401, 'Khuôn mặt không khớp, hãy quét lại');
      }
    }

    const target = pendingFor(spotCheck, req.user._id);
    Object.assign(target, { respondedAt: new Date(), distance });
    const record = session.records.find((rec) => rec.student?.equals(req.user._id));
    if (record?.status === 'left') record.status = target.prevStatus || 'present';
    await session.save();
    res.json({ ok: true, distance });
  });

  return r;
}
