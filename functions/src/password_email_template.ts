/**
 * Branded Arabic (RTL) password emails for staff ("موظف إداري").
 *
 * Pure module: no Firebase imports, unit-tested. The email never contains a
 * password, only a one-time Firebase action link.
 */

export type PasswordEmailVariant = "new_account" | "forgot_password";

export const BRAND_PRIMARY = "#6750A4";
export const DEFAULT_ACTION_PAGE_URL = "https://tashil-account.web.app/auth/action/";
export const DEFAULT_LOGO_URL = "https://tashil-hr-test.web.app/email/tashil-logo.png";

export interface PasswordEmailInput {
  variant: PasswordEmailVariant;
  displayName: string;
  link: string;
  logoUrl?: string;
}

export interface PasswordEmail {
  subject: string;
  html: string;
  text: string;
}

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function isSafeActionLink(link: string): boolean {
  return /^https:\/\/[^\s"'<>]+$/.test(link) || /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/[^\s"'<>]*$/.test(link);
}

export function buildPasswordEmail(input: PasswordEmailInput): PasswordEmail {
  if (!isSafeActionLink(input.link)) throw new Error("unsafe_link");
  const isNew = input.variant === "new_account";
  const name = escapeHtml((input.displayName || "").trim() || "زميلنا");
  const link = escapeHtml(input.link);
  const logo = escapeHtml(input.logoUrl || DEFAULT_LOGO_URL);
  const P = BRAND_PRIMARY;
  const subject = isNew ? "تسهيل - تعيين كلمة السر لحسابك" : "تسهيل - إعادة تعيين كلمة السر";
  const button = isNew ? "تعيين كلمة السر" : "إعادة تعيين كلمة السر";
  const intro = isNew
    ? "تم إنشاء حساب ليك على <b>تسهيل</b> بصفة <b>موظف إداري</b>. اضغط الزرار تحت عشان تختار كلمة السر بتاعتك."
    : "وصلنا طلب لإعادة تعيين كلمة السر لحسابك على <b>تسهيل</b>. اضغط الزرار تحت عشان تختار كلمة سر جديدة.";
  const introText = intro.replace(/<\/?b>/g, "");

  const html = `<!doctype html><html dir="rtl" lang="ar"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${subject}</title></head>
<body style="margin:0;padding:0;background:#F3EDF7;font-family:Cairo,Tahoma,Arial,sans-serif;" dir="rtl">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F3EDF7;"><tr><td align="center" style="padding:20px 12px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;background:#ffffff;border-radius:24px;overflow:hidden;">
<tr><td align="center" style="background:${P};padding:28px 16px;"><img src="${logo}" width="64" height="64" alt="تسهيل" style="display:block;border-radius:16px;border:2px solid #ffffff;"><div style="color:#ffffff;font-size:22px;font-weight:700;margin-top:10px;">تسهيل</div></td></tr>
<tr><td dir="rtl" style="padding:28px 24px 8px;text-align:right;color:#1D1B20;">
<div style="font-size:22px;font-weight:700;">أهلاً ${name}</div>
<p style="font-size:16px;line-height:1.8;color:#49454F;margin:12px 0 0;">${intro}</p></td></tr>
<tr><td align="center" style="padding:20px 24px;"><a href="${link}" target="_blank" style="display:block;background:${P};color:#ffffff;text-decoration:none;font-size:18px;font-weight:700;padding:16px;border-radius:100px;">${button}</a>
<p style="font-size:13px;color:#79747E;margin:12px 0 0;">اللينك صالح لفترة محدودة ولمرة واحدة بس. لو انتهى، اطلب لينك جديد من "نسيت كلمة المرور" في التطبيق.</p></td></tr>
<tr><td style="padding:8px 24px 24px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F7F2FA;border-radius:16px;"><tr><td dir="rtl" style="padding:16px 18px;text-align:right;color:#1D1B20;font-size:15px;line-height:2;">
<div style="font-weight:700;color:${P};font-size:16px;">إزاي تدخل بعد كده؟</div>
1. افتح تطبيق تسهيل<br>2. اختار تبويب <b>"موظف إداري"</b><br>3. اكتب رقم الموبايل + كلمة السر</td></tr></table></td></tr>
<tr><td style="padding:16px 24px 24px;border-top:1px solid #E7E0EC;text-align:center;font-size:12px;color:#79747E;line-height:1.8;">لو مطلبتش ده، تجاهل الإيميل ومحدش هيقدر يغيّر كلمة السر بتاعتك.<br>هذه رسالة تلقائية من تسهيل، من فضلك متردش عليها.</td></tr>
</table></td></tr></table></body></html>`;

  const text = [
    `أهلاً ${(input.displayName || "").trim() || "زميلنا"}`,
    introText,
    `${button}: ${input.link}`,
    "اللينك صالح لفترة محدودة ولمرة واحدة بس.",
    "للدخول: افتح تطبيق تسهيل ← تبويب \"موظف إداري\" ← رقم الموبايل + كلمة السر.",
    "لو مطلبتش ده، تجاهل الإيميل.",
  ].join("\n\n");

  return {subject, html, text};
}

/** Roles allowed to create staff accounts / send setup emails. */
const INVITER_ROLES = new Set(["super_admin", "superadmin", "technical_support", "technicalsupport", "tech_support"]);

export function canSendStaffInvite(role: unknown): boolean {
  return typeof role === "string" && INVITER_ROLES.has(role.trim().toLowerCase().replace(/-/g, "_"));
}

/**
 * Moves a Firebase action link onto our own handler page, keeping every query
 * param (mode, oobCode, apiKey, lang, continueUrl...). Only our staff emails
 * use this; the project-wide action URL (Angular) is not changed.
 */
export function rewriteActionLink(link: string, pageUrl: string = DEFAULT_ACTION_PAGE_URL): string {
  const src = new URL(link);
  const dst = new URL(pageUrl);
  if (dst.protocol !== "https:" && !/^(127\.0\.0\.1|localhost)$/.test(dst.hostname)) throw new Error("unsafe_page_url");
  src.searchParams.forEach((v, k) => dst.searchParams.set(k, v));
  return dst.toString();
}
