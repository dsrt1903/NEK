export const services = [
  { id: "consultation", name: "Консультация", duration: 30, price: 0, icon: "bubble.left" },
  { id: "laser-small", name: "Лазерная эпиляция · малая зона", duration: 45, price: 90, icon: "sparkles" },
  { id: "laser-combo", name: "Лазерная эпиляция · комплекс", duration: 60, price: 190, icon: "wand.and.stars" }
];

export const masters = [
  { id: "alina", name: "Алина" },
  { id: "sofia", name: "София" }
];

const studioDay = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Asia/Dushanbe", year: "numeric", month: "2-digit", day: "2-digit"
});
const slotStartMinutes = Array.from({ length: 16 }, (_, index) => 10 * 60 + index * 30);

export function daysFrom(now) {
  const first = Date.parse(studioDay.format(now) + "T00:00:00Z");
  return Array.from({ length: 7 }, (_, index) =>
    new Date(first + index * 86_400_000).toISOString().slice(0, 10)
  );
}

export function candidateSlots(day, duration, now) {
  if (!daysFrom(now).includes(day)) return [];
  const midnight = Date.parse(day + "T00:00:00+05:00");
  return slotStartMinutes
    .filter(minutes => minutes + duration <= 18 * 60)
    .map(minutes => {
      const value = midnight + minutes * 60_000;
      const startsAt = new Date(value).toISOString();
      const endsAt = new Date(value + duration * 60_000).toISOString();
      return { startsAt, endsAt };
    })
    .filter(slot => Date.parse(slot.startsAt) > now.getTime());
}
