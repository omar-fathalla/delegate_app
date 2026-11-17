import * as admin from "firebase-admin";
import {normalizePhone} from "./delegate_login_logic";
import {
  PHONE_OWNER_FIELDS,
  docHoldsPhone,
  normalizeStoredPhone,
  phoneCollisionQueryValues,
  phoneOwnedByOther,
} from "./staff_phones_claim_logic";

export type PhoneOwnerHit = {collection: "users" | "delegate"; id: string; path: string};

const SCAN_PAGE_SIZE = 500;

/**
 * Only these lookups are backed by an index in production
 * (users: automatic single-field; delegates: firestore.indexes.json
 * COLLECTION_GROUP override on phoneNumber). Any other field is covered by
 * the full scan.
 */
function indexedLookups(db: FirebaseFirestore.Firestore): {
  collection: PhoneOwnerHit["collection"];
  query: (field: string) => FirebaseFirestore.Query;
  fields: readonly string[];
}[] {
  return [
    {collection: "users", query: () => db.collection("users"), fields: PHONE_OWNER_FIELDS},
    {collection: "delegate", query: () => db.collectionGroup("delegates"), fields: ["phoneNumber"]},
  ];
}

/**
 * Every users doc and delegate doc, phone fields only, in document-id order.
 * Stored values can carry spaces, dashes, +20/0020 or Arabic digits, so only
 * a normalized comparison over all docs is complete.
 */
export async function scanPhoneOwnerDocs(
  db: FirebaseFirestore.Firestore,
  visit: (hit: PhoneOwnerHit, data: Record<string, unknown>) => void,
): Promise<void> {
  const sources: {collection: PhoneOwnerHit["collection"]; base: FirebaseFirestore.Query}[] = [
    {collection: "users", base: db.collection("users")},
    {collection: "delegate", base: db.collectionGroup("delegates")},
  ];
  for (const source of sources) {
    let last: FirebaseFirestore.QueryDocumentSnapshot | null = null;
    for (;;) {
      let q = source.base
        .select(...PHONE_OWNER_FIELDS)
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(SCAN_PAGE_SIZE);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      for (const doc of snap.docs) {
        visit({collection: source.collection, id: doc.id, path: doc.ref.path}, doc.data());
      }
      if (snap.size < SCAN_PAGE_SIZE) break;
      last = snap.docs[snap.docs.length - 1];
    }
  }
}

/**
 * Owners of `phoneRaw` (normalized) in any phone field of users or delegates,
 * excluding the users doc `excludeUid`.
 */
export async function findPhoneOwners(
  db: FirebaseFirestore.Firestore,
  phoneRaw: string,
  excludeUid: string,
): Promise<PhoneOwnerHit[]> {
  const target = normalizePhone(phoneRaw);
  if (!target) return [];
  const hits: PhoneOwnerHit[] = [];
  const seen = new Set<string>();
  const add = (hit: PhoneOwnerHit) => {
    if (hit.collection === "users" && hit.id === excludeUid) return;
    if (seen.has(hit.path)) return;
    seen.add(hit.path);
    hits.push(hit);
  };

  const values = phoneCollisionQueryValues(target);
  for (const lookup of indexedLookups(db)) {
    for (const field of lookup.fields) {
      const snap = await lookup.query(field).where(field, "in", values).limit(5).get();
      for (const doc of snap.docs) add({collection: lookup.collection, id: doc.id, path: doc.ref.path});
    }
  }
  if (hits.length > 0) return hits;

  await scanPhoneOwnerDocs(db, (hit, data) => {
    if (docHoldsPhone(data, target)) add(hit);
  });
  return hits;
}

export async function hasStaffPhoneCollision(
  db: FirebaseFirestore.Firestore,
  uid: string,
  phoneRaw: string,
): Promise<boolean> {
  const hits = await findPhoneOwners(db, phoneRaw, uid);
  return phoneOwnedByOther(uid, hits);
}

/** normalized phone -> every doc holding it in any phone field (one full scan). */
export async function buildPhoneOwnerIndex(
  db: FirebaseFirestore.Firestore,
): Promise<Map<string, PhoneOwnerHit[]>> {
  const index = new Map<string, PhoneOwnerHit[]>();
  await scanPhoneOwnerDocs(db, (hit, data) => {
    const phones = new Set(PHONE_OWNER_FIELDS.map((f) => normalizeStoredPhone(data[f])).filter(Boolean));
    for (const phone of phones) {
      const list = index.get(phone) || [];
      list.push(hit);
      index.set(phone, list);
    }
  });
  return index;
}

/** Collision from a prebuilt index, same semantics as hasStaffPhoneCollision. */
export function indexedStaffPhoneCollision(
  index: Map<string, PhoneOwnerHit[]>,
  uid: string,
  phoneRaw: string,
): boolean {
  const target = normalizeStoredPhone(phoneRaw);
  if (!target) return false;
  const hits = (index.get(target) || []).filter((h) => !(h.collection === "users" && h.id === uid));
  return phoneOwnedByOther(uid, hits);
}

/**
 * Read merged custom claims for a Firebase Auth user (empty when missing).
 */
export async function readAuthCustomClaims(uid: string): Promise<Record<string, unknown>> {
  try {
    const user = await admin.auth().getUser(uid);
    return {...(user.customClaims || {})};
  } catch {
    return {};
  }
}
