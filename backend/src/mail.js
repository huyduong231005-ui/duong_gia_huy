// Gửi email qua Brevo HTTP API (Render free chặn cổng SMTP nên không dùng Gmail SMTP được).
const BREVO_URL = 'https://api.brevo.com/v3/smtp/email';

const SUBJECTS = {
  register: 'Mã xác minh đăng ký tài khoản',
  login: 'Mã OTP đăng nhập',
};

export function brevoMailer({ apiKey, from }) {
  return async (to, code, purpose) => {
    const res = await fetch(BREVO_URL, {
      method: 'POST',
      headers: { 'api-key': apiKey, 'content-type': 'application/json' },
      body: JSON.stringify({
        sender: { email: from, name: 'Điểm danh SV' },
        to: [{ email: to }],
        subject: SUBJECTS[purpose],
        htmlContent: `<p>Mã OTP của bạn là:</p><h2 style="letter-spacing:4px">${code}</h2><p>Mã có hiệu lực trong 5 phút. Không chia sẻ mã này cho ai.</p>`,
      }),
    });
    if (!res.ok) throw new Error(`Brevo ${res.status}: ${await res.text()}`);
  };
}
