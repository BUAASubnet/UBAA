import { afterAll } from "vitest";
import { env } from "./runtime";
afterAll(() => env.DB.close());
