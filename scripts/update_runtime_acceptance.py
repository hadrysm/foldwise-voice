"""Run FoldWise's isolated Sparkle replacement-and-relaunch acceptance."""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

if __package__:
    from scripts.build_swift_app import build_binary, build_bundle, render_assets
else:
    from build_swift_app import build_binary, build_bundle, render_assets

PRODUCTION_BUNDLE_IDENTIFIER = "com.foldwise.voice.native"
PRODUCTION_TEAM_IDENTIFIER = "6849P798YW"
SOURCE_VERSION = "9000"
TARGET_VERSION = "9001"
TEST_SPARKLE_PRIVATE_KEY = "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA="
TEST_SPARKLE_PUBLIC_KEY = "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ="
REPOSITORY = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class BundleIdentity:
    path: str
    bundle_identifier: str
    team_identifier: str
    version: str


@dataclass(frozen=True)
class RuntimeEvidence:
    source: BundleIdentity
    target: BundleIdentity
    installed_path: str
    deferred_process_alive: bool
    deferred_installed_version: str
    relaunched_installed_version: str
    events: list[dict[str, object]]

    def violations(self) -> list[str]:
        violations: list[str] = []
        self._check_identity(violations)
        self._check_deferred_state(violations)
        self._check_relaunch(violations)
        return violations

    def _check_identity(self, violations: list[str]) -> None:
        if self.source.bundle_identifier != PRODUCTION_BUNDLE_IDENTIFIER:
            violations.append(
                "source bundle identifier changed: expected "
                f"{PRODUCTION_BUNDLE_IDENTIFIER}, got {self.source.bundle_identifier}"
            )
        if self.target.bundle_identifier != self.source.bundle_identifier:
            violations.append(
                "target bundle identifier changed: expected "
                f"{self.source.bundle_identifier}, got {self.target.bundle_identifier}"
            )
        if self.source.team_identifier != PRODUCTION_TEAM_IDENTIFIER:
            violations.append(
                "source Team identifier changed: expected "
                f"{PRODUCTION_TEAM_IDENTIFIER}, got {self.source.team_identifier}"
            )
        if self.target.team_identifier != self.source.team_identifier:
            violations.append(
                "target Team identifier changed: expected "
                f"{self.source.team_identifier}, got {self.target.team_identifier}"
            )
        if self._numeric_version(self.target.version) <= self._numeric_version(
            self.source.version
        ):
            violations.append(
                "target version is not newer than source: "
                f"{self.source.version} -> {self.target.version}"
            )

    def _check_deferred_state(self, violations: list[str]) -> None:
        if not self.deferred_process_alive:
            violations.append("source process terminated while Dictation was active")
        if self.deferred_installed_version != self.source.version:
            violations.append(
                "installed version changed before Dictation finished: expected "
                f"{self.source.version}, got {self.deferred_installed_version}"
            )

    @staticmethod
    def _numeric_version(version: str) -> tuple[int, ...]:
        try:
            return tuple(int(component) for component in version.split("."))
        except ValueError:
            return (-1,)

    def _check_relaunch(self, violations: list[str]) -> None:
        if self.relaunched_installed_version != self.target.version:
            violations.append(
                "relaunch used unexpected installed version: expected "
                f"{self.target.version}, got {self.relaunched_installed_version}"
            )

        expected_order = [
            "source-ready",
            "dictation-started",
            "update-prepared",
            "termination-deferred",
            "dictation-finished",
            "target-started",
            "target-ready",
        ]
        actual_order = [str(event.get("event")) for event in self.events]
        if actual_order != expected_order:
            violations.append(
                f"runtime events were out of order: expected {expected_order}, got {actual_order}"
            )
            return

        completion = self.events[4]
        completion_version = completion.get("installedVersionAtCompletion")
        if completion_version != self.source.version:
            violations.append(
                "installed version changed before Dictation finished: expected "
                f"{self.source.version}, got {completion_version}"
            )

        readiness = self.events[-1]
        if readiness.get("version") != self.target.version:
            violations.append(
                "relaunch readiness reported unexpected version: expected "
                f"{self.target.version}, got {readiness.get('version')}"
            )
        if readiness.get("bundlePath") != self.installed_path:
            violations.append(
                "relaunch did not use the installed bundle path: expected "
                f"{self.installed_path}, got {readiness.get('bundlePath')}"
            )
        if readiness.get("badgeVisible") is not True:
            violations.append(
                "relaunch readiness was emitted before the Badge was visible"
            )
        if readiness.get("hotkeyHealth") != "global":
            violations.append(
                "relaunch readiness was emitted before global hotkey registration"
            )


class AcceptanceFailure(RuntimeError):
    pass


class QuietRequestHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format_string: str, *args: object) -> None:
        return


class RuntimeAcceptanceHarness:
    def __init__(self, artifacts: Path, timeout: float) -> None:
        self.artifacts = artifacts.resolve()
        self.timeout = timeout
        temporary_parent = os.environ.get("RUNNER_TEMP")
        self.workspace = Path(
            tempfile.mkdtemp(
                prefix="foldwise-update-acceptance-",
                dir=temporary_parent,
            )
        )
        self.control = self.workspace / "control"
        self.feed = self.workspace / "feed"
        self.home = self.workspace / "home"
        self.server: http.server.ThreadingHTTPServer | None = None
        self.server_thread: threading.Thread | None = None
        self.source_process: subprocess.Popen[bytes] | None = None
        self.source_log: Any = None
        self.diagnostics: dict[str, Any] = {
            "phases": [],
            "workspace": str(self.workspace),
        }

    def run(self) -> RuntimeEvidence:
        self._prepare_directories()
        try:
            self._require_signing_identity()
            feed_url = self._start_server()
            installed, target = self._build_fixture(feed_url)
            source_identity = self._bundle_identity(installed)
            target_identity = self._bundle_identity(target)
            self.diagnostics["sourceIdentity"] = source_identity.__dict__
            self.diagnostics["targetIdentity"] = target_identity.__dict__
            identity_violations = RuntimeEvidence(
                source=source_identity,
                target=target_identity,
                installed_path=str(installed),
                deferred_process_alive=True,
                deferred_installed_version=source_identity.version,
                relaunched_installed_version=target_identity.version,
                events=self._complete_event_placeholders(installed),
            ).violations()
            if identity_violations:
                raise AcceptanceFailure("; ".join(identity_violations))

            self._prepare_signed_appcast(target)
            self._launch_source(installed)
            self._wait_for_event("termination-deferred", require_source_alive=True)
            deferred_process_alive = self.source_process is not None \
                and self.source_process.poll() is None
            deferred_installed_version = self._bundle_version(installed)
            self._phase(
                "termination-deferred-observed",
                processAlive=deferred_process_alive,
                installedVersion=deferred_installed_version,
            )

            self._signal("finish-dictation")
            self._wait_for_event(
                "dictation-finished",
                require_source_alive=True,
                expected_installed=(installed, source_identity.version),
            )
            target_ready = self._wait_for_event("target-ready")
            relaunched_installed_version = self._bundle_version(installed)
            events = self._events()
            evidence = RuntimeEvidence(
                source=source_identity,
                target=target_identity,
                installed_path=str(installed),
                deferred_process_alive=deferred_process_alive,
                deferred_installed_version=deferred_installed_version,
                relaunched_installed_version=relaunched_installed_version,
                events=events,
            )
            violations = evidence.violations()
            self.diagnostics["events"] = events
            self.diagnostics["violations"] = violations
            if violations:
                raise AcceptanceFailure("; ".join(violations))

            target_pid = self._integer(target_ready.get("pid"), "target-ready pid")
            if not self._process_is_alive(target_pid):
                raise AcceptanceFailure(
                    f"relaunched target process {target_pid} was not alive at readiness"
                )
            self._signal("terminate-target")
            self._wait_for_process_exit(target_pid)
            self._phase("complete", targetPID=target_pid)
            return evidence
        except Exception:
            self._capture_failure_state()
            raise
        finally:
            self._write_diagnostics()
            self._clean_up()

    def _prepare_directories(self) -> None:
        self.artifacts.mkdir(parents=True, exist_ok=True)
        self.control.mkdir(parents=True)
        self.feed.mkdir(parents=True)
        self.home.mkdir(parents=True)

    def _require_signing_identity(self) -> None:
        identity = os.environ.get("CODESIGN_IDENTITY")
        if not identity:
            raise AcceptanceFailure(
                "CODESIGN_IDENTITY is required for the stable Developer ID runtime test"
            )
        self.diagnostics["codesignIdentity"] = identity

    def _start_server(self) -> str:
        handler = functools.partial(QuietRequestHandler, directory=str(self.feed))
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.server_thread = threading.Thread(
            target=self.server.serve_forever,
            name="foldwise-update-origin",
            daemon=True,
        )
        self.server_thread.start()
        port = self.server.server_address[1]
        feed_url = f"http://localhost:{port}/"
        self.diagnostics["feedURL"] = feed_url
        self._phase("local-update-origin-started", feedURL=feed_url)
        return feed_url

    def _build_fixture(self, feed_url: str) -> tuple[Path, Path]:
        binary = build_binary(("FOLDWISE_UPDATE_ACCEPTANCE",))
        icon, _ = render_assets()
        launch_environment = {
            "CFFIXED_USER_HOME": str(self.home),
            "FOLDWISE_UPDATE_ACCEPTANCE_DIRECTORY": str(self.control),
        }
        source = build_bundle(
            binary,
            self.workspace / "source",
            "FoldWise Voice",
            icon,
            share_repo_config=False,
            version=SOURCE_VERSION,
            update_feed_url=f"{feed_url}appcast.xml",
            update_public_ed_key=TEST_SPARKLE_PUBLIC_KEY,
            launch_environment=launch_environment,
            extra_info={
                "FoldWiseUpdateAcceptanceRole": "source",
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
            },
            timestamp_signatures=False,
        )
        target = build_bundle(
            binary,
            self.workspace / "target",
            "FoldWise Voice",
            icon,
            share_repo_config=False,
            version=TARGET_VERSION,
            update_feed_url=f"{feed_url}appcast.xml",
            update_public_ed_key=TEST_SPARKLE_PUBLIC_KEY,
            launch_environment=launch_environment,
            extra_info={
                "FoldWiseUpdateAcceptanceRole": "target",
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
            },
            timestamp_signatures=False,
        )
        installed = self.workspace / "Applications" / "FoldWise Voice.app"
        installed.parent.mkdir(parents=True)
        shutil.copytree(source, installed, symlinks=True)
        self._run(
            ["/usr/bin/xattr", "-dr", "com.apple.quarantine", str(installed)],
            allow_failure=True,
        )
        self._phase(
            "bundles-built",
            sourceVersion=SOURCE_VERSION,
            targetVersion=TARGET_VERSION,
            installedPath=str(installed),
        )
        return installed, target

    def _prepare_signed_appcast(self, target: Path) -> None:
        archive = self.feed / f"FoldWise-Voice-{TARGET_VERSION}.zip"
        self._run([
            "/usr/bin/ditto",
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            str(target),
            str(archive),
        ])
        private_key = self.workspace / "sparkle-test-private-key"
        private_key.write_text(f"{TEST_SPARKLE_PRIVATE_KEY}\n", encoding="utf-8")
        private_key.chmod(0o600)
        generate_appcast = (
            REPOSITORY
            / ".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
        )
        feed_url = str(self.diagnostics["feedURL"])
        try:
            self._run([
                str(generate_appcast),
                "--ed-key-file",
                str(private_key),
                "--download-url-prefix",
                feed_url,
                "--maximum-versions",
                "0",
                "--maximum-deltas",
                "0",
                str(self.feed),
            ])
        finally:
            private_key.unlink(missing_ok=True)
        appcast = self.feed / "appcast.xml"
        if not appcast.exists():
            raise AcceptanceFailure("Sparkle did not generate appcast.xml")
        shutil.copy2(appcast, self.artifacts / "appcast.xml")
        self._phase(
            "signed-appcast-ready",
            archive=archive.name,
            appcast=str(appcast),
        )

    def _launch_source(self, installed: Path) -> None:
        executable = installed / "Contents/MacOS/FoldWiseVoice"
        log_path = self.artifacts / "source-process.log"
        self.source_log = log_path.open("wb")
        environment = dict(os.environ)
        environment.update({
            "CFFIXED_USER_HOME": str(self.home),
            "FOLDWISE_UPDATE_ACCEPTANCE_DIRECTORY": str(self.control),
        })
        self.source_process = subprocess.Popen(
            [str(executable)],
            cwd=installed.parent,
            env=environment,
            stdout=self.source_log,
            stderr=subprocess.STDOUT,
        )
        self._phase("source-launched", pid=self.source_process.pid)

    def _wait_for_event(
        self,
        name: str,
        *,
        require_source_alive: bool = False,
        expected_installed: tuple[Path, str] | None = None,
    ) -> dict[str, object]:
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            failure = self.control / "application-failure.json"
            if failure.exists():
                raise AcceptanceFailure(failure.read_text(encoding="utf-8"))
            for event in self._events():
                if event.get("event") == name:
                    return event
            if require_source_alive and self.source_process is not None:
                status = self.source_process.poll()
                if status is not None:
                    raise AcceptanceFailure(
                        f"source process exited with status {status} before {name}"
                    )
            if expected_installed is not None:
                installed, expected_version = expected_installed
                actual_version = self._bundle_version(installed)
                if actual_version != expected_version:
                    raise AcceptanceFailure(
                        "installed version changed before Dictation finished: "
                        f"expected {expected_version}, got {actual_version}"
                    )
            time.sleep(0.1)
        raise AcceptanceFailure(f"timed out waiting for runtime event {name}")

    def _events(self) -> list[dict[str, object]]:
        event_path = self.control / "events.jsonl"
        if not event_path.exists():
            return []
        events: list[dict[str, object]] = []
        for line in event_path.read_text(encoding="utf-8").splitlines():
            if line:
                value = json.loads(line)
                if not isinstance(value, dict):
                    raise AcceptanceFailure("runtime event was not a JSON object")
                events.append(value)
        return events

    def _signal(self, name: str) -> None:
        signal = self.control / name
        signal.write_text("requested\n", encoding="utf-8")
        self._phase("signal-sent", signal=name)

    def _bundle_identity(self, app: Path) -> BundleIdentity:
        result = self._run(
            ["/usr/bin/codesign", "-d", "--verbose=4", str(app)]
        )
        values: dict[str, str] = {}
        for line in result.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
        identifier = values.get("Identifier")
        team = values.get("TeamIdentifier")
        if not identifier or not team:
            raise AcceptanceFailure(
                f"signature diagnostics missing identity for {app}:\n{result}"
            )
        self.diagnostics.setdefault("signatures", {})[str(app)] = result
        return BundleIdentity(
            path=str(app),
            bundle_identifier=identifier,
            team_identifier=team,
            version=self._bundle_version(app),
        )

    def _bundle_version(self, app: Path) -> str:
        info_path = app / "Contents/Info.plist"
        with info_path.open("rb") as file:
            info = plistlib.load(file)
        version = info.get("CFBundleVersion")
        if not isinstance(version, str):
            raise AcceptanceFailure(f"missing CFBundleVersion in {info_path}")
        return version

    def _run(
        self,
        command: list[str],
        *,
        allow_failure: bool = False,
    ) -> str:
        result = subprocess.run(
            command,
            cwd=REPOSITORY,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.diagnostics.setdefault("commands", []).append({
            "command": command,
            "output": result.stdout,
            "status": result.returncode,
        })
        if result.returncode != 0 and not allow_failure:
            raise AcceptanceFailure(
                f"command failed ({result.returncode}): {' '.join(command)}\n"
                f"{result.stdout}"
            )
        return result.stdout

    def _phase(self, name: str, **details: object) -> None:
        self.diagnostics["phases"].append({"name": name, **details})
        self._write_diagnostics()

    def _write_diagnostics(self) -> None:
        self.artifacts.mkdir(parents=True, exist_ok=True)
        path = self.artifacts / "diagnostics.json"
        path.write_text(
            json.dumps(self.diagnostics, indent=2, sort_keys=True),
            encoding="utf-8",
        )

    def _capture_failure_state(self) -> None:
        self.diagnostics["events"] = self._events()
        if self.source_process is not None:
            self.diagnostics["sourceProcess"] = {
                "pid": self.source_process.pid,
                "status": self.source_process.poll(),
            }
        process_snapshot = subprocess.run(
            ["/bin/ps", "-axo", "pid=,ppid=,state=,command="],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        ).stdout
        self.diagnostics["workspaceProcesses"] = [
            line
            for line in process_snapshot.splitlines()
            if str(self.workspace) in line
        ]
        self.diagnostics["targetStarted"] = next(
            (
                event
                for event in self.diagnostics["events"]
                if event.get("event") == "target-started"
            ),
            None,
        )
        failure = self.control / "application-failure.json"
        if failure.exists():
            self.diagnostics["applicationFailure"] = failure.read_text(
                encoding="utf-8"
            )
        installed = self.workspace / "Applications" / "FoldWise Voice.app"
        if installed.exists():
            try:
                self.diagnostics["installedVersion"] = self._bundle_version(installed)
            except Exception as error:
                self.diagnostics["installedVersionError"] = str(error)

    def _clean_up(self) -> None:
        if self.server is not None:
            self.server.shutdown()
            self.server.server_close()
        if self.server_thread is not None:
            self.server_thread.join(timeout=5)
        if self.source_process is not None and self.source_process.poll() is None:
            self.source_process.terminate()
            try:
                self.source_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.source_process.kill()
                self.source_process.wait(timeout=5)
        if self.source_log is not None:
            self.source_log.close()
        shutil.rmtree(self.workspace, ignore_errors=True)

    def _wait_for_process_exit(self, pid: int) -> None:
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            if not self._process_is_alive(pid):
                return
            time.sleep(0.1)
        raise AcceptanceFailure(f"target process {pid} did not terminate")

    @staticmethod
    def _process_is_alive(pid: int) -> bool:
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    @staticmethod
    def _integer(value: object, name: str) -> int:
        if not isinstance(value, int):
            raise AcceptanceFailure(f"{name} was not an integer: {value}")
        return value

    @staticmethod
    def _complete_event_placeholders(installed: Path) -> list[dict[str, object]]:
        return [
            {"event": "source-ready", "version": SOURCE_VERSION},
            {"event": "dictation-started", "version": SOURCE_VERSION},
            {"event": "update-prepared", "version": SOURCE_VERSION},
            {"event": "termination-deferred", "version": SOURCE_VERSION},
            {
                "event": "dictation-finished",
                "version": SOURCE_VERSION,
                "installedVersionAtCompletion": SOURCE_VERSION,
            },
            {
                "event": "target-started",
                "version": TARGET_VERSION,
                "bundlePath": str(installed),
            },
            {
                "event": "target-ready",
                "version": TARGET_VERSION,
                "bundlePath": str(installed),
                "badgeVisible": True,
                "hotkeyHealth": "global",
            },
        ]


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--artifacts",
        type=Path,
        default=REPOSITORY / "dist/update-runtime-acceptance",
        help="directory that receives the appcast, process log, and diagnostics",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=180,
        help="seconds to wait for each explicit runtime signal",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        evidence = RuntimeAcceptanceHarness(
            artifacts=arguments.artifacts,
            timeout=arguments.timeout,
        ).run()
    except Exception as error:
        print(f"update runtime acceptance failed: {error}", file=sys.stderr)
        return 1
    print(
        "update runtime acceptance passed: "
        f"{evidence.source.version} -> {evidence.target.version} "
        f"at {evidence.installed_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
