// Sandcastle's entry point: ask what to run, check the CLIs behind it, then
// hand the workflow its dispatch and get out of the way.
//
// Usage (from the repo root — Sandcastle resolves git against process.cwd()):
//   .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts

import { cancel, log } from "@clack/prompts";
import { choosePlan, printRunHeader, rememberRunV1 } from "./cli/flow.mts";
import { prepare } from "./runner.mts";

async function main(): Promise<void> {
  const chosen = await choosePlan();
  if (!chosen) {
    cancel("Sandcastle cancelled.");
    return;
  }

  const dispatch = prepare(chosen.plan);

  // Remember the picks before the first dispatch — outside the worktree, so
  // nothing an agent commits can be affected by this write.
  if (!rememberRunV1(chosen)) {
    log.warn("Could not save these picks for next time.");
  }

  printRunHeader(chosen.plan);

  await chosen.plan.workflow.run({ dispatch, knobs: chosen.plan.knobs });

  console.log("\nAll done.");
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`\nCannot start Sandcastle\n\n${message}\n`);
  process.exitCode = 1;
});
