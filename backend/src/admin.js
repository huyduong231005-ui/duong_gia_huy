// API chỉ dành cho admin: tài khoản, môn học, lớp học phần, ghi danh. Gắn ở /admin.
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { User, Subject, ClassSection, Session, LeaveRequest, ROLES } from './models.js';
import { HttpError, str, EMAIL_RE, USERNAME_RE, MIN_PASSWORD } from './auth.js';

const LIST_LIMIT = 200; // ponytail: chưa phân trang, đủ cho quy mô 1 khoa; thêm skip/limit khi vượt

export const like = (q) => new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');

/** Chỉ lấy các trường được phép sửa có mặt trong body. */
export const pick = (body, keys) =>
  Object.fromEntries(keys.filter((k) => body?.[k] !== undefined).map((k) => [k, body[k]]));

const updateOpts = { new: true, runValidators: true };

async function mustExist(model, id, filter, message) {
  if (!(await model.exists({ _id: id, ...filter }))) throw new HttpError(400, message);
}

export function adminRouter() {
  const r = Router();

  // ---- Tài khoản ----
  r.get('/users', async (req, res) => {
    const filter = {};
    if (ROLES.includes(req.query.role)) filter.role = req.query.role;
    const q = str(req.query.q);
    if (q) filter.$or = ['username', 'email', 'fullName'].map((f) => ({ [f]: like(q) }));
    res.json(await User.find(filter).sort({ role: 1, username: 1 }).limit(LIST_LIMIT));
  });

  r.post('/users', async (req, res) => {
    const email = str(req.body?.email).toLowerCase();
    const username = str(req.body?.username).toLowerCase();
    const password = typeof req.body?.password === 'string' ? req.body.password : '';
    const role = req.body?.role ?? 'student';
    if (!EMAIL_RE.test(email)) throw new HttpError(400, 'Email không hợp lệ');
    if (!USERNAME_RE.test(username)) throw new HttpError(400, 'Tên đăng nhập 3–30 ký tự: chữ thường, số, dấu _ hoặc .');
    if (password.length < MIN_PASSWORD) throw new HttpError(400, `Mật khẩu tối thiểu ${MIN_PASSWORD} ký tự`);
    if (!ROLES.includes(role)) throw new HttpError(400, 'Vai trò không hợp lệ');
    const user = await User.create({
      email, username, role, fullName: str(req.body?.fullName),
      passwordHash: await bcrypt.hash(password, 10),
      active: true, // admin tạo thì không cần xác minh email
    });
    res.status(201).json(user);
  });

  r.patch('/users/:id', async (req, res) => {
    const isSelf = req.params.id === req.user.id;
    const changes = pick(req.body, isSelf ? ['fullName'] : ['fullName', 'role', 'active']);
    if (typeof req.body?.password === 'string' && req.body.password) {
      if (req.body.password.length < MIN_PASSWORD) throw new HttpError(400, `Mật khẩu tối thiểu ${MIN_PASSWORD} ký tự`);
      changes.passwordHash = await bcrypt.hash(req.body.password, 10);
    }
    const user = await User.findByIdAndUpdate(req.params.id, changes, updateOpts);
    if (!user) throw new HttpError(404, 'Không tìm thấy tài khoản');
    res.json(user);
  });

  r.delete('/users/:id', async (req, res) => {
    const id = req.params.id;
    if (id === req.user.id) throw new HttpError(400, 'Không thể tự xoá tài khoản đang đăng nhập');
    if (await ClassSection.exists({ lecturer: id })) {
      throw new HttpError(409, 'Giảng viên đang phụ trách lớp, hãy đổi giảng viên trước khi xoá');
    }
    const user = await User.findByIdAndDelete(id);
    if (!user) throw new HttpError(404, 'Không tìm thấy tài khoản');
    await Promise.all([
      ClassSection.updateMany({}, { $pull: { students: id } }),
      Session.updateMany({}, { $pull: { records: { student: id } } }),
      LeaveRequest.deleteMany({ student: id }),
    ]);
    res.status(204).end();
  });

  // ---- Môn học ----
  r.get('/subjects', async (req, res) => {
    const q = str(req.query.q);
    const filter = q ? { $or: [{ code: like(q) }, { name: like(q) }] } : {};
    res.json(await Subject.find(filter).sort({ code: 1 }).limit(LIST_LIMIT));
  });

  r.post('/subjects', async (req, res) => {
    res.status(201).json(await Subject.create(pick(req.body, ['code', 'name', 'credits'])));
  });

  r.patch('/subjects/:id', async (req, res) => {
    const subject = await Subject.findByIdAndUpdate(req.params.id, pick(req.body, ['code', 'name', 'credits']), updateOpts);
    if (!subject) throw new HttpError(404, 'Không tìm thấy môn học');
    res.json(subject);
  });

  r.delete('/subjects/:id', async (req, res) => {
    if (await ClassSection.exists({ subject: req.params.id })) {
      throw new HttpError(409, 'Môn học đang có lớp học phần, hãy xoá lớp trước');
    }
    if (!(await Subject.findByIdAndDelete(req.params.id))) throw new HttpError(404, 'Không tìm thấy môn học');
    res.status(204).end();
  });

  // ---- Lớp học phần (xem danh sách lớp ở GET /classes, dùng chung mọi vai trò) ----
  const CLASS_FIELDS = ['code', 'subject', 'lecturer', 'room', 'schedule', 'semester', 'plannedSessions'];

  async function checkClassRefs(body) {
    if (body.subject !== undefined) await mustExist(Subject, body.subject, {}, 'Môn học không tồn tại');
    if (body.lecturer !== undefined) {
      await mustExist(User, body.lecturer, { role: 'lecturer' }, 'Giảng viên không tồn tại');
    }
  }

  r.post('/classes', async (req, res) => {
    const data = pick(req.body, CLASS_FIELDS);
    await checkClassRefs(data);
    res.status(201).json(await ClassSection.create(data));
  });

  r.patch('/classes/:id', async (req, res) => {
    const changes = pick(req.body, CLASS_FIELDS);
    await checkClassRefs(changes);
    const cls = await ClassSection.findByIdAndUpdate(req.params.id, changes, updateOpts);
    if (!cls) throw new HttpError(404, 'Không tìm thấy lớp học phần');
    res.json(cls);
  });

  r.delete('/classes/:id', async (req, res) => {
    if (!(await ClassSection.findByIdAndDelete(req.params.id))) throw new HttpError(404, 'Không tìm thấy lớp học phần');
    await Promise.all([
      Session.deleteMany({ classSection: req.params.id }),
      LeaveRequest.deleteMany({ classSection: req.params.id }),
    ]);
    res.status(204).end();
  });

  // ---- Ghi danh sinh viên ----
  r.post('/classes/:id/students', async (req, res) => {
    await mustExist(User, req.body?.studentId, { role: 'student' }, 'Sinh viên không tồn tại');
    const cls = await ClassSection.findByIdAndUpdate(
      req.params.id, { $addToSet: { students: req.body.studentId } }, { new: true },
    );
    if (!cls) throw new HttpError(404, 'Không tìm thấy lớp học phần');
    // ponytail: SV ghi danh muộn chỉ có tên trong các buổi tạo sau đó
    res.status(201).json(cls);
  });

  r.delete('/classes/:id/students/:studentId', async (req, res) => {
    const cls = await ClassSection.findByIdAndUpdate(
      req.params.id, { $pull: { students: req.params.studentId } }, { new: true },
    );
    if (!cls) throw new HttpError(404, 'Không tìm thấy lớp học phần');
    res.json(cls);
  });

  return r;
}
