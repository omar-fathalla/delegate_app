import * as admin from "firebase-admin";
import {normalizePhone, phoneQueryVariants} from "./delegate_login_logic";
import {phoneOwnedByOther} from "./staff_phones_claim_logic";

export type PhoneOwnerHit = {collection: "users" | "delegate"; id: string};

/**
 * Returns owners of the phone variants excluding `excludeUid` when scanning users.
 */
export async function findPhoneOwners(
  db: FirebaseFirestore.Firestore,
  phoneRaw: string,
  excludeUid: string,
): Promise<PhoneOwnerHit[]> {
  const normalized = normalizePhone(phoneRaw);
  if (!normalized) return [];
  const variants = phoneQueryVariants(normalized);
  const hits: PhoneOwnerHit[] = [];
  const seen = new Set<string>();

  const add = (collection: PhoneOwnerHit["collection"], id: string) => {
    const key = `${collection}|${id}`;
    if (seen.has(key)) return;
    seen.add(key);
    hits.push({collection, id});
  };

  for (const v of variants) {
    const userSnap = await db.collection("users").where("phoneNumber", "==", v).limit(5).get();
    for (const doc of userSnap.docs) {
      if (doc.id !== excludeUid) add("users", doc.id);
    }
    const delSnap = await db.collectionGroup("delegates").where("phoneNumber", "==", v).limit(5).get();
    for (const doc of delSnap.docs) {
      add("delegate", doc.id);
    }
  }

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