import { createServer } from "node:http";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { makeAPI } from "./api.js";
import { openStore } from "./store.js";

const host = process.env.HOST ?? "127.0.0.1";
const port = Number(process.env.PORT ?? 8080);
const dbPath = process.env.DB_PATH ?? "data/nek.sqlite";
mkdirSync(dirname(dbPath), { recursive: true });
const store = openStore(dbPath);
const api = makeAPI(store);

const server = createServer(async (incoming, outgoing) => {
  try {
    const parts = [];
    let size = 0;
    for await (const part of incoming.iterator({ destroyOnReturn: false })) {
      size += part.length;
      if (size > 8_192) {
        outgoing.writeHead(413, { Connection: "close", "Content-Type": "application/json" });
        outgoing.end(JSON.stringify({ message: "Слишком большой запрос." }));
        return;
      }
      parts.push(part);
    }
    const body = parts.length && !["GET", "HEAD"].includes(incoming.method)
      ? Buffer.concat(parts) : undefined;
    const headers = new Headers(incoming.headers);
    const url = new URL(incoming.url, "http://localhost");
    const result = await api(new Request(url, { method: incoming.method, headers, body }));
    outgoing.writeHead(result.status, Object.fromEntries(result.headers));
    outgoing.end(Buffer.from(await result.arrayBuffer()));
  } catch (error) {
    console.error(error.message);
    outgoing.writeHead(500, { "Content-Type": "application/json" });
    outgoing.end(JSON.stringify({ message: "Сервер не смог обработать запрос." }));
  }
});
server.listen(port, host, () => console.log(`NEK API · http://${host}:${port}`));
for (const signal of ["SIGTERM", "SIGINT"]) {
  process.once(signal, () => server.close(() => store.close()));
}
