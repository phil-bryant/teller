import json
import subprocess
import tempfile
from pathlib import Path
import unittest


class GenerateSupplyChainArtifactsTests(unittest.TestCase):
    def test_generates_sbom_signature_and_attestation(self):
        #R110-T01
        repo_root = Path(__file__).resolve().parents[2]
        script = repo_root / "src/scripts/security/generate_supply_chain_artifacts.py"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            runtime_lock = tmp_path / "requirements.txt"
            security_lock = tmp_path / "requirements-security.txt"
            output_dir = tmp_path / "artifacts"

            runtime_lock.write_text(
                "requests==2.34.2 \\\n"
                "    --hash=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
                encoding="utf-8",
            )
            security_lock.write_text(
                "bandit==1.9.4 \\\n"
                "    --hash=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    "python3",
                    str(script),
                    "--runtime-lock",
                    str(runtime_lock),
                    "--security-lock",
                    str(security_lock),
                    "--output-dir",
                    str(output_dir),
                    "--signing-mode",
                    "scaffold",
                ],
                cwd=repo_root,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            sbom = output_dir / "sbom.cdx.json"
            signature = output_dir / "sbom.signature"
            attestation = output_dir / "sbom.attestation.json"
            self.assertTrue(sbom.exists())
            self.assertTrue(signature.exists())
            self.assertTrue(attestation.exists())

            payload = json.loads(sbom.read_text(encoding="utf-8"))
            self.assertEqual(payload.get("bomFormat"), "CycloneDX")


if __name__ == "__main__":
    unittest.main()
