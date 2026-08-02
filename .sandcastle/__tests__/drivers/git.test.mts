// The git edge, against a real repository.
//
// Three of #404's load-bearing claims are not claims about this code at all —
// they are claims about git, and asserting them against an injected port would
// assert them against a fake written by the same person who wrote the
// assumption. So this file spawns git, and every assertion below would fail if
// git ever stopped behaving the way the topology assumes:
//
//   1. `--no-ff` leaves exactly one merge commit per item, naming its branch.
//   2. A conflicting merge fails detectably enough to rewind one item, and
//      leaves that item's branch whole.
//   3. **`git branch -d` refuses unmerged work** — the entire no-force-flag
//      safety argument, and the reason the cleanup path carries no `--force`,
//      `-D` or `-f`.

import assert from "node:assert/strict";
import { describe, it, type TestContext } from "node:test";
import { waveGit } from "../../drivers/git.mts";
import {
  CONTESTED_FILE,
  tempRepo,
  WORKSPACE_BRANCH,
  worktreePath,
  type TempRepo,
} from "../support/repo.mts";

/** Cut a branch in its own worktree and put one commit on it, as an item would. */
function itemBranchWith(repo: TempRepo, branch: string, contents: string): string {
  const path = worktreePath(repo.root, branch);
  repo.git(["worktree", "add", "-b", branch, path, "HEAD"]);
  repo.commit(CONTESTED_FILE, contents, path);
  return path;
}

describe("counting what an item produced", () => {
  it("counts only the commits on that item's branch since the wave base", async (t) => {
    const repo = tempRepo(t);
    const base = repo.headSha();
    itemBranchWith(repo, "sandcastle/419-one", "from 419");

    assert.equal(waveGit(repo.root).commitsOn("sandcastle/419-one", base), 1);
  });

  it("answers zero for an item whose branch was never cut", async (t) => {
    const repo = tempRepo(t);

    // An item that crashed before its worktree existed produced nothing, which
    // is the same answer as an item that produced nothing — the run must not
    // have to tell a missing branch from an empty one to know that.
    assert.equal(waveGit(repo.root).commitsOn("sandcastle/999-never-cut", repo.headSha()), 0);
  });
});

describe("fan-in", () => {
  it("leaves exactly one merge commit per item, naming its branch", async (t) => {
    const repo = tempRepo(t);
    itemBranchWith(repo, "sandcastle/419-one", "from 419");
    // Different files, so both merge cleanly.
    const path = worktreePath(repo.root, "sandcastle/420-two");
    repo.git(["worktree", "add", "-b", "sandcastle/420-two", path, "HEAD"]);
    repo.commit("other.txt", "from 420", path);

    const git = waveGit(repo.root);
    assert.equal(git.merge("sandcastle/419-one").kind, "merged");
    assert.equal(git.merge("sandcastle/420-two").kind, "merged");

    assert.deepEqual(repo.mergeSubjects(), [
      `Merge branch 'sandcastle/419-one' into ${WORKSPACE_BRANCH}`,
      `Merge branch 'sandcastle/420-two' into ${WORKSPACE_BRANCH}`,
    ]);
  });

  it("does not fast-forward the first merge of a wave", async (t) => {
    const repo = tempRepo(t);
    itemBranchWith(repo, "sandcastle/419-one", "from 419");

    // The one every item's attribution depends on: without `--no-ff` this merge
    // fast-forwards, no merge commit exists, and the only per-item boundary in
    // an otherwise flat diff is gone.
    assert.equal(waveGit(repo.root).merge("sandcastle/419-one").kind, "merged");
    assert.deepEqual(repo.mergeSubjects(), [
      `Merge branch 'sandcastle/419-one' into ${WORKSPACE_BRANCH}`,
    ]);
  });

  it("rewinds a conflicting merge to the pre-merge SHA and names the paths", async (t) => {
    const repo = tempRepo(t);
    itemBranchWith(repo, "sandcastle/419-one", "from 419");
    itemBranchWith(repo, "sandcastle/420-two", "from 420");

    const git = waveGit(repo.root);
    assert.equal(git.merge("sandcastle/419-one").kind, "merged");
    const afterFirst = repo.headSha();
    const second = git.merge("sandcastle/420-two");

    assert.equal(second.kind, "conflict-rewound");
    assert.deepEqual(second.kind === "conflict-rewound" ? second.paths : [], [CONTESTED_FILE]);
    // One item rewound, not the wave: everything that already merged is still
    // merged, and the conflicted item's own commits are untouched.
    assert.equal(repo.headSha(), afterFirst);
    assert.equal(repo.git(["status", "--porcelain"]).trim(), "");
    assert.equal(git.commitsOn("sandcastle/420-two", afterFirst), 1);
  });
});

describe("what reached the workspace branch", () => {
  it("tells a branch the Merger merged by hand from one it left behind", async (t) => {
    const repo = tempRepo(t);
    itemBranchWith(repo, "sandcastle/419-one", "from 419");
    itemBranchWith(repo, "sandcastle/420-two", "from 420");
    const git = waveGit(repo.root);
    assert.equal(git.merge("sandcastle/419-one").kind, "merged");
    assert.equal(git.merge("sandcastle/420-two").kind, "conflict-rewound");

    assert.equal(git.isMerged("sandcastle/419-one"), true);
    assert.equal(git.isMerged("sandcastle/420-two"), false);

    // What the Merger does to a rewound branch, done by hand here: after it, git
    // says merged whatever the verdict claimed — which is why the driver asks
    // git and not the agent.
    repo.git(["merge", "--no-ff", "--no-edit", "-X", "ours", "sandcastle/420-two"]);
    assert.equal(git.isMerged("sandcastle/420-two"), true);
  });

  it("answers no for a branch that never existed", async (t) => {
    const repo = tempRepo(t);

    assert.equal(waveGit(repo.root).isMerged("sandcastle/999-never-cut"), false);
  });
});

describe("cleanup, which git itself enforces", () => {
  it("refuses to delete an unmerged branch, and says so rather than throwing", async (t) => {
    const repo = tempRepo(t);
    const path = itemBranchWith(repo, "sandcastle/419-one", "from 419");
    // Detach the worktree so the refusal under test is about the merge state and
    // not about the branch being checked out somewhere.
    assert.ok(waveGit(repo.root).removeWorktree(path).ok);

    const deleted = waveGit(repo.root).deleteBranch("sandcastle/419-one");

    // The whole no-force-flag safety argument, in one assertion: nothing in the
    // cleanup path can destroy work, because git will not let it.
    assert.equal(deleted.ok, false);
    assert.match(deleted.detail, /not fully merged/);
    assert.ok(repo.branchExists("sandcastle/419-one"));
  });

  it("deletes a merged item's worktree and branch", async (t) => {
    const repo = tempRepo(t);
    const path = itemBranchWith(repo, "sandcastle/419-one", "from 419");
    const git = waveGit(repo.root);
    assert.equal(git.merge("sandcastle/419-one").kind, "merged");

    assert.deepEqual(git.removeWorktree(path), { ok: true, detail: "" });
    assert.deepEqual(git.deleteBranch("sandcastle/419-one"), { ok: true, detail: "" });
    assert.equal(repo.branchExists("sandcastle/419-one"), false);
  });

  it("refuses to remove a worktree carrying untracked work", async (t) => {
    const repo = tempRepo(t);
    const path = itemBranchWith(repo, "sandcastle/419-one", "from 419");
    const git = waveGit(repo.root);
    assert.equal(git.merge("sandcastle/419-one").kind, "merged");
    // Whatever the agent left behind uncommitted. Merged or not, this is not a
    // copy of work that is safely on the workspace branch.
    repo.write("untracked.txt", "left behind", path);

    const removed = git.removeWorktree(path);

    assert.equal(removed.ok, false);
    assert.match(removed.detail, /untracked files|use --force/);
  });
});
