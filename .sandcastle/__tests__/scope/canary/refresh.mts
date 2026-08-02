// Refresh the schema canary. Network. Deliberate. Never automated.
//
//   pnpm --dir .sandcastle exec tsx __tests__/scope/canary/refresh.mts
//
// This file is not a test and the suite's `**/*.test.mts` glob does not match
// it, which is the point: a canary CI could refresh is a canary that can never
// fail, because it would rewrite the evidence before comparing against it.
//
// It records the exact reads `resolveScope` makes for this repository's own
// SPEC, through the real transport, so the fixture is a faithful capture rather
// than a hand-written idea of one. Run it when you *want* to know whether
// GitHub has moved — then read the test diff before committing it.

import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { API_VERSION, ghTransport, resolveScope, type GitHubTransport } from "../../../scope/github.mts";
import { CANARY_SCOPE } from "./canary.mts";

const FIXTURE = fileURLToPath(new URL("./spec-418-tree.json", import.meta.url));

const responses: Record<string, unknown> = {};
const live = ghTransport();
const recording: GitHubTransport = async (request) => {
  const value = await live(request);
  responses[request.path] = value;
  return value;
};

const outcome = await resolveScope(CANARY_SCOPE, recording);

writeFileSync(
  FIXTURE,
  `${JSON.stringify(
    {
      capturedAt: new Date().toISOString(),
      apiVersion: API_VERSION,
      scope: CANARY_SCOPE,
      outcome: outcome.ok ? "ok" : `${outcome.reason}: ${outcome.message}`,
      responses,
    },
    null,
    0,
  )}\n`,
);

console.log(
  `Recorded ${Object.keys(responses).length} responses into ${FIXTURE} (${outcome.ok ? "resolved" : outcome.reason}).`,
);
