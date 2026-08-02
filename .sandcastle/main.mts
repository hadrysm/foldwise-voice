// Sandcastle's entry point: ask what to run, check the CLIs behind it, then
// hand the workflow its dispatch and get out of the way.
//
// Usage (from the repo root — Sandcastle resolves git against process.cwd()):
//   .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts

import { cancel, log } from "@clack/prompts";
import { runToRemember } from "./cli/flow.mts";
import { choosePlan, printRunHeader } from "./cli/prompts.mts";
import { writeStoredRun } from "./cli/store.mts";
import { prepare } from "./runner.mts";

async function main(): Promise<void> {
  const plan = await choosePlan();
  if (!plan) {
    cancel("Sandcastle cancelled.");
    return;
  }

  const dispatch = prepare(plan);

  // Remember the answers before the first dispatch — outside the worktree, so
  // nothing an agent commits can be affected by this write. The scope is
  // remembered as the answer that was given, never as the snapshot it produced:
  // a snapshot is an outcome, and GitHub is the only source of truth for those.
  if (!writeStoredRun(runToRemember(plan))) {
    log.warn("Could not save these picks for next time.");
  }

  printRunHeader(plan);

  await plan.workflow.run({ dispatch, knobs: plan.knobs, maxWorkItems: plan.maxWorkItems });

  console.log("\nAll done.");
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`\nCannot start Sandcastle\n\n${message}\n`);
  process.exitCode = 1;
});
