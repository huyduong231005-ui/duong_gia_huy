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
  },
  {
    timestamps: true,
    toJSON: {
      transform: (_doc, { _id, username, email, fullName, role, active }) =>
        ({ id: _id, username, email, fullName, role, active }),
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
