import DefaultTheme from "vitepress/theme";
import { h } from "vue";
import HomeShowcase from "./HomeShowcase.vue";
import "./custom.css";

export default {
  extends: DefaultTheme,
  Layout: () =>
    h(DefaultTheme.Layout, null, {
      "home-hero-after": () => h(HomeShowcase),
    }),
};
