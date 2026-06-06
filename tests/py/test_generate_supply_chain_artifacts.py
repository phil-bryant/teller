import json
import subprocess
import tempfile
from pathlib import Path
import unittest


class GenerateSupplyChainArtifactsTests(unittest.TestCase):
    def test_generates_sbom_signature_and_attestation(self):
        #R110-T01: Run generator with sample lockfiles and verify SBOM, signature, and attestation artifacts are written.
        #R115-T01: Verify generated SBOM components include `purl`, SHA256 hash entries, and non-empty `licenses[]` metadata for runtime and security dependencies (`tests/py/test_generate_supply_chain_artifacts.py`).
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
            self.assertEqual(payload.get("specVersion"), "1.5")
            self.assertTrue(str(payload.get("serialNumber", "")).startswith("urn:uuid:"))
            components = payload.get("components", [])
            by_name = {component["name"]: component for component in components}
            self.assertIn("requests", by_name)
            self.assertIn("bandit", by_name)

            requests_component = by_name["requests"]
            self.assertEqual(requests_component["purl"], "pkg:pypi/requests@2.34.2")
            self.assertEqual(requests_component["bom-ref"], "pkg:pypi/requests@2.34.2")
            self.assertEqual(requests_component["scope"], "required")
            self.assertEqual(
                requests_component["hashes"],
                [
                    {
                        "alg": "SHA-256",
                        "content": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    }
                ],
            )
            self.assertIn("licenses", requests_component)
            self.assertTrue(requests_component["licenses"])

            bandit_component = by_name["bandit"]
            self.assertEqual(bandit_component["scope"], "optional")
            self.assertEqual(bandit_component["purl"], "pkg:pypi/bandit@1.9.4")
            self.assertIn("licenses", bandit_component)
            self.assertTrue(bandit_component["licenses"])

    def test_required_mode_fails_without_cosign_context(self):
        #R120-T01: Verify required signing mode fails with a clear context error when neither key-based nor keyless signing context is available (`tests/py/test_generate_supply_chain_artifacts.py`).
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
                    "required",
                ],
                cwd=repo_root,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "Signing mode is required, but cosign signing context is unavailable",
                result.stderr,
            )


if __name__ == "__main__":
    unittest.main()
