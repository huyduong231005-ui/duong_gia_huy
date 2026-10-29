// Thời khoá biểu: tính theo giờ Việt Nam vì server Render chạy giờ UTC.
const VN_OFFSET_MS = 7 * 60 * 60 * 1000; // UTC+7, Việt Nam không có giờ mùa hè
export const EARLY_OPEN_MIN = 15; // cho GV mở buổi sớm 15 phút trước giờ học

/** Ngày (YYYY-MM-DD), thứ (1 = Thứ 2 … 7 = CN) và phút trong ngày theo giờ Việt Nam. */
export function vnNow(now = Date.now()) {
  const d = new Date(now + VN_OFFSET_MS);
  return {
    date: d.toISOString().slice(0, 10),
    weekday: d.getUTCDay() || 7,
    minutes: d.getUTCHours() * 60 + d.getUTCMinutes(),
  };
}

export const toMinutes = (hhmm) => {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
};

const inTerm = (cls, date) => (!cls.startDate || date >= cls.startDate) && (!cls.endDate || date <= cls.endDate);

/** Các buổi của lớp trong ngày [now] (theo thứ + trong học kỳ). */
export function meetingsOn(cls, now = Date.now()) {
  const { date, weekday } = vnNow(now);
  return inTerm(cls, date) ? (cls.meetings ?? []).filter((m) => m.weekday === weekday) : [];
}

/** Buổi theo TKB đang diễn ra lúc [now] (tính cả 15 phút mở sớm), hoặc undefined. */
export function currentMeeting(cls, now = Date.now()) {
  const { minutes } = vnNow(now);
  return meetingsOn(cls, now).find(
    (m) => minutes >= toMinutes(m.start) - EARLY_OPEN_MIN && minutes <= toMinutes(m.end),
  );
}

/** Lớp có TKB mà buổi mở không rơi vào giờ học hôm nay → buổi bù. Lớp chưa có TKB thì không xét. */
export const isMakeup = (cls, date, now = Date.now()) =>
  (cls.meetings?.length ?? 0) > 0 && !(date === vnNow(now).date && currentMeeting(cls, now));
