from __future__ import annotations

import base64
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).parents[2]
FINALIZER = REPOSITORY_ROOT / "scripts" / "finalize_release.sh"
TOOL_STAGER = REPOSITORY_ROOT / "scripts" / "stage_release_tools.sh"


class ReleaseFinalizerShellTests(unittest.TestCase):
    def stage_release_tools(self, destination: Path) -> None:
        result = subprocess.run(
            ["/bin/bash", str(TOOL_STAGER), str(destination)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.strip(),
            str(destination / FINALIZER.name),
        )

    def testStageReleaseToolsPreservesCompleteCurrentToolchain(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "release-tools"

            self.stage_release_tools(destination)

            self.assertEqual(
                {path.name for path in destination.iterdir()},
                {
                    "finalize_release.sh",
                    "release_notarization.py",
                    "release_publication.py",
                },
            )

    def testStagedNotarizationImportsCurrentPublisherFromHistoricalCheckout(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            current_tools = root / "current-tools"
            self.stage_release_tools(current_tools)
            historical_checkout = root / "historical-checkout"
            (historical_checkout / "scripts").mkdir(parents=True)
            (
                historical_checkout / "scripts" / "release_publication.py"
            ).write_text('raise RuntimeError("historical publisher loaded")\n')
            artifact_directory = historical_checkout / "dist" / "notarization"
            artifact_directory.mkdir(parents=True)
            record = artifact_directory / "submission.json"
            record.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "tag": "v0.18.0",
                        "filename": "FoldWise-Voice-0.18.0.dmg",
                        "sha256": "0" * 64,
                        "source_run_id": "30178724003",
                        "commit": "release-commit",
                        "submission_filename": "submitted.dmg",
                        "submission_id": "submission-id",
                    }
                )
            )
            environment = {
                **os.environ,
                "NOTARY_KEY_PATH": str(root / "notary-key.p8"),
                "NOTARY_API_KEY_ID": "key-id",
                "NOTARY_API_ISSUER_ID": "issuer-id",
            }
            for name in (
                "AWS_ACCESS_KEY_ID",
                "AWS_SECRET_ACCESS_KEY",
                "SPARKLE_ED_PRIVATE_KEY",
                "UPDATE_R2_ACCOUNT_ID",
                "UPDATE_R2_BUCKET",
            ):
                environment.pop(name, None)

            result = subprocess.run(
                [
                    "python3",
                    str(current_tools / "release_notarization.py"),
                    "finalize",
                    "--artifact-directory",
                    "dist/notarization",
                    "--record",
                    "dist/notarization/submission.json",
                    "--log",
                    "dist/notarization/notarization-log.json",
                    "--repository",
                    "hadrysm/foldwise-voice",
                    "--release-source-root",
                    str(historical_checkout),
                ],
                cwd=historical_checkout,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "Missing required publication environment",
                result.stderr,
            )
            self.assertNotIn("historical publisher loaded", result.stderr)

    def finalizer_environment(
        self,
        root: Path,
        *,
        exit_code: int = 0,
    ) -> tuple[dict[str, str], Path, Path]:
        arguments = root / "arguments.txt"
        fake_bin = root / "bin"
        fake_bin.mkdir()
        python = fake_bin / "python3"
        python.write_text(
            "#!/bin/bash\n"
            'printf "%s\\n" "$@" > "$FINALIZER_ARGUMENTS"\n'
            'exit "$FINALIZER_EXIT_CODE"\n',
        )
        python.chmod(0o755)
        runner_temp = root / "runner"
        runner_temp.mkdir()
        environment = {
            **os.environ,
            "FINALIZER_ARGUMENTS": str(arguments),
            "FINALIZER_EXIT_CODE": str(exit_code),
            "GITHUB_REPOSITORY": "hadrysm/foldwise-voice",
            "NOTARY_API_ISSUER_ID": "issuer",
            "NOTARY_API_KEY_ID": "key-id",
            "NOTARY_API_PRIVATE_KEY_BASE64": base64.b64encode(
                b"private key",
            ).decode(),
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "PUBLICATION_MODE": "routine",
            "RUNNER_TEMP": str(runner_temp),
        }
        return environment, arguments, runner_temp

    def run_finalizer(
        self,
        environment: dict[str, str],
        *,
        finalizer: Path = FINALIZER,
        working_directory: Path = REPOSITORY_ROOT,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/bin/bash", str(finalizer)],
            cwd=working_directory,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def testCopiedFinalizerUsesCurrentToolsFromHistoricalCheckout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment, arguments, _ = self.finalizer_environment(root)
            current_tools = root / "current-tools"
            self.stage_release_tools(current_tools)
            copied_finalizer = current_tools / FINALIZER.name
            historical_checkout = root / "historical-checkout"
            (historical_checkout / "scripts").mkdir(parents=True)
            (historical_checkout / "scripts" / "release_notarization.py").touch()

            result = self.run_finalizer(
                environment,
                finalizer=copied_finalizer,
                working_directory=historical_checkout,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                arguments.read_text().splitlines(),
                [
                    str(current_tools / "release_notarization.py"),
                    "finalize",
                    "--artifact-directory",
                    "dist/notarization",
                    "--record",
                    "dist/notarization/submission.json",
                    "--log",
                    "dist/notarization/notarization-log.json",
                    "--repository",
                    "hadrysm/foldwise-voice",
                    "--release-source-root",
                    str(historical_checkout.resolve()),
                ],
            )

    def testRoutinePublicationInvokesFinalizerWithoutRepairArguments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment, arguments, runner_temp = self.finalizer_environment(
                root,
            )
            result = self.run_finalizer(environment)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                arguments.read_text().splitlines(),
                [
                    str(REPOSITORY_ROOT / "scripts" / "release_notarization.py"),
                    "finalize",
                    "--artifact-directory",
                    "dist/notarization",
                    "--record",
                    "dist/notarization/submission.json",
                    "--log",
                    "dist/notarization/notarization-log.json",
                    "--repository",
                    "hadrysm/foldwise-voice",
                    "--release-source-root",
                    str(REPOSITORY_ROOT),
                ],
            )
            self.assertFalse(
                (runner_temp / "foldwise-notary-key.p8").exists(),
            )

    def testFinalizerFailureSurvivesCredentialCleanup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment, _, runner_temp = self.finalizer_environment(
                root,
                exit_code=37,
            )

            result = self.run_finalizer(environment)

            self.assertEqual(result.returncode, 37, result.stderr)
            self.assertFalse(
                (runner_temp / "foldwise-notary-key.p8").exists(),
            )

    def testMissingRepairArgumentsFailBeforeCredentialMaterialization(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment, _, runner_temp = self.finalizer_environment(root)
            environment["PUBLICATION_MODE"] = "forward-repair"
            environment.pop("BAD_VERSION", None)

            result = self.run_finalizer(environment)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("BAD_VERSION", result.stderr)
            self.assertFalse(
                (runner_temp / "foldwise-notary-key.p8").exists(),
            )


if __name__ == "__main__":
    unittest.main()
