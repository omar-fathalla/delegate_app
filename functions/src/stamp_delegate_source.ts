/**
 * Stamps delegateSource on a new (or still-unstamped) nested delegate doc.
 * Admin SDK only. Clients cannot write these fields (firestore.rules).
 *
 * Deploy: functions:tashil-mobile-notifications:stampDelegateSource
 * Do not deploy suspendExpiredSubscriptions with this function.
 */
import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";
import {
  inferChainOrigin,
  inferPersonSource,
  shouldSkipStamp,
  stampPayload,
  type ChainEvidence,
  type RequestEvidence,
  type WebCreateEvidence,
} from "./delegate_source_logic";

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function chainFromDoc(
  path: string,
  id: string,
  data: FirebaseFirestore.DocumentData,
): ChainEvidence {
  return {
    path,
    uid: str(data.uid) || id,
    organizationUID: str(data.organizationUID || data.organizationId),
    companyUID: str(data.companyUID || data.companyId),
    approvedRequestId: str(data.approvedRequestId),
    registeredVia: str(data.registeredVia),
    statusReason: str(data.statusReason),
    version: data.version,
    alreadyStamped: str(data.delegateSource) !== "",
  };
}

async function loadEvidence(uid: string, self: ChainEvidence): Promise<{
  appRequestById: RequestEvidence | null;
  chainDocs: ChainEvidence[];
  webCreates: WebCreateEvidence[];
  supervisorOrgId: string;
}> {
  const db = admin.firestore();
  const reqSnap = await db.collection("delegate_requests").doc(uid).get();
  let appRequestById: RequestEvidence | null = null;
  if (reqSnap.exists) {
    const d = reqSnap.data() || {};
    appRequestById = {
      id: reqSnap.id,
      requestType: str(d.requestType),
      status: str(d.status),
      supervisorUid: str(d.supervisorUid),
      existingDelegateUid: str(d.existingDelegateUid),
      organizationUID: str(d.organizationUID),
    };
  }

  const chainDocs: ChainEvidence[] = [self];
  try {
    const sib = await db.collectionGroup("delegates").where("uid", "==", uid).limit(20).get();
    const seen = new Set([self.path]);
    for (const doc of sib.docs) {
      if (seen.has(doc.ref.path)) continue;
      seen.add(doc.ref.path);
      chainDocs.push(chainFromDoc(doc.ref.path, doc.id, doc.data()));
    }
  } catch (e) {
    functions.logger.warn("stampDelegateSource sibling query failed", {uid, message: String(e)});
  }

  let webCreates: WebCreateEvidence[] = [];
  const mapWeb = (d: FirebaseFirestore.DocumentData, org = "", company = ""): WebCreateEvidence => ({
    targetDelegateId: str(d.targetDelegateId) || uid,
    organizationUID: str(d.organizationUID) || org,
    companyUID: str(d.companyUID) || company,
  });
  try {
    const web = await db.collectionGroup("requests")
      .where("targetDelegateId", "==", uid)
      .where("actionType", "==", "create")
      .limit(10)
      .get();
    webCreates = web.docs.map((doc) => mapWeb(doc.data() || {}));
  } catch (e) {
    functions.logger.warn("stampDelegateSource web requests query failed", {uid, message: String(e)});
    const seen = new Set<string>();
    for (const c of chainDocs) {
      const org = str(c.organizationUID);
      const company = str(c.companyUID);
      if (!org || !company || seen.has(`${org}/${company}`)) continue;
      seen.add(`${org}/${company}`);
      try {
        const snap = await db.collection(`organizations/${org}/companies/${company}/requests`)
          .where("actionType", "==", "create")
          .limit(50)
          .get();
        for (const doc of snap.docs) {
          const d = doc.data() || {};
          if (str(d.targetDelegateId) === uid) webCreates.push(mapWeb(d, org, company));
        }
      } catch (e2) {
        functions.logger.warn("stampDelegateSource nested web requests query failed", {
          org, company, message: String(e2),
        });
      }
    }
  }

  let supervisorOrgId = "";
  const sup = str(appRequestById?.supervisorUid);
  if (sup) {
    try {
      const u = await db.collection("users").doc(sup).get();
      supervisorOrgId = str(u.data()?.organizationUID);
    } catch (e) {
      functions.logger.warn("stampDelegateSource supervisor lookup failed", {uid: sup, message: String(e)});
    }
  }

  return {appRequestById, chainDocs, webCreates, supervisorOrgId};
}

async function stampIfMissing(
  ref: FirebaseFirestore.DocumentReference,
  data: FirebaseFirestore.DocumentData,
  delegateId: string,
): Promise<void> {
  if (shouldSkipStamp(data)) return;
  const self = chainFromDoc(ref.path, delegateId, data);
  const ev = await loadEvidence(self.uid, self);
  const person = inferPersonSource({
    uid: self.uid,
    appRequestById: ev.appRequestById,
    chainDocs: ev.chainDocs,
    webCreates: ev.webCreates,
  });
  const addOrg = ev.appRequestById
    ? str(ev.appRequestById.requestType) === "add_organization" &&
      str(ev.appRequestById.existingDelegateUid) === self.uid
    : false;
  const origin = inferChainOrigin({
    doc: self,
    person,
    supervisorOrgId: ev.supervisorOrgId,
    requestOrgId: ev.appRequestById?.organizationUID,
    hasAddOrganizationRequest: addOrg,
  });
  const payload = stampPayload(origin, person, "trigger", "trigger");
  await ref.update({
    ...payload,
    delegateSourceAt: FieldValue.serverTimestamp(),
  });
}

export const stampDelegateSource = functions.firestore
  .document("organizations/{orgId}/companies/{companyId}/delegates/{delegateId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const data = change.after.data() || {};
    if (shouldSkipStamp(data)) return null;
    try {
      await stampIfMissing(change.after.ref, data, context.params.delegateId);
    } catch (e) {
      functions.logger.error("stampDelegateSource failed", {
        path: change.after.ref.path,
        message: String(e),
      });
      throw e;
    }
    return null;
  });
