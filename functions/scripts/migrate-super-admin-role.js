/**
 * One-off rewrite of role "super_admin" to "super-admin".
 *
 * Not imported by index.js. Not part of deploy. Do not run unless an operator
 * explicitly chooses to. Default mode prints the documents it would change
 * and writes nothing.
 *
 *   cd functions
 *   node scripts/migrate-super-admin-role.js
 *   node scripts/migrate-super-admin-role.js --apply
 *
 * Uses Application Default Credentials. Prints document paths and counts only.
 */

const admin = require("firebase-admin");

/**
 * True only for the exact legacy role string the app used to write.
 * Already-correct "super-admin" and unrelated values stay untouched.
 * @param {unknown} role
 * @return {boolean}
 */
function isLegacySuperAdminRole(role) {
  return typeof role === "string" && role.trim().toLowerCase() === "super_admin";
}

/**
 * @param {unknown} role
 * @return {unknown}
 */
function canonicalSuperAdminRole(role) {
  return isLegacySuperAdminRole(role) ? "super-admin" : role;
}

/**
 * @param {FirebaseFirestore.Query} query
 * @param {boolean} apply
 * @return {Promise<number>}
 */
async function rewriteQuery(query, apply) {
  const snap = await query.get();
  let count = 0;
  let batch = admin.firestore().batch();
  let pending = 0;

  for (const doc of snap.docs) {
    if (!isLegacySuperAdminRole(doc.get("role"))) continue;
    count += 1;
    console.log(`${apply ? "update" : "would update"} ${doc.ref.path}`);
    if (!apply) continue;
    batch.update(doc.ref, {role: "super-admin"});
    pending += 1;
    if (pending === 400) {
      await batch.commit();
      batch = admin.firestore().batch();
      pending = 0;
    }
  }

  if (apply && pending > 0) {
    await batch.commit();
  }
  return count;
}

async function main() {
  const apply = process.argv.includes("--apply");
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
  const db = admin.firestore();
  const users = await rewriteQuery(
    db.collection("users").where("role", "==", "super_admin"),
    apply,
  );
  const delegates = await rewriteQuery(
    db.collectionGroup("delegates").where("role", "==", "super_admin"),
    apply,
  );
  console.log(
    `${apply ? "updated" : "would update"} users=${users} delegates=${delegates}`,
  );
}

module.exports = {
  isLegacySuperAdminRole,
  canonicalSuperAdminRole,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "migration failed");
    process.exitCode = 1;
  });
}
