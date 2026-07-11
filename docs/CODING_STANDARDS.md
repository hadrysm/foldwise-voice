# Coding Standards

Judgment-level standards for Swift code in this repository. This document covers the
decisions a linter cannot make: what to test, where to put a seam, when a design is
too shallow. **Formatting and idiom mechanics are owned by `.swiftformat` and
`.swiftlint.yml`** — do not restate or second-guess them here; run
`swiftformat .` and `swiftlint lint --strict` and let the tools decide.

## Style

Prefer clarity over brevity. Explicit code beats clever code.

- **Value types for data, classes for orchestration.** Domain data is a `struct`
  (`Mode` in `Config.swift`) or an exhaustive `enum` (`PipelineState` in
  `Pipeline.swift`). Reserve `final class` for objects that own mutable state or
  side effects (`Pipeline`, `HotkeyListener`).
- **No force-unwrap, `as!`, or `try!` where failure is reachable at runtime.**
  Sanctioned exceptions, all of which are unreachable-by-construction: unwrapping a
  compile-time-constant literal (`URL(string:)!` on a hardcoded URL in
  `UpdateChecker`), an invariant guaranteed by an API contract (the C callback's
  `userInfo!` in `HotkeyListener`), and app-lifecycle IUO properties confined to
  `AppMain`. Anything else: recoverable failures `throw` (`KeyMap.parse`,
  `Config.load(from:)`); non-critical paths degrade gracefully with `guard let` /
  `try?` plus a log line explaining what was skipped — see `OllamaClient` falling
  back to the raw transcript when Ollama is unreachable.
- **Fail early in initializers.** If a type can't do its job with the arguments given,
  its `init` throws (`HotkeyListener.init` parses hotkey strings up front) rather than
  deferring the crash to first use.
- **Avoid nested ternaries** — use `switch` or `if`/`else` chains.
- **Comments explain *why*, not *what*.** Don't narrate code the reader can see;
  do record a constraint the code can't show (e.g. the note in
  `ConfigRoundTripTests.swift` on why the serializer is hand-rolled).
- No commented-out code and no `TODO` comments in committed code — file an issue
  instead. (SwiftLint's `todo` rule is deliberately disabled so `--strict` CI never
  hard-fails on one; this rule is enforced by review.)

## Testing

Use **XCTest**. It is the suite's existing framework; do not introduce Swift Testing
(`@Test` / `#expect`) — a split suite costs more than the newer syntax is worth here.

### Core principle

Test **behavior through the public interface**, never internals. A test passes data
into a public function or type and asserts on what comes back or what observably
changed. (`@testable import FoldWiseVoiceKit` is the norm here — the Kit's types are
`internal` because it is an app module, not a library — so "public interface" means
a type's non-`private` API.) If a test needs a `private` member or knowledge of
*how* the result was computed, the test — or the interface — is wrong.

Name tests `test<What><Condition>` so the failure message reads as a sentence:
`testLoadOrCreateWritesDefaultsWhenFileMissing`, `testModeOrderSurvivesNonAlphabetically`.
One logical assertion per test.

**Good** — exercises `Config`'s public API end to end and asserts on the outcome
(`ConfigRoundTripTests.swift`):

```swift
private func roundTrip(_ json: String) throws -> Config {
    let url = try write(json)
    let config = try Config.load(from: url)
    try config.save()
    return try Config.load(from: url)
}

func testModeOrderSurvivesNonAlphabetically() throws {
    let reloaded = try roundTrip(fixture)
    XCTAssertEqual(reloaded.modeOrder, ["Zebra", "Alpha", "Middle"])
}
```

**Bad** — asserts on the serializer's private intermediate state instead of the
observable result:

```swift
func testSaveBuildsOrderedKeyList() throws {
    let config = try Config.load(from: url)
    // Reaches into internals; breaks on any refactor even when behavior is intact.
    XCTAssertEqual(config.orderedKeysForSerialization(), ["Zebra", "Alpha", "Middle"])
}
```

### Test isolation

Tests that touch the filesystem own a throwaway directory and clean it up
(`ConfigBehaviorTests.swift`):

```swift
private let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("foldwise-tests-\(UUID().uuidString)")

override func setUpWithError() throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: dir)
}
```

Never share state between tests; never depend on test order. Test methods that call
throwing code are themselves `throws` — propagate, don't `try!` or swallow.

### Mocking

Mock **only at system boundaries** — the microphone, the CGEvent tap, the Ollama HTTP
API, GitHub releases. Everything inside the boundary is tested for real: the current
suite has no test doubles at all because it targets pure logic (`Config`
serialization, `KeyMap` parsing, `UpdateChecker` version comparison) with real files
in temp directories.

When a boundary must be faked, define a small `protocol` at that boundary, inject the
fake through the initializer, and keep the fake dumb — canned responses, no logic.
Never monkeypatch, swizzle, or mock a type you own just to avoid wiring it up.

### TDD and vertical slices

Work RGR (Red → Green → Refactor): write a failing test that pins the new behavior,
make it pass with the smallest change, then clean up with the tests green.

Slice work **vertically**: each iteration delivers one thin end-to-end behavior
(hotkey string → parsed `KeySpec`; config file → loaded `Config`) with its test,
rather than a horizontal layer ("all the models, no callers") that nothing exercises.
If new behavior can't be reached from a public interface, that is a design smell —
fix the interface, don't reach around it.

### Binding coverage policy

Run `./scripts/coverage.sh` before review. It is the same executable policy CI
uses and runs XCTest once with SwiftPM/LLVM coverage. The permanent gates are:

- every included production Swift file has at least 90% line coverage;
- the included core aggregate has at least 90% line coverage and may not fall
  below the higher accepted floor recorded in `coverage-policy.json`;
- changed executable lines in included production files have at least 90%
  coverage relative to the target branch; and
- overall `FoldWiseVoiceKit` production coverage, including exempt files, may
  not fall below its accepted floor.

Production files are included by default. An exemption must name one complete
file in `coverage-policy.json`, explain why it is a declarative or thin system
boundary (or contains no LLVM-instrumentable production lines), and receive
explicit review. Only a zero-instrumentation exemption may explicitly permit a
missing LLVM report entry. Extract meaningful decisions into an included
collaborator before exempting a mixed file. There are no line-level waivers or
suppression comments, and coverage is never uploaded to a hosted service.

Tests must be deterministic: use unique temporary storage and explicit signals,
expectations, continuations, or injected scheduling instead of shared state,
real services, or fixed sleeps where a deterministic signal is practical. CI
does not retry tests. A flaky test is fixed immediately or the introducing
change is reverted; it is not retried, quarantined, or silently excluded.

## Interface Design

### Deep modules

A module should be **deep**: a small public surface hiding significant complexity.
`Config` is the house example — a handful of members (`load(from:)`,
`loadOrCreate(at:)`, `save()`, `mode`, `setActiveMode(_:)`) conceal a hand-rolled
JSON serializer, mode-order preservation, validation, and fallback rules. Callers
get "load my config" without knowing any of that exists.

When adding functionality, prefer deepening an existing module over widening its API
or scattering helpers. Red flags for a *shallow* module: a type whose methods map
one-to-one onto its fields, a "manager" that just forwards calls, or an abstraction
with exactly one caller that saves no complexity.

Define errors out of existence where possible: `Config.loadOrCreate(at:)` returns a
usable config whether or not the file exists, instead of making every caller handle
a "missing file" error.

### Design for testability

- **Inject dependencies through the initializer.** Collaborators and callbacks arrive
  as `init` parameters (`HotkeyListener` takes `onPress`/`onRelease`/`onToggle`
  closures; `Pipeline` takes its `Config`). No singletons reached from deep inside
  logic, no service locators.
- **Closures are lightweight seams.** For a single-callback boundary, an injected
  closure (`onState: ((PipelineState) -> Void)?`) beats a one-method protocol.
  Reach for a protocol when a boundary has several operations or needs a stateful fake.
- **Separate deciding from doing.** Keep pure logic (parsing, version comparison,
  state transitions) in functions that take values and return values — those test
  trivially. Push I/O (files, network, CGEvent taps) to thin shells at the edge.
  `KeyMap` computes; `HotkeyListener` touches the event tap.
- **Parameterize paths and endpoints.** Anything that reads the environment (config
  path, base URL) takes it as an argument with a production default, so tests can
  point it at a temp directory.
