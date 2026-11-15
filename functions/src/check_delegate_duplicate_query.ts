/** Shared Firestore uniqueness scan used by check/edit/submit/review. */
import {
  decideDuplicate,
  DuplicateDecision,
  DuplicateField,
  DuplicateHit,
  duplicateHitFromDoc,
  isExistingDelegateStatus,
  isOpenRequestStatus,
  isExcludableDelegateRecord,
  normalizeEgyptianPhone,
  phoneQueryVariants,
  publicDuplicateResult,
} from "./check_delegate_duplicate_logic";

export interface FindDuplicateOpts {
  nationalId?: string;
  phoneNumber?: string;
  companyUID: string;
  excludeDelegateUid?: string;
}

export async function findDuplicateDecision(
  db: FirebaseFirestore.Firestore,
  opts: FindDuplicateOpts,
): Promise<DuplicateDecision> {
  const hits: DuplicateHit[] = [];
  const seen = new Set<string>();
  const addHit = (data: FirebaseFirestore.DocumentData, kind: DuplicateField) => {
    const hit = duplicateHitFromDoc(data, kind);
    const key = `${hit.companyUID}|${hit.field}`;
    if (seen.has(key)) return;
    seen.add(key);
    hits.push(hit);
  };

  const scanRequests = async (
    field: "nationalId" | "nationalityID" | "phoneNumber",
    value: string,
    kind: DuplicateField,
  ) => {
    const company = opts.companyUID.trim();
    const scans: Promise<FirebaseFirestore.QuerySnapshot>[] = [];
    if (company) {
      scans.push(
        db.collection("delegate_requests")
          .where("companyUID", "==", company)
          .where(field, "==", value)
          .get(),
        db.collection("delegate_requests")
          .where("companyId", "==", company)
          .where(field, "==", value)
          .get(),
      );
    } else {
      scans.push(db.collection("delegate_requests").where(field, "==", value).get());
    }
    const results = await Promise.all(scans);
    for (const snap of results) {
      for (const doc of snap.docs) {
        if (isExcludableDelegateRecord(doc.data(), doc.id, opts.excludeDelegateUid, opts.companyUID)) continue;
        if (!isOpenRequestStatus(doc.data().status)) continue;
        addHit(doc.data(), kind);
      }
    }
  };

  const scanDelegates = async (
    field: "nationalId" | "nationalityID" | "phoneNumber",
    value: string,
    kind: DuplicateField,
  ) => {
    const snap = await db.collectionGroup("delegates").where(field, "==", value).get();
    for (const doc of snap.docs) {
      if (isExcludableDelegateRecord(doc.data(), doc.id, opts.excludeDelegateUid, opts.companyUID)) continue;
      if (!isExistingDelegateStatus(doc.data().status)) continue;
      addHit(doc.data(), kind);
    }
  };

  if (opts.nationalId) {
    await scanRequests("nationalId", opts.nationalId, "nationalId");
    await scanRequests("nationalityID", opts.nationalId, "nationalId");
    await scanDelegates("nationalId", opts.nationalId, "nationalId");
    await scanDelegates("nationalityID", opts.nationalId, "nationalId");
  }
  const phoneLocal = opts.phoneNumber ? normalizeEgyptianPhone(opts.phoneNumber) : "";
  if (phoneLocal) {
    const variants = phoneQueryVariants(opts.phoneNumber as string);
    for (const v of variants) {
      await scanRequests("phoneNumber", v, "phoneNumber");
      await scanDelegates("phoneNumber", v, "phoneNumber");
    }
  }

  return decideDuplicate(opts.companyUID, hits);
}

export async function findDuplicatePublic(
  db: FirebaseFirestore.Firestore,
  opts: FindDuplicateOpts,
) {
  return publicDuplicateResult(await findDuplicateDecision(db, opts));
}
