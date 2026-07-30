import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { parseVersion, PROVIDERS, versionIsAtLeast } from "../../providers/registry.mts";

describe("parseVersion", () => {
  it("reads a bare version", () => {
    assert.deepEqual(parseVersion("1.2.3"), [1, 2, 3]);
  });

  it("finds a version embedded in surrounding text", () => {
    // The real shape: `codex --version` prints the binary name alongside it.
    assert.deepEqual(parseVersion("codex-cli 0.144.2 (rust)"), [0, 144, 2]);
  });

  it("keeps multi-digit components whole", () => {
    assert.deepEqual(parseVersion("claude 2.1.220 (Claude Code)"), [2, 1, 220]);
  });

  it("returns undefined when there is no version", () => {
    assert.equal(parseVersion("command not found"), undefined);
  });

  it("returns undefined for a two-component version", () => {
    // A minimum-version gate that accepted "0.144" would compare garbage.
    assert.equal(parseVersion("codex-cli 0.144"), undefined);
  });
});

describe("versionIsAtLeast", () => {
  it("accepts the exact minimum", () => {
    assert.equal(versionIsAtLeast([0, 144, 0], [0, 144, 0]), true);
  });

  it("accepts a newer version", () => {
    assert.equal(versionIsAtLeast([1, 0, 0], [0, 144, 0]), true);
  });

  it("rejects an older version", () => {
    assert.equal(versionIsAtLeast([0, 143, 0], [0, 144, 0]), false);
  });

  it("lets a later component decide when the earlier ones tie", () => {
    assert.equal(versionIsAtLeast([0, 144, 0], [0, 143, 9]), true);
    assert.equal(versionIsAtLeast([0, 143, 9], [0, 144, 0]), false);
  });

  it("compares patch levels", () => {
    assert.equal(versionIsAtLeast([0, 144, 1], [0, 144, 2]), false);
    assert.equal(versionIsAtLeast([0, 144, 2], [0, 144, 1]), true);
  });
});

describe("the Claude Code auth predicate", () => {
  const isAuthenticated = PROVIDERS["claude-code"].isAuthenticated;

  // Verified against `claude auth status` on Claude Code 2.1.220.
  const loggedIn = JSON.stringify({
    loggedIn: true,
    authMethod: "claude.ai",
    apiProvider: "firstParty",
    subscriptionType: "team",
  });

  it("accepts a logged-in status", () => {
    assert.equal(isAuthenticated(loggedIn), true);
  });

  it("rejects an explicitly logged-out status", () => {
    assert.equal(isAuthenticated(JSON.stringify({ loggedIn: false })), false);
  });

  it("rejects a status with no loggedIn field", () => {
    assert.equal(isAuthenticated(JSON.stringify({ authMethod: "claude.ai" })), false);
  });
});

describe("the Codex auth predicate", () => {
  const isAuthenticated = PROVIDERS.codex.isAuthenticated;

  it("accepts a logged-in status whatever its case", () => {
    // Verified against `codex login status` on codex-cli 0.144.
    assert.equal(isAuthenticated("Logged in using ChatGPT"), true);
    assert.equal(isAuthenticated("logged in using an API key"), true);
  });

  it("rejects a logged-out status", () => {
    // Verified by pointing CODEX_HOME at an empty directory: codex prints this
    // and exits 1. An unanchored /logged in/i matches it — which would start a
    // run unauthenticated the moment codex stopped signalling with exit status.
    assert.equal(isAuthenticated("Not logged in"), false);
  });

  it("sees past a leading warning line", () => {
    // `executeProviderCommand` concatenates stdout and stderr, and the CLI
    // shim prepends warnings, so the match cannot be anchored to the output.
    assert.equal(
      isAuthenticated("WARNING: could not create PATH aliases\nLogged in using ChatGPT"),
      true,
    );
  });
});
