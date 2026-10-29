// Điểm danh bằng QR động + GPS.
// QR đổi mỗi 60 giây, ký HMAC bằng khoá của server → chụp mã gửi bạn ở nhà sẽ hết hạn sau ~1 phút;
// SV phải đứng trong bán kính cho phép quanh vị trí GV lúc chiếu QR.
import crypto from 'node:crypto';
import { HttpError } from './auth.js';

export const QR_WINDOW_MS = 60_000;
// Quét đúng lúc mã vừa đổi: mã cũ vẫn nhận thêm chừng này (bù độ trễ camera + mạng)
export const QR_GRACE_MS = 10_000;
const EARTH_RADIUS_M = 6_371_000;

export const qrWindow = (now = Date.now()) => Math.floor(now / QR_WINDOW_MS);

/** Mã QR = "<sessionId>.<cửa sổ thời gian>.<chữ ký>". */
export function qrToken(sessionId, window, secret) {
  const sig = crypto
    .createHmac('sha256', secret)
    .update(`qr:${sessionId}.${window}`)
    .digest('base64url')
    .slice(0, 22);
  return `${sessionId}.${window}.${sig}`;
}

/** Kiểm chữ ký + hạn dùng, trả về sessionId. Nhận mã đang chiếu, và mã ngay trước nó trong QR_GRACE_MS đầu tiên sau khi đổi. */
export function verifyQr(token, secret, now = Date.now()) {
  const raw = typeof token === 'string' ? token : '';
  const [sessionId, w] = raw.split('.');
  const window = Number(w);
  const expected = sessionId && Number.isInteger(window) ? qrToken(sessionId, window, secret) : '';
  const a = Buffer.from(expected);
  const b = Buffer.from(raw);
  if (a.length === 0 || a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    throw new HttpError(400, 'Mã QR không hợp lệ');
  }
  const current = qrWindow(now);
  const justChanged = now - current * QR_WINDOW_MS < QR_GRACE_MS;
  if (window !== current && !(window === current - 1 && justChanged)) {
    throw new HttpError(400, 'Mã QR đã hết hạn, hãy quét mã mới trên màn hình');
  }
  return sessionId;
}

/**
 * Kiểm vị trí SV gửi lên so với vị trí GV của buổi học (dùng chung cho quét QR và kiểm tra đột xuất).
 * Trả về { lat, lng, distance } (distance null nếu GV chưa ghim vị trí), sai thì ném HttpError.
 */
export function checkLocation(session, body) {
  if (body?.mocked === true) throw new HttpError(400, 'Phát hiện vị trí giả lập, hãy tắt ứng dụng fake GPS');
  const lat = Number(body?.lat);
  const lng = Number(body?.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) throw new HttpError(400, 'Thiếu vị trí GPS');
  if (session.lat == null || session.lng == null) return { lat, lng, distance: null };
  const distance = Math.round(distanceM(session.lat, session.lng, lat, lng));
  if (distance > session.radius) {
    throw new HttpError(400, `Bạn đang cách lớp khoảng ${distance} m (cho phép ${session.radius} m)`);
  }
  return { lat, lng, distance };
}

/** Khoảng cách 2 toạ độ (mét), công thức haversine. */
export function distanceM(lat1, lng1, lat2, lng2) {
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}
