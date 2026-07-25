from __future__ import annotations

import base64
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).parents[2]
FINALIZER = REPOSITORY_ROOT / "scripts" / "finalize_release.sh"


class ReleaseFinalizerShellTests(unittest.TestCase):
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
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/bin/bash", str(FINALIZER)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
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
                    "scripts/release_notarization.py",
                    "finalize",
                    "--artifact-directory",
                    "dist/notarization",
                    "--record",
                    "dist/notarization/submission.json",
                    "--log",
                    "dist/notarization/notarization-log.json",
                    "--repository",
                    "hadrysm/foldwise-voice",
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
