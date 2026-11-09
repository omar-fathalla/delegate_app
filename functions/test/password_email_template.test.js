const test = require("node:test");
const assert = require("node:assert/strict");
const t = require("../lib/password_email_template");
const LINK = "https://practice-firebase-72df1.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=abc&apiKey=k";

test("new account email: RTL, link, button, no password", () => {
  const m = t.buildPasswordEmail({variant: "new_account", displayName: "هاجر", link: LINK});
  assert.match(m.html, /dir="rtl"/);
  assert.match(m.html, /تعيين كلمة السر/);
  assert.match(m.html, /موظف إداري/);
  assert.ok(m.html.includes(LINK.replace(/&/g, "&amp;")));
  assert.ok(!/كلمة السر المؤقتة|password:/i.test(m.html + m.text));
  assert.ok(!/base64/.test(m.html));
  assert.ok(!/sw-point/.test(m.html));
  assert.match(m.html, /tashil-logo\.png/);
});

test("forgot variant uses reset wording", () => {
  const m = t.buildPasswordEmail({variant: "forgot_password", displayName: "x", link: LINK});
  assert.match(m.subject, /إعادة تعيين/);
  assert.match(m.html, /إعادة تعيين كلمة السر/);
});

test("escapes names and rejects unsafe links", () => {
  const m = t.buildPasswordEmail({variant: "new_account", displayName: "<script>", link: LINK});
  assert.ok(!m.html.includes("<script>"));
  assert.throws(() => t.buildPasswordEmail({variant: "new_account", displayName: "a", link: "javascript:alert(1)"}));
});

test("only super admin / tech support can invite", () => {
  assert.equal(t.canSendStaffInvite("super-admin"), true);
  assert.equal(t.canSendStaffInvite("technical_support"), true);
  assert.equal(t.canSendStaffInvite("hr"), false);
  assert.equal(t.canSendStaffInvite("branches_marketing"), false);
});

test("rewriteActionLink moves link to our page and keeps all params", () => {
  const raw = "https://tashil.sw-point.com/auth/action?mode=resetPassword&oobCode=abc&apiKey=k&lang=ar&continueUrl=https%3A%2F%2Fx.web.app%2F";
  const out = new URL(t.rewriteActionLink(raw));
  assert.equal(out.origin + out.pathname, "https://tashil-account.web.app/auth/action/");
  for (const [k, v] of new URL(raw).searchParams) assert.equal(out.searchParams.get(k), v);
  assert.equal(new URL(t.rewriteActionLink(raw, "https://y.web.app/a/")).host, "y.web.app");
  assert.throws(() => t.rewriteActionLink(raw, "http://evil.com/"));
});
