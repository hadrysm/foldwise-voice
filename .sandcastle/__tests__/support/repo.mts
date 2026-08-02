// A real git repository in a temporary directory, thrown away after each test.
//
// **You only fake what is expensive.** Agents cost money, minutes and a provider
// login, so a wave's bodies are faked. Real git costs nothing — the same
// reasoning that made every provider factory a plain object literal — and it is
// the *only* way to assert the three claims #404's topology rests on that are
// really claims about git: that `--no-ff` leaves exactly one merge commit per
// item, that a conflicting merge fails detectably enough to rewind one item, and
// that `git branch -d` refuses unmerged work.
//
// **Accepted cost, stated plainly:** every suite built on this spawns processes
// and touches the filesystem, which breaks the *spawns nothing* property the
// rest of `__tests__/` has. It buys the only proof the safety argument holds.

import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { TestContext } from "node:test";

/** The branch a run merges into, standing in for a Conductor workspace branch. */
export const WORKSPACE_BRANCH = "t3code/fake-workspace";

/** The file two items are made to fight over, present from the first commit. */
export const CONTESTED_FILE = "shared.txt";

export interface TempRepo {
  readonly root: string;
  /** Run git in the repo root, or in a worktree when `cwd` is given. */
  readonly git: (args: readonly string[], cwd?: string) => string;
  readonly headSha: () => string;
  /** `git log --merges` oldest first, one subject per line. */
  readonly mergeSubjects: () => readonly string[];
  readonly branchExists: (branch: string) => boolean;
  /** Write a file and commit it, in the repo root or in a worktree. */
  readonly commit: (file: string, contents: string, cwd?: string) => void;
  /** Write a file and leave it there, the way an agent leaves work behind. */
  readonly write: (file: string, contents: string, cwd?: string) => void;
}

/**
 * A repository with one commit on `WORKSPACE_BRANCH`, removed when the test
 * ends. Identity and merge behaviour are pinned locally rather than inherited
 * from whatever the machine's `~/.gitconfig` says, so the suite reads the same
 * on a maintainer's Mac and on a CI runner.
 */
export function tempRepo(t: TestContext): TempRepo {
  const root = mkdtempSync(join(tmpdir(), "sandcastle-wave-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));

  const git = (args: readonly string[], cwd: string = root): string =>
    execFileSync("git", [...args], {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });

  const commit = (file: string, contents: string, cwd: string = root): void => {
    writeFileSync(join(cwd, file), contents);
    git(["add", file], cwd);
    git(["commit", "-m", `${file}: ${contents.split("\n")[0]}`], cwd);
  };

  git(["init", "--initial-branch", WORKSPACE_BRANCH]);
  git(["config", "user.email", "sandcastle@example.test"]);
  git(["config", "user.name", "Sandcastle Suite"]);
  // A merge with no strategy configured is what production does; pinning it
  // keeps a machine-level `merge.ff` or `pull.rebase` out of the assertions.
  git(["config", "merge.ff", "true"]);
  // Worktrees live under the repo they were cut from and are gitignored there
  // too — without this the workspace tree is permanently dirty and `git merge`
  // refuses, which is a property of the fixture rather than of the driver.
  writeFileSync(join(root, ".gitignore"), ".sandcastle/\n");
  git(["add", ".gitignore"]);
  commit(CONTESTED_FILE, "base");

  return {
    root,
    git,
    headSha: () => git(["rev-parse", "HEAD"]).trim(),
    mergeSubjects: () =>
      git(["log", "--merges", "--reverse", "--format=%s"])
        .split("\n")
        .filter(Boolean),
    branchExists: (branch) => git(["branch", "--list", branch]).trim() !== "",
    commit,
    write: (file, contents, cwd = root) => writeFileSync(join(cwd, file), contents),
  };
}

/** Where a fake worktree for one branch lands, mirroring Sandcastle's layout. */
export function worktreePath(root: string, branch: string): string {
  return join(root, ".sandcastle", "worktrees", branch.replace(/\//g, "-"));
}

export function worktreeExists(root: string, branch: string): boolean {
  return existsSync(worktreePath(root, branch));
}
