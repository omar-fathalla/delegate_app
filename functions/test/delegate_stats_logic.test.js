// TAS-87: delta logic of the delegate stats docs. Fake data only.
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("../lib/delegate_stats_logic");

const CAIRO = "القاهرة";
const GIZA = "الجيزة";

const d = (over = {}) => ({
  status: "active",
  city: CAIRO,
  position: "Promoter",
  documents: [],
  ...over,
});
const s1 = (o = {}) => ({documentKey: "insuranceLetter", secondaryURL: "https://fake/s1.png", ...o});
const health = (o = {}) => ({documentKey: "healthCertificate", documentStatus: "approved", receiptCode: "R-1", ...o});

const asObj = (deltas) => {
  const o = {};
  L.applyDeltas(o, deltas);
  return L.normalizeStats(o);
};

test("create counts total, active, city x position and the company breakdown", () => {
  const {org, company} = L.planDelegateStats(null, d(), "co1");
  assert.deepEqual(asObj(org), {
    active: 1,
    byCity: {[CAIRO]: {Promoter: 1}},
    byCompany: {co1: {active: 1, total: 1}},
    total: 1,
  });
  assert.deepEqual(asObj(company), {active: 1, byCity: {[CAIRO]: {Promoter: 1}}, total: 1});
});

test("delete is the exact negative of create", () => {
  const data = d({documents: [s1(), health()]});
  const c = L.planDelegateStats(null, data, "co1");
  const r = L.planDelegateStats(data, null, "co1");
  const o = {};
  L.applyDeltas(o, c.org);
  L.applyDeltas(o, r.org);
  assert.deepEqual(L.normalizeStats(o), {});
  assert.equal(r.company.find((x) => x.path[0] === "s1InsuranceDocs").value, -1);
});

test("an update that touches no counted field writes nothing", () => {
  const before = d({name: "Fake A", lastSeen: 1});
  const after = d({name: "Fake B", lastSeen: 2, documents: [{documentKey: "nationalId", secondaryURL: "x"}]});
  assert.deepEqual(L.planDelegateStats(before, after, "co1"), {org: [], company: []});
});

test("status and city changes move the counts", () => {
  const {org} = L.planDelegateStats(d({status: "pending"}), d({city: GIZA}), "co1");
  assert.deepEqual(asObj(org), {
    active: 1,
    byCity: {[CAIRO]: {Promoter: -1}, [GIZA]: {Promoter: 1}},
    byCompany: {co1: {active: 1}},
  });
});

test("financial rules match the web (S1 per letter, embassy = first health cert approved in holder mode)", () => {
  const c = L.contributionOf(d({
    documents: [
      s1(), s1({secondaryURL: "", receiptCode: "RC"}), s1({secondaryURL: ""}),
      health({documentStatus: "pending"}), health(),
    ],
  }));
  assert.equal(c.s1InsuranceDocs, 2);
  assert.equal(c.embassyHealthCerts, 0, "only the first healthCertificate item counts, like the web's find()");
  assert.equal(L.contributionOf(d({documents: [health()]})).embassyHealthCerts, 1);
  assert.equal(L.contributionOf(d({documents: [health({receiptCode: "", secondaryURL: ""})]})).embassyHealthCerts, 0);
});

test("bad data never throws and is not counted where unusable", () => {
  for (const bad of [{}, {documents: "x"}, {documents: [null, 3, "s", [1]]}, {city: 5, position: {}},
    {city: "__x__", position: "Promoter"}, {city: "a".repeat(101), position: "Promoter"}, {status: ["active"]}]) {
    const {org} = L.planDelegateStats(null, bad, "co1");
    const o = asObj(org);
    assert.equal(o.total, 1);
    assert.equal(o.byCity, undefined);
    assert.equal(o.active, undefined);
  }
  assert.deepEqual(L.planDelegateStats(null, null, "co1"), {org: [], company: []});
  assert.deepEqual(L.planDelegateStats(undefined, "nope", "co1"), {org: [], company: []});
});

test("positions other than Promoter/Supervisor are kept raw (the web filters them)", () => {
  const {company} = L.planDelegateStats(null, d({position: " Supervisor "}), "co1");
  assert.deepEqual(asObj(company).byCity, {[CAIRO]: {" Supervisor ": 1}}, "raw value, like the web's === check");
});

test("nestDeltas builds the merge object", () => {
  const o = L.nestDeltas([{path: ["total"], value: 1}, {path: ["byCity", CAIRO, "Promoter"], value: -1}], (v) => `inc(${v})`);
  assert.deepEqual(o, {total: "inc(1)", byCity: {[CAIRO]: {Promoter: "inc(-1)"}}});
});

test("parseDelegatePath only accepts nested company delegates", () => {
  assert.deepEqual(L.parseDelegatePath("organizations/o/companies/c/delegates/u"), {orgId: "o", companyId: "c", delegateId: "u"});
  assert.equal(L.parseDelegatePath("delegates/u"), null);
  assert.equal(L.parseDelegatePath("organizations/o/delegates/u"), null);
});

test("sameStats ignores zero leaves, empty maps and metadata", () => {
  assert.ok(L.sameStats({total: 2, byCity: {[CAIRO]: {Promoter: 0}}, updatedAt: 1}, {total: 2, active: 0}));
  assert.ok(!L.sameStats({total: 2}, {total: 3}));
});

// Property test: any sequence of creates / updates / deletes / company moves,
// applied as deltas, equals a recompute from the final docs (the backfill).
test("random write sequences: incremental == recompute", () => {
  let seed = 87;
  const rnd = (n) => {
    seed = (seed * 1103515245 + 12345) % 2147483648;
    return seed % n;
  };
  const pick = (a) => a[rnd(a.length)];
  const randomDoc = () => d({
    status: pick(["active", "pending", "inactive", undefined]),
    city: pick([CAIRO, GIZA, "", undefined, 7]),
    position: pick(["Promoter", "Supervisor", "Other", undefined]),
    documents: pick([[], [s1()], [s1(), s1({receiptCode: "r", secondaryURL: ""})], [health()], [health({documentStatus: "rejected"})], "bad"]),
  });
  for (let round = 0; round < 30; round++) {
    const docs = new Map(); // id -> {company, data}
    const org = {};
    const companies = {};
    const apply = (companyId, before, after) => {
      const p = L.planDelegateStats(before, after, companyId);
      L.applyDeltas(org, p.org);
      L.applyDeltas((companies[companyId] = companies[companyId] || {}), p.company);
    };
    for (let i = 0; i < 200; i++) {
      const id = `u${rnd(25)}`;
      const cur = docs.get(id);
      const op = rnd(4);
      if (!cur) {
        const company = pick(["c1", "c2", "c3"]);
        const data = randomDoc();
        docs.set(id, {company, data});
        apply(company, null, data);
      } else if (op === 0) {
        docs.delete(id);
        apply(cur.company, cur.data, null);
      } else if (op === 1) {
        const company = pick(["c1", "c2", "c3"]); // move = delete + create
        apply(cur.company, cur.data, null);
        docs.set(id, {company, data: cur.data});
        apply(company, null, cur.data);
      } else {
        const data = randomDoc();
        apply(cur.company, cur.data, data);
        docs.set(id, {company: cur.company, data});
      }
    }
    const orgFresh = L.emptyStats(true);
    const coFresh = {};
    for (const {company, data} of docs.values()) {
      L.accumulate(orgFresh, data, company);
      L.accumulate((coFresh[company] = coFresh[company] || L.emptyStats(false)), data, null);
    }
    assert.ok(L.sameStats(org, orgFresh), `org round ${round}`);
    for (const c of ["c1", "c2", "c3"]) {
      assert.ok(L.sameStats(companies[c] || {}, coFresh[c] || {}), `company ${c} round ${round}`);
    }
  }
});
