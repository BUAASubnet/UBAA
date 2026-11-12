const timeZone = "Asia/Shanghai";
const campusFormatter = new Intl.DateTimeFormat("en-CA", {
  timeZone,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

const campusClock = new Intl.DateTimeFormat("en-GB", {
  timeZone,
  hourCycle: "h23",
  hour: "2-digit",
  minute: "2-digit",
});

export function campusDay(instant: Date): string {
  const parts = campusFormatter.formatToParts(instant);
  const year = parts.find(({ type }) => type === "year")?.value;
  const month = parts.find(({ type }) => type === "month")?.value;
  const day = parts.find(({ type }) => type === "day")?.value;
  return `${year}-${month}-${day}`;
}

export function campusMinute(instant: Date): string {
  return `${campusDay(instant)}T${campusClock.format(instant)}`;
}

export function shiftDay(day: string, days: number): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}
