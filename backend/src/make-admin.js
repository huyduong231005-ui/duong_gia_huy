// Cấp quyền admin cho 1 tài khoản đã có: npm run make-admin -- <username>
import mongoose from 'mongoose';
import { User } from './models.js';

const username = process.argv[2]?.toLowerCase();
if (!username) throw new Error('Cách dùng: npm run make-admin -- <username>');

await mongoose.connect(process.env.MONGODB_URI);
const user = await User.findOneAndUpdate({ username }, { role: 'admin', active: true }, { new: true });
console.log(user ? `Đã cấp quyền admin cho ${user.username}` : `Không có tài khoản ${username}`);
await mongoose.disconnect();
