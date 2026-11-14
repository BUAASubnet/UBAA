import { readFileSync } from "node:fs";
import source from "./download-source.json" with { type: "json" };

export { describe } from "./download_model.js";
import { describe } from "./download_model.js";

export default {
  watch: ["./download.json", "./download-source.json"],
  load() {
    return describe(
      JSON.parse(
        readFileSync(new URL("./download.json", import.meta.url), "utf8"),
      ),
      JSON.parse(
        readFileSync(
          new URL("./download-source.json", import.meta.url),
          "utf8",
        ),
      ),
    );
  },
};
