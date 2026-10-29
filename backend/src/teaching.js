// API dùng chung các vai trò, tự giới hạn dữ liệu theo người gọi:
// admin thấy hết, giảng viên thấy lớp mình dạy, sinh viên thấy lớp mình học.
import { Router } from 'express';
import { ClassSection, Session, LeaveRequest, ATTENDANCE } from './models.js';
import { HttpError, str } from './auth.js';
import { pick } from './admin.js';

const ABSENCE_LIMIT = 0.2; // vắng quá 20% số buổi thì bị cấm thi
const USER_FIELDS = 'username fullName email';

const scopeOf = (user) =>
  user.role === 'admin' ? {} : user.role === 'lecturer' ? { lecturer: user._id } : { students: user._id };

const isTeacher = (user) => user.role === 'lecturer' || user.role === 'admin';

function requireTeacher(user) {
  if (!isTeacher(user)) throw new HttpError(403, 'Chỉ giảng viên mới làm được việc này');
}

async function findClass(id, user) {
  // Không có id thì Mongoose bỏ điều kiện _id → trả về lớp bất kỳ trong phạm vi
  if (!id) throw new HttpError(400, 'Thiếu lớp học phần');
  const cls = await ClassSection.findOne({ _id: id, ...scopeOf(user) });
  if (!cls) throw new HttpError(404, 'Không tìm thấy lớp học phần');
  return cls;
}

/** Tìm buổi học và kiểm tra người gọi có quyền với lớp của buổi đó. */
async function findSession(id, user) {
  const session = await Session.findById(id);
  if (!session) throw new HttpError(404, 'Không tìm thấy buổi học');
  await findClass(session.classSection, user);
  return session;
}

const statusOf = (session, studentId) =>
  session.records.find((r) => r.student?.equals(studentId))?.status ?? null;

export function teachingRouter() {
  const r = Router();

  // ---- Lớp học phần ----
  r.get('/classes', async (req, res) => {
    const classes = await ClassSection.find(scopeOf(req.user))
      .populate('subject')
      .populate('lecturer', USER_FIELDS)
      .sort({ code: 1 });
    res.json(classes);
  });

  r.get('/classes/:id', async (req, res) => {
    const cls = await findClass(req.params.id, req.user);
    await cls.populate([
      { path: 'subject' },
      { path: 'lecturer', select: USER_FIELDS },
      { path: 'students', select: USER_FIELDS, options: { sort: { username: 1 } } },
    ]);
    res.json(cls);
  });

  // ---- Buổi học / phiên điểm danh ----
  r.get('/classes/:id/sessions', async (req, res) => {
    await findClass(req.params.id, req.user);
    const sessions = await Session.find({ classSection: req.params.id }).sort({ date: -1, createdAt: -1 });
    if (isTeacher(req.user)) return res.json(sessions);
    // Sinh viên chỉ thấy trạng thái của chính mình
    res.json(sessions.map((s) => ({
      id: s.id, date: s.date, topic: s.topic, open: s.open, myStatus: statusOf(s, req.user._id),
    })));
  });

  r.post('/classes/:id/sessions', async (req, res) => {
    requireTeacher(req.user);
    const cls = await findClass(req.params.id, req.user);
    const date = str(req.body?.date);
    // SV đã có đơn nghỉ được duyệt cho ngày này thì vào sẵn "có phép"
    const excused = await LeaveRequest.find({ classSection: cls._id, date, status: 'approved' }).distinct('student');
    const session = await Session.create({
      classSection: cls._id,
      date,
      topic: str(req.body?.topic),
      records: cls.students.map((student) => ({
        student,
        status: excused.some((id) => id.equals(student)) ? 'excused' : 'absent',
      })),
    });
    res.status(201).json(session);
  });

  r.get('/sessions/:id', async (req, res) => {
    const session = await findSession(req.params.id, req.user);
    await session.populate('records.student', USER_FIELDS);
    if (!isTeacher(req.user)) {
      session.records = session.records.filter((rec) => rec.student?._id.equals(req.user._id));
    }
    res.json(session);
  });

  r.patch('/sessions/:id', async (req, res) => {
    requireTeacher(req.user);
    const session = await findSession(req.params.id, req.user);
    session.set(pick(req.body, ['date', 'topic', 'open']));
    res.json(await session.save());
  });

  r.delete('/sessions/:id', async (req, res) => {
    requireTeacher(req.user);
    const session = await findSession(req.params.id, req.user);
    await session.deleteOne();
    res.status(204).end();
  });

  r.patch('/sessions/:id/records/:studentId', async (req, res) => {
    requireTeacher(req.user);
    const status = req.body?.status;
    if (!ATTENDANCE.includes(status)) throw new HttpError(400, 'Trạng thái điểm danh không hợp lệ');
    const session = await findSession(req.params.id, req.user);
    const record = session.records.find((rec) => rec.student?.equals(req.params.studentId));
    if (!record) throw new HttpError(404, 'Sinh viên không có trong buổi học này');
    record.status = status;
    record.checkedAt = status === 'present' || status === 'late' ? new Date() : undefined;
    res.json(await session.save());
  });

  // ---- Lịch sử chuyên cần của sinh viên + số buổi còn được vắng ----
  r.get('/me/attendance', async (req, res) => {
    const classes = await ClassSection.find({ students: req.user._id }).populate('subject').sort({ code: 1 });
    const sessions = await Session.find({ classSection: { $in: classes.map((c) => c._id) } }).sort({ date: -1 });
    res.json(classes.map((cls) => {
      const mine = sessions
        .filter((s) => s.classSection.equals(cls._id))
        .map((s) => ({ id: s.id, date: s.date, topic: s.topic, status: statusOf(s, req.user._id) }));
      const count = (st) => mine.filter((s) => s.status === st).length;
      const allowedAbsences = Math.floor(cls.plannedSessions * ABSENCE_LIMIT);
      return {
        classSection: { id: cls.id, code: cls.code, subject: cls.subject?.name ?? '', plannedSessions: cls.plannedSessions },
        sessions: mine,
        summary: {
          total: mine.length,
          present: count('present'),
          late: count('late'),
          absent: count('absent'),
          excused: count('excused'),
          allowedAbsences,
          remainingAbsences: allowedAbsences - count('absent'),
        },
      };
    }));
  });

  // ---- Đơn xin nghỉ phép ----
  r.get('/leaves', async (req, res) => {
    const { user } = req;
    const filter = user.role === 'student' ? { student: user._id }
      : user.role === 'lecturer' ? { classSection: { $in: await ClassSection.find({ lecturer: user._id }).distinct('_id') } }
      : {};
    const leaves = await LeaveRequest.find(filter)
      .populate({ path: 'classSection', select: 'code subject', populate: { path: 'subject', select: 'name' } })
      .populate('student', USER_FIELDS)
      .sort({ createdAt: -1 });
    res.json(leaves);
  });

  r.post('/leaves', async (req, res) => {
    if (req.user.role !== 'student') throw new HttpError(403, 'Chỉ sinh viên mới gửi đơn xin nghỉ');
    const cls = await findClass(req.body?.classId, req.user); // chỉ gửi cho lớp mình đang học
    const leave = await LeaveRequest.create({
      classSection: cls._id, student: req.user._id, date: str(req.body?.date), reason: str(req.body?.reason),
    });
    res.status(201).json(leave);
  });

  r.patch('/leaves/:id', async (req, res) => {
    const leave = await LeaveRequest.findById(req.params.id);
    if (!leave) throw new HttpError(404, 'Không tìm thấy đơn');

    if (req.user.role === 'student') {
      if (!leave.student.equals(req.user._id)) throw new HttpError(404, 'Không tìm thấy đơn');
      if (leave.status !== 'pending') throw new HttpError(400, 'Đơn đã được xử lý, không sửa được nữa');
      leave.set(pick(req.body, ['date', 'reason']));
      return res.json(await leave.save());
    }

    await findClass(leave.classSection, req.user);
    const status = req.body?.status;
    if (status !== 'approved' && status !== 'rejected') throw new HttpError(400, 'Chỉ được duyệt hoặc từ chối');
    leave.set({ status, reviewedBy: req.user._id });
    await leave.save();
    if (status === 'approved') {
      // Buổi học đã mở cho ngày đó: đổi "vắng" thành "có phép"
      await Session.updateMany(
        { classSection: leave.classSection, date: leave.date },
        { $set: { 'records.$[rec].status': 'excused' } },
        { arrayFilters: [{ 'rec.student': leave.student, 'rec.status': 'absent' }] },
      );
    }
    res.json(leave);
  });

  r.delete('/leaves/:id', async (req, res) => {
    const leave = await LeaveRequest.findById(req.params.id);
    const own = leave?.student.equals(req.user._id);
    if (!leave || (!own && req.user.role !== 'admin')) throw new HttpError(404, 'Không tìm thấy đơn');
    if (own && leave.status !== 'pending') throw new HttpError(400, 'Đơn đã được xử lý, không rút được nữa');
    await leave.deleteOne();
    res.status(204).end();
  });

  return r;
}
