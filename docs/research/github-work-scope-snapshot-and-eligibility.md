# GitHub Work scope snapshot and eligibility

Research for [Establish the GitHub issue-tree snapshot and eligibility
query](https://github.com/hadrysm/foldwise-voice/issues/390), current as of
2026-07-30. This note uses the current GitHub REST API version
`2026-03-10` and GitHub CLI `2.96.0`. GitHub says REST versions are named for
their release date, recommends sending `X-GitHub-Api-Version`, and currently
supports both `2026-03-10` and `2022-11-28`; an omitted header still defaults
to the older version. ([API versioning](https://docs.github.com/en/rest/about-the-rest-api/api-versions))

This is API research and a recommended loader contract, not an implementation.
Queue order, whether a later eligibility change skips or stops a run, and the
final handoff lifecycle remain decisions for [Settle batch ordering, stop
conditions, and handoff
semantics](https://github.com/hadrysm/foldwise-voice/issues/394).

## Conclusion

Use the versioned REST API through `gh api`, not `gh issue view`, as the
source of truth:

1. Parse the user's value locally into a positive issue number. A URL is
   accepted only when it is exactly a same-repository
   `https://github.com/hadrysm/foldwise-voice/issues/<number>` URL.
2. Fetch the canonical issue from
   `GET /repos/hadrysm/foldwise-voice/issues/<number>`, then reject a pull
   request, a canonical repository mismatch, or a canonical number mismatch.
3. For Specific SPEC, breadth-first traverse every parent's paginated
   `/sub_issues` endpoint. Do not filter while traversing: closed, unreleased,
   blocked, and `ready-for-human` descendants are part of the visible tree even
   though they are not executable.
4. For every issue, fetch its paginated `/comments`; comments can amend
   acceptance context, including review-bounce instructions.
5. For every candidate, fetch the paginated `/dependencies/blocked_by`
   endpoint and derive `openBlockers` by filtering the returned issues to
   `state == "open"`.
6. Normalize all data, derive eligibility in the runner, and freeze an explicit
   executable allow-list before a workflow dispatches an agent. An agent never
   discovers or selects another issue.

There is no recursive REST call: recursion is client-side over the one-level
sub-issue endpoint. GitHub permits up to 100 direct sub-issues per parent, up to
eight hierarchy levels, and sub-issues from other repositories, so complete
pagination and an explicit repository check at every edge are required.
([Adding sub-issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues),
[List sub-issues](https://docs.github.com/en/rest/issues/sub-issues?apiVersion=2026-03-10#list-sub-issues))

## API facts

### `gh issue view` is useful interactively, but unsafe as the resolver

The current CLI exposes `blockedBy`, `blocking`, `parent`, `subIssues`, and
`subIssuesSummary` as `gh issue view --json` fields.
([`gh issue view` manual](https://cli.github.com/manual/gh_issue_view))
However, a live read-only probe with CLI `2.96.0` showed:

```console
$ gh issue view https://github.com/cli/cli/issues/1 \
    --repo hadrysm/foldwise-voice --json number,url
{"number":1,"url":"https://github.com/cli/cli/pull/1"}
```

The URL overrode `--repo`, and an `/issues/1` URL resolved to a pull request.
The REST Issues API likewise treats every pull request as an issue and requires
callers to distinguish one by the `pull_request` key.
([REST Issues API](https://docs.github.com/en/rest/issues/issues?apiVersion=2026-03-10))
Therefore the loader must not pass an unvalidated user URL to `gh`, and must
reject a non-null `pull_request` response even after local parsing.

### The four definitive reads

All four reads require only Issues repository permission (read), and public
resources can be read without authentication. The sub-issue, comment, and
dependency list endpoints are paginated, with `per_page` capped at 100.
([Get an issue](https://docs.github.com/en/rest/issues/issues?apiVersion=2026-03-10#get-an-issue),
[List sub-issues](https://docs.github.com/en/rest/issues/sub-issues?apiVersion=2026-03-10#list-sub-issues),
[List issue comments](https://docs.github.com/en/rest/issues/comments?apiVersion=2026-03-10#list-issue-comments),
[List dependencies an issue is blocked by](https://docs.github.com/en/rest/issues/issue-dependencies?apiVersion=2026-03-10#list-dependencies-an-issue-is-blocked-by))
`gh api --paginate` follows all pages; `--slurp` can wrap page responses for a
later `jq` reduction. ([`gh api` manual](https://cli.github.com/manual/gh_api))

```bash
repo=hadrysm/foldwise-voice
number=390
accept='Accept: application/vnd.github+json'
version='X-GitHub-Api-Version: 2026-03-10'

# Canonical issue, including body, state, labels, repository_url, and identity.
gh api -H "$accept" -H "$version" \
  "repos/$repo/issues/$number"

# One level of native children. Repeat for every returned child.
gh api --paginate --slurp -H "$accept" -H "$version" \
  "repos/$repo/issues/$number/sub_issues?per_page=100"

# Complete acceptance context. GitHub returns comments by ascending ID.
gh api --paginate --slurp -H "$accept" -H "$version" \
  "repos/$repo/issues/$number/comments?per_page=100"

# All native blocker relationships. Filter open blockers client-side.
gh api --paginate --slurp -H "$accept" -H "$version" \
  "repos/$repo/issues/$number/dependencies/blocked_by?per_page=100"
```

GitHub's REST pagination is represented by `Link` response headers; missing
pagination is a documented cause of missing results.
([REST pagination](https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api))
The per-issue comments endpoint documents ascending numeric ID order and
returns stable `id`/`node_id`, author, body, creation time, and update time.
([List issue comments](https://docs.github.com/en/rest/issues/comments?apiVersion=2026-03-10#list-issue-comments))

The root issue response contains useful summaries, but they do not replace the
identity-bearing list endpoints. On 2026-07-30, the live response for the
[Work scope map](https://github.com/hadrysm/foldwise-voice/issues/389) included:

```json
{
  "number": 389,
  "updated_at": "2026-07-30T18:41:27Z",
  "sub_issues_summary": {
    "total": 9,
    "completed": 0,
    "percent_completed": 0
  },
  "issue_dependencies_summary": {
    "blocked_by": 0,
    "total_blocked_by": 0,
    "blocking": 0,
    "total_blocking": 0
  }
}
```

The `/sub_issues` response supplies the nine child identities. Likewise,
`issue_dependencies_summary.blocked_by` is an observed convenient open count,
but `/dependencies/blocked_by` supplies blocker identities and states.

### Dependency reads include closed blockers

A live probe of [Delete the v1 run-store read branch once every clone has
migrated](https://github.com/hadrysm/foldwise-voice/issues/381) returned closed
[Migrate the run store to v2 with per-workflow knobs and upsert
writes](https://github.com/hadrysm/foldwise-voice/issues/377) from
`/dependencies/blocked_by`, while the subject's summary was:

```json
{
  "blocked_by": 0,
  "total_blocked_by": 1
}
```

Therefore relationship presence is not the execution gate. The normalized
gate is:

```text
openBlockers = allBlockedByRelationships.filter(blocker.state == "open")
blocked = openBlockers.length > 0
```

Retaining closed blocker identities is optional for the prompt, but the loader
must not classify an issue as blocked merely because the endpoint returned a
relationship. GitHub defines dependencies as the native representation of
issues that block other work, and the CLI also exposes them programmatically.
([Creating issue dependencies](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-issue-dependencies))

## Exact resolver and traversal contract

### 1. Parse before calling GitHub

Trim surrounding whitespace, then accept one of:

- a bare decimal matching `^[1-9][0-9]*$`; or
- an HTTPS URL with host `github.com`, no credentials, port, query, or
  fragment, and exactly the path
  `/hadrysm/foldwise-voice/issues/<positive-decimal>` (an optional final slash
  is harmless). Owner and repository comparison may be case-insensitive
  because GitHub documents those path parameters as case-insensitive.

Reject `/pull/<n>`, shorthand such as `owner/repo#n`, other hosts, and every
other repository. Build the API endpoint only from the constant repository and
the parsed integer; never interpolate the original URL.

After `GET /issues/<number>`, require:

```text
repository_url == "https://api.github.com/repos/hadrysm/foldwise-voice"
number         == parsed number
pull_request   is absent/null
node_id        is present
```

Comparing the canonical response matters because GitHub's Get issue endpoint
may redirect (`301` is documented), for example after a transfer. `node_id` is
the snapshot's issue identity; the repository and number remain human-facing
coordinates.

### 2. Validate the explicit anchor

Every explicit anchor must:

- be `open`;
- have `ready-for-agent`;
- not have `ready-for-human`; and
- have no open native blocker.

Specific SPEC additionally requires `spec`. The SPEC anchor is the controlling
contract, not an executable work item; only its eligible descendants enter the
SPEC executable allow-list. Specific issue has exactly the validated anchor in
its allow-list.

Check labels as exact names from `labels[].name`. If both
`ready-for-agent` and `ready-for-human` appear, `ready-for-human` wins and the
target is invalid; report the conflicting labels rather than silently choosing
AFK execution.

### 3. Traverse a SPEC without eligibility pruning

Use a queue initially containing the anchor. For each parent:

1. Fetch every page of `/sub_issues`.
2. For each child, validate its `repository_url`, `number`, `node_id`, and
   absence of `pull_request`.
3. Record the parent-child edge before deriving eligibility.
4. Add unseen children to the queue, regardless of state or labels.
5. Fail on a duplicate/cycle rather than producing an ambiguous tree.

Do not stop at a closed, blocked, unreleased, or `ready-for-human` intermediate
node: GitHub supports nested hierarchies, and an eligible descendant can exist
below an ineligible parent. Eligibility filters executable nodes, not tree
discovery.

Because GitHub explicitly permits cross-repository sub-issues, a cross-repo
child is a real structural state rather than malformed JSON. The recommended
same-repository contract classifies it as `cross_repository_descendant` and
fails the whole Specific SPEC load before dispatch. Silently omitting that
subtree would claim to have drained a controlling SPEC without having observed
its full tree; following it would widen the selected repository scope.

### 4. Fetch blockers for every executable candidate

Fetch and paginate `/dependencies/blocked_by` for the explicit anchor and each
potential work item. Normalize every returned blocker with repository, node
identity, number, URL, title, and state; derive `openBlockers` explicitly.
An open cross-repository blocker is valid as a gate: it remains outside Work
scope but makes the candidate ineligible.

The live REST responses also expose `issue_dependencies_summary`. A loader may
use its total and open counts as an integrity cross-check against the paginated
relationship response, but the list endpoint and explicit state filter are the
contract because the REST reference documents that endpoint.

### 5. Repository-wide candidate query

For All ready-for-agent issues, the candidate read is:

```bash
gh api --paginate --slurp \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  'repos/hadrysm/foldwise-voice/issues?state=open&labels=ready-for-agent&per_page=100'
```

Filter out responses with `pull_request`, reject `ready-for-human`, then fetch
blockers for each remaining candidate. The Issues endpoint can return pull
requests, so that filter is required even though the path says `issues`.
The configurable 1–50 limit and execution order apply only after this complete
eligibility normalization; their policy belongs to the lifecycle ticket.

## Recommended normalized shape

Keep one internal snapshot for selection and handoff, then project only the
controlling SPEC and current work item into each agent prompt.

```ts
type ExclusionReason =
  | "closed"
  | "unreleased"
  | "ready_for_human"
  | "blocked";

type IssueSnapshot = {
  databaseId: number;
  nodeId: string;
  number: number;
  repository: "hadrysm/foldwise-voice";
  url: string;
  title: string;
  body: string;
  state: "open" | "closed";
  stateReason: string | null;
  labels: string[];             // lexical order
  updatedAt: string;
  comments: Array<{
    databaseId: number;
    nodeId: string;
    authorLogin: string | null; // deleted/ghost authors remain representable
    body: string;
    createdAt: string;
    updatedAt: string;
  }>;                            // ascending numeric databaseId
  parentNodeId: string | null;
  childNodeIds: string[];       // canonical order, not queue policy
  openBlockers: Array<{
    nodeId: string;
    repository: string;
    number: number;
    url: string;
    title: string;
    state: "open";
  }>;
  role: "anchor" | "work_item";
  eligibility:
    | { status: "eligible"; reasons: [] }
    | { status: "excluded"; reasons: ExclusionReason[] };
};

type WorkScopeSnapshot = {
  schemaVersion: 1;
  repository: "hadrysm/foldwise-voice";
  scopeKind: "specific_spec" | "specific_issue" | "all_ready_for_agent";
  anchorNodeId: string | null;
  memberNodeIds: string[];      // complete frozen membership
  executableNodeIds: string[];  // the only AFK implementation allow-list
  issues: IssueSnapshot[];
  snapshotId: `sha256:${string}`;
};
```

Representative Specific SPEC JSON:

```json
{
  "schemaVersion": 1,
  "repository": "hadrysm/foldwise-voice",
  "scopeKind": "specific_spec",
  "anchorNodeId": "I_SPEC",
  "memberNodeIds": ["I_SPEC", "I_401", "I_402", "I_403"],
  "executableNodeIds": ["I_401"],
  "issues": [
    {
      "nodeId": "I_SPEC",
      "number": 400,
      "role": "anchor",
      "state": "open",
      "labels": ["ready-for-agent", "spec"],
      "comments": [],
      "parentNodeId": null,
      "childNodeIds": ["I_401", "I_402", "I_403"],
      "openBlockers": [],
      "eligibility": {"status": "eligible", "reasons": []}
    },
    {
      "nodeId": "I_401",
      "number": 401,
      "role": "work_item",
      "state": "open",
      "labels": ["ready-for-agent"],
      "comments": [
        {
          "databaseId": 9001,
          "nodeId": "IC_9001",
          "authorLogin": "maintainer",
          "body": "Acceptance clarification from review.",
          "createdAt": "2026-07-30T10:00:00Z",
          "updatedAt": "2026-07-30T10:00:00Z"
        }
      ],
      "parentNodeId": "I_SPEC",
      "childNodeIds": [],
      "openBlockers": [],
      "eligibility": {"status": "eligible", "reasons": []}
    },
    {
      "nodeId": "I_402",
      "number": 402,
      "role": "work_item",
      "state": "open",
      "labels": [],
      "comments": [],
      "parentNodeId": "I_SPEC",
      "childNodeIds": [],
      "openBlockers": [],
      "eligibility": {
        "status": "excluded",
        "reasons": ["unreleased"]
      }
    },
    {
      "nodeId": "I_403",
      "number": 403,
      "role": "work_item",
      "state": "open",
      "labels": ["ready-for-agent"],
      "comments": [],
      "parentNodeId": "I_SPEC",
      "childNodeIds": [],
      "openBlockers": [
        {
          "nodeId": "I_399",
          "repository": "hadrysm/foldwise-voice",
          "number": 399,
          "url": "https://github.com/hadrysm/foldwise-voice/issues/399",
          "title": "Blocking work",
          "state": "open"
        }
      ],
      "eligibility": {
        "status": "excluded",
        "reasons": ["blocked"]
      }
    }
  ],
  "snapshotId": "sha256:<canonical-payload-digest>"
}
```

The abbreviated example omits the required title/body/URL/database ID fields
only for readability.

For deterministic bytes, construct keys in the schema's fixed order; sort
labels lexically, comments by numeric `databaseId`, and repository/issue
references by `(repository, number, nodeId)`; serialize without
locale-dependent formatting; and hash that canonical JSON, including every
comment identity, author, body, and timestamp. Exclude observation-only
metadata such as `capturedAt` from the canonical payload so the same GitHub
state produces the same digest. This canonical order is a serialization rule,
not the run's work order.

## Eligibility and failure behavior

| State | Explicit Specific issue/SPEC anchor | SPEC descendant |
| --- | --- | --- |
| Malformed input | Reject before any API request. | Not applicable. |
| Cross-repository URL | Reject before any API request. | Classify `cross_repository_descendant`; fail the complete scope load. |
| Pull request | Reject after canonical REST read (`pull_request` is present). | Fail the scope load. |
| Missing or inaccessible | `404`: report “not found or inaccessible”; do not claim which. `410`: report gone. | Fail the scope load; never dispatch from a partial tree. |
| Closed | Reject. | Keep visible; exclude with `closed`. |
| Missing `ready-for-agent` | Reject as unreleased. | Keep visible; exclude with `unreleased`. |
| Has `ready-for-human` | Reject, even if it also has `ready-for-agent`. | Keep visible; exclude with `ready_for_human`. |
| Missing `spec` | Reject only for Specific SPEC. | No descendant `spec` requirement. |
| One or more open blockers | Reject as blocked and show blocker identities. | Keep visible; exclude with `blocked` and show blocker identities. |
| Only closed blockers | Not blocked. | Not blocked. |
| GitHub `401`/`403`/`429`/`5xx`, including any comment page | Fail without dispatch; surface authentication, permission, rate-limit, or service error. | Same; never treat an API failure as an empty issue, child, comment, or blocker list. |
| Changed after capture | Must pass a fresh pre-dispatch identity, ancestry, state, label, body, comment, and blocker check. | Same; never dispatch stale or newly ineligible data. |

GitHub intentionally uses `404 Not Found` for some inaccessible private
resources, so an API client cannot reliably distinguish missing from
unauthorized. ([Troubleshooting the REST
API](https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api?apiVersion=2026-03-10))
The user-facing error must preserve that ambiguity.

When more than one exclusion applies, retain every reason in a fixed precedence
order (`closed`, `ready_for_human`, `unreleased`, `blocked`) for deterministic
handoff reporting. No exclusion removes the node from `memberNodeIds`; it only
removes it from `executableNodeIds`.

## Staleness and consistency

GitHub does not expose these separate REST reads as one transactional snapshot.
That conclusion is an inference from the endpoint model, not a documented
atomicity guarantee. A safe loader should:

1. Read the anchor, every sub-issue page, every issue representation, every
   comment page, and every blocker page.
2. Canonicalize the result.
3. Re-read all issue, relationship, comment, and blocker representations and
   require the same canonical result before dispatch, retrying a bounded number
   of times.
4. If the tree does not converge, fail as “Work scope changed while loading.”

Do not use the anchor's `updated_at` as the tree version. In the live map probe,
the parent remained updated at `2026-07-30T18:41:27Z`, while all nine native
children were created from `18:42:03Z` onward. Adding sub-issue relationships
did not advance the parent's timestamp.

ETags can optimize revalidation: GitHub says most endpoints return `etag`, and
an authenticated conditional `GET` with `If-None-Match` returns `304` when the
representation is unchanged.
([REST best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api))
The ETag must be retained per exact issue, sub-issue page, comment page, and
dependency page; one issue timestamp or one root ETag cannot represent the
whole tree.

Immediately before each dispatch, re-read the current work item, its
paginated `/comments`, its `/dependencies/blocked_by`, and its `/parent` chain
back to the frozen SPEC anchor. The parent endpoint is a first-class REST
endpoint.
([Get parent issue](https://docs.github.com/en/rest/issues/sub-issues?apiVersion=2026-03-10#get-parent-issue))
The minimum invariant is:

- identity, repository, and frozen ancestry still match;
- the issue remains open, released, not `ready-for-human`, and unblocked; and
- the prompt uses a freshly acknowledged body and complete comment set rather
  than silently using stale acceptance context.

If any check changes, do not dispatch it. Whether the run refreshes, skips, or
stops is the lifecycle decision left to [Settle batch ordering, stop
conditions, and handoff
semantics](https://github.com/hadrysm/foldwise-voice/issues/394). Newly added
descendants and issues released after the snapshot never join the current
run's allow-list; they require a new snapshot. That is the key no-widening
property.

## Prompt boundary and ADR consequences

[ADR-0010](../adr/0010-sandcastle-workflows-are-folders-driven-by-injected-dispatch.md)
puts control flow in each workflow and gives it a narrow injected `dispatch`.
Universal Work scope should therefore be runner input passed into every
workflow, while the runner owns resolution, normalization, and the frozen
allow-list. A workflow chooses only among the allow-listed items handed to it;
an agent receives:

- `snapshotId`, `scopeKind`, and the immutable allowed issue identities;
- the controlling SPEC identity, full body, and comments, when applicable;
- exactly one `currentWorkItem` identity, full body, and comments; and
- an explicit rule that it may implement/review only `currentWorkItem`, may not
  search for substitute work, and must report staleness rather than broaden
  scope.

Implementer and reviewer must receive the same `snapshotId` and current item.
No eligible item means no dispatch. Excluded nodes and their reasons remain in
the runner's snapshot for narration and handoff rather than being offered as
work.

[ADR-0001](../adr/0001-sandcastle-in-place-not-sandboxed.md) is the hard limit
on what “prevents widening” can mean. Agents run on the host and inherit the
maintainer's `gh` login, so a prompt snapshot is not an authorization boundary:
an agent can still call GitHub. Within this map, enforcement is structural and
auditable rather than a security sandbox: the runner selects one allowed item,
the prompt contains frozen scope data, and the workflow/reviewer rejects work
or mutations outside that item. Preventing the process from reading or writing
other GitHub issues would require separately scoped credentials or isolation,
which is outside the settled destination and contrary to the current host-run
model.
