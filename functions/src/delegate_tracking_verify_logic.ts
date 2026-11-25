/**
 * TAS-48: server check of delegate_tracking/{delegateId}.
 *
 * The delegate's own app writes the live tracking doc with the branch
 * coordinates, the geofence radius and its own inside/outside verdict, so a
 * modified app can claim "inside" by writing the branch coords = its own
 * position (or the status itself). The trigger recomputes the verdict from
 * the stored branch (staff-only writes, TAS-54) and stamps server-only
 * fields the supervisor/HR screens prefer. Old app builds keep writing the
 * same client fields; nothing they write is rejected here.
 */

/** Same tolerance the app adds on top of the branch radius (radius + 50 m). */
export const GEOFENCE_TOLERANCE_METERS = 50;
/** The app's default radius when the branch has none. */
export const DEFAULT_GEOFENCE_RADIUS = 100;
/**
 * Distance formulas differ by a meter or two between the app (Geolocator)
 * and here; a delegate standing on the edge must not be flagged for that.
 */
export const MISMATCH_MARGIN_METERS = 25;

/** Fields only the trigger writes. The rules deny them to every client. */
export const TRACKING_SERVER_FIELDS = [
  "verifiedStatus",
  "verifiedDistanceMeters",
  "verifiedBranchLat",
  "verifiedBranchLng",
  "verifiedBranchRadius",
  "verifiedReason",
  "verifiedAt",
  "statusMismatch",
  "scopeMismatch",
];

export type VerifiedStatus = "inside" | "outside" | "unknown";

export type VerifiedReason =
  | "ok"
  | "no_position"
  | "no_branch"
  | "branch_not_found"
  | "branch_without_location";

export interface TrackingInputs {
  lat: number | null;
  lng: number | null;
  branchId: string;
  organizationUID: string;
  companyUID: string;
  clientStatus: string;
}

export interface BranchGeofence {
  lat: number;
  lng: number;
  radius: number;
}

export interface TrackingVerification {
  verifiedStatus: VerifiedStatus;
  verifiedDistanceMeters: number | null;
  verifiedBranchLat: number | null;
  verifiedBranchLng: number | null;
  verifiedBranchRadius: number | null;
  verifiedReason: VerifiedReason;
  statusMismatch: boolean;
  scopeMismatch: boolean;
}

type Doc = Record<string, unknown> | null | undefined;

function str(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function coord(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

/** A real coordinate pair: finite, in range, and not the 0,0 placeholder. */
function validPair(lat: number | null, lng: number | null): boolean {
  if (lat == null || lng == null) return false;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return false;
  return !(lat === 0 && lng === 0);
}

/** The fields the verdict depends on, as the app wrote them. */
export function trackingInputs(data: Doc): TrackingInputs {
  const d = data || {};
  return {
    lat: coord(d.lastLatitude),
    lng: coord(d.lastLongitude),
    branchId: str(d.branchId),
    organizationUID: str(d.organizationUID) || str(d.organizationId),
    companyUID: str(d.companyUID) || str(d.companyId),
    clientStatus: str(d.currentStatus).toLowerCase(),
  };
}

export function sameInputs(a: TrackingInputs, b: TrackingInputs): boolean {
  return a.lat === b.lat && a.lng === b.lng && a.branchId === b.branchId
    && a.organizationUID === b.organizationUID && a.companyUID === b.companyUID
    && a.clientStatus === b.clientStatus;
}

/**
 * Loop guard. Run only when an input changed, or when the doc has no
 * verdict yet (first write, or a client set() that dropped it). The
 * trigger's own write changes verified* fields only, so it stops here.
 */
export function needsVerification(before: Doc, after: Doc): boolean {
  if (!after) return false;
  if (!before) return true;
  if (after.verifiedAt == null) return true;
  return !sameInputs(trackingInputs(before), trackingInputs(after));
}

/**
 * Branch geofence the way the app reads it: location.{latitude|lat,
 * longitude|lng}, then top-level latitude/longitude, radius default 100.
 */
export function branchGeofence(branch: Doc): BranchGeofence | null {
  if (!branch) return null;
  const loc = (branch.location && typeof branch.location === "object") ?
    branch.location as Record<string, unknown> : {};
  const lat = coord(loc.latitude) ?? coord(loc.lat) ?? coord(branch.latitude);
  const lng = coord(loc.longitude) ?? coord(loc.lng) ?? coord(branch.longitude);
  if (!validPair(lat, lng)) return null;
  const r = coord(branch.geofenceRadius);
  return {lat: lat as number, lng: lng as number, radius: r != null && r > 0 ? r : DEFAULT_GEOFENCE_RADIUS};
}

/** Great-circle distance in meters (haversine, mean Earth radius). */
export function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371008.8;
  const rad = (x: number) => x * Math.PI / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** True when the delegate link doc is a live member (exists, not deleted). */
export function isLiveMembership(link: Doc): boolean {
  if (!link) return false;
  const status = str(link.status).toLowerCase();
  return !["deleted", "removed", "archived"].includes(status);
}

export interface VerifyInput {
  inputs: TrackingInputs;
  /** null when branchId is empty or the branch doc was not found. */
  branch: Doc;
  /** organizations/{org}/companies/{co}/delegates/{delegateId}, or null. */
  membership: Doc;
}

/**
 * The server verdict. statusMismatch only compares the geofence statuses
 * (inside/outside); offline, checked_out and the like are left alone.
 */
export function verifyTracking({inputs, branch, membership}: VerifyInput): TrackingVerification {
  const scopeMismatch = !(inputs.organizationUID && inputs.companyUID && isLiveMembership(membership));
  const base: TrackingVerification = {
    verifiedStatus: "unknown",
    verifiedDistanceMeters: null,
    verifiedBranchLat: null,
    verifiedBranchLng: null,
    verifiedBranchRadius: null,
    verifiedReason: "ok",
    statusMismatch: false,
    scopeMismatch,
  };
  const claimsInside = inputs.clientStatus === "inside";

  if (!validPair(inputs.lat, inputs.lng)) return {...base, verifiedReason: "no_position"};
  if (!inputs.branchId) return {...base, verifiedReason: "no_branch"};
  if (!branch) {
    // A branch id that matches no branch cannot back an "inside" claim.
    return {...base, verifiedReason: "branch_not_found", statusMismatch: claimsInside};
  }
  const fence = branchGeofence(branch);
  if (!fence) return {...base, verifiedReason: "branch_without_location"};

  const distance = haversineMeters(inputs.lat as number, inputs.lng as number, fence.lat, fence.lng);
  const limit = fence.radius + GEOFENCE_TOLERANCE_METERS;
  const verifiedStatus: VerifiedStatus = distance <= limit ? "inside" : "outside";
  let statusMismatch = false;
  if (claimsInside) statusMismatch = distance > limit + MISMATCH_MARGIN_METERS;
  else if (inputs.clientStatus === "outside") statusMismatch = distance < limit - MISMATCH_MARGIN_METERS;

  return {
    ...base,
    verifiedStatus,
    verifiedDistanceMeters: Math.round(distance * 10) / 10,
    verifiedBranchLat: fence.lat,
    verifiedBranchLng: fence.lng,
    verifiedBranchRadius: fence.radius,
    statusMismatch,
  };
}
