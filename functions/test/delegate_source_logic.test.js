const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/delegate_source_logic");

const uid = "d1";
const approvedApp = {
  id: uid,
  requestType: "new_delegate",
  status: "approved",
  supervisorUid: "sup",
  existingDelegateUid: "",
  organizationUID: "o-target",
};
const pendingApp = {
  id: uid,
  requestType: "new_delegate",
  status: "pending",
  supervisorUid: "sup",
  organizationUID: "o-target",
};

function chain(over = {}) {
  return {
    path: `organizations/o-target/companies/c1/delegates/${uid}`,
    uid,
    organizationUID: "o-target",
    companyUID: "c1",
    approvedRequestId: uid,
    ...over,
  };
}

test("rule 1: approved new_delegate with supervisor is app / high", () => {
  const p = L.inferPersonSource({
    uid,
    appRequestById: approvedApp,
    chainDocs: [chain()],
    webCreates: [],
  });
  assert.deepEqual(p, {uid, source: "app", rule: 1, confidence: "high"});
  assert.equal(
    L.inferChainOrigin({doc: chain(), person: p, requestOrgId: "o-target"}),
    "app_new_delegate",
  );
});

test("rule 1: supervisor copy gets app_supervisor_copy", () => {
  const p = L.inferPersonSource({
    uid,
    appRequestById: approvedApp,
    chainDocs: [
      chain(),
      chain({
        path: `organizations/o-sup/companies/c1/delegates/${uid}`,
        organizationUID: "o-sup",
      }),
    ],
    webCreates: [],
  });
  const copy = chain({
    path: `organizations/o-sup/companies/c1/delegates/${uid}`,
    organizationUID: "o-sup",
  });
  assert.equal(
    L.inferChainOrigin({
      doc: copy,
      person: p,
      supervisorOrgId: "o-sup",
      requestOrgId: "o-target",
    }),
    "app_supervisor_copy",
  );
});

test("rule 2: pending/rejected new_delegate with supervisor is app / high", () => {
  for (const status of ["pending", "rejected"]) {
    const p = L.inferPersonSource({
      uid,
      appRequestById: {...pendingApp, status},
      chainDocs: [chain({approvedRequestId: ""})],
      webCreates: [],
    });
    assert.equal(p.rule, 2, status);
    assert.equal(p.source, "app");
    assert.equal(p.confidence, "high");
    assert.equal(
      L.inferChainOrigin({doc: chain({approvedRequestId: ""}), person: p}),
      "app_new_delegate",
    );
  }
});

test("rule 1 does not fire for add_organization or existingDelegateUid", () => {
  const addOrg = L.inferPersonSource({
    uid,
    appRequestById: {...approvedApp, requestType: "add_organization", existingDelegateUid: "d1"},
    chainDocs: [chain({statusReason: "create"})],
    webCreates: [],
  });
  // Falls through to web signals on the chain doc.
  assert.equal(addOrg.rule, 3);
  assert.equal(addOrg.source, "web");
});

test("rule 3: web create request, statusReason, or version => web / high", () => {
  const byRequest = L.inferPersonSource({
    uid,
    appRequestById: null,
    chainDocs: [chain({approvedRequestId: "", registeredVia: ""})],
    webCreates: [{targetDelegateId: uid, organizationUID: "o-web", companyUID: "c1"}],
  });
  assert.deepEqual(byRequest, {uid, source: "web", rule: 3, confidence: "high"});

  const byReason = L.inferPersonSource({
    uid,
    appRequestById: null,
    chainDocs: [chain({approvedRequestId: "", statusReason: "billing_cycle_reset"})],
    webCreates: [],
  });
  assert.equal(byReason.rule, 3);

  const byVersion = L.inferPersonSource({
    uid,
    appRequestById: null,
    chainDocs: [chain({approvedRequestId: "", version: 3})],
    webCreates: [],
  });
  assert.equal(byVersion.rule, 3);
  assert.equal(
    L.inferChainOrigin({doc: chain({approvedRequestId: "", version: 3}), person: byVersion}),
    "web_request",
  );
});

test("rule 3: web delegate later added from the app stays web, chainOrigin app_add_organization", () => {
  const person = L.inferPersonSource({
    uid,
    appRequestById: {
      id: "add-1",
      requestType: "add_organization",
      status: "approved",
      supervisorUid: "sup",
      existingDelegateUid: uid,
      organizationUID: "o-app",
    },
    chainDocs: [
      chain({
        path: `organizations/o-web/companies/c1/delegates/${uid}`,
        organizationUID: "o-web",
        approvedRequestId: "",
        statusReason: "create",
        version: 1,
      }),
      chain({
        path: `organizations/o-app/companies/c2/delegates/${uid}`,
        organizationUID: "o-app",
        companyUID: "c2",
        approvedRequestId: "add-1",
        registeredVia: "mobile_app",
      }),
    ],
    webCreates: [{targetDelegateId: uid, organizationUID: "o-web"}],
  });
  assert.equal(person.source, "web");
  assert.equal(person.rule, 3);
  const added = chain({
    path: `organizations/o-app/companies/c2/delegates/${uid}`,
    organizationUID: "o-app",
    approvedRequestId: "add-1",
    registeredVia: "mobile_app",
  });
  assert.equal(
    L.inferChainOrigin({
      doc: added,
      person,
      hasAddOrganizationRequest: true,
    }),
    "app_add_organization",
  );
  const original = chain({
    path: `organizations/o-web/companies/c1/delegates/${uid}`,
    organizationUID: "o-web",
    approvedRequestId: "",
    statusReason: "create",
    version: 1,
  });
  assert.equal(L.inferChainOrigin({doc: original, person}), "web_request");
});

test("rule 4: registeredVia mobile_app only is app / low, origin unknown", () => {
  const p = L.inferPersonSource({
    uid,
    appRequestById: null,
    chainDocs: [chain({approvedRequestId: "", registeredVia: "mobile_app"})],
    webCreates: [],
  });
  assert.deepEqual(p, {uid, source: "app", rule: 4, confidence: "low"});
  assert.equal(
    L.inferChainOrigin({
      doc: chain({approvedRequestId: "", registeredVia: "mobile_app"}),
      person: p,
    }),
    "unknown",
  );
});

test("rule 5: no signals default to web / review, origin unknown", () => {
  const p = L.inferPersonSource({
    uid,
    appRequestById: null,
    chainDocs: [chain({approvedRequestId: "", registeredVia: ""})],
    webCreates: [],
  });
  assert.deepEqual(p, {uid, source: "web", rule: 5, confidence: "review"});
  assert.equal(
    L.inferChainOrigin({
      doc: chain({approvedRequestId: ""}),
      person: p,
    }),
    "unknown",
  );
});

test("web self-request (no supervisorUid) is not an app registration", () => {
  const p = L.inferPersonSource({
    uid,
    appRequestById: {...approvedApp, supervisorUid: ""},
    chainDocs: [chain({statusReason: "create"})],
    webCreates: [],
  });
  assert.equal(p.source, "web");
  assert.equal(p.rule, 3);
});
