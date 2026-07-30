// The provider mechanics: which CLI stands behind each provider, how to ask it
// for its version and login state, which reasoning efforts it actually
// advertises, and how to turn a model pick into a Sandcastle agent.
//
// Everything here talks to a CLI on the host. That is why `parseVersion`,
// `versionIsAtLeast` and the auth predicates in `PROVIDERS` are exported: they
// are the pure part of that conversation, and each one fails silently when it
// stops matching. A `--version` string the regex misses means the
// minimum-version gate never fires; an auth predicate that mismatches means
// either a false "not logged in" or a run that starts unauthenticated.

import { spawnSync } from "node:child_process";
import * as sandcastle from "@ai-hero/sandcastle";
import type {
  ModelID,
  Provider,
  RunEffort,
  RunModel,
  VersionComponents,
} from "../agents/models.mts";

export const PROVIDERS = {
  "claude-code": {
    executable: "claude",
    helpArgs: ["--help"],
    authArgs: ["auth", "status"],
    authHint: "Run `claude auth login` and try again.",
    isAuthenticated: (output: string) => /"loggedIn"\s*:\s*true/.test(output),
    createAgent: (model: ModelID, effort: RunEffort) => sandcastle.claudeCode(model, { effort }),
  },
  codex: {
    executable: "codex",
    helpArgs: ["exec", "--help"],
    authArgs: ["login", "status"],
    authHint: "Run `codex login` and try again.",
    // Anchored to a line start, because the logged-out output is `Not logged
    // in` — an unanchored match reads that as authenticated. Codex signals the
    // case with exit 1 too, so `executeProviderCommand` throws first today;
    // this predicate must not depend on that. Per-line rather than per-output
    // because stderr is concatenated onto stdout and the CLI shim prepends
    // warnings. The cost is a loud false negative if codex ever prefixes the
    // phrase (`Auth: Logged in …`), which beats a silent false positive.
    isAuthenticated: (output: string) => /^[ \t]*logged in/im.test(output),
    createAgent: (model: ModelID, effort: RunEffort) => {
      if (effort === "max") {
        throw new Error("Max effort is not supported by the installed Sandcastle Codex adapter.");
      }
      return sandcastle.codex(model, { effort });
    },
  },
} as const;

function executeProviderCommand(
  provider: Provider,
  args: readonly string[],
  failureMessage: string,
): string {
  const result = spawnSync(PROVIDERS[provider].executable, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  if (result.error || result.status !== 0) throw new Error(failureMessage);
  return `${result.stdout}\n${result.stderr}`.trim();
}

// `--help` output is per-provider and unchanging within a run, but the picker
// asks per agent — cache so choosing two models does not re-spawn the CLI.
const providerHelpCache = new Map<Provider, string>();

function providerHelp(model: RunModel): string {
  const cached = providerHelpCache.get(model.provider);
  if (cached !== undefined) return cached;
  const help = executeProviderCommand(
    model.provider,
    PROVIDERS[model.provider].helpArgs,
    `${model.providerLabel} is not installed or is unavailable in PATH.`,
  );
  providerHelpCache.set(model.provider, help);
  return help;
}

export function availableEfforts(model: RunModel): readonly RunEffort[] {
  const help = providerHelp(model);

  if (model.provider !== "claude-code") return model.efforts;

  const advertised = help.match(/Effort level[^\n]*\n?[^\n]*\(([^)]+)\)/)?.[1];
  if (!advertised) {
    throw new Error(
      `Could not detect supported effort levels from ${model.providerLabel}. Update the CLI or choose another provider.`,
    );
  }
  const supported = new Set(advertised.split(",").map((effort) => effort.trim()));
  return model.efforts.filter((effort) => supported.has(effort));
}

export function parseVersion(output: string): VersionComponents | undefined {
  const match = output.match(/(\d+)\.(\d+)\.(\d+)/);
  if (!match?.[1] || !match[2] || !match[3]) return undefined;
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

export function versionIsAtLeast(actual: VersionComponents, minimum: VersionComponents): boolean {
  for (let index = 0; index < minimum.length; index++) {
    const difference = (actual[index] ?? 0) - (minimum[index] ?? 0);
    if (difference !== 0) return difference > 0;
  }
  return true;
}

/**
 * Check that the CLI behind this model is installed, new enough, and logged in.
 * Takes a `RunModel` rather than a whole picked configuration because neither
 * check varies by effort — which is also what makes the model id the right
 * dedupe key at the call site.
 */
export function validateModel(model: RunModel): void {
  const provider = PROVIDERS[model.provider];
  const versionOutput = executeProviderCommand(
    model.provider,
    ["--version"],
    `${model.providerLabel} is not installed or is unavailable in PATH.`,
  );
  const minimum = model.minimumCliVersion;
  if (minimum) {
    const installed = parseVersion(versionOutput);
    if (!installed || !versionIsAtLeast(installed, minimum.components)) {
      throw new Error(
        `${model.label} requires ${model.providerLabel} ${minimum.label} or newer.\nInstalled: ${versionOutput}`,
      );
    }
  }

  const authOutput = executeProviderCommand(
    model.provider,
    provider.authArgs,
    `Could not verify the ${model.providerLabel} login. ${provider.authHint}`,
  );
  if (!provider.isAuthenticated(authOutput)) {
    throw new Error(`No active ${model.providerLabel} login. ${provider.authHint}`);
  }
}
