"use strict";

/**
 * Minimal in-memory Firestore used by Paymob scenario tests.
 * Supports the subset of the Admin SDK that subscription_jobs and the
 * webhook handler actually call. Not a general emulator.
 */
const {FieldValue, Timestamp} = require("firebase-admin/firestore");

function isServerTs(v) {
  try {
    return !!(v && typeof v.isEqual === "function" && FieldValue.serverTimestamp().isEqual(v));
  } catch {
    return false;
  }
}
function isDelete(v) {
  try {
    return !!(v && typeof v.isEqual === "function" && FieldValue.delete().isEqual(v));
  } catch {
    return false;
  }
}

function clone(v) {
  if (v == null) return v;
  if (v instanceof Timestamp || v instanceof Date) return v;
  if (Array.isArray(v)) return v.map(clone);
  if (typeof v === "object") {
    const out = {};
    for (const [k, val] of Object.entries(v)) out[k] = clone(val);
    return out;
  }
  return v;
}

function applySentinels(data, now) {
  if (data == null || typeof data !== "object" || data instanceof Timestamp || data instanceof Date) {
    return data;
  }
  if (Array.isArray(data)) return data.map((v) => applySentinels(v, now));
  const out = {};
  for (const [k, v] of Object.entries(data)) {
    if (isDelete(v)) continue;
    if (isServerTs(v)) out[k] = Timestamp.fromDate(now);
    else if (v && typeof v === "object" && !(v instanceof Timestamp) && !(v instanceof Date)) {
      out[k] = applySentinels(v, now);
    } else {
      out[k] = v;
    }
  }
  return out;
}

let _seq = 0;
function autoId() {
  _seq += 1;
  return `auto_${_seq}_${Math.random().toString(36).slice(2, 8)}`;
}

class MemSnap {
  constructor(ref, data) {
    this.ref = ref;
    this.id = ref.id;
    this._data = data ? clone(data) : null;
    this.exists = data != null;
  }
  data() {
    return this._data ? clone(this._data) : undefined;
  }
  get(field) {
    return this._data ? this._data[field] : undefined;
  }
}

class MemRef {
  constructor(db, path) {
    this._db = db;
    this.path = path.replace(/^\/+|\/+$/g, "");
    const parts = this.path.split("/");
    this.id = parts[parts.length - 1];
  }
  collection(name) {
    return new MemCol(this._db, `${this.path}/${name}`);
  }
  async get() {
    return new MemSnap(this, this._db._store.get(this.path));
  }
  async set(data, _options) {
    this._db._store.set(this.path, applySentinels(data, this._db.now()));
  }
  async delete() {
    this._db._store.delete(this.path);
  }
  async create(data) {
    if (this._db._store.has(this.path)) {
      const err = new Error(`Document already exists: ${this.path}`);
      err.code = 6;
      throw err;
    }
    await this.set(data);
  }
  async update(data) {
    if (!this._db._store.has(this.path)) {
      const err = new Error("no entity to update");
      err.code = 5;
      throw err;
    }
    const cur = clone(this._db._store.get(this.path));
    const patch = applySentinels(data, this._db.now());
    // Re-apply deletes from the original patch (applySentinels already dropped them).
    for (const [k, v] of Object.entries(data)) {
      if (isDelete(v)) delete cur[k];
      else if (patch[k] !== undefined) {
        if (patch[k] && typeof patch[k] === "object" && !Array.isArray(patch[k]) &&
            !(patch[k] instanceof Timestamp) && !(patch[k] instanceof Date) &&
            cur[k] && typeof cur[k] === "object") {
          cur[k] = {...cur[k], ...patch[k]};
        } else {
          cur[k] = patch[k];
        }
      }
    }
    this._db._store.set(this.path, cur);
  }
}

class MemCol {
  constructor(db, path, filters = [], groupName = null) {
    this._db = db;
    this.path = path.replace(/^\/+|\/+$/g, "");
    this._filters = filters;
    this._groupName = groupName;
  }
  doc(id) {
    return new MemRef(this._db, `${this.path}/${id || autoId()}`);
  }
  where(field, op, value) {
    return new MemCol(this._db, this.path, [...this._filters, {field, op, value}], this._groupName);
  }
  async get() {
    const docs = [];
    for (const [path, data] of this._db._store) {
      if (!this._matchesPath(path)) continue;
      if (!this._matchesFilters(data)) continue;
      docs.push(new MemSnap(new MemRef(this._db, path), data));
    }
    return {docs, size: docs.length, empty: docs.length === 0};
  }
  _matchesPath(path) {
    if (this._groupName) {
      const parts = path.split("/");
      return parts.length >= 2 && parts[parts.length - 2] === this._groupName;
    }
    if (!path.startsWith(this.path + "/")) return false;
    const rest = path.slice(this.path.length + 1);
    return rest.length > 0 && !rest.includes("/");
  }
  _matchesFilters(data) {
    return this._filters.every(({field, op, value}) => {
      const got = data[field];
      if (op === "==") return got === value;
      if (op === "in") return Array.isArray(value) && value.includes(got);
      return false;
    });
  }
}

class MemTx {
  constructor(db) {
    this._db = db;
  }
  get(ref) {
    return ref.get();
  }
  set(ref, data, options) {
    return ref.set(data, options);
  }
  create(ref, data) {
    return ref.create(data);
  }
  update(ref, data) {
    return ref.update(data);
  }
  delete(ref) {
    return ref.delete();
  }
}

class MemoryFirestore {
  constructor() {
    this._store = new Map();
    this._now = () => new Date();
  }
  now() {
    return this._now();
  }
  collection(name) {
    return new MemCol(this, name);
  }
  collectionGroup(name) {
    return new MemCol(this, `__group__:${name}`, [], name);
  }
  doc(path) {
    return new MemRef(this, path);
  }
  async getAll(...refs) {
    return Promise.all(refs.map((r) => r.get()));
  }
  async runTransaction(fn) {
    return fn(new MemTx(this));
  }
  batch() {
    const ops = [];
    return {
      set(ref, data) {
        ops.push(() => ref.set(data));
      },
      update(ref, data) {
        ops.push(() => ref.update(data));
      },
      delete(ref) {
        ops.push(() => ref.delete());
      },
      async commit() {
        for (const op of ops) await op();
      },
    };
  }
}

module.exports = {MemoryFirestore, Timestamp, FieldValue};
