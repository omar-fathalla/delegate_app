/**
 * One-off operator script: provision a technical_support staff account.
 *
 * Not imported by index.js or firebase deploy. Default mode is dry-run (prints
 * the Firestore document only). With --apply: creates a Firebase Auth user (or
 * reuses by email), writes users/{uid} without any password fields, and queues
 * a password-setup email in `mail` (same flow as createStaffUser).
 *
 * Never writes `password`, `temporaryPassword`, or `tempPassword` to Firestore.
 *
 *   cd functions
 *   node create_tech_support.js --email tech@example.com --phone 01111111111
 *   node create_tech_support.js --email tech@example.com --phone 01111111111 --apply
 */

const admin = require("firebase-admin");
const {setupEmail} = require("./lib/staff_accounts_logic");
const {SECRET_KEYS} = require("./scripts/p0-common");

const DEFAULT_DISPLAY_NAME = "Technical Support";
const DEFAULT_ROLE = "technical_support";

/**
 * @param {string[]} argv
 * @return {Record<string, string|boolean>}
 */
function parseArgs(argv) {
  /** @type {Record<string, string|boolean>} */
  const out = {apply: false};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") {
      out.apply = true;
      continue;
    }
    if (!arg.startsWith("--")) {
      throw new Error(`unexpected argument ${arg}`);
    }
    const value = argv[i + 1];
    if (value == null || value.startsWith("--")) {
      throw new Error(`${arg} needs a value`);
    }
    out[arg.slice(2)] = value;
    i++;
  }
  return out;
}

/**
 * @param {{
 *   uid: string,
 *   email: string,
 *   phoneNumber: string,
 *   displayName?: string,
 *   role?: string,
 * }} input
 * @return {Record<string, unknown>}
 */
function buildTechSupportUserDoc(input) {
  const uid = String(input.uid || "").trim();
  const email = String(input.email || "").trim().toLowerCase();
  const phoneNumber = String(input.phoneNumber || "").trim();
  const displayName = String(input.displayName || DEFAULT_DISPLAY_NAME).trim();
  const role = String(input.role || DEFAULT_ROLE).trim();
  if (!uid) throw new Error("uid is required");
  if (!email || !email.includes("@")) throw new Error("valid email is required");
  if (!/^\d{10,15}$/.test(phoneNumber)) throw new Error("phoneNumber must be 10–15 digits");

  return {
    uid,
    email,
    phoneNumber,
    displayName,
    role,
    isActive: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: "create_tech_support_script",
  };
}

/**
 * @param {Record<string, unknown>} doc
 * @return {void}
 */
function assertNoSecretFields(doc) {
  for (const k of SECRET_KEYS) {
    if (Object.prototype.hasOwnProperty.call(doc, k)) {
      throw new Error(`refusing to write forbidden field ${k} on users`);
    }
  }
}

/**
 * Strip legacy secret keys if present on an existing profile (merge delete).
 * @return {Record<string, unknown>}
 */
function secretFieldDeletes() {
  /** @type {Record<string, unknown>} */
  const out = {};
  for (const k of SECRET_KEYS) {
    out[k] = admin.firestore.FieldValue.delete();
  }
  return out;
}

async function queueSetupEmail(db, email, displayName) {
  const link = await admin.auth().generatePasswordResetLink(email);
  await db.collection("mail").add({to: [email], message: setupEmail(displayName, link)});
}

/**
 * @param {Record<string, string|boolean>} args
 * @param {{
 *   db?: FirebaseFirestore.Firestore,
 *   auth?: import("firebase-admin").auth.Auth,
 * }} deps
 */
async function runCreateTechSupport(args, deps = {}) {
  const email = String(args.email || "").trim().toLowerCase();
  const phone = String(args.phone || args.phoneNumber || "").trim();
  const displayName = args["display-name"] ? String(args["display-name"]).trim() : DEFAULT_DISPLAY_NAME;
  const apply = args.apply === true;

  if (!email || !email.includes("@")) throw new Error("--email is required");
  if (!/^\d{10,15}$/.test(phone)) throw new Error("--phone is required (10–15 digits)");

  const db = deps.db;
  const auth = deps.auth;

  if (!apply) {
    const previewUid = "AUTH_UID_AFTER_APPLY";
    const doc = buildTechSupportUserDoc({
      uid: previewUid,
      email,
      phoneNumber: phone,
      displayName,
    });
    assertNoSecretFields(doc);
    console.log("dry-run: would ensure Auth user and write users/{uid}");
    console.log(JSON.stringify(doc, null, 2));
    console.log("Then queue password-setup mail (link not printed).");
    return {mode: "dry-run", uid: previewUid};
  }

  if (!db || !auth) throw new Error("db and auth required when --apply");

  let user;
  try {
    user = await auth.createUser({email, displayName, emailVerified: false, disabled: false});
  } catch (e) {
    if ((e).code === "auth/email-already-exists") {
      user = await auth.getUserByEmail(email);
    } else {
      throw e;
    }
  }

  const userDoc = buildTechSupportUserDoc({
    uid: user.uid,
    email,
    phoneNumber: phone,
    displayName,
  });
  assertNoSecretFields(userDoc);

  const userRef = db.collection("users").doc(user.uid);
  const existing = await userRef.get();
  const payload = existing.exists ?
    {...userDoc, ...secretFieldDeletes(), updatedAt: admin.firestore.FieldValue.serverTimestamp()} :
    userDoc;

  await userRef.set(payload, {merge: true});
  await queueSetupEmail(db, email, displayName);

  console.log(`users/${user.uid} written; setup email queued for ${email}`);
  return {mode: "apply", uid: user.uid};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.apply !== true) {
    await runCreateTechSupport(args);
    return;
  }
  if (admin.apps.length === 0) admin.initializeApp();
  await runCreateTechSupport(args, {db: admin.firestore(), auth: admin.auth()});
}

module.exports = {
  parseArgs,
  buildTechSupportUserDoc,
  assertNoSecretFields,
  runCreateTechSupport,
  DEFAULT_DISPLAY_NAME,
  DEFAULT_ROLE,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "create_tech_support failed");
    process.exitCode = 1;
  });
}