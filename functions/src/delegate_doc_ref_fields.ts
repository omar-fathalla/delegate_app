/**
 * TAS-331: Firestore fields a document re-upload writes on the delegate /
 * request doc: the legacy URL fields plus the Storage path field (deleted
 * when the caller sent only a URL, so a stale path never wins).
 */
import {FieldValue} from "firebase-admin/firestore";
import {
  pathFieldsForDocType,
  urlFieldsForDocType,
} from "./supervisor_delegate_doc_reupload_logic";

export function refFieldsForDocType(
  docType: string,
  newUrl: string,
  newPath: string,
): Record<string, unknown> {
  const out: Record<string, unknown> = {...urlFieldsForDocType(docType, newUrl)};
  for (const [k, v] of Object.entries(pathFieldsForDocType(docType, newPath))) {
    out[k] = v ?? FieldValue.delete();
  }
  return out;
}
