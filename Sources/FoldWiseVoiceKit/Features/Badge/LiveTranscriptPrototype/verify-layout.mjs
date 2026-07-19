import fs from "node:fs";
import { fileURLToPath } from "node:url";

const cssURL = new URL("prototype.css", import.meta.url);
const css = fs.readFileSync(fileURLToPath(cssURL), "utf8");

function block(selector) {
  const match = css.match(new RegExp(`\\.${selector}\\s*\\{([^}]*)\\}`, "m"));
  if (!match) throw new Error(`Missing .${selector} rule`);
  return match[1];
}

function pixels(rule, property) {
  const match = rule.match(new RegExp(`${property}\\s*:\\s*(-?\\d+)px`));
  if (!match) throw new Error(`Missing ${property} pixel value`);
  return Number(match[1]);
}

const stageBottom = pixels(block("badge-stage"), "bottom");
const actionRule = block("primary-action");
const actionBottom = stageBottom + pixels(actionRule, "bottom");
const actionBounds = [actionBottom, actionBottom + pixels(actionRule, "height")].sort(
  (left, right) => left - right,
);

const switcherRule = block("prototype-switcher");
const switcherBottom = pixels(switcherRule, "bottom");
const switcherBounds = [
  switcherBottom,
  switcherBottom + pixels(switcherRule, "height"),
];

const overlap = Math.max(
  0,
  Math.min(actionBounds[1], switcherBounds[1]) -
    Math.max(actionBounds[0], switcherBounds[0]),
);

if (overlap > 0) {
  throw new Error(`Start live comparison overlaps the variant switcher by ${overlap}px`);
}

console.log("PASS: Start live comparison is clear of the variant switcher");
