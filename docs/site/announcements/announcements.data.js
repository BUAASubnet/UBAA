import { loadAnnouncements } from "../../../scripts/check/app_service/content.mjs";

export default {
  watch: ["./*.md"],
  load(files) {
    return { builtAt: Date.now(), announcements: loadAnnouncements(files) };
  },
};
