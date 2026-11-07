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
    await assertSucceeds(
      companyAdmin.doc("organizations/o1/companies/c1/delegates/del-1").update({
        status: "suspended",
      }),
    );
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
        imageUrl: "https://example.com/x.jpg",
        imagePath: "organizations/o1/task_images/comp/x.jpg",
      }));
      await assertFails(comp.doc("organizations/o1/tasks/new2").set({
        companyId: "c1", assignedTo: "del-1", createdBy: "comp", title: "T",
        imagePath: "organizations/o1/task_images/hr/x.jpg",
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
  });
});
