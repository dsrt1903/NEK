import { authenticate } from "./store.js";
import { candidateSlots, daysFrom, masters, services } from "./studio.js";

const json = (value, status = 200) => Response.json(value, {
  status, headers: { "Cache-Control": "no-store" }
});
const problem = (status, message) => json({ message }, status);

function bookingView(store, row) {
  const { client, ...booking } = row;
  return {
    ...booking,
    clientName: store.clientName(client),
    serviceName: services.find(item => item.id === row.serviceId)?.name ?? row.serviceId,
    masterName: masters.find(item => item.id === row.masterId)?.name ?? row.masterId
  };
}

export function makeAPI(store, clock = () => new Date()) {
  return async (request) => {
    const { pathname, searchParams } = new URL(request.url);
    const route = request.method + " " + pathname;
    const now = clock();
    if (route === "GET /api/health") return json({ status: "ok" });
    if (route === "POST /api/session") {
      const body = await request.json().catch(() => null);
      if (typeof body?.login !== "string" || typeof body?.password !== "string"
          || body.login.length > 64 || body.password.length > 128) {
        return problem(400, "Укажите логин и пароль.");
      }
      const account = authenticate(body.login.trim().toLowerCase(), body.password);
      if (!account) return problem(401, "Неверный логин или пароль.");
      return json({ account, token: store.createSession(account.login, now.getTime()) }, 201);
    }

    const token = /^Bearer ([a-f0-9]{64})$/.exec(request.headers.get("Authorization") ?? "")?.[1];
    const account = token && store.accountFor(token, now.getTime());
    if (!account) return problem(401, "Войдите в приложение повторно.");

    if (route === "DELETE /api/session") {
      store.signOut(token);
      return json({ status: "ok" });
    }
    if (route === "GET /api/catalog") {
      const days = daysFrom(now);
      const defaultDay = days.find(day => candidateSlots(day, services[0].duration, now).length) ?? days[0];
      return json({ services, masters, days, defaultDay });
    }

    if (route === "GET /api/schedule") {
      if (account.role !== "admin") return problem(403, "Расписание доступно администратору.");
      const day = searchParams.get("day");
      if (!daysFrom(now).includes(day)) return problem(400, "Выберите день из расписания.");
      return json(store.dayBookings(day).map(row => bookingView(store, row)));
    }

    if (route === "GET /api/bookings") {
      return json(store.clientBookings(account.login).map(row => bookingView(store, row)));
    }
    if (route === "GET /api/slots" || route === "POST /api/bookings") {
      const creating = request.method === "POST";
      if (creating && account.role !== "client") return problem(403, "Запись создаётся из кабинета клиента.");
      const input = creating ? await request.json().catch(() => null) : Object.fromEntries(searchParams);
      const service = services.find(item => item.id === input?.serviceId);
      const master = masters.find(item => item.id === input?.masterId);
      if (!service || !master || !daysFrom(now).includes(input.day)) {
        return problem(400, "Проверьте услугу, специалиста и дату.");
      }
      const slots = candidateSlots(input.day, service.duration, now);
      if (!creating) return json(slots.filter(slot => store.available(master.id, slot)));

      const slot = slots.find(item => item.startsAt === input.startsAt);
      if (!slot) return problem(400, "Выберите время из списка свободных окон.");
      const row = { client: account.login, serviceId: service.id, masterId: master.id, ...slot };
      const id = store.createBooking(row);
      if (!id) return problem(409, "Это время уже занято. Выберите другое окно.");
      return json(bookingView(store, { id, ...row }), 201);
    }
    return problem(404, "Такого маршрута нет.");
  };
}
