/**
 * One-off operator script: provision a technical_support staff account.
 *
 * Not imported by index.js or firebase deploy. Requires --project (allow-list:
 * tashil-dev, demo-*; prod refused unless --allow-prod-project= with approval).
 *
 * With --apply: creates a Firebase Auth user (or reuses by email), writes
 * users/{uid} without secret fields, and may queue a password-setup email in
 * `mail` (same flow as createStaffUser). Does not change role or touch accounts
 * that already have another role or companyUID unless --allow-role-change (does
 * not override uid mismatch or orphan Firestore without Auth).
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

/** @param {unknown} raw */
function normalizeLookupEmail(raw) {
  return String(raw || "").trim().toLowerCase();
}

/** @param {unknown} raw */
function normalizeLookupPhone(raw) {
  return String(raw || "").trim();
}

/**
 * @param {unknown} stored
 * @param {string} normTarget
 */
function emailsMatch(stored, normTarget) {
  return normalizeLookupEmail(stored) === normTarget;
}

/**
 * @param {string} normEmail
 * @param {string} rawEmail
 * @return {string[]}
 */
function emailLookupVariants(normEmail, rawEmail) {
  const raw = String(rawEmail || "").trim();
  const set = new Set([normEmail]);
  if (raw) set.add(raw);
  return [...set].filter(Boolean).slice(0, 10);
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
    emailNormalized: email,
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
 * @param {string} normEmail
 * @param {string} phone
 * @param {string} rawEmail
 * @return {Promise<{id: string, data: Record<string, unknown>}[]>}
 */
async function lookupExistingProfiles(db, normEmail, phone, rawEmail) {
  const normPhone = normalizeLookupPhone(phone);
  /** @type {Map<string, {id: string, data: Record<string, unknown>}>} */
  const byId = new Map();
  const merge = (snap) => {
    for (const doc of snap.docs) {
      byId.set(doc.id, {id: doc.id, data: doc.data()});
    }
  };
  const variants = emailLookupVariants(normEmail, rawEmail);
  if (variants.length === 1) {
    merge(await db.collection("users").where("email", "==", variants[0]).limit(5).get());
  } else if (variants.length > 1) {
    merge(await db.collection("users").where("email", "in", variants).limit(10).get());
  }
  try {
    merge(await db.collection("users").where("emailNormalized", "==", normEmail).limit(5).get());
  } catch (indexErr) {
    if (indexErr && typeof indexErr === "object") {
      /* optional emailNormalized index */
    }
  }
  merge(await db.collection("users").where("phoneNumber", "==", normPhone).limit(10).get());
  merge(await db.collection("users").where("phone", "==", normPhone).limit(10).get());

  /** @type {Map<string, {id: string, data: Record<string, unknown>}>} */
  const matched = new Map();
  for (const p of byId.values()) {
    const docPhone = normalizeLookupPhone(p.data.phoneNumber || p.data.phone || "");
    if (emailsMatch(p.data.email, normEmail) || docPhone === normPhone) {
      matched.set(p.id, p);
    }
  }
  return [...matched.values()];
}

/**
 * Shared dry-run + apply guard for existing Firestore profiles and Auth uid alignment.
 *
 * @param {{id: string, data: Record<string, unknown>}[]} profiles
 * @param {{allowRoleChange: boolean, authUid: string|null}} opts
 * @return {{ok: boolean, reason?: string, changes: {field: string, from: unknown, to: unknown, profileId?: string}[]}}
 */
function assessProvisioningProfiles(profiles, opts) {
  /** @type {{field: string, from: unknown, to: unknown, profileId?: string}[]} */
  const changes = [];
  for (const p of profiles) {
    const a = assessExistingProfile(p.data, {allowRoleChange: opts.allowRoleChange});
    for (const c of a.changes) {
      changes.push({...c, profileId: p.id});
    }
    if (!a.ok) {
      return {ok: false, reason: a.reason, changes};
    }
  }
  if (profiles.length === 0) {
    return {ok: true, changes};
  }
  if (!opts.authUid) {
    for (const p of profiles) {
      changes.push({
        field: "uid",
        from: p.id,
        to: "(no Auth user for email/phone)",
        profileId: p.id,
      });
    }
    return {ok: false, reason: "orphan_profile", changes};
  }
  for (const p of profiles) {
    if (p.id !== opts.authUid) {
      changes.push({field: "uid", from: p.id, to: opts.authUid, profileId: p.id});
      return {ok: false, reason: "uid_mismatch", changes};
    }
  }
  return {ok: true, changes};
}

/**
 * @param {import("firebase-admin").auth.Auth} auth
 * @param {string} email
 * @return {Promise<string|null>}
 */
async function resolveAuthUidByEmail(auth, email) {
  try {
    const user = await auth.getUserByEmail(email);
    return user.uid;
  } catch (e) {
    if ((e).code === "auth/user-not-found") return null;
    throw e;
  }
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {import("firebase-admin").auth.Auth} auth
 * @param {string} email
 * @param {string} phone
 * @param {boolean} allowRoleChange
 */
async function planProvisioning(db, auth, normEmail, phone, rawEmail, allowRoleChange) {
  const profiles = await lookupExistingProfiles(db, normEmail, phone, rawEmail);
  const authUid = auth ? await resolveAuthUidByEmail(auth, normEmail) : null;
  const assessment = assessProvisioningProfiles(profiles, {allowRoleChange, authUid});
  const primaryProfile = profiles.find((p) => emailsMatch(p.data.email, normEmail)) || profiles[0] || null;
  return {profiles, authUid, assessment, primaryProfile};
}

/**
 * @param {{ok: boolean, reason?: string}} assessment
 * @param {string} mode
 */
function refuseProvisioning(assessment, mode) {
  logPlannedChanges(assessment.changes);
  const hint = assessment.reason === "orphan_profile" ?
    "Firestore profile exists without matching Auth user" :
    assessment.reason === "uid_mismatch" ?
      "Firestore doc id does not match Auth uid (migrate or delete the old doc first)" :
      "existing profile has another role or companyUID";
  const suffix = assessment.reason === "existing_profile_scope" ?
    " (use --allow-role-change)" :
    "";
  throw new Error(`refusing ${mode}: ${hint}${suffix}`);
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
  const rawEmail = String(args.email || "").trim();
  const email = normalizeLookupEmail(rawEmail);
  const phone = normalizeLookupPhone(args.phone || args.phoneNumber || "");
  const displayName = args["display-name"] ? String(args["display-name"]).trim() : DEFAULT_DISPLAY_NAME;
  const apply = args.apply === true;
  const allowRoleChange = args.allowRoleChange === true;
  const project = deps.project || resolveProjectTarget(args);
  console.log(`target project: ${project}`);

  if (!email || !email.includes("@")) throw new Error("--email is required");
  if (!/^\d{10,15}$/.test(phone)) throw new Error("--phone is required (10–15 digits)");

  const db = deps.db;
  const auth = deps.auth;

  if (!db) throw new Error("db is required");

  const plan = await planProvisioning(db, auth, email, phone, rawEmail, allowRoleChange);

  if (!apply) {
    if (!plan.assessment.ok) {
      refuseProvisioning(plan.assessment, "dry-run");
    }
    const previewUid = plan.authUid || plan.primaryProfile?.id || "AUTH_UID_AFTER_APPLY";
    const doc = buildTechSupportUserDoc({
      uid: previewUid,
      email,
      phoneNumber: phone,
      displayName,
    });
    assertNoSecretFields(doc);
    console.log("dry-run: would ensure Auth user and write users/{uid}");
    logPlannedChanges(plan.assessment.changes);
    console.log(JSON.stringify(doc, null, 2));
    const mailNote = plan.primaryProfile &&
      !shouldQueueSetupEmail(plan.primaryProfile.data, args.forceSetupEmail === true) ?
      "skip password-setup mail (sent recently; use --force-setup-email)" :
      "queue password-setup mail (link not printed)";
    console.log(`Then ${mailNote}.`);
    return {mode: "dry-run", uid: previewUid, project, mailSkipped: mailNote.startsWith("skip")};
  }

  if (!auth) throw new Error("auth required when --apply");

  if (!plan.assessment.ok) {
    refuseProvisioning(plan.assessment, "apply");
  }
  logPlannedChanges(plan.assessment.changes);

  let user;
  if (plan.authUid) {
    user = await auth.getUser(plan.authUid);
  } else {
    try {
      user = await auth.createUser({email, displayName, emailVerified: false, disabled: false});
    } catch (e) {
      if ((e).code === "auth/email-already-exists") {
        user = await auth.getUserByEmail(email);
        const recheck = assessProvisioningProfiles(
          await lookupExistingProfiles(db, email, phone, rawEmail),
          {allowRoleChange, authUid: user.uid},
        );
        if (!recheck.ok) {
          refuseProvisioning(recheck, "apply");
        }
      } else {
        throw e;
      }
    }
  }

  const userRef = db.collection("users").doc(user.uid);
  const existingSnap = await userRef.get();
  const existingData = existingSnap.exists ? existingSnap.data() :
    (plan.primaryProfile?.id === user.uid ? plan.primaryProfile.data : undefined);

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

  const mailExisting = existingData || plan.primaryProfile?.data;
  let mailQueued = false;
  if (shouldQueueSetupEmail(mailExisting, args.forceSetupEmail === true)) {
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
  assessProvisioningProfiles,
  normalizeLookupEmail,
  normalizeLookupPhone,
  emailsMatch,
  lookupExistingProfiles,
  planProvisioning,
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