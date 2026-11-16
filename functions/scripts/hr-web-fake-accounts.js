/**
 * Create or delete FAKE HR-web test accounts on Firebase project tashil-dev.
 *
 * Not imported by index.js. Not part of deploy. Dry-run is the default.
 * Refuses every project except tashil-dev, including practice-firebase-72df1.
 * --apply also refuses unless the credentials' project is tashil-dev.
 *
 * Passwords are generated at runtime and written only to
 * scripts/.hr-web-fake-accounts.local.json. They are never printed.
 *
 *   cd functions
 *   node scripts/hr-web-fake-accounts.js --project tashil-dev
 *   node scripts/hr-web-fake-accounts.js --project tashil-dev --apply
 *   node scripts/hr-web-fake-accounts.js --project tashil-dev --cleanup
 *   node scripts/hr-web-fake-accounts.js --project tashil-dev --cleanup --apply
 */

const fs = require("fs");
const path = require("path");
const lib = require("./hr-web-fake-accounts-lib");

const PASSWORD_FILE = path.join(__dirname, lib.PASSWORD_FILE_NAME);

/**
 * @param {NodeJS.ProcessEnv} env
 * @return {Promise<string>}
 */
async function lookupCredentialProject(env) {
  return lib.resolveCredentialProject({
    env,
    readFile: (filePath) => fs.readFileSync(filePath, "utf8"),
    lookup: async () => {
      const {GoogleAuth} = require("google-auth-library");
      const auth = new GoogleAuth();
      return auth.getProjectId();
    },
  });
}

/**
 * @param {import("firebase-admin")} admin
 */
function adapters(admin) {
  const db = admin.firestore();
  const auth = admin.auth();
  return {
    db: {
      get: async (docPath) => {
        const snap = await db.doc(docPath).get();
        return snap.exists ? snap.data() : null;
      },
      set: async (docPath, data, opts) => {
        lib.assertNoSecretKeys(data);
        await db.doc(docPath).set(data, opts);
      },
      delete: async (docPath) => {
        await db.doc(docPath).delete();
      },
    },
    auth: {
      getUser: async (uid) => {
        try {
          const user = await auth.getUser(uid);
          return {email: user.email || "", displayName: user.displayName};
        } catch (error) {
          if (error && error.code === "auth/user-not-found") return null;
          throw error;
        }
      },
      createUser: async (user) => {
        await auth.createUser(user);
      },
      updateUser: async (uid, patch) => {
        await auth.updateUser(uid, patch);
      },
      deleteUser: async (uid) => {
        await auth.deleteUser(uid);
      },
    },
    serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * @param {string[]} argv
 * @param {NodeJS.ProcessEnv} [env]
 */
async function main(argv, env = process.env, deps = {}) {
  const args = lib.parseArgs(argv);
  const project = lib.assertDevProject(args.project);
  const readFile = deps.readFile || ((filePath) => fs.readFileSync(filePath, "utf8"));
  lib.assertLocalCredentialSignals(env, readFile);
  const plan = lib.buildPlan();

  if (!args.apply) {
    const text = args.cleanup ? lib.formatCleanupDryRun(plan) : lib.formatDryRun(plan);
    console.log(text);
    return {mode: args.cleanup ? "cleanup-dry-run" : "dry-run", project};
  }

  const credentialProject = await (deps.lookupCredentialProject || lookupCredentialProject)(env);
  lib.assertCredentialProject(credentialProject);
  if (lib.normalizeProject(credentialProject) !== project) {
    throw new Error("credentials project does not match --project.");
  }

  const admin = deps.admin || require("firebase-admin");
  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: project,
    });
  }
  const appProject = admin.app().options.projectId;
  lib.assertDevProject(appProject);
  lib.assertCredentialProject(appProject);

  const io = adapters(admin);
  if (args.cleanup) {
    const report = await lib.cleanupSeed({plan, db: io.db, auth: io.auth});
    lib.assertNoSecretKeys(report);
    console.log(JSON.stringify({
      mode: "cleanup",
      project,
      seedTag: plan.seedTag,
      deletedDocs: report.deletedDocs.length,
      deletedAuth: report.deletedAuth.length,
      skippedDocs: report.skippedDocs,
      skippedAuth: report.skippedAuth,
    }, null, 2));
    return report;
  }

  const passwordFile = deps.passwordFile || PASSWORD_FILE;
  lib.assertPasswordFilePath(passwordFile);
  const previousLedger = lib.readPasswordLedger(passwordFile);
  const result = await lib.applySeed({
    plan,
    db: io.db,
    auth: io.auth,
    rotatePasswords: args.rotatePasswords,
    generatePassword: lib.generatePassword,
    previousLedger,
    serverTimestamp: io.serverTimestamp,
    onProgress: (ledger) => lib.writePasswordLedger(passwordFile, ledger),
  });
  lib.writePasswordLedger(passwordFile, result.ledger);
  const summary = {...result.summary, passwordFile};
  console.log(lib.formatApplySummary(summary));
  return summary;
}

module.exports = {main, PASSWORD_FILE};

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    const message = error instanceof Error ? error.message : "seed failed";
    console.error(message);
    process.exitCode = 1;
  });
}
