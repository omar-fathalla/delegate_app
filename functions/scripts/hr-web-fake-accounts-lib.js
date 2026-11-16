/**
 * Pure plan + guards for fake HR-web accounts on tashil-dev.
 *
 * No firebase-admin import and no network. The CLI in
 * hr-web-fake-accounts.js is the only writer. Shapes follow the fields the
 * app reads today: users/{uid} for staff phone login, and
 * organizations/{org}/companies/{company}/delegates/{uid} for the HR list
 * (TA-8 company scope). The first 22 accounts use the canonical role strings
 * in DelegateModel.roleToString / firestore.rules; ROLE_SHAPE_ACCOUNTS add the
 * other supervisor / HR spellings and company fields found in production.
 */

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const ALLOWED_PROJECT = "tashil-dev";
const PROD_PROJECT = "practice-firebase-72df1";
const SEED_TAG = "tashil-dev-hr-web-fake-v1";
const CREATED_BY = "hr-web-fake-accounts";
const ORG_ID = "seed-fake-hr-org";
const ORG_NAME = "Fake Test Organization";
const ORG_NAME_AR = "منظمة وهمية للاختبار";
const PASSWORD_FILE_NAME = ".hr-web-fake-accounts.local.json";
const EMAIL_DOMAIN = "@example.com";

const HR_ROLES = new Set(["hr", "company-hr", "company_hr", "human_resources"]);

/**
 * Extra supervisor / HR accounts, one per users/{uid} shape seen in
 * production: the Angular invite (claimInvite writes company-admin),
 * createStaffUser, client grants and legacy imports. Fake data only.
 * Appended after the original 22 accounts so their phones do not move.
 */
const ROLE_SHAPE_ACCOUNTS = [
  {
    uid: "seed-fake-company-admin-invite-alpha",
    email: "fake.companyadmin.invite.alpha@example.com",
    role: "company-admin",
    displayName: "Fake Company Admin Invite alpha",
    company: "alpha",
    extra: {emailVerified: true, status: "Approved"},
    shape: "Angular invite (claimInvite)",
  },
  {
    uid: "seed-fake-company-admin-legacy-alpha",
    email: "fake.companyadmin.legacy.alpha@example.com",
    role: "company_admin",
    displayName: "Fake Company Admin Legacy alpha",
    company: "alpha",
    shape: "createStaffUser / legacy",
  },
  {
    uid: "seed-fake-companyadmin-companyid-alpha",
    email: "fake.companyadmin.companyid.alpha@example.com",
    role: "companyadmin",
    displayName: "Fake Company Admin CompanyId alpha",
    company: "alpha",
    companyField: "companyId",
    shape: "legacy companyId field only",
  },
  {
    uid: "seed-fake-admin-position-alpha",
    email: "fake.admin.position.alpha@example.com",
    role: "admin",
    displayName: "Fake Admin Supervisor alpha",
    company: "alpha",
    extra: {position: "supervisor"},
    shape: "admin + position supervisor",
  },
  {
    uid: "seed-fake-company-supervisor-beta",
    email: "fake.company-supervisor.beta@example.com",
    role: "company_supervisor",
    displayName: "Fake Company Supervisor Underscore beta",
    company: "beta",
    extra: {jobTitle: "Company Supervisor"},
    shape: "createStaffUser company_supervisor",
  },
  {
    uid: "seed-fake-admin-usertype-hr-beta",
    email: "fake.admin.usertype-hr.beta@example.com",
    role: "admin",
    displayName: "Fake Admin UserType HR beta",
    company: "beta",
    extra: {userType: "HR"},
    shape: "admin + legacy userType HR",
  },
  {
    uid: "seed-fake-company-hr-alpha",
    email: "fake.company-hr.alpha@example.com",
    role: "company-hr",
    displayName: "Fake Company HR Hyphen alpha",
    company: "alpha",
    shape: "legacy company-hr",
  },
  {
    uid: "seed-fake-company-hr-beta",
    email: "fake.company_hr.beta@example.com",
    role: "company_hr",
    displayName: "Fake Company HR Underscore beta",
    company: "beta",
    shape: "company_hr",
  },
  {
    uid: "seed-fake-human-resources-beta",
    email: "fake.human-resources.beta@example.com",
    role: "human_resources",
    displayName: "Fake Human Resources beta",
    company: "beta",
    extra: {jobTitle: "HR"},
    shape: "human_resources",
  },
  {
    uid: "seed-fake-admin-no-company",
    email: "fake.admin.nocompany@example.com",
    role: "admin",
    displayName: "Fake Legacy Admin No Company",
    company: null,
    shape: "legacy admin without a company",
  },
];

const COMPANIES = [
  {
    id: "seed-fake-co-alpha",
    name: "Fake Company Alpha",
    nameAr: "شركة وهمية ألف",
    companyCodeInOrg: "FAKE-ALPHA",
    code: 9001,
    phone: "01000000901",
    email: "fake.company.alpha@example.com",
    branchId: "seed-fake-br-alpha",
    branchName: "Fake Branch Alpha",
    latitude: 30.1001,
    longitude: 31.2001,
  },
  {
    id: "seed-fake-co-beta",
    name: "Fake Company Beta",
    nameAr: "شركة وهمية باء",
    companyCodeInOrg: "FAKE-BETA",
    code: 9002,
    phone: "01000000902",
    email: "fake.company.beta@example.com",
    branchId: "seed-fake-br-beta",
    branchName: "Fake Branch Beta",
    latitude: 30.1002,
    longitude: 31.2002,
  },
];

/**
 * @param {unknown} raw
 * @return {string}
 */
function normalizeProject(raw) {
  if (typeof raw !== "string") return "";
  return raw.trim().toLowerCase().replace(/^projects\//, "");
}

/**
 * @param {string} project
 * @param {string} label
 * @return {string}
 */
function assertExactDevProject(project, label) {
  const id = normalizeProject(project);
  if (!id) {
    throw new Error(`${label} is required and must be exactly ${ALLOWED_PROJECT}.`);
  }
  if (id === PROD_PROJECT) {
    throw new Error(
      `Refusing ${label} "${PROD_PROJECT}" (production). This script only runs on ${ALLOWED_PROJECT}.`,
    );
  }
  if (id !== ALLOWED_PROJECT) {
    throw new Error(`Refusing ${label} "${id}": this script only runs on ${ALLOWED_PROJECT}.`);
  }
  return id;
}

/** @param {unknown} project @return {string} */
function assertDevProject(project) {
  return assertExactDevProject(project, "--project");
}

/** @param {unknown} project @return {string} */
function assertCredentialProject(project) {
  return assertExactDevProject(project, "credentials project");
}

/**
 * Refuse when a local env signal names any project other than tashil-dev.
 * Unset variables are ignored so a dry run needs no credentials.
 * @param {NodeJS.ProcessEnv} env
 * @param {(filePath: string) => string} [readFile]
 */
function assertLocalCredentialSignals(env, readFile) {
  for (const key of ["GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT", "GCP_PROJECT"]) {
    if (env[key]) assertCredentialProject(env[key]);
  }
  if (env.FIREBASE_CONFIG) {
    let parsed;
    try {
      parsed = JSON.parse(env.FIREBASE_CONFIG);
    } catch {
      throw new Error("FIREBASE_CONFIG is not valid JSON.");
    }
    if (parsed && parsed.projectId) assertCredentialProject(parsed.projectId);
  }
  const credPath = env.GOOGLE_APPLICATION_CREDENTIALS;
  if (credPath && readFile) {
    let json;
    try {
      json = JSON.parse(readFile(credPath));
    } catch {
      throw new Error("Could not read GOOGLE_APPLICATION_CREDENTIALS as JSON.");
    }
    if (!json || !json.project_id) {
      throw new Error("credentials file has no project_id.");
    }
    assertCredentialProject(json.project_id);
  }
}

/**
 * @param {{env: NodeJS.ProcessEnv, readFile?: (p: string) => string, lookup?: () => Promise<string>}} sources
 * @return {Promise<string>}
 */
async function resolveCredentialProject(sources) {
  const env = sources.env || {};
  if (env.GOOGLE_APPLICATION_CREDENTIALS) {
    if (!sources.readFile) throw new Error("credentials file is set but no reader was provided.");
    const json = JSON.parse(sources.readFile(env.GOOGLE_APPLICATION_CREDENTIALS));
    if (!json || !json.project_id) throw new Error("credentials file has no project_id.");
    return String(json.project_id);
  }
  if (env.FIREBASE_CONFIG) {
    const parsed = JSON.parse(env.FIREBASE_CONFIG);
    if (parsed && parsed.projectId) return String(parsed.projectId);
  }
  if (env.GOOGLE_CLOUD_PROJECT) return String(env.GOOGLE_CLOUD_PROJECT);
  if (env.GCLOUD_PROJECT) return String(env.GCLOUD_PROJECT);
  if (env.GCP_PROJECT) return String(env.GCP_PROJECT);
  if (typeof sources.lookup !== "function") {
    throw new Error("could not determine credentials project.");
  }
  const live = await sources.lookup();
  if (!live) throw new Error("could not determine credentials project.");
  return String(live);
}

/**
 * @param {string[]} argv
 * @return {{project: string, apply: boolean, cleanup: boolean, rotatePasswords: boolean, dryRun: boolean}}
 */
function parseArgs(argv) {
  const out = {project: "", apply: false, cleanup: false, rotatePasswords: false, dryRun: false};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--apply") {
      out.apply = true;
      continue;
    }
    if (arg === "--cleanup") {
      out.cleanup = true;
      continue;
    }
    if (arg === "--dry-run") {
      out.dryRun = true;
      continue;
    }
    if (arg === "--rotate-passwords") {
      out.rotatePasswords = true;
      continue;
    }
    if (arg.startsWith("--allow-prod")) {
      throw new Error("Refusing --allow-prod: this script never runs on production.");
    }
    if (arg === "--project" || arg.startsWith("--project=")) {
      const value = arg === "--project" ? argv[++i] : arg.slice("--project=".length);
      if (value == null || value.startsWith("--")) throw new Error("--project needs a value.");
      out.project = value;
      continue;
    }
    throw new Error(`unexpected argument ${arg}`);
  }
  if (out.dryRun && out.apply) {
    throw new Error("Cannot use --dry-run together with --apply.");
  }
  if (out.rotatePasswords && (!out.apply || out.cleanup)) {
    throw new Error("--rotate-passwords is only valid with --apply (not with --cleanup).");
  }
  return out;
}

/** @param {number} n @return {string} */
function fakePhone(n) {
  const phone = `01000000${String(n).padStart(3, "0")}`;
  if (!/^01000000\d{3}$/.test(phone) || !/^01[0125]\d{8}$/.test(phone)) {
    throw new Error(`fake phone out of range: ${n}`);
  }
  return phone;
}

/**
 * Deterministic, clearly fake 14-digit national IDs for mobile delegate login.
 * Century digit 0 is invalid for a real Egyptian NID, so these cannot be
 * mistaken for live IDs. Unique per company slug + index.
 * @param {string} slug
 * @param {number} index
 * @return {string}
 */
function fakeNationalId(slug, index) {
  const companyCode = slug === "alpha" ? "01" : slug === "beta" ? "02" : "99";
  const id = `0000000000${companyCode}${String(index).padStart(2, "0")}`;
  if (!/^[0-9]{14}$/.test(id)) {
    throw new Error(`fake national id must be 14 ASCII digits: ${slug}-${index}`);
  }
  return id;
}

/**
 * @param {Buffer|Uint8Array} bytes
 * @return {string}
 */
function passwordFromBytes(bytes) {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
  let out = "";
  for (let i = 0; i < 20; i++) out += alphabet[bytes[i] % alphabet.length];
  return out;
}

/** @param {() => Buffer} [randomBytes] @return {string} */
function generatePassword(randomBytes = () => crypto.randomBytes(20)) {
  return passwordFromBytes(randomBytes());
}

/**
 * @param {string} filePath
 * @return {string}
 */
function assertPasswordFilePath(filePath) {
  if (path.basename(filePath) !== PASSWORD_FILE_NAME) {
    throw new Error(`password file must be named ${PASSWORD_FILE_NAME}`);
  }
  return filePath;
}

function baseDoc() {
  return {seedTag: SEED_TAG, fake: true, createdBy: CREATED_BY};
}

/**
 * @return {{
 *   seedTag: string,
 *   organizationId: string,
 *   accounts: object[],
 *   writes: {kind: string, path: string, data: Record<string, unknown>}[],
 * }}
 */
function buildPlan() {
  /** @type {object[]} */
  const accounts = [];
  /** @type {{kind: string, path: string, data: Record<string, unknown>}[]} */
  const writes = [];
  let phoneN = 1;
  const nextPhone = () => fakePhone(phoneN++);

  writes.push({
    kind: "organization",
    path: `organizations/${ORG_ID}`,
    data: {
      ...baseDoc(),
      name: ORG_NAME,
      nameAr: ORG_NAME_AR,
      status: "active",
      admins: 1,
    },
  });

  for (const company of COMPANIES) {
    writes.push({
      kind: "company",
      path: `organizations/${ORG_ID}/companies/${company.id}`,
      data: {
        ...baseDoc(),
        uid: company.id,
        name: company.name,
        nameAr: company.nameAr,
        companyCodeInOrg: company.companyCodeInOrg,
        organizationUID: ORG_ID,
        organizationName: ORG_NAME,
        type: "retail",
        status: "active",
        admins: 4,
        delegates: 5,
        deferredPayment: false,
        description: "Fake company for tashil-dev HR web tests. Not a real company.",
        address: "Fake Street",
        phone: company.phone,
        email: company.email,
        code: company.code,
      },
    });
    const branch = {
      ...baseDoc(),
      branchName: company.branchName,
      name: company.branchName,
      location: {latitude: company.latitude, longitude: company.longitude},
      latitude: company.latitude,
      longitude: company.longitude,
      geofenceRadius: 100,
      organizationUID: ORG_ID,
      organizationName: ORG_NAME,
      companyUID: company.id,
    };
    writes.push({
      kind: "branch",
      path: `organizations/${ORG_ID}/branches/${company.branchId}`,
      data: branch,
    });
    writes.push({
      kind: "branch",
      path: `branches/${company.branchId}`,
      data: {...branch},
    });
  }

  /**
   * @param {{
   *   uid: string,
   *   email: string,
   *   role: string,
   *   displayName: string,
   *   company?: typeof COMPANIES[number]|null,
   *   omitCompany?: boolean,
   *   status?: string,
   *   isActive?: boolean,
   *   delegate?: Record<string, unknown>|null,
   *   companyField?: "companyUID"|"companyId",
   *   extra?: Record<string, unknown>,
   *   shape?: string,
   * }} spec
   */
  function addAccount(spec) {
    const company = spec.omitCompany ? null : spec.company || null;
    const companyField = spec.companyField || "companyUID";
    const phoneNumber = nextPhone();
    const status = spec.status || "approved";
    const isActive = spec.isActive !== undefined ? spec.isActive : status !== "suspended";
    const names = spec.displayName.split(" ");
    /** @type {Record<string, unknown>} */
    const user = {
      ...baseDoc(),
      uid: spec.uid,
      email: spec.email,
      emailNormalized: spec.email,
      phoneNumber,
      phone: phoneNumber,
      role: spec.role,
      displayName: spec.displayName,
      fullName: spec.displayName,
      firstName: names[0] || "Fake",
      lastName: names.slice(1).join(" ") || "Account",
      isActive,
      status,
      organizationUID: ORG_ID,
      organizationName: ORG_NAME,
    };
    if (company) {
      user[companyField] = company.id;
      user.companyName = company.name;
    }
    if (spec.extra) Object.assign(user, spec.extra);
    const account = {
      uid: spec.uid,
      email: spec.email,
      phoneNumber,
      role: spec.role,
      displayName: spec.displayName,
      companyUID: company && companyField === "companyUID" ? company.id : "",
      companyName: company ? company.name : "",
      status,
      isActive,
    };
    if (company && companyField === "companyId") account.companyId = company.id;
    if (spec.shape) account.shape = spec.shape;
    if (spec.delegate) {
      Object.assign(user, spec.delegate);
      user.uid = spec.uid;
      user.email = spec.email;
      user.phoneNumber = phoneNumber;
      user.phone = phoneNumber;
      user.role = "delegate";
      user.status = status;
      user.isActive = isActive;
      writes.push({
        kind: "delegate",
        path: `organizations/${ORG_ID}/companies/${company.id}/delegates/${spec.uid}`,
        data: {...user},
      });
    }
    writes.push({kind: "user", path: `users/${spec.uid}`, data: user});
    accounts.push(account);
  }

  addAccount({
    uid: "seed-fake-super-admin",
    email: "fake.superadmin@example.com",
    role: "super-admin",
    displayName: "Fake Super Admin",
    omitCompany: true,
  });
  addAccount({
    uid: "seed-fake-tech-support",
    email: "fake.techsupport@example.com",
    role: "technical_support",
    displayName: "Fake Technical Support",
    omitCompany: true,
  });
  addAccount({
    uid: "seed-fake-org-admin",
    email: "fake.orgadmin@example.com",
    role: "organization-admin",
    displayName: "Fake Organization Admin",
    omitCompany: true,
  });
  // Same uid/email/phone as the former no-company HR account, now attached
  // to company alpha. HR is always created under a company.
  addAccount({
    uid: "seed-fake-no-company",
    email: "fake.nocompany@example.com",
    role: "hr",
    displayName: "Fake HR Alpha Extra",
    company: COMPANIES[0],
  });

  for (const company of COMPANIES) {
    const slug = company.id.endsWith("alpha") ? "alpha" : "beta";
    const supervisorUid = `seed-fake-supervisor-${slug}`;
    addAccount({
      uid: supervisorUid,
      email: `fake.supervisor.${slug}@example.com`,
      role: "supervisor",
      displayName: `Fake Company Supervisor ${slug}`,
      company,
    });
    addAccount({
      uid: `seed-fake-hr-${slug}`,
      email: `fake.hr.${slug}@example.com`,
      role: "hr",
      displayName: `Fake HR ${slug}`,
      company,
    });
    addAccount({
      uid: `seed-fake-marketing-${slug}`,
      email: `fake.marketing.${slug}@example.com`,
      role: "marketing",
      displayName: `Fake Branch Marketing ${slug}`,
      company,
    });
    addAccount({
      uid: `seed-fake-bmm-${slug}`,
      email: `fake.branches-marketing.${slug}@example.com`,
      role: "branches_marketing",
      displayName: `Fake Branches Marketing Manager ${slug}`,
      company,
    });
    for (let i = 1; i <= 5; i++) {
      const suspended = i === 5;
      addAccount({
        uid: `seed-fake-del-${slug}-${i}`,
        email: `fake.delegate.${slug}.${i}@example.com`,
        role: "delegate",
        displayName: `Fake Delegate ${slug} ${i}`,
        company,
        status: suspended ? "suspended" : "active",
        isActive: !suspended,
        delegate: {
          middleName: "",
          nationalityID: fakeNationalId(slug, i),
          nationalId: fakeNationalId(slug, i),
          motherName: "Fake Mother",
          city: "Fake City",
          gender: i === 2 ? "Female" : "Male",
          position: i === 4 ? "Supervisor" : "Promoter",
          birthDate: "1990-01-01T00:00:00.000Z",
          delegatePublicId: `FAKE-${slug.toUpperCase()}-${i}`,
          allReceiptCodes: [],
          hasPendingUpdate: false,
          isDeductedFromCompany: false,
          isPrinted: false,
          isProfileComplete: true,
          numberOfDocuments: 0,
          paymentAmount: 0,
          version: 1,
          documents: [],
          isDeviceLocked: false,
          isExternal: false,
          isAnnualLeaveEnabled: false,
          annualLeaveQuota: 21,
          supervisorUid,
          supervisorName: `Fake Company Supervisor ${slug}`,
          ...(suspended ? {statusReason: "Fake suspended test account"} : {}),
        },
      });
    }
  }

  for (const spec of ROLE_SHAPE_ACCOUNTS) {
    const company = spec.company ? COMPANIES.find((c) => c.id.endsWith(spec.company)) : null;
    addAccount({...spec, company, omitCompany: !company});
  }

  assertPlanSafe({seedTag: SEED_TAG, organizationId: ORG_ID, accounts, writes});
  return {seedTag: SEED_TAG, organizationId: ORG_ID, accounts, writes};
}

/**
 * @param {{writes: {data: Record<string, unknown>, path: string}[], accounts: object[]}} plan
 */
function assertPlanSafe(plan) {
  const emails = new Set();
  const phones = new Set();
  const uids = new Set();
  for (const account of plan.accounts) {
    if (!String(account.email).endsWith(EMAIL_DOMAIN)) {
      throw new Error(`refusing non-example.com email ${account.email}`);
    }
    if (emails.has(account.email) || phones.has(account.phoneNumber) || uids.has(account.uid)) {
      throw new Error(`duplicate fake account identity ${account.email}`);
    }
    emails.add(account.email);
    phones.add(account.phoneNumber);
    uids.add(account.uid);
    if (account.phoneNumber === "01508899965") {
      throw new Error("refusing a known real phone number");
    }
    if (HR_ROLES.has(account.role) && !account.companyUID && !account.companyId) {
      throw new Error(`HR account ${account.email} must belong to a company`);
    }
  }
  const serialized = JSON.stringify(plan);
  if (serialized.includes(PROD_PROJECT)) {
    throw new Error("plan must not mention the production project");
  }
  const nationalIds = new Set();
  for (const write of plan.writes) {
    assertNoSecretKeys(write.data);
    if (write.data.seedTag !== SEED_TAG || write.data.fake !== true) {
      throw new Error(`write ${write.path} is missing the seed tag`);
    }
    if (!write.path.includes("seed-fake-")) {
      throw new Error(`write path is outside the fake id prefix: ${write.path}`);
    }
    const nid = write.data.nationalityID;
    if (nid != null || write.kind === "delegate" || write.data.role === "delegate") {
      if (typeof nid !== "string" || !/^[0-9]{14}$/.test(nid)) {
        throw new Error(`delegate ${write.path} national id must be 14 ASCII digits`);
      }
      if (write.data.nationalId != null && write.data.nationalId !== nid) {
        throw new Error(`delegate ${write.path} nationalId does not match nationalityID`);
      }
      // Nested delegate docs are one per person; users/{uid} repeats the same id.
      if (write.kind === "delegate") {
        if (nationalIds.has(nid)) {
          throw new Error(`duplicate fake national id ${nid}`);
        }
        nationalIds.add(nid);
      }
    }
  }
}

const SECRET_KEY = /^(password|temporarypassword|temppassword|secret|token|accesstoken|refreshtoken)$/i;

/** @param {unknown} value @param {string} [at] */
function assertNoSecretKeys(value, at = "") {
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertNoSecretKeys(item, `${at}[${index}]`));
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    if (SECRET_KEY.test(key)) {
      throw new Error(`refusing to print or store secret field ${at}.${key}`);
    }
    assertNoSecretKeys(child, `${at}.${key}`);
  }
}

/** @param {Record<string, unknown>|null|undefined} data @return {boolean} */
function docDeletable(data) {
  return !!data
    && data.seedTag === SEED_TAG
    && data.fake === true;
}

/**
 * Auth delete only when the Auth email is still the planned @example.com
 * address and the Firestore doc is still tagged.
 * @param {{email: string, uid: string}} account
 * @param {Record<string, unknown>|null|undefined} doc
 * @param {string|null|undefined} authEmail
 * @return {{deleteDoc: boolean, deleteAuth: boolean, reason: string}}
 */
function decideUserCleanup(account, doc, authEmail) {
  const authOk = typeof authEmail === "string"
    && authEmail === account.email
    && authEmail.endsWith(EMAIL_DOMAIN)
    && String(account.uid).startsWith("seed-fake-");
  if (doc == null) {
    return {deleteDoc: false, deleteAuth: authOk, reason: authOk ? "doc-missing" : "missing"};
  }
  if (!docDeletable(doc)) return {deleteDoc: false, deleteAuth: false, reason: "not-tagged"};
  if (doc.email !== account.email) {
    return {deleteDoc: false, deleteAuth: false, reason: "email-diverged"};
  }
  return {deleteDoc: true, deleteAuth: authOk, reason: authOk ? "tagged" : "auth-mismatch"};
}

/** @param {{kind: string, path: string, data: Record<string, unknown>}[]} writes */
function cleanupOrder(writes) {
  const rank = {delegate: 0, user: 1, branch: 2, company: 3, organization: 4};
  return writes.slice().sort((a, b) => (rank[a.kind] ?? 9) - (rank[b.kind] ?? 9));
}

/**
 * @param {ReturnType<typeof buildPlan>} plan
 * @return {string}
 */
function formatDryRun(plan) {
  const lines = [
    "mode: dry-run",
    `project: ${ALLOWED_PROJECT}`,
    `seedTag: ${plan.seedTag}`,
    "writes:",
  ];
  for (const write of plan.writes) {
    const company = write.data.companyUID ? ` companyUID=${write.data.companyUID}` : "";
    const legacyCompany = write.data.companyId ? ` companyId=${write.data.companyId}` : "";
    const role = write.data.role ? ` role=${write.data.role}` : "";
    lines.push(`  ${write.kind} ${write.path}${role}${company}${legacyCompany}`);
  }
  lines.push("accounts (no passwords):");
  for (const account of plan.accounts) {
    const company = account.companyUID || "(none)";
    const legacyCompany = account.companyId ? ` companyId=${account.companyId}` : "";
    const shape = account.shape ? ` shape="${account.shape}"` : "";
    lines.push(
      `  ${account.role} ${account.email} phone=${account.phoneNumber} companyUID=${company}${legacyCompany} status=${account.status}${shape}`,
    );
  }
  lines.push("passwords: not generated in dry-run.");
  lines.push(`--apply writes them only to ${PASSWORD_FILE_NAME} and does not print them.`);
  const text = lines.join("\n");
  assertNoSecretKeys({text});
  return text;
}

/** @param {ReturnType<typeof buildPlan>} plan @return {string} */
function formatCleanupDryRun(plan) {
  const lines = [
    "mode: cleanup dry-run",
    `project: ${ALLOWED_PROJECT}`,
    `seedTag: ${plan.seedTag}`,
    "would delete only documents tagged with this seedTag and fake=true:",
  ];
  for (const write of cleanupOrder(plan.writes)) {
    lines.push(`  ${write.path}`);
  }
  lines.push("auth users: only seed-fake-* uids whose email is still the planned @example.com address.");
  return lines.join("\n");
}

/**
 * @param {{created: number, unchanged: number, rotated: number, passwordFile: string}} summary
 * @return {string}
 */
function formatApplySummary(summary) {
  assertNoSecretKeys(summary);
  return [
    "mode: apply",
    `project: ${ALLOWED_PROJECT}`,
    `auth created: ${summary.created}`,
    `auth unchanged: ${summary.unchanged}`,
    `auth rotated: ${summary.rotated}`,
    `passwords file: ${summary.passwordFile} (contents not shown)`,
  ].join("\n");
}

/**
 * @param {unknown} previous
 * @param {{email: string, uid: string, role: string, phoneNumber: string, status: string, password?: string}[]} updates
 */
function mergePasswordLedger(previous, updates) {
  /** @type {Map<string, object>} */
  const byEmail = new Map();
  const prevAccounts = previous && typeof previous === "object" && Array.isArray(previous.accounts)
    ? previous.accounts
    : [];
  for (const row of prevAccounts) {
    if (row && row.email) byEmail.set(row.email, row);
  }
  for (const update of updates) {
    const prev = byEmail.get(update.email);
    if (update.status === "unchanged") {
      const kept = prev && typeof prev.password === "string" ? prev.password : undefined;
      /** @type {Record<string, unknown>} */
      const row = {
        email: update.email,
        uid: update.uid,
        role: update.role,
        phoneNumber: update.phoneNumber,
        status: kept ? "unchanged" : "unchanged-unknown",
      };
      if (kept) row.password = kept;
      byEmail.set(update.email, row);
    } else {
      byEmail.set(update.email, {
        email: update.email,
        uid: update.uid,
        role: update.role,
        phoneNumber: update.phoneNumber,
        status: update.status,
        password: update.password,
      });
    }
  }
  return {
    project: ALLOWED_PROJECT,
    seedTag: SEED_TAG,
    note: "Local only. Fake @example.com accounts. Do not commit or share.",
    accounts: [...byEmail.values()],
  };
}

/**
 * @param {string} filePath
 * @param {unknown} ledger
 */
function writePasswordLedger(filePath, ledger) {
  assertPasswordFilePath(filePath);
  const body = `${JSON.stringify(ledger, null, 2)}\n`;
  if (body.includes(PROD_PROJECT)) {
    throw new Error("refusing to write a ledger that mentions production");
  }
  const tmp = `${filePath}.tmp`;
  fs.writeFileSync(tmp, body, {mode: 0o600, flag: "w"});
  fs.renameSync(tmp, filePath);
  fs.chmodSync(filePath, 0o600);
}

/** @param {string} filePath @return {unknown} */
function readPasswordLedger(filePath) {
  assertPasswordFilePath(filePath);
  if (!fs.existsSync(filePath)) return {accounts: []};
  const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
  if (!parsed || !Array.isArray(parsed.accounts)) {
    throw new Error("password ledger is not in the expected shape; refusing to overwrite it.");
  }
  return parsed;
}

/**
 * @param {{
 *   plan: ReturnType<typeof buildPlan>,
 *   db: {get: (path: string) => Promise<Record<string, unknown>|null>, set: (path: string, data: Record<string, unknown>, opts: {merge: boolean}) => Promise<void>},
 *   auth: {getUser: (uid: string) => Promise<{email?: string}|null>, createUser: (user: object) => Promise<void>, updateUser: (uid: string, patch: object) => Promise<void>},
 *   rotatePasswords: boolean,
 *   generatePassword: () => string,
 *   previousLedger: unknown,
 *   serverTimestamp: () => unknown,
 * }} deps
 */
async function applySeed(deps) {
  let created = 0;
  let unchanged = 0;
  let rotated = 0;
  /** @type {{email: string, uid: string, role: string, phoneNumber: string, status: string, password?: string}[]} */
  const updates = [];
  for (const write of deps.plan.writes) {
    assertNoSecretKeys(write.data);
    const existing = await deps.db.get(write.path);
    /** @type {Record<string, unknown>} */
    const data = {...write.data};
    if (existing) delete data.createdAt;
    else data.createdAt = deps.serverTimestamp();
    await deps.db.set(write.path, data, {merge: true});
  }
  for (const account of deps.plan.accounts) {
    let existing = null;
    try {
      existing = await deps.auth.getUser(account.uid);
    } catch (error) {
      if (!error || error.code !== "auth/user-not-found") throw error;
    }
    if (existing) {
      if (existing.email && existing.email !== account.email) {
        throw new Error(`uid ${account.uid} already belongs to another email; refusing to touch it.`);
      }
      if (deps.rotatePasswords) {
        const password = deps.generatePassword();
        await deps.auth.updateUser(account.uid, {
          email: account.email,
          displayName: account.displayName,
          password,
          emailVerified: true,
          disabled: false,
        });
        rotated += 1;
        updates.push({...publicIdentity(account), status: "rotated", password});
      } else {
        await deps.auth.updateUser(account.uid, {
          email: account.email,
          displayName: account.displayName,
          emailVerified: true,
          disabled: false,
        });
        unchanged += 1;
        updates.push({...publicIdentity(account), status: "unchanged"});
      }
    } else {
      const password = deps.generatePassword();
      try {
        await deps.auth.createUser({
          uid: account.uid,
          email: account.email,
          displayName: account.displayName,
          password,
          emailVerified: true,
          disabled: false,
        });
      } catch (error) {
        if (error && (error.code === "auth/email-already-exists" || error.code === "auth/uid-already-exists")) {
          throw new Error(`Auth already has ${account.email} under a different uid; refusing to touch it.`);
        }
        throw error;
      }
      created += 1;
      updates.push({...publicIdentity(account), status: "created", password});
    }
    if (typeof deps.onProgress === "function") {
      deps.onProgress(mergePasswordLedger(deps.previousLedger, updates));
    }
  }
  return {
    summary: {created, unchanged, rotated},
    ledger: mergePasswordLedger(deps.previousLedger, updates),
  };
}

/** @param {{email: string, uid: string, role: string, phoneNumber: string}} account */
function publicIdentity(account) {
  return {
    email: account.email,
    uid: account.uid,
    role: account.role,
    phoneNumber: account.phoneNumber,
  };
}

/**
 * @param {{
 *   plan: ReturnType<typeof buildPlan>,
 *   db: {get: (path: string) => Promise<Record<string, unknown>|null>, delete: (path: string) => Promise<void>},
 *   auth: {getUser: (uid: string) => Promise<{email?: string}|null>, deleteUser: (uid: string) => Promise<void>},
 * }} deps
 */
async function cleanupSeed(deps) {
  /** @type {string[]} */
  const deletedDocs = [];
  /** @type {{path: string, reason: string}[]} */
  const skippedDocs = [];
  /** @type {string[]} */
  const deletedAuth = [];
  /** @type {{email: string, reason: string}[]} */
  const skippedAuth = [];
  const accountsByUid = new Map(deps.plan.accounts.map((account) => [account.uid, account]));
  for (const write of cleanupOrder(deps.plan.writes)) {
    const data = await deps.db.get(write.path);
    if (write.kind === "user") {
      const account = accountsByUid.get(String(write.data.uid));
      let authUser = null;
      try {
        authUser = await deps.auth.getUser(account.uid);
      } catch (error) {
        if (!error || error.code !== "auth/user-not-found") throw error;
      }
      const decision = decideUserCleanup(account, data, authUser && authUser.email);
      if (decision.deleteAuth) {
        await deps.auth.deleteUser(account.uid);
        deletedAuth.push(account.email);
      } else if (authUser || decision.reason !== "missing") {
        skippedAuth.push({email: account.email, reason: decision.reason});
      }
      if (decision.deleteDoc) {
        await deps.db.delete(write.path);
        deletedDocs.push(write.path);
      } else {
        skippedDocs.push({path: write.path, reason: decision.reason});
      }
      continue;
    }
    if (!docDeletable(data)) {
      skippedDocs.push({path: write.path, reason: data ? "not-tagged" : "missing"});
      continue;
    }
    if (!write.path.includes("seed-fake-")) {
      skippedDocs.push({path: write.path, reason: "path-not-owned"});
      continue;
    }
    await deps.db.delete(write.path);
    deletedDocs.push(write.path);
  }
  return {deletedDocs, skippedDocs, deletedAuth, skippedAuth};
}

/** Rows safe to print: emails, roles, phones. No passwords. */
function publicCatalog(plan = buildPlan()) {
  return plan.accounts.map((account) => ({
    role: account.role,
    email: account.email,
    phoneNumber: account.phoneNumber,
    companyUID: account.companyUID || "",
    ...(account.companyId ? {companyId: account.companyId} : {}),
    status: account.status,
    ...(account.shape ? {shape: account.shape} : {}),
  }));
}

module.exports = {
  ALLOWED_PROJECT,
  PROD_PROJECT,
  SEED_TAG,
  ORG_ID,
  PASSWORD_FILE_NAME,
  COMPANIES,
  HR_ROLES,
  ROLE_SHAPE_ACCOUNTS,
  normalizeProject,
  assertDevProject,
  assertCredentialProject,
  assertLocalCredentialSignals,
  resolveCredentialProject,
  parseArgs,
  fakePhone,
  fakeNationalId,
  generatePassword,
  passwordFromBytes,
  assertPasswordFilePath,
  buildPlan,
  assertPlanSafe,
  assertNoSecretKeys,
  docDeletable,
  decideUserCleanup,
  cleanupOrder,
  formatDryRun,
  formatCleanupDryRun,
  formatApplySummary,
  mergePasswordLedger,
  writePasswordLedger,
  readPasswordLedger,
  applySeed,
  cleanupSeed,
  publicCatalog,
};
