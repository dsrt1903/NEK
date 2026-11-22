import { createHash, randomBytes, scryptSync, timingSafeEqual } from "node:crypto";
import { DatabaseSync } from "node:sqlite";

const accounts = new Map([
  ["client", { name: "Милана", role: "client", password: "client-demo" }],
  ["admin", { name: "Администратор NEK", role: "admin", password: "admin-demo" }],
  ["guest", { name: "Давид", role: "client", password: "guest-demo" }]
].map(([login, { name, role, password }]) => {
  const salt = randomBytes(16);
  return [login, { login, name, role, salt, digest: scryptSync(password, salt, 32) }];
}));
const fallbackSalt = randomBytes(16);
const tokenHash = token => createHash("sha256").update(token).digest("hex");

export function authenticate(login, password) {
  const account = accounts.get(login);
  const digest = scryptSync(password, account?.salt ?? fallbackSalt, 32);
  if (!account || !timingSafeEqual(account.digest, digest)) return null;
  return { login: account.login, name: account.name, role: account.role };
}

export function openStore(path) {
  const db = new DatabaseSync(path);
  db.exec(`
    PRAGMA busy_timeout = 3000;
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY, login TEXT NOT NULL, expires_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS bookings (
      id INTEGER PRIMARY KEY, client TEXT NOT NULL, service_id TEXT NOT NULL,
      master_id TEXT NOT NULL, starts_at TEXT NOT NULL, ends_at TEXT NOT NULL,
      CHECK (starts_at < ends_at)
    );
    CREATE INDEX IF NOT EXISTS bookings_master_start ON bookings(master_id, starts_at);
  `);

  // NEK uses the Epil TJ half-open occupancy rule. A master's adjacent visits may touch.
  const conflict = db.prepare(`
    SELECT 1 FROM bookings WHERE master_id = ? AND starts_at < ? AND ends_at > ? LIMIT 1
  `);
  const insert = db.prepare(`
    INSERT INTO bookings (client, service_id, master_id, starts_at, ends_at) VALUES (?, ?, ?, ?, ?)
  `);
  const select = `
    SELECT id, client, service_id AS serviceId, master_id AS masterId,
      starts_at AS startsAt, ends_at AS endsAt FROM bookings
  `;
  const forClient = db.prepare(select + " WHERE client = ? ORDER BY starts_at, id");
  const forDay = db.prepare(select + " WHERE starts_at >= ? AND starts_at < ? ORDER BY starts_at, id");
  const lookupSession = db.prepare("SELECT login FROM sessions WHERE token_hash = ? AND expires_at > ?");

  return {
    createSession(login, now) {
      const token = randomBytes(32).toString("hex");
      db.prepare("DELETE FROM sessions WHERE expires_at <= ?").run(now);
      db.prepare("INSERT INTO sessions VALUES (?, ?, ?)").run(tokenHash(token), login, now + 8 * 3_600_000);
      return token;
    },
    accountFor(token, now) {
      const session = lookupSession.get(tokenHash(token), now);
      const account = accounts.get(session?.login);
      return account && { login: account.login, role: account.role, name: account.name };
    },
    signOut(token) {
      db.prepare("DELETE FROM sessions WHERE token_hash = ?").run(tokenHash(token));
    },
    available(masterId, { startsAt, endsAt }) {
      return !conflict.get(masterId, endsAt, startsAt);
    },
    createBooking({ client, serviceId, masterId, startsAt, endsAt }) {
      db.exec("BEGIN IMMEDIATE");
      try {
        const occupied = conflict.get(masterId, endsAt, startsAt);
        const result = occupied ? null : insert.run(client, serviceId, masterId, startsAt, endsAt);
        db.exec("COMMIT");
        return result ? Number(result.lastInsertRowid) : null;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
    },
    clientBookings(login) {
      return forClient.all(login);
    },
    dayBookings(day) {
      const midnight = Date.parse(day + "T00:00:00+05:00");
      return forDay.all(new Date(midnight).toISOString(), new Date(midnight + 86_400_000).toISOString());
    },
    clientName(login) {
      return accounts.get(login)?.name ?? "Клиент";
    },
    close() { db.close(); }
  };
}
