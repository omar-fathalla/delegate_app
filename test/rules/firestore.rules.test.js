/**
 * Firestore rules tests for the tightened ruleset.
 *
 * Runs against the local emulator only (project demo-tashil-rules).
 * Nothing here talks to practice-firebase-72df1.
 *
 * Staff authority comes from users/{uid}.role. Legacy spellings still grant
 * access. A custom claim does not. Delegate authority comes from the
 * delegateLoginV2 token (role, delegateIds, org, company, phones).
 */
const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

const PROJECT_ID = "demo-tashil-rules";

const DELEGATE = {
  role: "delegate",
  delegateId: "del-1",
  delegateIds: ["del-1", "del-2"],
  orgId: "o1",
  companyId: "c1",
  phones: ["01011111111", "+201011111111"],
  firebase: {sign_in_provider: "custom"},
};

describe("firestore tightened rules", () => {
  /** @type {import("@firebase/rules-unit-testing").RulesTestEnvironment} */
  let testEnv;

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
      },
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const users = {
        super: {role: "super-admin", organizationUID: "o1", companyUID: "c1"},
        legacy: {role: "super_admin", organizationUID: "o1", companyUID: "c1"},
        compact: {role: "superadmin", organizationUID: "o1", companyUID: "c1"},
        orgadmin: {role: "organization-admin", organizationUID: "o1"},
        orglegacy: {role: "organization_admin", organizationUID: "o1"},
        org2: {role: "organization-admin", organizationUID: "o2"},
        comp: {role: "company-admin", organizationUID: "o1", companyUID: "c1"},
        comp2: {role: "company-admin", organizationUID: "o1", companyUID: "c2"},
        hr: {role: "hr", organizationUID: "o1", companyUID: "c1"},
        hrlegacy: {role: "company_hr", organizationUID: "o1", companyUID: "c1"},
        marketing: {role: "marketing", organizationUID: "o1", companyUID: "c1"},
        tech: {role: "technical_support", organizationUID: "o1"},
        accountant: {role: "accountant", organizationUID: "o1", companyUID: "c1"},
        owner: {
          role: "delegate",
          status: "approved",
          organizationUID: "o1",
          companyUID: "c1",
          uid: "owner",
          phoneNumber: "01022222222",
          email: "owner@example.com",
          displayName: "Owner",
        },
        victim: {role: "delegate", organizationUID: "o1", companyUID: "c1", status: "approved"},
      };
      for (const [id, data] of Object.entries(users)) {
        await db.doc(`users/${id}`).set(data);
      }
      await db.doc("organizations/o1").set({name: "Org 1", admins: 1});
      await db.doc("organizations/o2").set({name: "Org 2", admins: 1});
      await db.doc("organizations/o1/companies/c1").set({name: "Company 1"});
      await db.doc("organizations/o1/companies/c2").set({name: "Company 2"});
      await db.doc("organizations/o2/companies/c9").set({name: "Company 9"});
      await db.doc("organizations/o1/companies/c1/delegates/del-1").set({
        phoneNumber: "01011111111",
        organizationUID: "o1",
        companyUID: "c1",
        role: "delegate",
        status: "active",
        uid: "del-1",
      });
      await db.doc("organizations/o1/companies/c2/delegates/stranger").set({
        phoneNumber: "01033333333",
        organizationUID: "o1",
        companyUID: "c2",
        role: "delegate",
        status: "active",
      });
      await db.doc("organizations/o2/companies/c9/delegates/other").set({
        phoneNumber: "01099999999",
        organizationUID: "o2",
        companyUID: "c9",
        role: "delegate",
        status: "active",
      });
      await db.doc("organizations/o1/tasks/task1").set({
        companyId: "c1",
        assignedTo: "del-1",
        title: "Own",
      });
      await db.doc("organizations/o2/tasks/task2").set({
        companyId: "c9",
        assignedTo: "other",
        title: "Foreign",
      });
      await db.doc("invites/secret").set({status: "pending", organizationId: "o1"});
      await db.doc("notifications/n1").set({
        delegateUid: "del-1",
        title: "Hello",
        isRead: false,
        organizationId: "o1",
        companyId: "c1",
      });
      await db.doc("notifications/n2").set({
        delegateUid: "other",
        title: "Secret",
        isRead: false,
        organizationId: "o2",
        companyId: "c9",
      });
      await db.doc("attendance_logs/a1").set({
        delegateId: "del-1",
        userId: "del-1",
        organizationId: "o1",
        companyId: "c1",
      });
      await db.doc("attendance_logs/a2").set({
        delegateId: "other",
        userId: "other",
        organizationId: "o2",
        companyId: "c9",
      });
      await db.doc("security_audit_logs/s1").set({
        delegateUid: "del-1",
        organizationUID: "o1",
        companyUID: "c1",
      });
      await db.doc("security_audit_logs/s2").set({
        delegateUid: "other",
        organizationUID: "o2",
        companyUID: "c9",
      });
      await db.doc("device_unbind_requests/u1").set({
        delegateUid: "del-1",
        organizationUID: "o1",
        companyUID: "c1",
        status: "pending",
      });
      await db.doc("device_unbind_requests/u2").set({
        delegateUid: "other",
        organizationUID: "o2",
        companyUID: "c9",
        status: "pending",
      });
      await db.doc("penalties/p1").set({
        companyId: "c1",
        companyUID: "c1",
        organizationUID: "o1",
        targetDelegateId: "del-1",
      });
      await db.doc("penalties/p2").set({
        companyId: "c9",
        companyUID: "c9",
        organizationUID: "o2",
        targetDelegateId: "other",
      });
      await db.doc("monthly_collections/2026-01").set({period: "2026-01"});
      await db.doc("mail/existing").set({to: ["admin@example.com"]});
      await db.doc("delegate_login_rate_limits/secret").set({failCount: 1});
      await db.doc("staff_login_rate_limits/secret").set({failCount: 1});
    });
  });

  /**
   * @param {string} uid
   * @param {Record<string, unknown>=} token
   */
  function dbFor(uid, token = {}) {
    return testEnv.authenticatedContext(uid, token).firestore();
  }

  function anonDb() {
    return testEnv.authenticatedContext("anon-user", {
      firebase: {sign_in_provider: "anonymous"},
    }).firestore();
  }

  function guestDb() {
    return testEnv.unauthenticatedContext().firestore();
  }

  test("super-admin can create and delete organizations", async () => {
    const db = dbFor("super");
    await assertSucceeds(db.doc("organizations/created").set({name: "Created"}));
    await assertSucceeds(db.doc("organizations/o2").delete());
  });

  test("legacy super_admin and superadmin are treated as super-admin", async () => {
    await assertSucceeds(dbFor("legacy").doc("organizations/from-legacy").set({name: "Legacy"}));
    await assertSucceeds(dbFor("compact").doc("organizations/from-compact").set({name: "Compact"}));
  });

  test("a custom claim does not grant super-admin access", async () => {
    const db = dbFor("delegate-claim", {role: "super-admin"});
    await assertFails(db.doc("organizations/claimed").set({name: "No"}));
  });

  test("organization-admin can update only their organization", async () => {
    const db = dbFor("orgadmin");
    await assertSucceeds(db.doc("organizations/o1").update({name: "Renamed"}));
    await assertFails(db.doc("organizations/o2").update({name: "Stolen"}));
    await assertFails(db.doc("organizations/fresh").set({name: "Fresh"}));
  });

  test("legacy organization_admin is accepted and stays inside the org", async () => {
    const db = dbFor("orglegacy");
    await assertSucceeds(db.doc("organizations/o1").update({name: "Legacy org"}));
    await assertFails(db.doc("organizations/o2").delete());
  });

  test("company-admin can read own-company delegates and not another company", async () => {
    const db = dbFor("comp");
    await assertSucceeds(db.doc("organizations/o1/companies/c1/delegates/del-1").get());
    await assertFails(db.doc("organizations/o1/companies/c2/delegates/stranger").get());
    await assertFails(db.doc("organizations/o2/companies/c9/delegates/other").get());
  });

  test("staff token without a delegateId claim cannot read a delegate doc with no uid field", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("organizations/o1/companies/c2/delegates/no-uid").set({
        phoneNumber: "01000000000",
        organizationUID: "o1",
        companyUID: "c2",
        role: "delegate",
        status: "active",
      });
      await db.doc("organizations/o1/companies/c1/delegates/no-uid-own").set({
        phoneNumber: "01000000001",
        organizationUID: "o1",
        companyUID: "c1",
        role: "delegate",
        status: "active",
      });
    });
    const companyAdmin = dbFor("comp"); // c1 admin, no delegateId claim
    await assertFails(companyAdmin.doc("organizations/o1/companies/c2/delegates/no-uid").get());
    // Own-company read still works via company scope, not ownsDelegateId.
    await assertSucceeds(companyAdmin.doc("organizations/o1/companies/c1/delegates/no-uid-own").get());
    const otherCompanyAdmin = dbFor("comp2");
    await assertFails(otherCompanyAdmin.doc("organizations/o1/companies/c1/delegates/no-uid-own").get());
  });

  test("hr and legacy company_hr can read only their company's attendance", async () => {
    for (const uid of ["hr", "hrlegacy"]) {
      const db = dbFor(uid);
      await assertSucceeds(db.collection("attendance_logs").where("companyId", "==", "c1").get());
      await assertFails(db.collection("attendance_logs").where("companyId", "==", "c9").get());
    }
  });

  test("marketing cannot send mail or update an organization", async () => {
    const db = dbFor("marketing");
    await assertFails(db.collection("mail").add({to: ["a@b.c"]}));
    await assertFails(db.doc("organizations/o1").update({name: "Marketing"}));
    await assertSucceeds(db.doc("organizations/o1").get());
  });

  test("technical support can read security logs and cannot delete an organization", async () => {
    const db = dbFor("tech");
    await assertSucceeds(db.collection("security_audit_logs").get());
    await assertFails(db.doc("organizations/o1").delete());
  });

  test("accountant can read monthly collections and cannot delete an organization", async () => {
    const db = dbFor("accountant");
    await assertSucceeds(db.doc("monthly_collections/2026-01").get());
    await assertFails(db.doc("organizations/o1").delete());
  });

  test("a delegate token can read own profiles and not another company", async () => {
    const db = dbFor("del-1", DELEGATE);
    await assertSucceeds(db.doc("organizations/o1/companies/c1/delegates/del-1").get());
    await assertFails(db.doc("organizations/o1/companies/c2/delegates/stranger").get());
    await assertFails(db.doc("organizations/o2/companies/c9/delegates/other").get());
    await assertFails(db.doc("organizations/stolen").set({name: "No"}));
  });

  test("a delegate phone query is allowed and an unfiltered delegate list is not", async () => {
    const db = dbFor("del-1", DELEGATE);
    await assertSucceeds(
      db.collectionGroup("delegates").where("phoneNumber", "==", "01011111111").get(),
    );
    await assertFails(db.collectionGroup("delegates").get());
  });

  test("the owner cannot change role, status, organization, company, or uid", async () => {
    const db = dbFor("owner");
    await assertFails(db.doc("users/owner").update({role: "super-admin"}));
    await assertFails(db.doc("users/owner").update({status: "suspended"}));
    await assertFails(db.doc("users/owner").update({organizationUID: "o2"}));
    await assertFails(db.doc("users/owner").update({companyUID: "c9"}));
    await assertFails(db.doc("users/owner").update({uid: "someone-else"}));
    await assertSucceeds(db.doc("users/owner").update({displayName: "New name"}));
  });

  test("a signed-in user cannot create a super-admin document for someone else", async () => {
    const db = dbFor("owner");
    await assertFails(db.doc("users/planted").set({
      role: "super-admin",
      organizationUID: "o1",
      companyUID: "c1",
    }));
  });

  test("super-admin can grant super-admin and cannot write the legacy spelling", async () => {
    const db = dbFor("super");
    await assertSucceeds(db.doc("users/victim").update({role: "super-admin"}));
    await assertFails(db.doc("users/victim").update({role: "super_admin"}));
  });

  test("anonymous sign-in is denied on users, organizations, notifications, and attendance", async () => {
    const db = anonDb();
    await assertFails(db.doc("users/super").get());
    await assertFails(db.doc("organizations/o1").get());
    await assertFails(db.doc("notifications/n1").get());
    await assertFails(db.doc("attendance_logs/a1").get());
    await assertFails(db.collection("attendance_logs").add({
      delegateId: "anon-user",
      organizationId: "o1",
      companyId: "c1",
    }));
  });

  test("unauthenticated clients are denied and can still get one invite by id", async () => {
    const db = guestDb();
    await assertFails(db.doc("users/super").get());
    await assertFails(db.collection("users").get());
    await assertFails(db.doc("organizations/o1").get());
    await assertFails(db.doc("notifications/n1").get());
    await assertFails(db.collection("attendance_logs").get());
    await assertFails(db.collection("invites").get());
    await assertSucceeds(db.doc("invites/secret").get());
    await assertFails(db.doc("users/planted").set({role: "super-admin"}));
  });

  test("company-admin cannot cross into another company's security, devices, or penalties", async () => {
    const db = dbFor("comp");
    await assertSucceeds(db.collection("security_audit_logs").where("companyUID", "==", "c1").get());
    await assertFails(db.collection("security_audit_logs").where("companyUID", "==", "c9").get());
    await assertSucceeds(db.collection("device_unbind_requests").where("companyUID", "==", "c1").get());
    await assertFails(db.collection("device_unbind_requests").where("companyUID", "==", "c9").get());
    await assertSucceeds(db.collection("penalties").where("companyId", "==", "c1").get());
    await assertFails(db.collection("penalties").where("companyId", "==", "c9").get());
    await assertFails(db.collection("users").get());
    await assertSucceeds(db.collection("users").where("companyUID", "==", "c1").get());
  });

  test("notifications are readable by the recipient, not writable as a whole, and not world-deletable", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    await assertSucceeds(delegate.doc("notifications/n1").get());
    await assertFails(delegate.doc("notifications/n2").get());
    await assertSucceeds(delegate.doc("notifications/n1").update({isRead: true}));
    await assertFails(delegate.doc("notifications/n1").update({title: "changed"}));
    await assertFails(delegate.doc("notifications/n1").delete());
    await assertSucceeds(dbFor("super").doc("notifications/n1").delete());
  });

  test("fcm tokens are limited to the owner", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    await assertSucceeds(delegate.doc("fcm_tokens/del-1").set({token: "abc"}));
    await assertFails(delegate.doc("fcm_tokens/other").set({token: "nope"}));
    await assertFails(dbFor("comp").doc("fcm_tokens/del-1").get());
  });

  test("mail can be created by a company admin and not by a delegate", async () => {
    await assertSucceeds(dbFor("comp").collection("mail").add({to: ["new@example.com"]}));
    await assertFails(dbFor("del-1", DELEGATE).collection("mail").add({to: ["new@example.com"]}));
    await assertFails(dbFor("comp").doc("mail/existing").get());
    // mail holds set-password links: no client reads, not even super-admin.
    await assertFails(dbFor("super").doc("mail/existing").get());
  });

  test("delegate can stamp checkOutTime on own check-in (fix2 denormalize)", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    // a1 is seeded as del-1's own check-in in beforeEach
    await assertSucceeds(delegate.doc("attendance_logs/a1").update({
      checkOutTime: new Date(),
      checkOutDocId: "own-out",
      checkOutLocation: { latitude: 1, longitude: 2 },
    }));
    // a2 belongs to another delegate/org
    await assertFails(delegate.doc("attendance_logs/a2").update({
      checkOutTime: new Date(),
    }));
  });

  test("attendance creates are limited to the delegate's own org profile", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    await assertSucceeds(delegate.collection("attendance_logs").add({
      delegateId: "del-1",
      userId: "del-1",
      organizationId: "o1",
      companyId: "c1",
      type: "check_in",
    }));
    await assertFails(delegate.collection("attendance_logs").add({
      delegateId: "other",
      userId: "other",
      organizationId: "o2",
      companyId: "c9",
      type: "check_in",
    }));
    await assertFails(guestDb().collection("attendance_logs").add({
      delegateId: "del-1",
      organizationId: "o1",
      companyId: "c1",
    }));
  });

  test("tasks stay inside the delegate organization", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    await assertSucceeds(
      delegate.collection("organizations/o1/tasks").where("companyId", "==", "c1").get(),
    );
    await assertFails(delegate.doc("organizations/o2/tasks/task2").get());
  });

  test("device unbind creates are pending requests for the caller and cannot be deleted", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    await assertSucceeds(delegate.collection("device_unbind_requests").add({
      delegateUid: "del-1",
      organizationUID: "o1",
      companyUID: "c1",
      status: "pending",
    }));
    await assertFails(delegate.collection("device_unbind_requests").add({
      delegateUid: "other",
      organizationUID: "o2",
      companyUID: "c9",
      status: "pending",
    }));
    await assertFails(delegate.doc("device_unbind_requests/u1").delete());
    await assertSucceeds(dbFor("comp").doc("device_unbind_requests/u1").update({
      status: "approved",
      resolvedBy: "comp",
    }));
    await assertFails(dbFor("comp").doc("device_unbind_requests/u2").update({status: "approved"}));
    await assertFails(dbFor("org2").doc("device_unbind_requests/u1").update({status: "approved"}));
    await assertFails(delegate.doc("device_unbind_requests/u1").update({status: "approved"}));
    await assertSucceeds(dbFor("comp").collection("device_unbind_requests").add({
      delegateUid: "del-1",
      organizationUID: "o1",
      companyUID: "c1",
      status: "approved",
    }));
    await assertFails(delegate.collection("device_unbind_requests").add({
      delegateUid: "del-1",
      organizationUID: "o1",
      companyUID: "c1",
      status: "approved",
    }));
    await assertFails(dbFor("comp2").collection("device_unbind_requests").add({
      delegateUid: "del-1",
      organizationUID: "o1",
      companyUID: "c1",
      status: "approved",
    }));
  });

  test("clients cannot write device bindings or the mirrored delegate fields", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    const companyAdmin = dbFor("comp");
    await assertFails(delegate.doc("deviceBindings/del-1").set({deviceId: "phone-a"}));
    await assertFails(companyAdmin.doc("deviceBindings/del-1").get());
    await assertFails(dbFor("super").doc("deviceBindings/del-1").set({deviceId: "phone-a"}));
    await assertFails(
      delegate.doc("organizations/o1/companies/c1/delegates/del-1").update({
        boundDeviceId: "phone-a",
      }),
    );
    await assertFails(
      companyAdmin.doc("organizations/o1/companies/c1/delegates/del-1").update({
        boundDeviceId: "",
        isDeviceLocked: false,
      }),
    );
    // Mohamed 2026-11-10 14:00: only super-admin / tech may suspend.
    await assertFails(
      companyAdmin.doc("organizations/o1/companies/c1/delegates/del-1").update({
        status: "suspended",
      }),
    );
    await assertFails(
      companyAdmin.doc("organizations/o1/companies/c1/delegates/del-1").update({
        fullName: "Updated Name",
      }),
    );
    await assertSucceeds(
      dbFor("super").doc("organizations/o1/companies/c1/delegates/del-1").update({
        status: "suspended",
      }),
    );
  });

  test("clients cannot read or write billing_cycles", async () => {
    const orgAdmin = dbFor("orgadmin");
    const companyAdmin = dbFor("comp");
    const superAdmin = dbFor("super");
    await assertFails(orgAdmin.doc("billing_cycles/o1_2027_H1").set({state: "running"}));
    await assertFails(companyAdmin.doc("billing_cycles/o1_2027_H1").get());
    await assertFails(superAdmin.doc("billing_cycles/o1_2027_H1").set({state: "done"}));
    await assertFails(superAdmin.doc("billing_cycles/o1_2027_H1").get());
  });

  test("security logs can be created by the delegate and deleted only inside the company", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    await assertSucceeds(delegate.collection("security_audit_logs").add({
      delegateUid: "del-1",
      organizationUID: "o1",
      companyUID: "c1",
      violationType: "fake_gps",
    }));
    await assertFails(delegate.doc("security_audit_logs/s1").delete());
    await assertSucceeds(dbFor("comp").doc("security_audit_logs/s1").delete());
    await assertFails(dbFor("comp").doc("security_audit_logs/s2").delete());
  });

  test("rate-limit collections are denied even for super-admin", async () => {
    const db = dbFor("super");
    await assertFails(db.doc("delegate_login_rate_limits/secret").get());
    await assertFails(db.doc("staff_login_rate_limits/secret").get());
    await assertFails(guestDb().doc("delegate_login_rate_limits/secret").get());
  });

  test("otp-pending delegate can read own profile but not create attendance", async () => {
    const pending = {
      ...DELEGATE,
      otp_required: true,
      otp_verified: false,
    };
    const db = dbFor("del-1", pending);
    await assertSucceeds(db.doc("organizations/o1/companies/c1/delegates/del-1").get());
    await assertSucceeds(
      db.collectionGroup("delegates").where("phoneNumber", "==", "01011111111").get(),
    );
    await assertFails(db.collection("attendance_logs").add({
      delegateId: "del-1",
      userId: "del-1",
      organizationId: "o1",
      companyId: "c1",
    }));
    await assertFails(db.doc("attendance_logs/a1").get());
    await assertFails(db.doc("notifications/n1").get());
    await assertFails(db.doc("config/delegate_auth").get());
    await assertFails(db.doc("config/delegate_auth").set({otpEnforcementEnabled: false}));
  });

  test("otp-verified delegate regains attendance access under enforcement", async () => {
    const verified = {
      ...DELEGATE,
      otp_required: true,
      otp_verified: true,
    };
    const db = dbFor("del-1", verified);
    await assertSucceeds(db.doc("organizations/o1/companies/c1/delegates/del-1").get());
    await assertSucceeds(db.doc("attendance_logs/a1").get());
    await assertSucceeds(db.collection("attendance_logs").add({
      delegateId: "del-1",
      userId: "del-1",
      organizationId: "o1",
      companyId: "c1",
    }));
    await assertSucceeds(db.doc("notifications/n1").get());
  });

  test("delegate token without otp_required keeps working (enforcement off)", async () => {
    const db = dbFor("del-1", DELEGATE);
    await assertSucceeds(db.doc("organizations/o1/companies/c1/delegates/del-1").get());
    await assertSucceeds(db.doc("attendance_logs/a1").get());
    await assertSucceeds(db.collection("attendance_logs").add({
      delegateId: "del-1",
      userId: "del-1",
      organizationId: "o1",
      companyId: "c1",
    }));
  });

  test("staff access is unchanged when a delegate token is otp-pending", async () => {
    const db = dbFor("comp");
    await assertSucceeds(db.doc("organizations/o1/companies/c1/delegates/del-1").get());
    await assertSucceeds(db.collection("attendance_logs").where("companyId", "==", "c1").get());
  });

  test("signed-in clients can read only config/subscriptions", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("config/subscriptions").set({advanceRenewalEnabled: true, advanceRenewalDays: 60});
      await db.doc("config/delegate_auth").set({otpEnforcementEnabled: false});
    });
    const hr = dbFor("hr");
    await assertSucceeds(hr.doc("config/subscriptions").get());
    await assertFails(hr.doc("config/subscriptions").set({advanceRenewalEnabled: false}));
    await assertFails(hr.doc("config/delegate_auth").get());
    await assertFails(guestDb().doc("config/subscriptions").get());
  });

  test("HR can list company leave_requests by status", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("leave_requests/l-c1-pending").set({
        companyUID: "c1",
        organizationUID: "o1",
        delegateUid: "del-1",
        status: "pending",
      });
      await db.doc("leave_requests/l-c2-pending").set({
        companyUID: "c2",
        organizationUID: "o1",
        delegateUid: "del-9",
        status: "pending",
      });
    });
    await assertSucceeds(
      dbFor("hr").collection("leave_requests").where("companyUID", "==", "c1").where("status", "==", "pending").get(),
    );
    await assertFails(
      dbFor("hr").collection("leave_requests").where("companyUID", "==", "c2").where("status", "==", "pending").get(),
    );
    await assertSucceeds(
      dbFor("comp2").collection("leave_requests").where("companyUID", "==", "c2").where("status", "==", "pending").get(),
    );
  });


  describe("task images and sender-only edit/delete", () => {
    const seedSent = async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("organizations/o1/tasks/sent").set({
          companyId: "c1",
          assignedTo: "del-1",
          createdBy: "comp",
          title: "Sent",
          description: "Body",
          status: "pending",
          imageUrl: "https://example.com/a.jpg",
          imagePath: "organizations/o1/task_images/comp/a.jpg",
        });
      });
    };

    test("sender can create a task with an image in their own folder", async () => {
      const comp = dbFor("comp");
      await assertSucceeds(comp.doc("organizations/o1/tasks/new1").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: "task_images/c1/comp/task_comp_x.jpg",
      }));
      await assertFails(comp.doc("organizations/o1/tasks/new2").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: "task_images/c1/hr/task_hr_x.jpg",
      }));
      await assertFails(comp.doc("organizations/o1/tasks/new3").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: "task_images/c2/comp/task_comp_x.jpg",
      }));
      await assertFails(comp.doc("organizations/o1/tasks/new4").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: "organizations/o1/task_images/comp/x.jpg",
      }));
      await assertFails(comp.doc("organizations/o1/tasks/new5").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: "task_images/c1/comp/task_comp_2_x.jpg",
      }));
    });

    test("sender can create a task with up to 3 imagePaths; a 4th is rejected", async () => {
      const comp = dbFor("comp");
      const paths = [
        "task_images/c1/comp/task_comp_a.jpg",
        "task_images/c1/comp/task_comp_b.jpg",
        "task_images/c1/comp/task_comp_c.jpg",
      ];
      await assertSucceeds(comp.doc("organizations/o1/tasks/new3imgs").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: paths[0],
        imagePaths: paths,
      }));
      await assertFails(comp.doc("organizations/o1/tasks/new4imgs").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: paths[0],
        imagePaths: [...paths, "task_images/c1/comp/task_comp_d.jpg"],
      }));
      await assertFails(comp.doc("organizations/o1/tasks/newBadList").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: paths[0],
        imagePaths: [paths[0], "task_images/c1/hr/task_hr_x.jpg"],
      }));
      await assertFails(comp.doc("organizations/o1/tasks/newInconsistent").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: paths[1],
        imagePaths: paths,
      }));
    });

    test("only the sender edits content; other staff can still change status", async () => {
      await seedSent();
      const comp = dbFor("comp");
      const hr = dbFor("hr");
      await assertSucceeds(comp.doc("organizations/o1/tasks/sent").update({
        description: "Edited", editedAt: new Date(),
      }));
      await assertFails(hr.doc("organizations/o1/tasks/sent").update({description: "Hijack"}));
      await assertFails(hr.doc("organizations/o1/tasks/sent").update({imageUrl: "https://evil"}));
      await assertSucceeds(hr.doc("organizations/o1/tasks/sent").update({status: "inProgress"}));
    });

    test("delegate reads the image and updates status but cannot edit or delete", async () => {
      await seedSent();
      const delegate = dbFor("del-1", DELEGATE);
      await assertSucceeds(delegate.doc("organizations/o1/tasks/sent").get());
      await assertSucceeds(delegate.doc("organizations/o1/tasks/sent").update({
        status: "completed", completedBy: "del-1", notes: "done",
      }));
      await assertFails(delegate.doc("organizations/o1/tasks/sent").update({description: "x"}));
      await assertFails(delegate.doc("organizations/o1/tasks/sent").update({imageUrl: "x"}));
      await assertFails(delegate.doc("organizations/o1/tasks/sent").delete());
    });

    test("only the sender (or global staff) deletes", async () => {
      await seedSent();
      await assertFails(dbFor("hr").doc("organizations/o1/tasks/sent").delete());
      await assertFails(dbFor("comp2").doc("organizations/o1/tasks/sent").delete());
      await assertSucceeds(dbFor("comp").doc("organizations/o1/tasks/sent").delete());
      await seedSent();
      await assertSucceeds(dbFor("super").doc("organizations/o1/tasks/sent").delete());
    });

    test("delegates and accountants cannot change assignedTo or companyId; supervisors can", async () => {
      await seedSent();
      const delegate = dbFor("del-1", DELEGATE);
      await assertFails(delegate.doc("organizations/o1/tasks/sent").update({assignedTo: "all"}));
      await assertFails(delegate.doc("organizations/o1/tasks/sent").update({companyId: "c2"}));
      await assertFails(delegate.doc("organizations/o1/tasks/sent").update({companyUID: "c2"}));
      await assertSucceeds(delegate.doc("organizations/o1/tasks/sent").update({status: "inProgress"}));

      await assertFails(dbFor("accountant").doc("organizations/o1/tasks/sent").update({assignedTo: "all"}));
      await assertFails(dbFor("hr").doc("organizations/o1/tasks/sent").update({assignedTo: "all_branch_marketing"}));
      await assertSucceeds(dbFor("hr").doc("organizations/o1/tasks/sent").update({status: "inProgress"}));

      await assertSucceeds(dbFor("comp").doc("organizations/o1/tasks/sent").update({
        assignedTo: "all", assignedToName: "جميع المناديب",
      }));
    });
  });

  test("delegate can create a same-company supervisor leave notification without organizationId", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    await assertSucceeds(delegate.collection("notifications").add({
      delegateUid: "comp",
      companyUID: "c1",
      organizationUID: "o1",
      title: "طلب إجازة",
      type: "leave_request_submitted",
      targetRole: "supervisor",
      isRead: false,
      createdBy: "del-1",
    }));
    // Missing createdBy or a foreign company is denied.
    await assertFails(delegate.collection("notifications").add({
      delegateUid: "comp",
      companyUID: "c1",
      title: "طلب إجازة",
      type: "leave_request_submitted",
      targetRole: "supervisor",
      isRead: false,
    }));
    await assertFails(delegate.collection("notifications").add({
      delegateUid: "comp",
      companyUID: "c9",
      organizationUID: "o2",
      title: "طلب إجازة",
      type: "leave_request_submitted",
      targetRole: "supervisor",
      isRead: false,
      createdBy: "del-1",
    }));
  });

  test("org-admin can list role-key notification broadcasts", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("notifications/org-broadcast").set({
        delegateUid: "organizationAdmin",
        title: "دور",
        isRead: false,
      });
    });
    const orgAdmin = dbFor("orgadmin");
    await assertSucceeds(
      orgAdmin.collection("notifications").where("delegateUid", "==", "organizationAdmin").get(),
    );
  });

  test("company admin can create a role-key registration notification with createdBy", async () => {
    const comp = dbFor("comp");
    await assertSucceeds(comp.collection("notifications").add({
      delegateUid: "super-admin",
      title: "طلب إضافة مندوب جديد",
      type: "delegate_subscription_request",
      createdBy: "comp",
      companyUID: "c1",
      organizationUID: "o1",
      isRead: false,
      targetRoles: ["superAdmin", "technicalSupport"],
    }));
  });

  test("org-admin can list penalties by organizationId", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("penalties/p-org-o1").set({
        companyId: "c1",
        organizationId: "o1",
        organizationUID: "o1",
        targetDelegateId: "del-1",
      });
      await ctx.firestore().doc("penalties/p-org-o2").set({
        companyId: "c9",
        organizationId: "o2",
        organizationUID: "o2",
        targetDelegateId: "other",
      });
    });
    const orgAdmin = dbFor("orgadmin");
    const org2 = dbFor("org2");
    const hr = dbFor("hr");
    await assertSucceeds(
      orgAdmin.collection("penalties").where("organizationId", "==", "o1").get(),
    );
    await assertFails(
      orgAdmin.collection("penalties").where("organizationId", "==", "o2").get(),
    );
    await assertFails(
      org2.collection("penalties").where("organizationId", "==", "o1").get(),
    );
    await assertFails(
      hr.collection("penalties").where("organizationId", "==", "o1").get(),
    );
  });

  test("org-admin L1 landing: attendance_logs check_in queries by org and company", async () => {
    const start = new Date("2026-11-11T00:00:00.000Z");
    const mid = new Date("2026-11-11T08:00:00.000Z");
    const end = new Date("2026-11-12T00:00:00.000Z");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("attendance_logs/l1-checkin").set({
        delegateId: "del-1",
        organizationId: "o1",
        companyId: "c1",
        type: "check_in",
        timestamp: mid,
      });
      await ctx.firestore().doc("attendance_logs/l2-checkin").set({
        delegateId: "other",
        organizationId: "o2",
        companyId: "c9",
        type: "check_in",
        timestamp: mid,
      });
    });
    const orgAdmin = dbFor("orgadmin");
    const org2 = dbFor("org2");
    const hr = dbFor("hr");
    // Exact app queries from getTodayCheckedInCount: primary (with
    // timestamp bounds) and the fallback (type only).
    await assertSucceeds(
      orgAdmin.collection("attendance_logs")
        .where("organizationId", "==", "o1")
        .where("companyId", "==", "c1")
        .where("type", "==", "check_in")
        .where("timestamp", ">=", start)
        .where("timestamp", "<", end)
        .get(),
    );
    await assertSucceeds(
      orgAdmin.collection("attendance_logs")
        .where("organizationId", "==", "o1")
        .where("companyId", "==", "c1")
        .where("type", "==", "check_in")
        .get(),
    );
    await assertFails(
      orgAdmin.collection("attendance_logs")
        .where("organizationId", "==", "o2")
        .where("companyId", "==", "c9")
        .where("type", "==", "check_in")
        .get(),
    );
    await assertFails(
      org2.collection("attendance_logs")
        .where("organizationId", "==", "o1")
        .where("companyId", "==", "c1")
        .where("type", "==", "check_in")
        .get(),
    );
    // HR is company-scoped; the same companyId constraint is already
    // allowed, so extra organizationId + type filters must also succeed.
    await assertSucceeds(
      hr.collection("attendance_logs")
        .where("organizationId", "==", "o1")
        .where("companyId", "==", "c1")
        .where("type", "==", "check_in")
        .get(),
    );
    // HR must not list another company's attendance via the org+type query.
    await assertFails(
      hr.collection("attendance_logs")
        .where("organizationId", "==", "o2")
        .where("companyId", "==", "c9")
        .where("type", "==", "check_in")
        .get(),
    );
  });


  test("delegate can notify company supervisors when supervisorUid is empty", async () => {
    const delegate = dbFor("del-1", DELEGATE);
    await assertSucceeds(delegate.collection("notifications").add({
      delegateUid: "supervisor_c1",
      companyUID: "c1",
      organizationUID: "o1",
      title: "طلب إجازة",
      type: "leave_request_submitted",
      targetRole: "supervisor",
      isRead: false,
      createdBy: "del-1",
    }));
    const comp = dbFor("comp");
    await assertSucceeds(
      comp.collection("notifications").where("delegateUid", "==", "supervisor_c1").get(),
    );
  });

  describe("task proof photos", () => {
    const DELEGATE2 = {
      role: "delegate",
      delegateId: "del-2",
      delegateIds: ["del-2"],
      orgId: "o1",
      companyId: "c1",
      phones: ["01033333333"],
      firebase: {sign_in_provider: "custom"},
    };
    const seed = async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.doc("organizations/o1/tasks/all-task").set({
          companyId: "c1",
          assignedTo: "all",
          createdBy: "comp",
          title: "All",
          description: "Body",
          status: "inProgress",
        });
        await db.doc("organizations/o1/companies/c1/delegates/del-2").set({
          uid: "del-2",
          role: "delegate",
          organizationUID: "o1",
          companyUID: "c1",
          status: "approved",
        });
      });
    };
    const pathFor = (uid, token) =>
      `task_proof/c1/${uid}/proof_${uid}_${token}.jpg`;

    test("uploader can write up to 3 paths; a 4th and a foreign path are rejected", async () => {
      await seed();
      const del = dbFor("del-1", DELEGATE);
      const ref = del.doc("organizations/o1/tasks/all-task/proofs/del-1");
      const paths = [pathFor("del-1", "a"), pathFor("del-1", "b"), pathFor("del-1", "c")];
      await assertSucceeds(ref.set({
        uploadedBy: "del-1",
        companyUID: "c1",
        taskId: "all-task",
        imagePaths: paths,
      }));
      await assertFails(ref.set({
        uploadedBy: "del-1",
        companyUID: "c1",
        taskId: "all-task",
        imagePaths: [...paths, pathFor("del-1", "d")],
      }));
      await assertFails(ref.set({
        uploadedBy: "del-1",
        companyUID: "c1",
        taskId: "all-task",
        imagePaths: [pathFor("del-2", "a")],
      }));
    });

    test("proofs are per uploader: another assignee cannot read or write them", async () => {
      await seed();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("organizations/o1/tasks/all-task/proofs/del-1").set({
          uploadedBy: "del-1",
          companyUID: "c1",
          taskId: "all-task",
          imagePaths: [pathFor("del-1", "a")],
        });
      });
      const other = dbFor("del-2", DELEGATE2);
      await assertFails(other.doc("organizations/o1/tasks/all-task/proofs/del-1").get());
      await assertFails(other.doc("organizations/o1/tasks/all-task/proofs/del-1").set({
        uploadedBy: "del-2",
        companyUID: "c1",
        taskId: "all-task",
        imagePaths: [pathFor("del-2", "x")],
      }));
      await assertFails(other.doc("organizations/o1/tasks/all-task").collection("proofs").get());
      const self = dbFor("del-1", DELEGATE);
      await assertSucceeds(self.doc("organizations/o1/tasks/all-task/proofs/del-1").get());
    });

    test("sender and same-company supervisor can read; hr, marketing, tech, and other companies cannot", async () => {
      await seed();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("organizations/o1/tasks/all-task/proofs/del-1").set({
          uploadedBy: "del-1",
          companyUID: "c1",
          taskId: "all-task",
          imagePaths: [pathFor("del-1", "a")],
        });
      });
      const refPath = "organizations/o1/tasks/all-task/proofs/del-1";
      await assertSucceeds(dbFor("comp").doc(refPath).get());
      await assertSucceeds(dbFor("comp").doc("organizations/o1/tasks/all-task").collection("proofs").get());
      await assertFails(dbFor("hr").doc(refPath).get());
      await assertFails(dbFor("accountant").doc(refPath).get());
      await assertFails(dbFor("marketing").doc(refPath).get());
      await assertFails(dbFor("tech").doc(refPath).get());
      await assertFails(dbFor("super").doc(refPath).get());
      await assertFails(dbFor("comp2").doc(refPath).get());
      await assertFails(dbFor("comp").doc(refPath).update({imagePaths: []}));
    });

    test("held delegate cannot write a new proof but can still read their existing one", async () => {
      await seed();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.doc("organizations/o1/companies/c1/delegates/del-1").set({
          uid: "del-1",
          role: "delegate",
          organizationUID: "o1",
          companyUID: "c1",
          status: "suspended",
          holds: {admin_suspend: {at: "2026-11-12"}},
        }, {merge: true});
        await db.doc("organizations/o1/tasks/all-task/proofs/del-1").set({
          uploadedBy: "del-1",
          companyUID: "c1",
          taskId: "all-task",
          imagePaths: [pathFor("del-1", "a")],
        });
      });
      const del = dbFor("del-1", DELEGATE);
      const ref = del.doc("organizations/o1/tasks/all-task/proofs/del-1");
      await assertSucceeds(ref.get());
      await assertFails(ref.set({
        uploadedBy: "del-1",
        companyUID: "c1",
        taskId: "all-task",
        imagePaths: [pathFor("del-1", "a"), pathFor("del-1", "b")],
      }));
    });

    // B1: only the assignee / intended recipients, in the task's org and
    // company, on a non-cancelled task, may write proofs. The uploader
    // label is server-set (onTaskProofWritten) and cannot be spoofed.
    const seedB1 = async () => {
      await seed();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.doc("users/hrB").set({role: "hr", organizationUID: "o2", companyUID: "c9"});
        await db.doc("users/mpA").set({
          role: "marketingPromotion", organizationUID: "o1", companyUID: "c1", fullName: "MP A",
        });
        await db.doc("users/mpOrg").set({role: "marketingPromotion", organizationUID: "o1"});
        await db.doc("users/mpC2").set({
          role: "marketingPromotion", organizationUID: "o1", companyUID: "c2",
        });
        await db.doc("users/bmA").set({
          role: "branches_marketing_manager", organizationUID: "o1", companyUID: "c1",
        });
        await db.doc("organizations/o1/tasks/single-task").set({
          companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "One", status: "pending",
        });
        await db.doc("organizations/o1/tasks/mp-task").set({
          companyId: "c1", assignedTo: "mpA", createdBy: "comp", title: "MP", status: "pending",
        });
        await db.doc("organizations/o1/tasks/cancelled-task").set({
          companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "X", status: "cancelled",
        });
        await db.doc("organizations/o1/tasks/bm-task").set({
          companyId: "c1", assignedTo: "all_branch_marketing", createdBy: "comp", title: "BM",
          status: "pending",
        });
        await db.doc("organizations/o1/tasks/mp-sector-task").set({
          companyId: "c1", assignedTo: "all_marketing_promotion", createdBy: "comp", title: "MPS",
          status: "pending",
        });
      });
    };
    const proofDoc = (uid, taskId, extra = {}) => ({
      uploadedBy: uid,
      companyUID: "c1",
      taskId,
      imagePaths: [pathFor(uid, "a")],
      ...extra,
    });
    const textOnly = (uid, taskId) => ({uploadedBy: uid, companyUID: "c1", taskId, imagePaths: []});

    test("B1: other-org HR cannot plant a text-only proof", async () => {
      await seedB1();
      const db = dbFor("hrB");
      await assertFails(db.doc("organizations/o1/tasks/single-task/proofs/hrB")
        .set(textOnly("hrB", "single-task")));
      await assertFails(db.doc("organizations/o1/tasks/all-task/proofs/hrB")
        .set(textOnly("hrB", "all-task")));
    });

    test("B1: same-company accountant (not an attach role, not assigned) is denied", async () => {
      await seedB1();
      const db = dbFor("accountant");
      await assertFails(db.doc("organizations/o1/tasks/single-task/proofs/accountant")
        .set(textOnly("accountant", "single-task")));
      await assertFails(db.doc("organizations/o1/tasks/all-task/proofs/accountant")
        .set(textOnly("accountant", "all-task")));
    });

    test("B1: unassigned same-company marketing cannot write or spoof a name", async () => {
      await seedB1();
      const db = dbFor("mpA");
      await assertFails(db.doc("organizations/o1/tasks/single-task/proofs/mpA")
        .set(proofDoc("mpA", "single-task")));
      await assertFails(db.doc("organizations/o1/tasks/single-task/proofs/mpA")
        .set(proofDoc("mpA", "single-task", {uploadedByName: "مندوب تجريبي DEV"})));
    });

    test("B1: uploadedByName is server-set; clients cannot add or change it", async () => {
      await seedB1();
      const ref = "organizations/o1/tasks/mp-task/proofs/mpA";
      const db = dbFor("mpA");
      // The assigned marketing user may write, but not with a name.
      await assertFails(db.doc(ref).set(proofDoc("mpA", "mp-task", {uploadedByName: "مندوب تجريبي DEV"})));
      await assertSucceeds(db.doc(ref).set(proofDoc("mpA", "mp-task")));
      // Server (trigger) sets the real profile name.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(ref).update({uploadedByName: "MP A"});
      });
      await assertFails(db.doc(ref).update({uploadedByName: "مندوب تجريبي DEV"}));
      await assertSucceeds(db.doc(ref).set({imagePaths: [pathFor("mpA", "b")]}, {merge: true}));
      await assertSucceeds(db.doc(ref).set(proofDoc("mpA", "mp-task", {uploadedByName: "MP A"})));
      // No extra display fields either.
      await assertFails(db.doc(ref).set(proofDoc("mpA", "mp-task", {displayName: "X"})));
    });

    test("B1: the assignee cannot write proofs on a cancelled task", async () => {
      await seedB1();
      const del = dbFor("del-1", DELEGATE);
      await assertFails(del.doc("organizations/o1/tasks/cancelled-task/proofs/del-1")
        .set(proofDoc("del-1", "cancelled-task")));
      await assertSucceeds(del.doc("organizations/o1/tasks/single-task/proofs/del-1")
        .set(proofDoc("del-1", "single-task")));
    });

    test("B1: a delegate not assigned to a single-assignee task is denied", async () => {
      await seedB1();
      const other = dbFor("del-2", DELEGATE2);
      await assertFails(other.doc("organizations/o1/tasks/single-task/proofs/del-2")
        .set(proofDoc("del-2", "single-task")));
    });

    test("B1: «الكل» accepts same-company delegates only, not marketing or other companies", async () => {
      await seedB1();
      await assertSucceeds(dbFor("del-2", DELEGATE2).doc("organizations/o1/tasks/all-task/proofs/del-2")
        .set(proofDoc("del-2", "all-task")));
      await assertFails(dbFor("mpA").doc("organizations/o1/tasks/all-task/proofs/mpA")
        .set(proofDoc("mpA", "all-task")));
      await assertFails(dbFor("bmA").doc("organizations/o1/tasks/all-task/proofs/bmA")
        .set(proofDoc("bmA", "all-task")));
      await assertFails(dbFor("marketing").doc("organizations/o1/tasks/all-task/proofs/marketing")
        .set(proofDoc("marketing", "all-task")));
      const c2Delegate = {...DELEGATE2, delegateId: "stranger", delegateIds: ["stranger"], companyId: "c2"};
      await assertFails(dbFor("stranger", c2Delegate).doc("organizations/o1/tasks/all-task/proofs/stranger")
        .set(proofDoc("stranger", "all-task")));
      const o2Delegate = {...DELEGATE2, delegateId: "other", delegateIds: ["other"], orgId: "o2", companyId: "c9"};
      await assertFails(dbFor("other", o2Delegate).doc("organizations/o1/tasks/all-task/proofs/other")
        .set(proofDoc("other", "all-task")));
    });

    test("B1: sector tasks accept only the matching sector role", async () => {
      await seedB1();
      await assertSucceeds(dbFor("bmA").doc("organizations/o1/tasks/bm-task/proofs/bmA")
        .set(proofDoc("bmA", "bm-task")));
      await assertFails(dbFor("mpA").doc("organizations/o1/tasks/bm-task/proofs/mpA")
        .set(proofDoc("mpA", "bm-task")));
      await assertFails(dbFor("del-1", DELEGATE).doc("organizations/o1/tasks/bm-task/proofs/del-1")
        .set(proofDoc("del-1", "bm-task")));
      await assertSucceeds(dbFor("mpA").doc("organizations/o1/tasks/mp-sector-task/proofs/mpA")
        .set(proofDoc("mpA", "mp-sector-task")));
      await assertSucceeds(dbFor("mpOrg").doc("organizations/o1/tasks/mp-sector-task/proofs/mpOrg")
        .set(proofDoc("mpOrg", "mp-sector-task")));
      await assertFails(dbFor("mpC2").doc("organizations/o1/tasks/mp-sector-task/proofs/mpC2")
        .set(proofDoc("mpC2", "mp-sector-task")));
      await assertFails(dbFor("bmA").doc("organizations/o1/tasks/mp-sector-task/proofs/bmA")
        .set(proofDoc("bmA", "mp-sector-task")));
    });

    test("B1: signed-out and anonymous writes stay denied", async () => {
      await seedB1();
      const unauth = testEnv.unauthenticatedContext().firestore();
      await assertFails(unauth.doc("organizations/o1/tasks/all-task/proofs/del-1")
        .set(proofDoc("del-1", "all-task")));
      await assertFails(anonDb().doc("organizations/o1/tasks/all-task/proofs/anon-user")
        .set(textOnly("anon-user", "all-task")));
    });

    test("a sender title-only edit does not need to touch proof docs", async () => {
      await seed();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("organizations/o1/tasks/all-task/proofs/del-1").set({
          uploadedBy: "del-1",
          companyUID: "c1",
          taskId: "all-task",
          imagePaths: [pathFor("del-1", "a")],
        });
      });
      await assertSucceeds(dbFor("comp").doc("organizations/o1/tasks/all-task").update({
        title: "Renamed", editedAt: new Date(),
      }));
      const snap = await dbFor("comp").doc("organizations/o1/tasks/all-task/proofs/del-1").get();
      await assertSucceeds(Promise.resolve(snap));
      if (snap.data().imagePaths[0] !== pathFor("del-1", "a")) {
        throw new Error("proof paths were wiped by a title-only edit");
      }
    });
  });
});
