/**
 * One-off operator script: provision a technical_support staff account.
 *
 * Not imported by index.js or firebase deploy. Requires --project (allow-list:
 * tashil-dev, demo-*; prod refused unless --allow-prod-project= with approval).
 *
 * With --apply: creates a Firebase Auth user (or reuses by email), writes
 * users/{uid} without secret fields, and may queue a password-setup email in
 * `mail` (same flow as createStaffUser). Does not change role or touch accounts
 * that already have another role or companyUID unless --allow-role-change.
 *
 * Never writes `password`, `temporaryPassword`, or `tempPassword` to Firestore.
 *
 *   cd functions
 *   node create_tech_support.js --project tashil-dev --email tech@example.com --phone 01111111111
 *   node create_tech_support.js --project tashil-dev --email tech@example.com --phone 01111111111 --apply
 */

const admin = require("firebase-admin");
const {setupEmail} = require("./lib/staff_accounts_logic");
const {SECRET_KEYS, normalizeProject, assertTarget} = require("./scripts/p0-common");

const DEFAULT_DISPLAY_NAME = "Technical Support";
const DEFAULT_ROLE = "technical_support";
const SETUP_MAIL_COOLDOWN_MS = 60 * 60 * 1000; // align with createStaffUser reset link TTL
const TECH_ROLES = new Set([
  "technical_support",
  "technicalsupport",
  "tech_support",
  "techsupport",
]);

/**
 * @param {unknown} role
 * @return {string}
 */
function roleKey(role) {
  return typeof role === "string" ? role.trim().toLowerCase().replace(/-/g, "_") : "";
}

/**
 * @param {unknown} role
 * @return {boolean}
 */
function isTechSupportRole(role) {
  return TECH_ROLES.has(roleKey(role));
}

/**
 * @param {string[]} argv
 * @return {{
 *   apply: boolean,
 *   allowRoleChange: boolean,
 *   forceSetupEmail: boolean,
 *   project: string,
 *   allowProd: string,
 *   email?: string,
 *   phone?: string,
 *   phoneNumber?: string,
 *   "display-name"?: string,
 * }}
 */
function parseArgs(argv) {
  const out = {
    apply: false,
    allowRoleChange: false,
    forceSetupEmail: false,
    project: "",
    allowProd: "",
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") {
      out.apply = true;
      continue;
    }
    if (arg === "--allow-role-change") {
      out.allowRoleChange = true;
      continue;
    }
    if (arg === "--force-setup-email") {
      out.forceSetupEmail = true;
      continue;
    }
    if (arg.startsWith("--allow-prod-project=")) {
      out.allowProd = normalizeProject(arg.slice(21));
      continue;
    }
    if (arg === "--project") {
      out.project = normalizeProject(argv[++i]);
      continue;
    }
    if (arg.startsWith("--project=")) {
      out.project = normalizeProject(arg.slice(10));
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
 * @param {{project: string, allowProd: string}} args
 * @return {string}
 */
function resolveProjectTarget(args) {
  return assertTarget({project: args.project, allowProd: args.allowProd});
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
 * @param {Record<string, unknown>|null|undefined} existing
 * @param {{allowRoleChange: boolean, targetRole?: string}} opts
 * @return {{ok: boolean, reason?: string, changes: {field: string, from: unknown, to: unknown}[]}}
 */
function assessExistingProfile(existing, opts) {
  if (!existing) return {ok: true, changes: []};
  const targetRole = opts.targetRole || DEFAULT_ROLE;
  /** @type {{field: string, from: unknown, to: unknown}[]} */
  const changes = [];
  const existingRole = existing.role;
  if (existingRole != null && existingRole !== "" && !isTechSupportRole(existingRole)) {
    changes.push({field: "role", from: existingRole, to: targetRole});
  }
  const companyUID = String(existing.companyUID || "").trim();
  if (companyUID) {
    changes.push({field: "companyUID", from: companyUID, to: companyUID});
  }
  const blocked = changes.length > 0 && !opts.allowRoleChange;
  if (blocked) {
    return {ok: false, reason: "existing_profile_scope", changes};
  }
  return {ok: true, changes};
}

/**
 * @param {{field: string, from: unknown, to: unknown}[]} changes
 */
function logPlannedChanges(changes) {
  if (changes.length === 0) {
    console.log("profile: no role/company scope change");
    return;
  }
  console.log("profile: planned changes:");
  for (const c of changes) {
    console.log(`  ${c.field}: ${JSON.stringify(c.from)} -> ${JSON.stringify(c.to)}`);
  }
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

/**
 * @param {unknown} ts
 * @return {number}
 */
function timestampMs(ts) {
  if (ts && typeof ts === "object" && typeof ts.toMillis === "function") {
    return ts.toMillis();
  }
  if (typeof ts === "number") return ts;
  return 0;
}

/**
 * @param {Record<string, unknown>|null|undefined} existing
 * @param {boolean} force
 * @return {boolean}
 */
function shouldQueueSetupEmail(existing, force) {
  if (force) return true;
  if (!existing || !existing.lastPasswordSetupMailAt) return true;
  return Date.now() - timestampMs(existing.lastPasswordSetupMailAt) > SETUP_MAIL_COOLDOWN_MS;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} email
 * @param {string} displayName
 */
async function queueSetupEmail(db, email, displayName) {
  const link = await admin.auth().generatePasswordResetLink(email);
  await db.collection("mail").add({to: [email], message: setupEmail(displayName, link)});
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} email
 * @return {Promise<{id: string, data: Record<string, unknown>}|null>}
 */
async function findProfileByEmail(db, email) {
  const snap = await db.collection("users").where("email", "==", email).limit(1).get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  return {id: doc.id, data: doc.data()};
}

/**
 * @param {Record<string, string|boolean>} args
 * @param {{
 *   project?: string,
 *   db?: FirebaseFirestore.Firestore,
 *   auth?: import("firebase-admin").auth.Auth,
 * }} deps
 */
async function runCreateTechSupport(args, deps = {}) {
  const email = String(args.email || "").trim().toLowerCase();
  const phone = String(args.phone || args.phoneNumber || "").trim();
  const displayName = args["display-name"] ? String(args["display-name"]).trim() : DEFAULT_DISPLAY_NAME;
  const apply = args.apply === true;
  const project = deps.project || resolveProjectTarget(args);
  console.log(`target project: ${project}`);

  if (!email || !email.includes("@")) throw new Error("--email is required");
  if (!/^\d{10,15}$/.test(phone)) throw new Error("--phone is required (10–15 digits)");

  const db = deps.db;
  const auth = deps.auth;

  const profileByEmail = db ? await findProfileByEmail(db, email) : null;
  const previewAssessment = assessExistingProfile(profileByEmail?.data, {
    allowRoleChange: args.allowRoleChange === true,
  });

  if (!apply) {
    const previewUid = profileByEmail?.id || "AUTH_UID_AFTER_APPLY";
    const doc = buildTechSupportUserDoc({
      uid: previewUid,
      email,
      phoneNumber: phone,
      displayName,
    });
    assertNoSecretFields(doc);
    console.log("dry-run: would ensure Auth user and write users/{uid}");
    if (!previewAssessment.ok) {
      logPlannedChanges(previewAssessment.changes);
      throw new Error(
        "refusing dry-run: existing profile has another role or companyUID (use --allow-role-change)",
      );
    }
    logPlannedChanges(previewAssessment.changes);
    console.log(JSON.stringify(doc, null, 2));
    const mailNote = profileByEmail &&
      !shouldQueueSetupEmail(profileByEmail.data, args.forceSetupEmail === true) ?
      "skip password-setup mail (sent recently; use --force-setup-email)" :
      "queue password-setup mail (link not printed)";
    console.log(`Then ${mailNote}.`);
    return {mode: "dry-run", uid: previewUid, project, mailSkipped: mailNote.startsWith("skip")};
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

  const userRef = db.collection("users").doc(user.uid);
  const existingSnap = await userRef.get();
  const existingData = existingSnap.exists ? existingSnap.data() : profileByEmail?.id === user.uid ?
    profileByEmail.data :
    null;
  const assessment = assessExistingProfile(existingData, {
    allowRoleChange: args.allowRoleChange === true,
  });
  if (!assessment.ok) {
    logPlannedChanges(assessment.changes);
    throw new Error(
      "refusing apply: existing profile has another role or companyUID (use --allow-role-change)",
    );
  }
  logPlannedChanges(assessment.changes);

  const userDoc = buildTechSupportUserDoc({
    uid: user.uid,
    email,
    phoneNumber: phone,
    displayName,
  });
  assertNoSecretFields(userDoc);

  const payload = existingSnap.exists || existingData ?
    {...userDoc, ...secretFieldDeletes(), updatedAt: admin.firestore.FieldValue.serverTimestamp()} :
    userDoc;

  await userRef.set(payload, {merge: true});

  let mailQueued = false;
  if (shouldQueueSetupEmail(existingData, args.forceSetupEmail === true)) {
    await queueSetupEmail(db, email, displayName);
    await userRef.set({
      lastPasswordSetupMailAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    mailQueued = true;
    console.log(`users/${user.uid} written; setup email queued for ${email}`);
  } else {
    console.log(`users/${user.uid} written; setup email skipped (recent; use --force-setup-email)`);
  }

  return {mode: "apply", uid: user.uid, project, mailQueued};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const project = resolveProjectTarget(args);
  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: project});
  }
  await runCreateTechSupport(args, {
    project,
    db: admin.firestore(),
    auth: admin.auth(),
  });
}

module.exports = {
  parseArgs,
  buildTechSupportUserDoc,
  assertNoSecretFields,
  runCreateTechSupport,
  resolveProjectTarget,
  assessExistingProfile,
  shouldQueueSetupEmail,
  isTechSupportRole,
  DEFAULT_DISPLAY_NAME,
  DEFAULT_ROLE,
  SETUP_MAIL_COOLDOWN_MS,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "create_tech_support failed");
    process.exitCode = 1;
  });
}