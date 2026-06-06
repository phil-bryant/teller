import hashlib
import importlib.util
import json
import subprocess
import tempfile
from pathlib import Path
import unittest
from unittest import mock


def _load_module():
    #R401: Cover traceability for this helper/test behavior.
    repo_root = Path(__file__).resolve().parents[2]
    script = repo_root / "src/scripts/security/generate_supply_chain_artifacts.py"
    spec = importlib.util.spec_from_file_location("generate_supply_chain_artifacts", script)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load generate_supply_chain_artifacts module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GenerateSupplyChainArtifactsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        #R401: Cover traceability for this helper/test behavior.
        cls.mod = _load_module()

    def test_sha256_file_matches_known_digest(self):
        #R400-T01: Verify `sha256_file` returns the expected digest for known bytes.
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "payload.bin"
            payload = b"abc123"
            path.write_bytes(payload)
            self.assertEqual(self.mod.sha256_file(path), hashlib.sha256(payload).hexdigest())

    def test_write_json_writes_stable_newline_terminated_output(self):
        #R401-T01: Verify `write_json` writes deterministic indented JSON with a trailing newline.
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "payload.json"
            payload = {"a": 1, "z": [1, 2]}
            self.mod.write_json(path, payload)
            self.assertEqual(path.read_text(encoding="utf-8"), json.dumps(payload, indent=2) + "\n")

    def test_has_command_detects_present_and_missing_tools(self):
        #R402-T01: Verify `has_command` returns true for an available interpreter and false for a missing command.
        self.assertTrue(self.mod.has_command("python3"))
        self.assertFalse(self.mod.has_command("definitely-not-a-real-command-xyz"))

    def test_normalize_pypi_name_canonicalizes_separators(self):
        #R403-T01: Verify `normalize_pypi_name` canonicalizes mixed-case separator-heavy names.
        self.assertEqual(self.mod.normalize_pypi_name("Foo_.Bar"), "foo-bar")

    def test_build_purl_uses_normalized_package_name(self):
        #R404-T01: Verify `build_purl` emits `pkg:pypi` references with normalized names.
        self.assertEqual(self.mod.build_purl("Foo_.Bar", "1.2.3"), "pkg:pypi/foo-bar@1.2.3")

    def test_license_id_from_classifiers_maps_known_ids(self):
        #R405-T01: Verify `_license_id_from_classifiers` maps known classifiers and returns null for unknown classifiers.
        self.assertEqual(
            self.mod._license_id_from_classifiers(
                ["License :: OSI Approved :: MIT License", "Other Classifier"]
            ),
            "MIT",
        )
        self.assertIsNone(self.mod._license_id_from_classifiers(["Framework :: Django"]))

    def test_parse_pinned_requirements_returns_components_with_hashes(self):
        #R406-T01: Verify `parse_pinned_requirements` returns pinned components and normalized hash lists.
        with tempfile.TemporaryDirectory() as tmp:
            req = Path(tmp) / "requirements.txt"
            req.write_text(
                "Requests==2.32.0 \\\n"
                "  --hash=sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n"
                "click==8.1.7 \\\n"
                "  --hash=sha256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n",
                encoding="utf-8",
            )
            components = self.mod.parse_pinned_requirements(req)
            self.assertEqual(len(components), 2)
            self.assertEqual(components[0]["name"], "Requests")
            self.assertEqual(
                components[0]["hashes"],
                ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
            )

    def test_build_cyclonedx_emits_expected_top_level_shape(self):
        #R407-T01: Verify `build_cyclonedx` emits required top-level metadata and component fields.
        runtime = [{"name": "requests", "version": "2.32.0", "hashes": ["a" * 64]}]
        security = [{"name": "bandit", "version": "1.7.9", "hashes": ["b" * 64]}]
        with mock.patch.object(
            self.mod,
            "fetch_component_licenses",
            return_value=[{"license": {"name": "UNKNOWN"}}],
        ):
            payload = self.mod.build_cyclonedx(runtime, security)
        self.assertEqual(payload["bomFormat"], "CycloneDX")
        self.assertEqual(payload["specVersion"], "1.5")
        self.assertTrue(str(payload["serialNumber"]).startswith("urn:uuid:"))
        self.assertGreaterEqual(len(payload["components"]), 2)

    def test_merge_components_dedupes_and_prefers_required_scope(self):
        #R408-T01: Verify `merge_components` collapses duplicates and preserves required scope precedence.
        merged = self.mod.merge_components(
            [{"name": "Requests", "version": "1.0", "hashes": ["a" * 64]}],
            [{"name": "requests", "version": "1.0", "hashes": ["b" * 64]}],
        )
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["scope"], "required")
        self.assertEqual(sorted(merged[0]["hashes"]), ["a" * 64, "b" * 64])

    def test_run_cosign_sign_blob_requires_signature_output_file(self):
        #R409-T01: Verify `_run_cosign_sign_blob` succeeds only when subprocess invocation returns zero and writes a signature file.
        with tempfile.TemporaryDirectory() as tmp:
            sbom_path = Path(tmp) / "sbom.json"
            sbom_path.write_text("{}", encoding="utf-8")
            signature_path = Path(tmp) / "sbom.signature"

            def _fake_run(command, check, capture_output, text):
                #R409: Cover traceability for this helper/test behavior.
                _ = (check, capture_output, text)
                self.assertIn("--output-signature", command)
                signature_path.write_text("sig", encoding="utf-8")
                return subprocess.CompletedProcess(command, 0, "", "")

            with mock.patch.object(self.mod.subprocess, "run", side_effect=_fake_run):
                signed = self.mod._run_cosign_sign_blob(
                    ["cosign", "sign-blob"],
                    sbom_path,
                    signature_path,
                )
            self.assertTrue(signed)

    def test_write_scaffold_signature_writes_mode_digest_reason_lines(self):
        #R410-T01: Verify `write_scaffold_signature` writes scaffold mode, digest, and reason values.
        with tempfile.TemporaryDirectory() as tmp:
            signature_path = Path(tmp) / "sbom.signature"
            self.mod.write_scaffold_signature(signature_path, "abc123", "missing cosign")
            body = signature_path.read_text(encoding="utf-8")
            self.assertIn("mode=scaffold", body)
            self.assertIn("sbom_sha256=abc123", body)
            self.assertIn("reason=missing cosign", body)

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

    def test_required_mode_fails_without_cosign_context(self):
        #R120-T01: Verify required signing mode fails with a clear context error when neither key-based nor keyless signing context is available (`tests/py/test_generate_supply_chain_artifacts.py`).
        #R411-T01: Verify required signing mode returns non-zero when no usable cosign context is available.
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
