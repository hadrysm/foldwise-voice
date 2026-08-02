// The only module in `.sandcastle/` that talks to GitHub, and the only one that
// names a GitHub URL or an endpoint path. Everything downstream is pure over
// the snapshot value this module returns — the same split `resolveAgents` and
// `validateModels` already draw, and the thing that made `scope/snapshot.mts`
// testable without a network.
//
// Four rules run through the whole file:
//
//   1. **Parse the target locally, then build the path from the fixed
//      repository.** The original string is never interpolated into a request.
//      `gh issue view --repo` is not a safe resolver: a live probe showed a
//      pasted URL overriding `--repo` and an `/issues/1` URL resolving to a
//      pull request (#390).
//   2. **Traverse the whole tree before filtering.** Closed, blocked,
//      unreleased and `ready-for-human` intermediates are walked through, not
//      stopped at — GitHub nests eight levels deep, so pruning during discovery
//      is how a run reports a SPEC drained while an eligible descendant sits
//      below an unreleased parent.
//   3. **`blocked` derives from blocker *state*, never from relationship
//      presence.** `/dependencies/blocked_by` returns closed relationships too.
//   4. **Fail closed, always. An API failure is never an empty list.** Every
//      read below either produces its data or throws, and a partial tree aborts
//      the whole load. Nothing here degrades quietly, because a quiet
//      degradation looks exactly like a drained SPEC.
//
// Pagination is not optional anywhere: GitHub caps `per_page` at 100 and a
// missing page is the documented cause of missing results.

import { execFileSync } from "node:child_process";
import { repo } from "../repo.mts";
import {
  buildSnapshot,
  issueByNodeId,
  READY_FOR_AGENT,
  READY_FOR_HUMAN,
  SPEC,
  type BlockerRef,
  type IssueComment,
  type IssueRecord,
  type WorkScope,
  type WorkScopeSnapshot,
} from "./snapshot.mts";

/**
 * Pinned, because an omitted `X-GitHub-Api-Version` still defaults to the older
 * `2022-11-28` — and issue dependencies are a newer surface than that.
 */
export const API_VERSION = "2026-03-10";

const ACCEPT_HEADER = "Accept: application/vnd.github+json";
const VERSION_HEADER = `X-GitHub-Api-Version: ${API_VERSION}`;
const PER_PAGE = 100;

/** GitHub nests at most eight levels; the slack is only there to bound a loop. */
const MAX_ANCESTRY_DEPTH = 16;

const REPOSITORY = repo.repository;

// ---------------------------------------------------------------------------
// Failure
// ---------------------------------------------------------------------------

/**
 * Why a scope could not be loaded. Coarse on purpose: `not-found` deliberately
 * does *not* distinguish missing from unauthorized, because GitHub answers both
 * with `404` and a resolver that guessed would be confidently wrong half the
 * time.
 */
export type ScopeErrorReason =
  /** The string the maintainer typed is not a target this runner accepts. */
  | "invalid-target"
  /** `404` or `410`. Not found *or* inaccessible; GitHub does not say which. */
  | "not-found"
  /** A pull request, or a read that redirected to a different issue. */
  | "not-an-issue"
  /** A descendant outside this repository. Valid on GitHub, fatal to a scope. */
  | "cross-repository"
  /** A child reached twice: a duplicate parent or a cycle. */
  | "malformed-tree"
  /** GitHub answered, but not in the shape this runner reads. */
  | "malformed-response"
  /** Authentication, permission or rate limit. */
  | "denied"
  /** A service error, or `gh` itself failing to run. */
  | "unavailable"
  /** The target resolved, and is not something an unattended run may drive. */
  | "target-rejected";

export class ScopeError extends Error {
  readonly reason: ScopeErrorReason;
  /**
   * The resolved target, when there is one. A rejected target is the case the
   * picker must render — number, title and labels — rather than restate as a
   * bare sentence.
   */
  readonly anchor: IssueRecord | undefined;

  constructor(reason: ScopeErrorReason, message: string, anchor?: IssueRecord) {
    super(message);
    this.name = "ScopeError";
    this.reason = reason;
    this.anchor = anchor;
  }
}

/** A resolution attempt, as a value: the picker branches on it, it never throws at it. */
export type ScopeOutcome =
  | { readonly ok: true; readonly snapshot: WorkScopeSnapshot }
  | {
      readonly ok: false;
      readonly reason: ScopeErrorReason;
      readonly message: string;
      readonly anchor: IssueRecord | undefined;
    };

// ---------------------------------------------------------------------------
// The transport
// ---------------------------------------------------------------------------

export interface GitHubRequest {
  /** An API path, already built from the fixed repository. Never a full URL. */
  readonly path: string;
  /** A list endpoint: follow every page and hand back one flat array. */
  readonly paginate: boolean;
}

/**
 * The single seam between this module and the network. Everything above it is
 * request-building and parsing, which is why the abort paths are testable
 * without a GitHub account: a fake transport can fail exactly one page.
 */
export type GitHubTransport = (request: GitHubRequest) => Promise<unknown>;

/**
 * The `gh api` argument vector for one request. Extracted so the pinned headers
 * and `--paginate` are assertable without spawning anything — the two things
 * whose absence is silent rather than loud.
 */
export function ghArgs(request: GitHubRequest): readonly string[] {
  const args = ["api", "-H", ACCEPT_HEADER, "-H", VERSION_HEADER];
  if (request.paginate) args.push("--paginate", "--slurp");
  args.push(request.path);
  return args;
}

/**
 * `--slurp` wraps each page in an array, so a paginated read comes back as an
 * array of pages. Flatten exactly one level, and refuse anything else rather
 * than let a scalar page become a silently short list.
 */
export function flattenPages(value: unknown, path: string): readonly unknown[] {
  if (!Array.isArray(value)) {
    throw new ScopeError("malformed-response", `GitHub's \`${path}\` response is not a list.`);
  }
  return value.flatMap((page) => {
    if (!Array.isArray(page)) {
      throw new ScopeError("malformed-response", `A page of \`${path}\` is not a list.`);
    }
    return page;
  });
}

interface SpawnFailure {
  readonly stderr?: string | Buffer;
  readonly message?: string;
}

/**
 * `gh api` exits non-zero on an HTTP error and prints `(HTTP nnn)` to stderr.
 * The status only chooses the wording — every branch here still throws, because
 * the caller's behaviour is identical: abort before dispatch. Exported so that
 * choice is assertable without a network, a login or a spawn.
 */
export function httpFailure(path: string, stderr: string, fallback: string): ScopeError {
  const status = Number(/\(HTTP (\d{3})\)/.exec(stderr)?.[1] ?? NaN);
  const detail = stderr.split("\n")[0]?.trim() || fallback;

  if (status === 404 || status === 410) {
    return new ScopeError(
      "not-found",
      `GitHub returned ${status} for \`${path}\` — not found or inaccessible. GitHub answers both the same way, so this runner will not claim which.`,
    );
  }
  if (status === 401 || status === 403 || status === 429) {
    return new ScopeError(
      "denied",
      `GitHub returned ${status} for \`${path}\` — authentication, permission or rate limit: ${detail}`,
    );
  }
  return new ScopeError("unavailable", `Reading \`${path}\` from GitHub failed: ${detail}`);
}

function fromGhFailure(path: string, error: unknown): ScopeError {
  const failure = error as SpawnFailure;
  return httpFailure(
    path,
    failure.stderr === undefined || failure.stderr === null ? "" : String(failure.stderr).trim(),
    failure.message ?? "gh could not be run",
  );
}

/** The real transport: `gh api`, with the headers pinned and every list paginated. */
export function ghTransport(): GitHubTransport {
  return async (request) => {
    let stdout: string;
    try {
      stdout = execFileSync("gh", [...ghArgs(request)], {
        encoding: "utf8",
        maxBuffer: 128 * 1024 * 1024,
        // Captured rather than inherited. `gh` echoes `gh: Not Found (HTTP
        // 404)` to its own stderr, and one of those is an *expected answer*
        // here — an issue with no parent — so letting it through would print a
        // scary line into an append-only run ledger on a perfectly healthy run.
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (error) {
      throw fromGhFailure(request.path, error);
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(stdout);
    } catch {
      throw new ScopeError(
        "malformed-response",
        `GitHub's \`${request.path}\` response is not JSON.`,
      );
    }
    return request.paginate ? flattenPages(parsed, request.path) : parsed;
  };
}

/**
 * That `gh` is installed and logged in, checked once before a run starts.
 *
 * Here rather than in `runner.mts` because this module owns the GitHub boundary
 * — and it is the one exit code outside git's that this tool reads, which the
 * framework-agnostic rule permits precisely because `gh` is the tracker, not the
 * toolchain. The alternative is discovering at item seven that a token expired
 * two items ago, with every close and every bounce silently lost.
 */
export function assertGitHubAuth(): void {
  try {
    execFileSync("gh", ["auth", "status"], { stdio: ["ignore", "ignore", "pipe"] });
  } catch (error) {
    const failure = error as SpawnFailure;
    const detail =
      String(failure.stderr ?? "")
        .trim()
        .split("\n")
        .find((line) => line.trim() !== "") ?? failure.message ?? "gh could not be run";
    throw new Error(`\`gh auth status\` failed, so this run could not read or write issues: ${detail}`);
  }
}

// ---------------------------------------------------------------------------
// Target parsing
// ---------------------------------------------------------------------------

const BARE_NUMBER = /^[1-9][0-9]*$/;

function invalidTarget(raw: string, detail: string): ScopeError {
  return new ScopeError(
    "invalid-target",
    `\`${raw}\` is not a target for this repository: ${detail}. Give an issue number, or a ${REPOSITORY} issue URL.`,
  );
}

/**
 * The typed target, as a positive issue number. Every request path is then
 * built from `REPOSITORY` and this integer, so nothing a maintainer pastes
 * reaches GitHub verbatim — which is the whole reason a URL is parsed here
 * rather than handed to `gh`.
 *
 * A negative or zero number fails the pattern rather than being clamped: a
 * target nobody can have meant is not a target to guess at.
 */
export function parseTarget(raw: string): number {
  const trimmed = raw.trim();
  if (trimmed === "") throw invalidTarget(raw, "it is empty");
  if (BARE_NUMBER.test(trimmed)) {
    const number = Number(trimmed);
    if (!Number.isSafeInteger(number)) throw invalidTarget(raw, "the number is too large");
    return number;
  }

  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    throw invalidTarget(raw, "it is neither a positive issue number nor a URL");
  }

  if (url.protocol !== "https:") throw invalidTarget(raw, "only https URLs are accepted");
  if (url.hostname.toLowerCase() !== "github.com") throw invalidTarget(raw, "the host is not github.com");
  if (url.username || url.password) throw invalidTarget(raw, "the URL carries credentials");
  if (url.port) throw invalidTarget(raw, "the URL carries a port");
  if (url.search || url.hash) throw invalidTarget(raw, "the URL carries a query or fragment");

  // `/pull/<n>` fails this pattern, which is the point: a pull request is not
  // work, and the shape says so before anything is fetched.
  const segments = url.pathname.replace(/\/+$/, "").split("/").slice(1);
  const [owner, name, kind, number] = segments;
  if (segments.length !== 4 || kind !== "issues" || number === undefined) {
    throw invalidTarget(raw, "it is not an issue URL");
  }
  // Owner and repository are case-insensitive path parameters on GitHub.
  if (`${owner}/${name}`.toLowerCase() !== REPOSITORY.toLowerCase()) {
    throw invalidTarget(raw, `it names ${owner}/${name} rather than ${REPOSITORY}`);
  }
  if (!BARE_NUMBER.test(number)) throw invalidTarget(raw, "the issue number is not positive");

  const parsed = Number(number);
  if (!Number.isSafeInteger(parsed)) throw invalidTarget(raw, "the number is too large");
  return parsed;
}

// ---------------------------------------------------------------------------
// Reading GitHub's JSON
// ---------------------------------------------------------------------------

function malformed(what: string, detail: string): ScopeError {
  return new ScopeError(
    "malformed-response",
    `GitHub's ${what} response is not the shape this runner reads: ${detail}.`,
  );
}

function asObject(value: unknown, what: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw malformed(what, "expected an object");
  }
  return value as Record<string, unknown>;
}

function requireString(source: Record<string, unknown>, key: string, what: string): string {
  const value = source[key];
  if (typeof value !== "string") throw malformed(what, `\`${key}\` is not a string`);
  return value;
}

function optionalString(source: Record<string, unknown>, key: string, what: string): string | null {
  const value = source[key];
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw malformed(what, `\`${key}\` is not a string or null`);
  return value;
}

function requireInteger(source: Record<string, unknown>, key: string, what: string): number {
  const value = source[key];
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw malformed(what, `\`${key}\` is not an integer`);
  }
  return value;
}

/** `https://api.github.com/repos/<owner>/<name>` → `<owner>/<name>`. */
function repositoryOf(source: Record<string, unknown>, what: string): string {
  const url = requireString(source, "repository_url", what);
  const match = /\/repos\/([^/]+)\/([^/]+)$/.exec(url);
  if (!match) throw malformed(what, `\`repository_url\` is not a repository URL: ${url}`);
  return `${match[1]}/${match[2]}`;
}

function isPullRequest(value: unknown): boolean {
  return typeof value === "object" && value !== null && "pull_request" in value
    ? (value as Record<string, unknown>)["pull_request"] != null
    : false;
}

/** Identity, content and labels. Edges and comments are fetched separately. */
interface RawIssue {
  readonly databaseId: number;
  readonly nodeId: string;
  readonly number: number;
  readonly repository: string;
  readonly url: string;
  readonly title: string;
  readonly body: string;
  readonly state: "open" | "closed";
  readonly stateReason: string | null;
  readonly labels: readonly string[];
  readonly updatedAt: string;
}

function parseIssue(value: unknown, what: string): RawIssue {
  const raw = asObject(value, what);
  // The REST Issues API represents a pull request as an issue, so this check is
  // required even on a path that says `issues`.
  if (isPullRequest(raw)) {
    throw new ScopeError("not-an-issue", `${what} is a pull request, not an issue.`);
  }

  const state = requireString(raw, "state", what);
  if (state !== "open" && state !== "closed") throw malformed(what, `\`state\` is \`${state}\``);

  const rawLabels = raw["labels"] ?? [];
  if (!Array.isArray(rawLabels)) throw malformed(what, "`labels` is not a list");

  return {
    databaseId: requireInteger(raw, "id", what),
    nodeId: requireString(raw, "node_id", what),
    number: requireInteger(raw, "number", what),
    repository: repositoryOf(raw, what),
    url: requireString(raw, "html_url", what),
    title: requireString(raw, "title", what),
    body: optionalString(raw, "body", what) ?? "",
    state,
    stateReason: optionalString(raw, "state_reason", what),
    labels: rawLabels.map((label) =>
      typeof label === "string"
        ? label
        : requireString(asObject(label, `${what} label`), "name", `${what} label`),
    ),
    updatedAt: requireString(raw, "updated_at", what),
  };
}

function parseComment(value: unknown, what: string): IssueComment {
  const raw = asObject(value, what);
  const user = raw["user"];
  return {
    databaseId: requireInteger(raw, "id", what),
    nodeId: requireString(raw, "node_id", what),
    // A deleted account leaves the comment and loses the author, so this is
    // null rather than absent.
    authorLogin:
      user === undefined || user === null
        ? null
        : optionalString(asObject(user, `${what} author`), "login", `${what} author`),
    body: optionalString(raw, "body", what) ?? "",
    createdAt: requireString(raw, "created_at", what),
    updatedAt: requireString(raw, "updated_at", what),
  };
}

// ---------------------------------------------------------------------------
// The four definitive reads
// ---------------------------------------------------------------------------

function issuePath(number: number, suffix = ""): string {
  return `repos/${REPOSITORY}/issues/${number}${suffix}`;
}

async function readIssue(transport: GitHubTransport, number: number): Promise<RawIssue> {
  const what = `issue #${number}`;
  const issue = parseIssue(
    await transport({ path: issuePath(number), paginate: false }),
    what,
  );
  // `GET /issues/{n}` documents a `301` after a transfer, so the canonical
  // response is compared rather than trusted: a redirect that landed elsewhere
  // is a different issue wearing the number that was asked for.
  if (issue.repository.toLowerCase() !== REPOSITORY.toLowerCase() || issue.number !== number) {
    throw new ScopeError(
      "not-an-issue",
      `#${number} resolved to ${issue.repository}#${issue.number}. GitHub redirected the read, so the target is not the issue it names.`,
    );
  }
  return issue;
}

/**
 * One level of native children. The list returns the full issue representation,
 * so a child's own record comes from here rather than from a second
 * `GET /issues/{n}` — one read per node instead of two, over the same schema.
 */
async function readSubIssues(
  transport: GitHubTransport,
  parent: RawIssue,
): Promise<readonly RawIssue[]> {
  const what = `issue #${parent.number} sub-issues`;
  const page = await transport({
    path: issuePath(parent.number, `/sub_issues?per_page=${PER_PAGE}`),
    paginate: true,
  });
  if (!Array.isArray(page)) throw malformed(what, "expected a list");
  return page.map((child, index) => parseIssue(child, `${what}[${index}]`));
}

async function readComments(
  transport: GitHubTransport,
  issue: RawIssue,
): Promise<readonly IssueComment[]> {
  const what = `issue #${issue.number} comments`;
  const page = await transport({
    path: issuePath(issue.number, `/comments?per_page=${PER_PAGE}`),
    paginate: true,
  });
  if (!Array.isArray(page)) throw malformed(what, "expected a list");
  return page.map((comment, index) => parseComment(comment, `${what}[${index}]`));
}

/**
 * The blockers whose state is currently `open`. The endpoint returns closed
 * relationships too, so a run that read presence rather than state would call a
 * finished SPEC's every slice blocked — the exact case a live probe found on
 * #381, whose summary read `blocked_by: 0, total_blocked_by: 1`.
 */
async function readOpenBlockers(
  transport: GitHubTransport,
  issue: RawIssue,
): Promise<readonly BlockerRef[]> {
  const what = `issue #${issue.number} blockers`;
  const page = await transport({
    path: issuePath(issue.number, `/dependencies/blocked_by?per_page=${PER_PAGE}`),
    paginate: true,
  });
  if (!Array.isArray(page)) throw malformed(what, "expected a list");

  return page
    .map((blocker, index) => parseIssue(blocker, `${what}[${index}]`))
    .filter((blocker) => blocker.state === "open")
    .map((blocker) => ({
      nodeId: blocker.nodeId,
      // A blocker outside this repository is a real gate that can never be
      // work, so it is carried rather than refused.
      repository: blocker.repository,
      number: blocker.number,
      url: blocker.url,
      title: blocker.title,
    }));
}

/** The two per-issue reads that are not part of its own representation. */
interface IssueContext {
  readonly comments: readonly IssueComment[];
  readonly openBlockers: readonly BlockerRef[];
}

async function readContext(transport: GitHubTransport, issue: RawIssue): Promise<IssueContext> {
  return {
    comments: await readComments(transport, issue),
    openBlockers: await readOpenBlockers(transport, issue),
  };
}

interface IssueEdges {
  readonly parentNodeId: string | null;
  readonly childNodeIds: readonly string[];
}

function toRecord(issue: RawIssue, context: IssueContext, edges: IssueEdges): IssueRecord {
  return { ...issue, ...context, ...edges };
}

// ---------------------------------------------------------------------------
// Target validation
// ---------------------------------------------------------------------------

/**
 * Whether this resolved issue may be an explicit run target. A descendant is
 * judged by `scope/snapshot.mts` and stays visible when it fails; an explicit
 * target has nowhere to be visible *in*, so it is refused here with everything
 * that is wrong with it at once.
 */
function rejectUnusableTarget(scope: WorkScope, anchor: IssueRecord): void {
  const problems: string[] = [];
  if (anchor.state === "closed") problems.push("it is closed");

  const forHuman = anchor.labels.includes(READY_FOR_HUMAN);
  const forAgent = anchor.labels.includes(READY_FOR_AGENT);
  if (forHuman && forAgent) {
    // Reported rather than resolved. Reading a contradiction towards unattended
    // execution is the one reading that cannot be undone.
    problems.push(`it carries both \`${READY_FOR_HUMAN}\` and \`${READY_FOR_AGENT}\``);
  } else if (forHuman) {
    problems.push(`it carries \`${READY_FOR_HUMAN}\``);
  } else if (!forAgent) {
    problems.push(`it does not carry \`${READY_FOR_AGENT}\``);
  }

  if (scope.kind === "specific-spec" && !anchor.labels.includes(SPEC)) {
    problems.push(`it does not carry \`${SPEC}\``);
  }
  if (anchor.openBlockers.length > 0) {
    const blockers = anchor.openBlockers.map((blocker) => `#${blocker.number}`).join(", ");
    problems.push(`it is blocked by ${blockers}`);
  }

  if (problems.length > 0) {
    throw new ScopeError(
      "target-rejected",
      `#${anchor.number} ${anchor.title} cannot be a run target: ${problems.join("; ")}.`,
      anchor,
    );
  }
}

// ---------------------------------------------------------------------------
// Loading a scope
// ---------------------------------------------------------------------------

/**
 * Every descendant of `anchor`, breadth-first over the one-level `/sub_issues`
 * endpoint — there is no recursive REST call, so the recursion is here.
 *
 * Nothing is pruned on the way down. A cross-repository child aborts the load
 * rather than being skipped: omitting the subtree would claim a SPEC drained
 * without having seen it, and following it would widen the repository this run
 * touches.
 */
async function traverse(
  transport: GitHubTransport,
  anchor: RawIssue,
  anchorContext: IssueContext,
): Promise<readonly IssueRecord[]> {
  // The anchor arrives with its context already read, because validating the
  // target needed its blockers. Everything below it reads its own.
  const queue: { issue: RawIssue; context: IssueContext | null; parentNodeId: string | null }[] = [
    { issue: anchor, context: anchorContext, parentNodeId: null },
  ];
  const seen = new Set<string>([anchor.nodeId]);
  const members: IssueRecord[] = [];

  while (queue.length > 0) {
    const next = queue.shift();
    if (!next) break;

    const children = await readSubIssues(transport, next.issue);
    for (const child of children) {
      if (child.repository.toLowerCase() !== REPOSITORY.toLowerCase()) {
        throw new ScopeError(
          "cross-repository",
          `#${next.issue.number} has a sub-issue in ${child.repository} (#${child.number}). A Work scope cannot span repositories, and half a tree is not a scope.`,
        );
      }
      if (seen.has(child.nodeId)) {
        throw new ScopeError(
          "malformed-tree",
          `#${child.number} appears twice under #${anchor.number} — a duplicate parent or a cycle. The tree is ambiguous, so no order can be trusted.`,
        );
      }
      seen.add(child.nodeId);
      queue.push({ issue: child, context: null, parentNodeId: next.issue.nodeId });
    }

    members.push(
      toRecord(next.issue, next.context ?? (await readContext(transport, next.issue)), {
        parentNodeId: next.parentNodeId,
        // Authored order, straight from GitHub's list. Never sorted: the
        // reprioritise endpoint edits it, which is what makes it the one signal
        // carrying maintainer intent.
        childNodeIds: children.map((child) => child.nodeId),
      }),
    );
  }

  return members;
}

/**
 * The repository-wide queue. No anchor, so no tree and no authored order —
 * `scope/snapshot.mts` falls back to ascending number.
 */
async function loadQueue(transport: GitHubTransport): Promise<readonly IssueRecord[]> {
  const what = "repository issue queue";
  const path = `repos/${REPOSITORY}/issues?state=open&labels=${READY_FOR_AGENT}&per_page=${PER_PAGE}`;
  const page = await transport({ path, paginate: true });
  if (!Array.isArray(page)) throw malformed(what, "expected a list");

  const members: IssueRecord[] = [];
  for (const [index, candidate] of page.entries()) {
    // This endpoint returns pull requests too, so they are dropped rather than
    // refused: a pull request in the repository's own queue is normal, while a
    // pull request *named as a target* is a mistake worth reporting.
    if (isPullRequest(candidate)) continue;
    const issue = parseIssue(candidate, `${what}[${index}]`);
    members.push(
      toRecord(issue, await readContext(transport, issue), {
        parentNodeId: null,
        childNodeIds: [],
      }),
    );
  }
  return members;
}

async function loadScope(
  scope: WorkScope,
  transport: GitHubTransport,
): Promise<WorkScopeSnapshot> {
  if (scope.kind === "all-ready-for-agent") {
    return buildSnapshot({
      scopeKind: scope.kind,
      repository: REPOSITORY,
      anchorNodeId: null,
      issues: await loadQueue(transport),
    });
  }

  const anchorIssue = await readIssue(transport, parseTarget(scope.target));
  // Context is read before validation because "no open blocker" is one of the
  // things being validated, and a rejection has to be able to show the blockers.
  const anchorContext = await readContext(transport, anchorIssue);
  const anchor = toRecord(anchorIssue, anchorContext, { parentNodeId: null, childNodeIds: [] });
  rejectUnusableTarget(scope, anchor);

  return buildSnapshot({
    scopeKind: scope.kind,
    repository: REPOSITORY,
    anchorNodeId: anchor.nodeId,
    issues:
      scope.kind === "specific-issue"
        ? [anchor]
        : await traverse(transport, anchorIssue, anchorContext),
  });
}

/**
 * Resolve one Work scope into a frozen snapshot, or say why it could not be.
 *
 * The failure is a value rather than a throw because the picker's job is to
 * offer a recovery — retry, another target, another scope — and a value is what
 * makes the recovery paths testable. There is no third case: this never returns
 * a snapshot it could not fully read.
 */
export async function resolveScope(
  scope: WorkScope,
  transport: GitHubTransport = ghTransport(),
): Promise<ScopeOutcome> {
  try {
    return { ok: true, snapshot: await loadScope(scope, transport) };
  } catch (error) {
    if (error instanceof ScopeError) {
      return { ok: false, reason: error.reason, message: error.message, anchor: error.anchor };
    }
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Pre-dispatch revalidation
// ---------------------------------------------------------------------------

/**
 * What a pre-dispatch re-read found. GitHub exposes no atomic recursive
 * snapshot, so the tree can move under a run — and the three outcomes below are
 * distinguished because they mean different things about the *foundation*:
 * a closed item was done by somebody, a deregulated one never will be, and a
 * changed anchor means the contract the whole run serves is gone.
 *
 * Classifying the mismatch is this module's job. Deciding what the run does
 * about it is the driver's.
 */
export type Revalidation =
  /** Safe to dispatch, against this freshly-read record rather than the frozen one. */
  | { readonly status: "ok"; readonly issue: IssueRecord }
  /** The controlling contract changed. The caller aborts the run. */
  | { readonly status: "anchor-changed"; readonly detail: string }
  /** Someone did the work. The caller skips the item; dependents keep their foundation. */
  | { readonly status: "item-closed"; readonly detail: string }
  /** The work will not happen. The caller skips the item and its dependents. */
  | { readonly status: "item-deregulated"; readonly detail: string };

/**
 * The anchor's own live state. Only the anchor is label-checked: an
 * intermediate parent is deliberately allowed to be unreleased, because
 * traversal already refuses to prune below one, and re-checking it here would
 * abort every run over a tree that discovery was built to support.
 */
async function checkAnchor(
  transport: GitHubTransport,
  snapshot: WorkScopeSnapshot,
  anchorNodeId: string,
): Promise<string | null> {
  const frozen = issueByNodeId(snapshot, anchorNodeId);
  if (!frozen) return `the frozen anchor ${anchorNodeId} is not in its own snapshot`;

  const live = await readIssue(transport, frozen.number);
  if (live.nodeId !== anchorNodeId) return `#${frozen.number} is no longer the anchor issue`;
  if (live.state === "closed") return `#${frozen.number} is closed`;
  if (!live.labels.includes(READY_FOR_AGENT)) {
    return `#${frozen.number} no longer carries \`${READY_FOR_AGENT}\``;
  }
  if (live.labels.includes(READY_FOR_HUMAN)) {
    return `#${frozen.number} now carries \`${READY_FOR_HUMAN}\``;
  }
  if (snapshot.scopeKind === "specific-spec" && !live.labels.includes(SPEC)) {
    return `#${frozen.number} no longer carries \`${SPEC}\``;
  }
  return null;
}

/**
 * Whether `number` still descends from the frozen anchor, by walking GitHub's
 * `/parent` endpoint upward. Re-read rather than taken from the snapshot,
 * because the snapshot's edges are exactly what this is checking.
 */
async function stillDescendsFrom(
  transport: GitHubTransport,
  number: number,
  anchorNodeId: string,
): Promise<boolean> {
  let current = number;
  for (let depth = 0; depth < MAX_ANCESTRY_DEPTH; depth += 1) {
    let parent: unknown;
    try {
      parent = await transport({ path: issuePath(current, "/parent"), paginate: false });
    } catch (error) {
      // The one place a `404` is an answer rather than a failure: an issue with
      // no parent has no parent resource. Every other status still aborts.
      if (error instanceof ScopeError && error.reason === "not-found") return false;
      throw error;
    }
    const issue = parseIssue(parent, `issue #${current} parent`);
    if (issue.nodeId === anchorNodeId) return true;
    // A parent in another repository cannot be on the way to this anchor, and
    // its number would otherwise be read back against *our* repository — a
    // different issue entirely, walked as if it were the ancestor.
    if (issue.repository.toLowerCase() !== REPOSITORY.toLowerCase()) return false;
    current = issue.number;
  }
  return false;
}

/**
 * Re-read one work item and its ancestry immediately before dispatching it, and
 * refuse on any mismatch.
 *
 * The `ok` branch carries the *fresh* record, not the frozen one, so the prompt
 * is built from acceptance context the run just acknowledged rather than from
 * whatever was true when the picker ran. Membership is never widened: this
 * never adds an issue, only classifies one that is already in the snapshot.
 */
export async function revalidate(
  snapshot: WorkScopeSnapshot,
  nodeId: string,
  transport: GitHubTransport = ghTransport(),
): Promise<Revalidation> {
  const frozen = issueByNodeId(snapshot, nodeId);
  if (!frozen) throw new Error(`Revalidated an item outside the snapshot: ${nodeId}`);

  // Ancestry first: an abort outranks a skip, so a run whose contract is gone
  // never reports a per-item cause instead.
  const { anchorNodeId } = snapshot;
  if (anchorNodeId !== null && anchorNodeId !== nodeId) {
    const anchorProblem = await checkAnchor(transport, snapshot, anchorNodeId);
    if (anchorProblem !== null) return { status: "anchor-changed", detail: anchorProblem };
    if (!(await stillDescendsFrom(transport, frozen.number, anchorNodeId))) {
      const anchor = issueByNodeId(snapshot, anchorNodeId);
      return {
        status: "anchor-changed",
        detail: `#${frozen.number} no longer descends from #${anchor?.number ?? "the anchor"}`,
      };
    }
  }

  const live = await readIssue(transport, frozen.number);
  if (live.nodeId !== nodeId) {
    return {
      status: "item-deregulated",
      detail: `#${frozen.number} is no longer the issue this run froze`,
    };
  }
  if (live.state === "closed") {
    return { status: "item-closed", detail: `#${frozen.number} was closed during the run` };
  }
  if (live.labels.includes(READY_FOR_HUMAN)) {
    return {
      status: "item-deregulated",
      detail: `#${frozen.number} now carries \`${READY_FOR_HUMAN}\``,
    };
  }
  if (!live.labels.includes(READY_FOR_AGENT)) {
    return {
      status: "item-deregulated",
      detail: `#${frozen.number} no longer carries \`${READY_FOR_AGENT}\``,
    };
  }

  const issue = toRecord(live, await readContext(transport, live), {
    parentNodeId: frozen.parentNodeId,
    childNodeIds: frozen.childNodeIds,
  });
  // An in-set blocker is a precedence edge the driver already honours; only a
  // blocker this run will never reach is a new gate.
  const executable = new Set(snapshot.executableNodeIds);
  const outside = issue.openBlockers.filter((blocker) => !executable.has(blocker.nodeId));
  if (outside.length > 0) {
    return {
      status: "item-deregulated",
      detail: `#${frozen.number} is newly blocked from outside this run by ${outside.map((blocker) => `#${blocker.number}`).join(", ")}`,
    };
  }

  return { status: "ok", issue };
}
