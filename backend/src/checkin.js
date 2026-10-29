// Điểm danh bằng QR động + GPS.
// QR đổi mỗi 10 giây, ký HMAC bằng khoá của server → chụp mã gửi bạn ở nhà sẽ hết hạn ngay;
// SV phải đứng trong bán kính cho phép quanh vị trí GV lúc chiếu QR.
import crypto from 'node:crypto';
import { HttpError } from './auth.js';

export const QR_WINDOW_MS = 10_000;
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

/** Kiểm chữ ký + hạn dùng, trả về sessionId. Nhận cửa sổ hiện tại và cửa sổ liền trước (bù độ trễ khi quét). */
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
  if (window < current - 1 || window > current) {
    throw new HttpError(400, 'Mã QR đã hết hạn, hãy quét mã mới trên màn hình');
  }
  return sessionId;
}

/** Khoảng cách 2 toạ độ (mét), công thức haversine. */
export function distanceM(lat1, lng1, lat2, lng2) {
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}
