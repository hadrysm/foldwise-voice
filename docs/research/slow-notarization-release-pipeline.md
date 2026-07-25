# Slow-notarization release pipeline

Research answer for
[Decide how the release pipeline survives slow notarization](https://github.com/hadrysm/foldwise-voice/issues/298),
audited at repository commit `751554a` on 2026-07-25. External facts below
come only from Apple, GitHub, release-please, and first-party action sources.

## Decision

Keep notarization in the release workflow, but split it into two durable stages:

1. **Build and submit once.** Build and Developer ID-sign the DMG, record its
   SHA-256, persist that exact DMG as a recovery-only Actions artifact, submit
   it without an unbounded wait, capture the submission UUID in machine-readable
   output, and persist a second metadata artifact containing the UUID, tag,
   filename, checksum, run ID, and commit SHA.
2. **Finalize, repeatably.** Download the persisted DMG and metadata, verify the
   checksum, wait on the existing UUID, fetch its log, and only on `Accepted`
   staple, validate, run the existing `codesign`/`spctl` checks, attach the DMG
   to the GitHub release, and publish the release.

The first real FoldWise submission,
`0d749be0-3ead-4e6e-a71a-e4021b184e79`, took about 94 minutes and was accepted
([recorded resolution](https://github.com/hadrysm/foldwise-voice/issues/285#issuecomment-5079253569)).
Apple says processing typically takes less than an hour, while its own scripted
example waits up to two hours. A 94-minute result is therefore slow but still
within Apple's illustrated operating envelope; it does not justify resubmitting
or removing notarization from the release
([custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[two-hour Xcode script](https://developer.apple.com/documentation/security/customizing-the-xcode-archive-process)).

Use a **3-hour notary wait** and an explicit **4-hour finalizer-job timeout**.
Three hours gives the observed run 86 minutes of headroom and is deliberately
longer than Apple's two-hour example. Four hours leaves time for artifact
download, stapling, verification, and publication. GitHub's default job timeout
is 360 minutes and a GitHub-hosted job cannot exceed six hours, so neither limit
should be the pipeline's accidental control plane
([workflow `timeout-minutes`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idtimeout-minutes),
[hosted-job limit](https://docs.github.com/en/actions/concepts/security/github_token#about-the-github_token-secret)).

## Why the current workflow is not recoverable

The current job builds the DMG, runs `notarytool submit ... --wait`, staples,
verifies, and uploads on one ephemeral macOS runner
([workflow lines 37–113](../../.github/workflows/release-please.yml#L37)).
It correctly keeps the DMG off the release until after stapling and verification,
but it has no explicit wait timeout, no durable copy of the submitted DMG, and
no durable submission record. If the job is canceled or reaches the hosted-job
limit, Apple may still be processing while the only submitted bytes disappear
with the runner.

Xcode 26.2's bundled `notarytool(1)` says a timed-out `submit --wait` or
`notarytool wait` exits while the notary service continues processing. It also
defines `info`, `wait`, `history`, and `log` around the UUID returned by
`submit`. Apple distributes these developer man pages with Xcode and documents
the equivalent UUID/status/history/log workflow
([reading Xcode man pages](https://developer.apple.com/documentation/os/reading-unix-manual-pages),
[TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool),
[custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
Consequently, a client timeout is a **recoverable in-progress state**, not a
failed notarization.

## Concrete policy

| Event | Policy |
| --- | --- |
| Build/sign/preflight failure | Fail before submission. Do not publish. |
| Submit returns a UUID | Persist it immediately. Every later operation uses that UUID; never submit the same release again automatically. |
| Submit exits without a captured UUID | Do not blindly retry. Reconcile `notarytool history` by a unique upload filename containing tag + workflow run ID. Resume if exactly one match exists; require operator review for zero or multiple matches. Apple exposes team submission history specifically for this recovery path ([TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool#Get-history)). |
| `In Progress` at 3 hours | End the finalizer as recoverable and leave the release unpublished. Apple continues processing; re-run only the failed finalizer later against the same UUID and persisted DMG. |
| Transient `wait` / `info` transport failure | Retry the read-only operation against the same UUID up to three times with bounded backoff (for example 30 seconds, 2 minutes, 5 minutes), then use the same recovery path. Never route this retry back through `submit`. |
| `Invalid` or `Rejected` | Fetch and retain the notary log, fail terminally, and do not staple or publish. Apple says to fix reported problems and submit the corrected software again, and to inspect the log even after success ([common issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues), [TN3147 log guidance](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool#Fetch-the-notary-log)). |
| `Accepted` | Fetch the log, staple the persisted DMG, validate the ticket, run the existing signature and Gatekeeper checks, then publish. |
| Stapling transport/service failure | Retry stapling up to three times with bounded backoff; first treat a passing `stapler validate` as success in case the prior response was lost. A persistent failure leaves the release unpublished. |
| Release upload response is ambiguous | Query the existing asset. If its GitHub-reported SHA-256 digest equals the verified local final DMG, treat it as success; if the name exists with a different digest, hard-fail. Never use an unconditional clobber ([release asset digest](https://docs.github.com/en/rest/releases/releases#get-a-release)). |

Automatic retries are intentionally asymmetric: status checks, waits, log
downloads, and stapling are safe to repeat; **submission is not**. Apple tells
clients to save the returned submission ID for later status checks and exposes
history for previous submissions
([custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[TN3147](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)).

## Durable recovery data

Upload the signed, unstapled DMG and a manifest containing its SHA-256 **before**
calling `submit`. Upload the submission response/UUID as a separate artifact
after submission. Separate artifacts avoid attempting to mutate an existing
artifact: current `upload-artifact` artifacts are immutable. Use a unique name,
`if-no-files-found: error`, no compression for the already-compressed DMG, and
30-day retention
([official `upload-artifact` behavior](https://github.com/actions/upload-artifact#usage),
[workflow artifacts](https://docs.github.com/en/actions/concepts/workflows-and-actions/workflow-artifacts)).

The small interval between service acceptance and metadata upload remains
recoverable because the pre-submit manifest already contains the unique
submission filename and exact DMG. `notarytool history` can recover the UUID.
Do not include the API private key or any other credential in either artifact.

GitHub allows rerunning only failed jobs for up to 30 days, using the same commit
SHA and ref. Therefore the normal recovery operation is **Re-run failed jobs**,
which repeats finalization without repeating the already-successful submit job
([re-running jobs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs)).
A manual `workflow_dispatch` finalizer taking a source run ID is a useful second
entry point, because Actions artifacts can be downloaded by run ID
([manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow),
[artifact download](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)).

## Stapling and publication gate

Apple generates a ticket for the submitted top-level DMG and nested code.
Stapling embeds that ticket so Gatekeeper can validate offline; it belongs after
acceptance and before distribution
([custom workflow: tickets and stapling](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow#Staple-the-ticket-to-your-distribution),
[packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)).
Preserving and checksum-verifying the exact submitted DMG is the conservative
recovery contract; rebuilding is not resumption.

The public release should be a release-please **draft** until the final DMG
passes:

- accepted notary status and retained notary log;
- `xcrun stapler staple` and `xcrun stapler validate`;
- the existing strict `codesign` checks for app and DMG;
- the existing `spctl` checks for app and DMG;
- a final checksum captured for publication.

Draft releases are unpublished. Because GitHub normally delays tag creation for
a draft, set both release-please manifest options `"draft": true` and
`"force-tag-creation": true`; release-please documents the latter specifically
for draft releases. This preserves the current checkout-by-tag behavior and its
release-history bookkeeping
([GitHub draft releases](https://docs.github.com/en/rest/releases/releases#create-a-release),
[release-please draft/tag guidance](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md#release-configuration)).
The action already exposes `release_created`, `tag_name`, `sha`, and release
URLs, and officially supports attaching files with `gh release upload`
([release-please-action outputs and attachment](https://github.com/googleapis/release-please-action/blob/v4.4.1/README.md#outputs)).
Publish the draft only after the verified asset upload is confirmed.

## Concurrency and cancellation safety

Use one repository-wide concurrency group shared by the normal release workflow
and any recovery finalizer, with `queue: max` and no
`cancel-in-progress: true`. GitHub otherwise permits concurrent runs, and its
default single pending slot replaces older pending runs; `queue: max` retains
the queue. A release run must never cancel an older finalizer because canceling
the runner does not cancel Apple's already-created submission
([GitHub concurrency controls](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
[workflow cancellation](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-cancellation)).

Keep publication idempotent per tag: one submission record, one expected final
asset name, checksum comparison on an existing asset, and no clobber. Scope
permissions by job where practical: release-please needs pull-request and
contents writes, build/submit only needs contents read, and only the finalizer
needs release-write access. The current workflow grants both write permissions
to every job at workflow scope
([current workflow lines 7–9](../../.github/workflows/release-please.yml#L7)).

The build, submit, and finalize jobs should remain in the same workflow rather
than depending on an `on: release` workflow: resources created with the default
`GITHUB_TOKEN` generally do not trigger another workflow. A manual
`workflow_dispatch` recovery entry point remains allowed
([release-please-action token behavior](https://github.com/googleapis/release-please-action/blob/v4.4.1/README.md#other-actions-on-release-please-prs),
[GitHub token event rules](https://docs.github.com/en/actions/concepts/security/github_token#when-github_token-triggers-workflow-runs)).
