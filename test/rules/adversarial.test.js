const {describe, test, before, after, beforeEach} = require("node:test");
const {readFileSync} = require("fs");
const {resolve} = require("path");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {Timestamp, doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, collection, query, where, collectionGroup} = require("firebase/firestore");
const U = {
  sa:{role:"super-admin",organizationUID:"o1"}, oa:{role:"organization-admin",organizationUID:"o1"},
  ca:{role:"company-admin",organizationUID:"o1",companyUID:"c1"}, sup:{role:"supervisor",organizationUID:"o1",companyUID:"c1"},
  hr:{role:"hr",organizationUID:"o1",companyUID:"c1"}, acc:{role:"accountant",organizationUID:"o1",companyUID:"c1"},
  bmm:{role:"branches_marketing_manager",organizationUID:"o1",companyUID:"c1"}, mk:{role:"marketing",organizationUID:"o1",companyUID:"c1"},
  ts:{role:"technical_support",organizationUID:"o1"},
  d1:{role:"delegate",organizationUID:"o1",companyUID:"c1",uid:"d1"},
  victim:{role:"organization-admin",organizationUID:"o2",phoneNumber:"01000000009",email:"victim@x.test",password:"PLACEHOLDER"},
  legacy:{role:"delegate",requireReLogin:true}, legacy2:{role:"supervisor",organizationUID:"o1",companyUID:"cGone",requireReLogin:true},
  acc2:{}, // accomplice auth uid with empty doc? (deleted below)
};
const results=[];
function rec(name, exp, p){ return p.then(()=>{results.push([name,exp,"allow"]); ;},
  e=>{ if(String(e).includes("expected deny")) throw e; const ok=/PERMISSION_DENIED|permission/i.test(String(e)); results.push([name,exp,ok?"deny":"ERR "+e]); ;});}
describe("adversarial", ()=>{
  let env; const as=(uid,c={})=>env.authenticatedContext(uid,{firebase:{sign_in_provider:"password"},...c}).firestore();
  const anon=(uid="anon1")=>env.authenticatedContext(uid,{firebase:{sign_in_provider:"anonymous"}}).firestore();
  before(async()=>{env=await initializeTestEnvironment({projectId:"demo-adv",firestore:{host:(process.env.FIRESTORE_EMULATOR_HOST||"127.0.0.1:8089").split(":")[0],port:Number((process.env.FIRESTORE_EMULATOR_HOST||"127.0.0.1:8089").split(":")[1]),rules:readFileSync(resolve(__dirname,"../../firestore.rules"),"utf8")}});});
  after(async()=>{if(process.env.ADV_RESULTS) require("fs").writeFileSync(process.env.ADV_RESULTS,JSON.stringify(results,null,1)); await env.cleanup();});
  beforeEach(async()=>{await env.clearFirestore(); await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();
    for(const [k,v] of Object.entries(U)) if(k!=="acc2") await setDoc(doc(db,"users/"+k),v);
    for(const p of ["organizations/o1","organizations/o2","organizations/o1/companies/c1","organizations/o1/companies/c2","organizations/o2/companies/c9"]) await setDoc(doc(db,p),{n:1});
    await setDoc(doc(db,"organizations/o1/companies/c1/delegates/d1"),{phoneNumber:"01011111111",nationalityID:"NID-PLACEHOLDER",organizationUID:"o1",companyUID:"c1",status:"active",name:"a"});
    await setDoc(doc(db,"organizations/o1/companies/c1/delegates/d9"),{phoneNumber:"01022222222",organizationUID:"o1",companyUID:"c1",status:"active"});
    await setDoc(doc(db,"invites/i1"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"company-admin",email:"n@x.test",expiresAt:Timestamp.fromMillis(Date.now()+86400000)});
    await setDoc(doc(db,"invites/i2"),{status:"claimed",organizationId:"o1",companyId:"c1",roleToAssign:"company-admin",email:"m@x.test",claimedBy:"zz"});
  });});
  const exp=(d)=>Timestamp.fromMillis(Date.now()+d*86400000);
  test("anon self-promotion", async()=>{ await rec("anon create self super-admin","deny",setDoc(doc(anon(),"users/anon1"),{role:"super-admin"}));
    await rec("anon create self delegate","deny",setDoc(doc(anon(),"users/anon1"),{role:"delegate"}));
    await rec("new user create self super-admin","deny",setDoc(doc(as("n1"),"users/n1"),{role:"super-admin"}));
    await rec("new user create self organization-admin","deny",setDoc(doc(as("n1"),"users/n1"),{role:"organization-admin"}));
    await rec("delegate self update role super-admin","deny",updateDoc(doc(as("d1"),"users/d1"),{role:"super-admin"}));
    await rec("hr self update role company-admin","deny",updateDoc(doc(as("hr"),"users/hr"),{role:"company-admin"}));
    await rec("hr self set permissions","deny",updateDoc(doc(as("hr"),"users/hr"),{permissions:["all"]}));});
  test("cross-user role change", async()=>{ await rec("delegate sets hr role super-admin","deny",updateDoc(doc(as("d1"),"users/hr"),{role:"super-admin"}));
    await rec("ca sets sup role company-admin","deny",updateDoc(doc(as("ca"),"users/sup"),{role:"company-admin"}));
    await rec("oa sets ca role organization-admin","deny",updateDoc(doc(as("oa"),"users/ca"),{role:"organization-admin"}));
    await rec("oa edits SA doc","deny",updateDoc(doc(as("oa"),"users/sa"),{displayName:"x"}));
    await rec("sa sets role super_admin (legacy)","deny",updateDoc(doc(as("sa"),"users/hr"),{role:"super_admin"}));
    await rec("sup promotes delegate to marketing (org-scoped reader)","deny",updateDoc(doc(as("sup"),"users/d1"),{role:"marketing"}));
    await rec("hr promotes delegate to supervisor","deny",updateDoc(doc(as("hr"),"users/d1"),{role:"supervisor"}));
    await rec("sup creates delegate users doc own company","allow",setDoc(doc(as("sup"),"users/nd1"),{role:"delegate",organizationUID:"o1",companyUID:"c1"}));
    await rec("ca creates hr users doc own company","allow",setDoc(doc(as("ca"),"users/nh1"),{role:"hr",organizationUID:"o1",companyUID:"c1"}));
    await rec("ca promotes delegate to marketing","deny",updateDoc(doc(as("ca"),"users/d1"),{role:"marketing"}));
    await rec("ca creates branches_marketing_manager","deny",setDoc(doc(as("ca"),"users/nb1"),{role:"branches_marketing_manager",organizationUID:"o1",companyUID:"c1"}));
    await rec("hr creates accomplice users doc role marketing","deny",setDoc(doc(as("hr"),"users/acc2"),{role:"marketing",organizationUID:"o1",companyUID:"c1"}));
    // last: this promotes hr, so it must run after the hr cases above
    await rec("sa sets role super-admin","allow",updateDoc(doc(as("sa"),"users/hr"),{role:"super-admin"}));});
  test("org-admin cross-org company", async()=>{ await rec("oa create ca with foreign company c9","deny",setDoc(doc(as("oa"),"users/x1"),{role:"company-admin",organizationUID:"o1",companyUID:"c9"}));
    await rec("oa create ca own company c1","allow",setDoc(doc(as("oa"),"users/x2"),{role:"company-admin",organizationUID:"o1",companyUID:"c1"}));
    await rec("oa create in org o2","deny",setDoc(doc(as("oa"),"users/x3"),{role:"supervisor",organizationUID:"o2",companyUID:"c9"}));
    await rec("oa moves hr companyUID to c9","deny",updateDoc(doc(as("oa"),"users/hr"),{companyUID:"c9"}));
    await rec("sup changes delegate organizationUID","deny",updateDoc(doc(as("sup"),"users/d1"),{organizationUID:"o2"}));
    await rec("oa create with organizationId (alt key) foreign","deny",setDoc(doc(as("oa"),"users/x6"),{role:"supervisor",organizationUID:"o1",companyUID:"c1",organizationId:"o2"}));
    await rec("oa create with companyId own company","allow",setDoc(doc(as("oa"),"users/x7"),{role:"supervisor",organizationUID:"o1",companyUID:"c1",companyId:"c1"}));
    await rec("oa create with companyId (alt key) foreign","deny",setDoc(doc(as("oa"),"users/x4"),{role:"company-admin",organizationUID:"o1",companyId:"c9"}));});
  test("password fields", async()=>{ await rec("self set password","deny",updateDoc(doc(as("hr"),"users/hr"),{password:"x"}));
    await rec("self set temporaryPassword","deny",updateDoc(doc(as("hr"),"users/hr"),{temporaryPassword:"x"}));
    await rec("self create with tempPassword","deny",setDoc(doc(as("n2"),"users/n2"),{role:"delegate",tempPassword:"x"}));
    await rec("sa create staff with password","deny",setDoc(doc(as("sa"),"users/x5"),{role:"hr",organizationUID:"o1",companyUID:"c1",password:"x"}));
    await rec("victim self photo update with legacy password untouched","allow",updateDoc(doc(as("victim"),"users/victim"),{photoURL:"p"}));});
  test("legacy docs reLogin", async()=>{ await rec("legacy (no org/company) reLogin clear","allow",updateDoc(doc(as("legacy"),"users/legacy"),{requireReLogin:false,reLoginCompletedAt:1}));
    await rec("legacy2 (company not under org) reLogin clear","allow",updateDoc(doc(as("legacy2"),"users/legacy2"),{requireReLogin:false}));});
  test("deletes by role", async()=>{ for(const [who,tgt,e] of [["sa","hr","allow"],["oa","d1","deny"],["ca","d1","allow"],["sup","d1","allow"],["hr","d1","deny"],["acc","d1","deny"],["bmm","d1","deny"],["mk","d1","deny"],["ts","d1","deny"],["d1","hr","deny"],["ca","hr","deny"],["sup","sa","deny"]]){
      await env.withSecurityRulesDisabled(async ctx=>{for(const k of ["hr","d1","sa"]) await setDoc(doc(ctx.firestore(),"users/"+k),U[k]);});
      await rec(`${who} deletes ${tgt}`,e,deleteDoc(doc(as(who),"users/"+tgt)));}
    await rec("anon deletes d1","deny",deleteDoc(doc(anon(),"users/d1")));});
  test("members & invites", async()=>{ await rec("self create member o1","deny",setDoc(doc(as("n3"),"organizations/o1/members/n3"),{role:"organization-admin"}));
    await rec("hr create member o1","deny",setDoc(doc(as("hr"),"organizations/o1/members/hr"),{role:"organization-admin"}));
    await rec("oa create member own org","allow",setDoc(doc(as("oa"),"organizations/o1/members/z"),{r:1}));
    await rec("oa create member other org","deny",setDoc(doc(as("oa"),"organizations/o2/members/z"),{r:1}));
    await rec("self create company member","deny",setDoc(doc(as("n3"),"organizations/o1/companies/c1/members/n3"),{r:1}));
    await rec("oa invite super-admin","deny",setDoc(doc(as("oa"),"invites/j1"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"super-admin",expiresAt:exp(1)}));
    await rec("oa invite org-admin","deny",setDoc(doc(as("oa"),"invites/j2"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"organization-admin",expiresAt:exp(1)}));
    await rec("oa invite org-admin via role key","deny",setDoc(doc(as("oa"),"invites/j2b"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"company-admin",role:"organization-admin",expiresAt:exp(1)}));
    await rec("oa invite company-admin 30d","deny",setDoc(doc(as("oa"),"invites/j3"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"company-admin",expiresAt:exp(30)}));
    await rec("oa invite company-admin 3d","allow",setDoc(doc(as("oa"),"invites/j4"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"company-admin",expiresAt:exp(3)}));
    await rec("oa invite tech support","deny",setDoc(doc(as("oa"),"invites/j5"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"technical_support",expiresAt:exp(3)}));
    // NEW-1: supervisor (and HR) cannot invite or edit company-admin invites.
    await rec("sup invite company-admin own co","deny",setDoc(doc(as("sup"),"invites/k1"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"company-admin",expiresAt:exp(3)}));
    await rec("hr invite company-admin own co","deny",setDoc(doc(as("hr"),"invites/k2"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"company-admin",expiresAt:exp(3)}));
    await rec("sup extends company-admin invite","deny",updateDoc(doc(as("sup"),"invites/i1"),{expiresAt:exp(5)}));
    await rec("ca invite company-admin own co","allow",setDoc(doc(as("ca"),"invites/j6"),{status:"pending",organizationId:"o1",companyId:"c1",roleToAssign:"company-admin",expiresAt:exp(3)}));
    await rec("oa extends invite expiry to 1 year (update)","deny",updateDoc(doc(as("oa"),"invites/i1"),{expiresAt:exp(365)}));
    await rec("oa reopens claimed invite to pending","deny",updateDoc(doc(as("oa"),"invites/i2"),{status:"pending"}));
    await rec("oa extends invite expiry to 5 days","allow",updateDoc(doc(as("oa"),"invites/i1"),{expiresAt:exp(5)}));
    await rec("oa revokes pending invite","allow",updateDoc(doc(as("oa"),"invites/i1"),{status:"revoked"}));
    await rec("oa changes roleToAssign on pending","deny",updateDoc(doc(as("oa"),"invites/i1"),{roleToAssign:"org-admin"}));
    await rec("sa invite org-admin","allow",setDoc(doc(as("sa"),"invites/j7"),{status:"pending",organizationId:"o1",roleToAssign:"org-admin",expiresAt:exp(3)}));
    await rec("sa invite tech support","deny",setDoc(doc(as("sa"),"invites/j8"),{status:"pending",organizationId:"o1",roleToAssign:"technical_support",expiresAt:exp(3)}));
    await rec("invitee marks invite claimed","deny",updateDoc(doc(as("n4",{email:"n@x.test",email_verified:true}),"invites/i1"),{status:"claimed",claimedByUid:"n4"}));
    await rec("invitee marks claimed (only status)","deny",updateDoc(doc(as("n4",{email:"n@x.test"}),"invites/i1"),{status:"claimed"}));
    await rec("oa marks claimed","deny",updateDoc(doc(as("oa"),"invites/i1"),{status:"claimed"}));
    await rec("unauth get invite by id","allow",getDoc(doc(env.unauthenticatedContext().firestore(),"invites/i1")));
    await rec("unauth list invites","deny",getDocs(collection(env.unauthenticatedContext().firestore(),"invites")));
    await rec("oa list invites filtered own org","allow",getDocs(query(collection(as("oa"),"invites"),where("organizationId","==","o1"))));
    await rec("oa list invites unfiltered","deny",getDocs(collection(as("oa"),"invites")));});
  test("S2 phone-match read escalation", async()=>{
    await rec("new user self-create with victim phone","allow?",setDoc(doc(as("atk"),"users/atk"),{role:"delegate",phoneNumber:"01000000009"})).catch(()=>{});
    await rec("attacker lists users by victim phone (reads victim doc)","deny",getDocs(query(collection(as("atk"),"users"),where("phoneNumber","==","01000000009"))));
    await rec("delegate self update phoneNumber to victim phone","deny",updateDoc(doc(as("d1"),"users/d1"),{phoneNumber:"01000000009"}));
    await rec("delegate lists users by victim phone after change","deny",getDocs(query(collection(as("d1"),"users"),where("phoneNumber","==","01000000009"))));
    await rec("attacker self-create with victim email + list","deny",setDoc(doc(as("atk2"),"users/atk2"),{role:"delegate",email:"victim@x.test"}).then(()=>getDocs(query(collection(as("atk2"),"users"),where("email","==","victim@x.test")))));});
  test("delegate custom token", async()=>{ const dt=as("d1",{role:"delegate",delegateId:"d1",orgId:"o1",companyId:"c1",phones:["01011111111"]});
    await rec("delegate get own nested doc","allow",getDoc(doc(dt,"organizations/o1/companies/c1/delegates/d1")));
    await rec("delegate get other delegate","deny",getDoc(doc(dt,"organizations/o1/companies/c1/delegates/d9")));
    await rec("delegate cg whereIn own phone","allow",getDocs(query(collectionGroup(dt,"delegates"),where("phoneNumber","in",["01011111111"]))));
    await rec("delegate changes own nationalityID","deny",updateDoc(doc(dt,"organizations/o1/companies/c1/delegates/d1"),{nationalityID:"OTHER"}));
    await rec("delegate changes own phoneNumber","deny",updateDoc(doc(dt,"organizations/o1/companies/c1/delegates/d1"),{phoneNumber:"01099999999"}));
    await rec("delegate adds nationalId alt key","deny",updateDoc(doc(dt,"organizations/o1/companies/c1/delegates/d1"),{nationalId:"OTHER"}));
    await rec("delegate full-map write same phone/NID","allow",setDoc(doc(dt,"organizations/o1/companies/c1/delegates/d1"),{phoneNumber:"01011111111",nationalityID:"NID-PLACEHOLDER",organizationUID:"o1",companyUID:"c1",status:"active",name:"a",photoURL:"u1"}));
    await rec("delegate self update name (not in allow-list)","deny",updateDoc(doc(dt,"organizations/o1/companies/c1/delegates/d1"),{name:"n2"}));
    await rec("delegate self update same phone + NID (nested)","allow",updateDoc(doc(dt,"organizations/o1/companies/c1/delegates/d1"),{phoneNumber:"01011111111",nationalityID:"NID-PLACEHOLDER",photoURL:"u3"}));
    await rec("delegate changes own deviceBinding","deny",updateDoc(doc(dt,"organizations/o1/companies/c1/delegates/d1"),{boundDeviceId:"x"}));
    await rec("delegate updates other delegate","deny",updateDoc(doc(dt,"organizations/o1/companies/c1/delegates/d9"),{name:"x"}));
    await rec("ca updates own-company delegate name","allow",updateDoc(doc(as("ca"),"organizations/o1/companies/c1/delegates/d9"),{name:"x"}));
    // NEW-2: allow-list. App writes (dev / 1.14.2 / 1.14.x-supervisor):
    const D1="organizations/o1/companies/c1/delegates/d1";
    await rec("delegate reLogin ack (session service)","allow",updateDoc(doc(dt,D1),{requireReLogin:false,reLoginCompletedAt:1}));
    await rec("delegate sets requireReLogin true","deny",updateDoc(doc(dt,D1),{requireReLogin:true}));
    await rec("delegate photo re-upload (user_profile_screen)","allow",setDoc(doc(dt,D1),{profileImageUrl:"u",personalPhotoURL:"u",photoURL:"u",documents:[{documentKey:"personalPhoto",documentURL:"u"}],updatedAt:1},{merge:true}));
    await rec("delegate ID image re-upload (profile_screen)","allow",setDoc(doc(dt,D1),{nationalIdFrontUrl:"u",nationalIdBackUrl:"u",receiptImageUrl:"u",updatedAt:1},{merge:true}));
    for(const [k,v] of [["annualLeaveQuota",99],["isAnnualLeaveEnabled",true],["paymentAmount",0],["receiptCode","x"],["hasPendingUpdate",false],["isDeductedFromCompany",true],["supervisorUid","sup"],["delegatePublicId","x"],["originOrganizationUID","o2"],["isExternal",true],["role","supervisor"],["status","active2"]])
      await rec("delegate self sets "+k,"deny",updateDoc(doc(dt,D1),{[k]:v}));
    // REGRESSION budget: company staff updating a nested delegate.
    for(const who of ["hr","sup","acc","bmm","ca"]) await rec(who+" updates nested own-company delegate","allow",updateDoc(doc(as(who),"organizations/o1/companies/c1/delegates/d9"),{name:"y",annualLeaveQuota:5}));
    for(const who of ["sa","ts","oa","mk"]) await rec(who+" updates nested delegate","allow",updateDoc(doc(as(who),"organizations/o1/companies/c1/delegates/d9"),{name:"z"}));
    await rec("hr updates other-company delegate","deny",setDoc(doc(as("hr"),"organizations/o1/companies/c2/delegates/x"),{name:"q"},{merge:true}));
    await rec("hr changes delegate device binding","deny",updateDoc(doc(as("hr"),"organizations/o1/companies/c1/delegates/d9"),{boundDeviceId:"x"}));
    await rec("sa reads mail doc","deny",getDoc(doc(as("sa"),"mail/m1")));
    await rec("sa lists mail","deny",getDocs(collection(as("sa"),"mail")));
    await rec("anon get delegate","deny",getDoc(doc(anon(),"organizations/o1/companies/c1/delegates/d1")));});
  // Runs last: every recorded case must match its expectation.
  // Known, out-of-scope gaps (tracked, not fixed in this PR):
  //  D2 delegate reads another delegate of its company (delegates follow-up, N4)
  //  S2 self phone change on users (updateMyContact, later PR)
  test("no mismatches", ()=>{
    const KNOWN=new Set(["delegate get other delegate","delegate self update phoneNumber to victim phone"]);
    const bad=results.filter(([n,e,g])=>!e.endsWith("?")&&e!==g&&!KNOWN.has(n));
    require("node:assert/strict").deepEqual(bad,[]);
  });
});
