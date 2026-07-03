# ADR-0001: Sandcastle runs in place on the host, not in a sandbox

## Status

Accepted (2026-07-03). Amended (2026-07-03): the runner moved from custom
orchestration with the `head` branch strategy to the stock upstream
sequential-reviewer template, which works in host git worktrees on named
`sandcastle/sequential-reviewer/*` branches. The no-sandbox (host execution)
decision is unchanged.

## Context

The Sandcastle batch runner under `.sandcastle/` drives autonomous
implement→review agents against this repo's GitHub issues. Sandcastle's
default posture is to isolate each agent in a Linux Docker container built
from a repo-provided Dockerfile, working on a throwaway `sandcastle/*`
branch that the human later merges.

Two facts about this repo make that default unworkable or redundant:

- **The app cannot build in a Linux container.** FoldWiseVoice is a macOS
  AppKit Swift package (`platforms: [.macOS(.v14)]`) depending on AppKit,
  Carbon hotkey APIs, and other Apple-only frameworks. `swift build` and
  `swift test` — the verification the agents must run before every commit —
  only succeed on a macOS host with Xcode toolchains. There is no Linux
  image that can compile this code, so a container sandbox could never
  verify its own work.
- **The workspace is already the isolation boundary.** The maintainer works
  in Conductor, where each workspace is its own git worktree on its own
  branch. An agent scribbling on "the current checkout" is scribbling on an
  isolated, disposable workspace — not on the maintainer's main checkout.

## Decision

Run Sandcastle **on the macOS host**: the no-sandbox provider, with the
stock sequential-reviewer template's branch handling. Sandcastle creates a
git worktree on the host for each implement→review cycle; agents execute
there directly and commit to a named `sandcastle/sequential-reviewer/*`
branch, which the maintainer reviews and merges into the workspace branch
by hand. **No Dockerfile is included in this repo**, deliberately — its
absence signals that container mode is not a supported configuration, not
an omission.

Consequences that follow from this decision:

- **The Node runtime is quarantined in `.sandcastle/`.** With no container
  image to hold the runner's toolchain, it lives on the host instead — as a
  self-contained pnpm project inside `.sandcastle/`, so the Swift repo root
  stays free of `package.json`/`node_modules` noise.
- **Agents inherit the host environment.** Their `claude` and `gh` calls use
  the maintainer's existing logins; no token juggling in a `.env` file.
- **The human gate is the manual merge.** The run never pushes and never
  opens a PR — commits land on a local `sandcastle/sequential-reviewer/*`
  branch, and the maintainer reviews its diff and merges (then opens any PR)
  by hand.
- **Host runs are trust-scoped.** Agents run with the maintainer's user
  privileges, so the runner is a local, human-launched tool only — never
  wired into CI or run on untrusted input.

## Rejected alternative: Docker container sandbox

Sandcastle's containerized mode (agent in a Linux Docker sandbox, commits on
a throwaway `sandcastle/*` branch) was rejected because:

- The macOS-only Swift package cannot compile in a Linux container, so the
  agents' mandatory verify loop (`swift build --build-tests`, then
  `swift test --skip-build`) would fail on every iteration. This is a hard constraint, not a
  preference.
- The isolation it buys is already provided by Conductor worktrees and by
  the host git worktrees Sandcastle creates per cycle — the container adds
  nothing but the build breakage above.

Should the package ever gain a Linux-buildable core (e.g. a platform-free
library target), this decision is worth revisiting for that subset.
