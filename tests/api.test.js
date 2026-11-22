import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { makeAPI } from "../src/server/api.js";
import { openStore } from "../src/server/store.js";

const instant = new Date("2026-11-22T04:00:00Z");
const day = "2026-11-22";
const startsAt = "2026-11-22T05:00:00.000Z";
const booking = { day, startsAt, masterId: "alina", serviceId: "laser-small" };
const slots = "/api/slots?" + new URLSearchParams({ day, masterId: "alina", serviceId: "laser-small" });

function fixture(t, path = ":memory:") {
  const store = openStore(path);
  t.after(() => store.close());
  return requestTo(makeAPI(store, () => instant));
}

function requestTo(api) {
  return (path, { method = "GET", token, body } = {}) => api(new Request("http://localhost" + path, {
    method, headers: token ? { Authorization: "Bearer " + token } : {},
    body: body === undefined ? undefined : JSON.stringify(body)
  }));
}

async function login(send, name) {
  const response = await send("/api/session", {
    method: "POST", body: { login: name, password: name + "-demo" }
  });
  assert.equal(response.status, 201);
  return (await response.json()).token;
}

function book(send, token, body = booking) {
  return send("/api/bookings", { method: "POST", token, body });
}

test("вход, разграничение ролей и отзыв токена при выходе", async t => {
  const send = fixture(t);
  assert.equal((await send("/api/health")).status, 200);
  assert.equal((await send("/api/catalog")).status, 401);
  assert.equal((await send("/api/session", { method: "POST", body: { login: "client", password: "wrong" } })).status, 401);
  const client = await login(send, "client");
  const admin = await login(send, "admin");
  assert.equal((await send("/api/schedule?day=" + day, { token: client })).status, 403);
  assert.equal((await book(send, admin)).status, 403);
  assert.equal((await send("/api/session", { method: "DELETE", token: client })).status, 200);
  assert.equal((await send("/api/catalog", { token: client })).status, 401);
});

test("запись исчезает из доступных окон и отображается в календаре администратора", async t => {
  const send = fixture(t);
  const client = await login(send, "client");
  const admin = await login(send, "admin");
  const guest = await login(send, "guest");
  const initial = await (await send(slots, { token: client })).json();
  assert.equal(initial[0].startsAt, startsAt);
  const created = await book(send, client);
  assert.equal(created.status, 201);
  const row = await created.json();
  assert.equal(row.endsAt, "2026-11-22T05:45:00.000Z");
  const updated = await (await send(slots, { token: client })).json();
  assert.equal(updated[0].startsAt, "2026-11-22T06:00:00.000Z");
  assert.deepEqual(await (await send("/api/bookings", { token: client })).json(), [row]);
  assert.deepEqual(await (await send("/api/bookings", { token: guest })).json(), []);
  assert.deepEqual(await (await send("/api/schedule?day=" + day, { token: admin })).json(), [row]);
});

test("конкурирующие запросы: одна запись и один 409, другой мастер доступен", async t => {
  const send = fixture(t);
  const client = await login(send, "client");
  const guest = await login(send, "guest");
  const results = await Promise.all([book(send, client), book(send, guest)]);
  assert.deepEqual(results.map(response => response.status).sort(), [201, 409]);
  assert.equal((await book(send, client, { ...booking, masterId: "sofia" })).status, 201);
});

test("смежные визиты возможны, время вне сетки и за пределами недели отклоняется", async t => {
  const send = fixture(t);
  const client = await login(send, "client");
  const short = { ...booking, serviceId: "consultation" };
  assert.equal((await book(send, client, short)).status, 201);
  assert.equal((await book(send, client, { ...short, startsAt: "2026-11-22T05:30:00.000Z" })).status, 201);
  assert.equal((await book(send, client, { ...short, startsAt: "2026-11-22T05:05:00.000Z" })).status, 400);
  assert.equal((await book(send, client, { ...short, day: "2026-11-29" })).status, 400);
});

test("файл SQLite сохраняет записи после перезапуска", async () => {
  const dir = mkdtempSync(join(tmpdir(), "nek-test-"));
  try {
    const path = join(dir, "test.sqlite");
    let store = openStore(path);
    try {
      const send = requestTo(makeAPI(store, () => instant));
      assert.equal((await book(send, await login(send, "client"))).status, 201);
    } finally {
      store.close();
    }
    store = openStore(path);
    try {
      const send = requestTo(makeAPI(store, () => instant));
      const rows = await (await send("/api/bookings", { token: await login(send, "client") })).json();
      assert.equal(rows[0].startsAt, startsAt);
    } finally {
      store.close();
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
