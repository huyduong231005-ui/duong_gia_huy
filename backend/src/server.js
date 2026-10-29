import mongoose from 'mongoose';
import { OAuth2Client } from 'google-auth-library';
import { createApp } from './app.js';
import { brevoMailer } from './mail.js';

const { MONGODB_URI, JWT_SECRET, GOOGLE_CLIENT_ID, BREVO_API_KEY, MAIL_FROM, PORT = 3000 } = process.env;
const missing = Object.entries({ MONGODB_URI, JWT_SECRET, GOOGLE_CLIENT_ID, BREVO_API_KEY, MAIL_FROM })
  .filter(([, v]) => !v)
  .map(([k]) => k);
if (missing.length) throw new Error(`Thiếu biến môi trường: ${missing.join(', ')}`);

const google = new OAuth2Client();

await mongoose.connect(MONGODB_URI);
createApp({
  jwtSecret: JWT_SECRET,
  sendMail: brevoMailer({ apiKey: BREVO_API_KEY, from: MAIL_FROM }),
  verifyGoogle: async (idToken) =>
    (await google.verifyIdToken({ idToken, audience: GOOGLE_CLIENT_ID })).getPayload(),
}).listen(PORT, () => console.log(`API chạy ở cổng ${PORT}`));
