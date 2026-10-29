import mongoose from 'mongoose';

export const ROLES = ['admin', 'lecturer', 'student'];

const userSchema = new mongoose.Schema(
  {
    username: { type: String, required: true, unique: true, lowercase: true, trim: true },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    fullName: { type: String, default: '', trim: true },
    passwordHash: String, // không có với tài khoản tạo bằng Google
    googleId: { type: String, unique: true, sparse: true },
    role: { type: String, enum: ROLES, default: 'student' },
    active: { type: Boolean, default: false }, // true sau khi xác minh email
    // Vector khuôn mặt FaceNet-512 (không phải ảnh); không bao giờ trả về cho client
    faceEmbedding: { type: [Number], select: false, default: undefined },
    faceUpdatedAt: Date,
    faceFails: { type: Number, default: 0 }, // sai liên tiếp; quá giới hạn thì phải dùng mật khẩu
  },
  {
    timestamps: true,
    toJSON: {
      transform: (_doc, { _id, username, email, fullName, role, active, faceUpdatedAt }) =>
        ({ id: _id, username, email, fullName, role, active, hasFace: Boolean(faceUpdatedAt) }),
    },
  },
);

const otpSchema = new mongoose.Schema({
  userId: { type: mongoose.Types.ObjectId, required: true },
  purpose: { type: String, enum: ['register', 'login'], required: true },
  codeHash: { type: String, required: true },
  attempts: { type: Number, default: 0 },
  expiresAt: { type: Date, required: true, index: { expires: 0 } }, // MongoDB tự xoá khi hết hạn
});
otpSchema.index({ userId: 1, purpose: 1 }, { unique: true });

export const User = mongoose.model('User', userSchema);
export const Otp = mongoose.model('Otp', otpSchema);

// ---- Dữ liệu điểm danh ----

// left = rời lớp sớm: không xác minh được khi bị kiểm tra đột xuất giữa giờ
export const ATTENDANCE = ['present', 'late', 'absent', 'excused', 'left'];
export const LEAVE_STATUS = ['pending', 'approved', 'rejected'];
export const DATE_RE = /^\d{4}-\d{2}-\d{2}$/; // ngày dạng YYYY-MM-DD, so khớp theo ngày cho đơn giản
export const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/; // giờ dạng HH:mm

const ref = (model) => ({ type: mongoose.Types.ObjectId, ref: model });
const options = {
  timestamps: true,
  toJSON: { virtuals: true, versionKey: false, transform: (_doc, ret) => { delete ret._id; return ret; } },
};

const subjectSchema = new mongoose.Schema(
  {
    code: { type: String, required: true, unique: true, uppercase: true, trim: true },
    name: { type: String, required: true, trim: true },
    credits: { type: Number, min: 1, max: 10, default: 3 },
  },
  options,
);

const classSchema = new mongoose.Schema(
  {
    code: { type: String, required: true, unique: true, uppercase: true, trim: true },
    subject: { ...ref('Subject'), required: true },
    lecturer: { ...ref('User'), required: true },
    room: { type: String, default: '', trim: true },
    schedule: { type: String, default: '', trim: true }, // VD: "Thứ 2, tiết 1-3"
    semester: { type: String, default: '', trim: true },
    plannedSessions: { type: Number, min: 1, max: 100, default: 15 }, // để tính số buổi được vắng (20%)
    students: [ref('User')],
    // Thời khoá biểu: các buổi học trong tuần, áp dụng từ startDate đến endDate (giờ Việt Nam)
    meetings: [
      new mongoose.Schema(
        {
          weekday: { type: Number, min: 1, max: 7, required: true }, // 1 = Thứ 2 … 7 = Chủ nhật
          start: { type: String, match: TIME_RE, required: true },
          end: { type: String, match: TIME_RE, required: true },
          room: { type: String, default: '', trim: true },
        },
        { _id: false },
      ),
    ],
    startDate: { type: String, match: DATE_RE },
    endDate: { type: String, match: DATE_RE },
  },
  options,
);

const recordSchema = new mongoose.Schema(
  {
    student: ref('User'),
    status: { type: String, enum: ATTENDANCE, default: 'absent' },
    checkedAt: Date,
    // Vị trí SV gửi khi quét QR (chia sẻ vị trí cho GV xem trên bản đồ)
    lat: Number,
    lng: Number,
    distance: Number, // mét tới vị trí GV
  },
  { _id: false },
);

// Kiểm tra đột xuất giữa giờ: SV bị chọn chuyển sang "rời lớp sớm" ngay khi tạo,
// xác minh kịp (mặt + GPS) thì trả lại trạng thái cũ → không cần tác vụ nền xử lý hết giờ.
const spotCheckSchema = new mongoose.Schema(
  {
    startedAt: { type: Date, default: Date.now },
    expiresAt: { type: Date, required: true },
    targets: [
      new mongoose.Schema(
        { student: ref('User'), prevStatus: String, respondedAt: Date, distance: Number },
        { _id: false },
      ),
    ],
  },
  { toJSON: options.toJSON },
);

const sessionSchema = new mongoose.Schema(
  {
    classSection: { ...ref('ClassSection'), required: true, index: true },
    date: { type: String, required: true, match: DATE_RE },
    topic: { type: String, default: '', trim: true },
    open: { type: Boolean, default: true },
    makeup: { type: Boolean, default: false }, // buổi bù: mở ngoài giờ trong thời khoá biểu
    // Vị trí GV lúc chiếu QR; SV phải ở trong bán kính radius mét mới điểm danh được
    lat: { type: Number, min: -90, max: 90 },
    lng: { type: Number, min: -180, max: 180 },
    radius: { type: Number, min: 10, max: 1000, default: 100 },
    records: [recordSchema],
    spotChecks: [spotCheckSchema],
  },
  options,
);

const leaveSchema = new mongoose.Schema(
  {
    classSection: { ...ref('ClassSection'), required: true, index: true },
    student: { ...ref('User'), required: true, index: true },
    date: { type: String, required: true, match: DATE_RE },
    reason: { type: String, required: true, trim: true, maxlength: 500 },
    status: { type: String, enum: LEAVE_STATUS, default: 'pending' },
    reviewedBy: ref('User'),
  },
  options,
);

export const Subject = mongoose.model('Subject', subjectSchema);
export const ClassSection = mongoose.model('ClassSection', classSchema);
export const Session = mongoose.model('Session', sessionSchema);
export const LeaveRequest = mongoose.model('LeaveRequest', leaveSchema);
