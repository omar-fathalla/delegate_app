/**
 * Create or update users/{uid} for the super-admin password login.
 *
 * Not imported by index.js. Not part of deploy. Do not run unless an operator
 * explicitly chooses to. Default mode prints the document it would write and
 * writes nothing. This script does not create a Firebase Auth user and it
 * never accepts or prints a password.
 *
 * Create the Auth user in the Firebase console first, then:
 *
 *   cd functions
 *   node scripts/create-super-admin-user.js \
 *     --uid AUTH_UID \
 *     --email person@example.com
 *   node scripts/create-super-admin-user.js \
 *     --uid AUTH_UID \
 *     --email person@example.com \
 *     --organization-uid ORG_ID \
 *     --organization-name "Org name" \
 *     --company-uid COMPANY_ID \
 *     --company-name "Company" \
 *     --apply
 *
 * Uses Application Default Credentials only when --apply is passed.
 */

const admin = require("firebase-admin");

const DEFAULT_PHONE = "01508899965";
const DEFAULT_DISPLAY_NAME = "Omar Fathalla";

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
 * Fields the app reads for staff password login. The document id is the uid.
 * No password is stored.
 *
 * @param {{
 *   uid: string,
 *   email: string,
 *   phoneNumber?: string,
 *   displayName?: string,
 *   organizationUID?: string,
 *   organizationName?: string,
 *   companyUID?: string,
 *   companyName?: string,
 * }} input
 * @return {Record<string, string|boolean>}
 */
function buildSuperAdminUserDoc(input) {
  const uid = String(input.uid || "").trim();
  const email = String(input.email || "").trim();
  if (!uid) throw new Error("uid is required");
  if (!email || !email.includes("@")) throw new Error("email is required");

  const phoneNumber = String(input.phoneNumber || DEFAULT_PHONE).trim();
  const displayName = String(input.displayName || DEFAULT_DISPLAY_NAME).trim();
  /** @type {Record<string, string|boolean>} */
  const doc = {
    uid,
    email,
    phoneNumber,
    phone: phoneNumber,
    role: "super-admin",
    displayName,
    fullName: displayName,
    isActive: true,
  };

  const optional = {
    organizationUID: input.organizationUID,
    organizationName: input.organizationName,
    companyUID: input.companyUID,
    companyName: input.companyName,
  };
  for (const [key, value] of Object.entries(optional)) {
    const trimmed = value == null ? "" : String(value).trim();
    if (trimmed) doc[key] = trimmed;
  }
  return doc;
}

/**
 * @param {Record<string, string|boolean>} args
 * @return {{uid: string, doc: Record<string, string|boolean>}}
 */
function docFromArgs(args) {
  const uid = String(args.uid || "").trim();
  const doc = buildSuperAdminUserDoc({
    uid,
    email: String(args.email || ""),
    phoneNumber: args.phone ? String(args.phone) : undefined,
    displayName: args["display-name"] ? String(args["display-name"]) : undefined,
    organizationUID: args["organization-uid"] ?
      String(args["organization-uid"]) :
      undefined,
    organizationName: args["organization-name"] ?
      String(args["organization-name"]) :
      undefined,
    companyUID: args["company-uid"] ? String(args["company-uid"]) : undefined,
    companyName: args["company-name"] ? String(args["company-name"]) : undefined,
  });
  return {uid, doc};
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const {uid, doc} = docFromArgs(args);
  const apply = args.apply === true;
  console.log(`${apply ? "write" : "would write"} users/${uid}`);
  console.log(JSON.stringify(doc, null, 2));
  console.log("This script does not create a Firebase Auth user.");
  if (!apply) return;

  if (admin.apps.length === 0) admin.initializeApp();
  await admin.firestore().collection("users").doc(uid).set(doc, {merge: true});
  console.log(`updated users/${uid}`);
}

module.exports = {
  parseArgs,
  buildSuperAdminUserDoc,
  docFromArgs,
  DEFAULT_PHONE,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "setup failed");
    process.exitCode = 1;
  });
}
