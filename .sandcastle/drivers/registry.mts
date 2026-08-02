// Every execution shape, keyed by the id a workflow declares.
//
// A real registry rather than a literal list at each use site, because the
// sweeps that keep this tool framework-agnostic have to enumerate from one:
// *"no toolchain command reaches a driver"*, written as three assertions about
// today's drivers, silently stops covering the fourth one somebody adds later —
// which is exactly how a boundary rots while the suite stays green.
//
// Keyed exhaustively over `DriverId` for the same reason the picker's scope and
// effort rows are: a shape added to the vocabulary cannot ship undescribed.

import type { DriverId, Workflow } from "../contract.mts";
import type { Drive, Driver } from "./core.mts";
import { driveSequential } from "./sequential.mts";
import { driveWaveParallel } from "./wave-parallel.mts";
import { driveWholeBranch } from "./whole-branch.mts";

export const DRIVERS: Readonly<Record<DriverId, Driver>> = {
  sequential: {
    id: "sequential",
    drains: true,
    concurrent: false,
    drive: driveSequential,
  },
  "wave-parallel": {
    id: "wave-parallel",
    drains: true,
    concurrent: true,
    // Its worktrees, per-item timeout, fan-in and cleanup are built; the Planner
    // and the Merger arrive in slice 9, and until then every wave is the first
    // `MAX_PARALLEL` of the ready level — which is also the wave a rejected plan
    // falls back to. Reachable only once a workflow declares it (slice 10).
    drive: driveWaveParallel,
  },
  "whole-branch": {
    id: "whole-branch",
    drains: false,
    concurrent: false,
    drive: driveWholeBranch,
  },
};

/**
 * The driver this workflow runs on, refused if this build cannot run it.
 *
 * A preflight rather than a lookup that might return nothing: `prepare()` calls
 * it before it builds anything a dispatch can be reached through, so a workflow
 * pointed at an unbuilt shape fails at the first screen after confirmation
 * rather than at the first item.
 */
export function runnableDriver(workflow: Workflow): Drive {
  const driver = DRIVERS[workflow.driver];
  if (!driver.drive) {
    throw new Error(
      `The ${workflow.label} workflow declares the ${driver.id} driver, which this build cannot run yet.`,
    );
  }
  return driver.drive;
}
