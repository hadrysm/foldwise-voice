// The five git operations a wave-driven run needs, bound to one repo root.
//
// **Git is the one toolchain this runner is allowed to branch on**, because git
// is framework-neutral: nothing here says what language the workspace is written
// in, and the whole module would be identical in a web or a mobile repo. Every
// other exit code belongs to `merge-prompt.md`, where a failure can be
// *interpreted and repaired* — which is judgment, and judgment is an agent's.
//
// **Real git, never a port.** #396 settled this: the three claims #404's
// topology rests on are really claims *about git* — that `--no-ff` leaves
// exactly one merge commit per item, that a conflicting merge fails detectably
// enough to rewind one item, and that `git branch -d` refuses unmerged work,
// which is the entire no-force-flag safety argument. Asserted against an
// injected fake, all three would be asserted against a fake written by the same
// person who wrote the assumption. So this module spawns, and its suite runs it
// against a real temporary repository.
//
// **The repo root is a parameter, not `process.cwd()`.** Honest rather than
// test-only: a driver operates on *the workspace repo*, and saying so is what
// lets the suite point it somewhere disposable.
//
// **No `--force`, no `-D`, no `-f` appears anywhere below.** Both cleanup steps
// are self-enforcing — `git worktree remove` refuses a worktree with modified or
// untracked files and `git branch -d` refuses an unmerged branch — so git itself
// is what stops a run destroying work, and a refusal comes back as a value to
// report rather than an exception to swallow.

import { execFileSync } from "node:child_process";

/** One git step that is allowed to refuse, and what it said when it did. */
export interface GitStep {
  readonly ok: boolean;
  /** Git's own first line, ready to drop into the report. Empty when it worked. */
  readonly detail: string;
}

/**
 * What one item's fan-in came to. `conflict-rewound` carries the paths git
 * could not reconcile, which is what the Merger is handed — the runner detects a
 * conflict and rewinds, and never tries to resolve one.
 */
export type MergeAttempt =
  | { readonly kind: "merged"; readonly sha: string }
  | { readonly kind: "conflict-rewound"; readonly paths: readonly string[] };

export interface WaveGit {
  /**
   * `git rev-list --count <base>..<branch>` — what this item actually produced,
   * measured rather than reported. Zero when the branch does not exist, because
   * an item whose worktree was never cut produced nothing, which is the same
   * answer by a different route.
   */
  readonly commitsOn: (branch: string, base: string) => number;
  /**
   * `git merge --no-ff` into the checked-out workspace branch, rewinding to the
   * pre-merge SHA when git refuses.
   *
   * `--no-ff` on **every** merge, including a wave's first: without it that
   * merge fast-forwards and the item's attribution disappears, and the merge
   * commits are the only per-item boundary in an otherwise flat diff.
   */
  readonly merge: (branch: string) => MergeAttempt;
  /**
   * `git merge-base --is-ancestor <branch> HEAD` — has this branch reached the
   * workspace branch?
   *
   * Asked after the Merger has run, and asked of git rather than of the Merger:
   * a branch the Merger merged by hand is merged whatever its verdict said, and
   * a branch it claims to have merged but did not is not. The driver observes;
   * an agent's account of its own work is a report to print, never a fact to
   * record.
   */
  readonly isMerged: (branch: string) => boolean;
  readonly removeWorktree: (path: string) => GitStep;
  readonly deleteBranch: (branch: string) => GitStep;
}

/** Git writes its refusals to stderr; the first line is the one worth quoting. */
function refusal(error: unknown): string {
  const stderr =
    error !== null && typeof error === "object" && "stderr" in error
      ? String((error as { stderr?: unknown }).stderr ?? "").trim()
      : "";
  const message = stderr || (error instanceof Error ? error.message : String(error));
  return message.split("\n")[0]?.trim() ?? "";
}

export function waveGit(repoRoot: string): WaveGit {
  const git = (...args: readonly string[]): string =>
    execFileSync("git", [...args], {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });

  const attempt = (...args: readonly string[]): GitStep => {
    try {
      git(...args);
      return { ok: true, detail: "" };
    } catch (error) {
      return { ok: false, detail: refusal(error) };
    }
  };

  const headSha = (): string => git("rev-parse", "HEAD").trim();

  /** Only meaningful mid-conflict, and never allowed to mask the conflict itself. */
  const unmergedPaths = (): readonly string[] => {
    try {
      return git("diff", "--name-only", "--diff-filter=U").split("\n").filter(Boolean);
    } catch {
      return [];
    }
  };

  return {
    commitsOn: (branch, base) => {
      try {
        return Number(git("rev-list", "--count", `${base}..${branch}`).trim());
      } catch {
        return 0;
      }
    },

    merge: (branch) => {
      const before = headSha();
      try {
        // `--no-edit` rather than `-m`, so the message stays git's own
        // `Merge branch 'sandcastle/425-…'` and the branch name is what a
        // maintainer reads out of `git log --merges`.
        git("merge", "--no-ff", "--no-edit", branch);
        return { kind: "merged", sha: headSha() };
      } catch {
        const paths = unmergedPaths();
        // Tolerated: a merge that failed before it started leaves nothing to
        // abort, and the SHA check below is what actually decides.
        attempt("merge", "--abort");
        const after = headSha();
        if (after !== before) {
          throw new Error(
            `Merging ${branch} left ${repoRoot} at ${after} rather than back at ${before}. Resolve it by hand — this run will not guess.`,
          );
        }
        return { kind: "conflict-rewound", paths };
      }
    },

    isMerged: (branch) => attempt("merge-base", "--is-ancestor", branch, "HEAD").ok,

    removeWorktree: (path) => attempt("worktree", "remove", path),
    deleteBranch: (branch) => attempt("branch", "-d", branch),
  };
}
