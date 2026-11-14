const test = require("node:test");
const assert = require("node:assert/strict");
const J = require("../lib/subscription_jobs");

function mockDoc(id, data) {
  return {
    id,
    get(field) {
      return data[field];
    },
  };
}

test("loadCompanySupervisorCandidates uses one in-filter per query (no role disjunction stack)", async () => {
  const queryFilters = [];
  const db = {
    collection() {
      return {
        where(field, op, val) {
          const filters = [{field, op, val}];
          const chain = {
            where(f, o, v) {
              filters.push({field: f, op: o, val: v});
              return chain;
            },
            async get() {
              queryFilters.push(filters.map((x) => ({...x})));
              return {docs: []};
            },
          };
          return chain;
        },
      };
    },
  };
  const companies = Array.from({length: 40}, (_, i) => `co_${i}`);
  await J.loadCompanySupervisorCandidates(db, companies).then((r) => r.byCompany);
  assert.equal(queryFilters.length, 4);
  for (const filters of queryFilters) {
    const ins = filters.filter((x) => x.op === "in");
    assert.equal(ins.length, 1);
    assert.notEqual(ins[0].field, "role");
    assert.ok(ins[0].val.length <= 30);
  }
});

test("loadCompanySupervisorCandidates merges companyId field and survives chunk errors", async () => {
  let companyUidChunks = 0;
  const db = {
    collection() {
      return {
        where(field, op, part) {
          return {
            async get() {
              if (field === "companyUID") {
                companyUidChunks++;
                if (companyUidChunks === 2) throw new Error("Too many disjunctions");
                return {
                  docs: part.map((co, i) => mockDoc(`uid_${co}`, {
                    companyUID: co,
                    role: "supervisor",
                    status: "active",
                  })),
                };
              }
              const legacy = part.filter((co) => co === "c_legacy");
              return {
                docs: legacy.map(() => mockDoc("id_only", {
                  companyId: "c_legacy",
                  role: "company-supervisor",
                  status: "active",
                })),
              };
            },
          };
        },
      };
    },
  };
  const companies = [...Array.from({length: 35}, (_, i) => `co_${i}`), "c_legacy"];
  const {byCompany: map} = await J.loadCompanySupervisorCandidates(db, companies);
  assert.ok(map.get("c_legacy")?.some((u) => u.uid === "id_only"));
  assert.ok(map.get("co_0")?.length >= 1);
});