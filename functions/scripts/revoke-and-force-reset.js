/**
 * P0: revoke refresh tokens for staff accounts and send each a password
 * reset email (queued in `mail`; the link is never printed). Super-admins
 * first. Delegates/promoters are skipped (their login is not password based).
 *
 * Default: dry run, prints COUNTS ONLY.
 *   node scripts/revoke-and-force-reset.js --project tashil-dev
 *   node scripts/revoke-and-force-reset.js --project tashil-dev --super-only --apply
 *   node scripts/revoke-and-force-reset.js --project tashil-dev --apply
 * Allow-list: tashil-dev and demo-* only; prod needs --allow-prod-project=<id>
 * and written approval (not given).
 */
const admin = require("firebase-admin");
const {parseArgs, assertTarget, resetPriority} = require("./p0-common");

async function plan(db, superOnly) {
  const snap = await db.collection("users").get();
  const rows = [];
  for (const doc of snap.docs) {
    const p = resetPriority(doc.get("role"));
    if (p < 0 || (superOnly && p !== 0)) continue;
    rows.push({uid: doc.id, email: doc.get("email"), priority: p});
  }
  rows.sort((a, b) => a.priority - b.priority);
  return rows;
}

async function run(db, auth, {apply, superOnly}) {
  const rows = await plan(db, superOnly);
  const c = {targets: rows.length, superAdmins: rows.filter((r) => r.priority === 0).length,
    revoked: 0, resetQueued: 0, noAuthUser: 0, noEmail: 0};
  if (!apply) return c;
  for (const r of rows) {
    let user = null;
    try { user = await auth.getUser(r.uid); } catch (_) { /* fall back to email */ }
    if (!user && typeof r.email === "string" && r.email) {
      try { user = await auth.getUserByEmail(r.email.trim().toLowerCase()); } catch (_) { /* none */ }
    }
    if (!user) { c.noAuthUser++; continue; }
    await auth.revokeRefreshTokens(user.uid); c.revoked++;
    await db.collection("users").doc(r.uid).set({requireReLogin: true,
      forcedResetAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    if (!user.email) { c.noEmail++; continue; }
    const link = await auth.generatePasswordResetLink(user.email);
    await db.collection("mail").add({to: [user.email], message: {
      subject: "Tashil - إعادة تعيين كلمة السر",
      html: `<div dir="rtl"><p>لأسباب أمنية تم تسجيل خروجك. اضغط الرابط لتعيين كلمة سر جديدة.</p><p><a href="${link}">تعيين كلمة السر</a></p></div>`,
    }});
    c.resetQueued++;
  }
  return c;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = assertTarget(args);
  admin.initializeApp({projectId: project});
  const superOnly = args.rest.includes("--super-only");
  const c = await run(admin.firestore(), admin.auth(), {apply: args.apply, superOnly});
  console.log(JSON.stringify({mode: args.apply ? "apply" : "dry-run", project, superOnly, ...c}));
}

if (require.main === module) main().catch((e) => { console.error(e.message); process.exit(1); });
module.exports = {plan, run};
