export function isCurrentAnnouncement(announcement, now) {
  return (
    Date.parse(announcement.starts_at) <= now &&
    (announcement.ends_at === undefined ||
      now < Date.parse(announcement.ends_at))
  );
}
