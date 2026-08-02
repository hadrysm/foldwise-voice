// Sandcastle's entry point: ask what to run, check the CLIs behind it, then
// hand the workflow its dispatch and get out of the way.
//
// Usage (from the repo root — Sandcastle resolves git against process.cwd()):
//   .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts

import { cancel, log } from "@clack/prompts";
import { runToRemember } from "./cli/flow.mts";
import { choosePlan, printRunHeader } from "./cli/prompts.mts";
import { writeStoredRun } from "./cli/store.mts";
import { runnableDriver } from "./drivers/registry.mts";
import { prepare } from "./runner.mts";

async function main(): Promise<void> {
  const plan = await choosePlan();
  if (!plan) {
    cancel("Sandcastle cancelled.");
    return;
  }

  // Every preflight runs here, and the core it returns is the only value a
  // dispatch can be reached through — so nothing below can run an agent that
  // one of those checks would have refused.
  const core = prepare(plan);

  // Remember the answers before the first dispatch — outside the worktree, so
  // nothing an agent commits can be affected by this write. The scope is
  // remembered as the answer that was given, never as the snapshot it produced:
  // a snapshot is an outcome, and GitHub is the only source of truth for those.
  if (!writeStoredRun(runToRemember(plan))) {
    log.warn("Could not save these picks for next time.");
  }

  printRunHeader(plan);

  // No trailing `All done.` — a draining driver ends by printing its own run
  // report, and a bare "done" printed under a report naming two skipped items
  // and a bounce would be the run's last word contradicting its own record.
  await runnableDriver(plan.workflow)(core, plan.workflow);
}

main().catch((error: unknown) => {
  // "Stopped" rather than "cannot start": a draining driver revalidates against
  // GitHub before every item, so this is now reachable at item seven as well as
  // at the first screen, and a run that did five items should not report itself
  // as one that never began.
  const message = error instanceof Error ? error.message : String(error);
  console.error(`\nSandcastle stopped\n\n${message}\n`);
  process.exitCode = 1;
});
