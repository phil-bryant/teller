#!/usr/bin/env python3
#R001: Provide macOS-safe mutmut prepare/execute flow without in-process forks.
#R005: Run mutant tests via subprocess pytest with deterministic environment setup.
#R010: Integrate with pre-import setproctitle stub to avoid Darwin mutmut crash path.
"""macOS mutmut: prepare stats/mutants, then run mutations via subprocess pytest (no os.fork)."""
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


def _purge_pycache_under(mutants_root: Path) -> None:
    stamp = datetime.now().strftime("%Y-%m-%d-%H.%M.%S")
    for cache_dir in mutants_root.rglob("__pycache__"):
        if not cache_dir.is_dir():
            continue
        trash = Path.home() / ".Trash" / f"teller_pycache_{stamp}_{cache_dir.parent.name}"
        trash.parent.mkdir(parents=True, exist_ok=True)
        if trash.exists():
            trash = Path.home() / ".Trash" / f"teller_pycache_{stamp}_{cache_dir.parent.name}_{os.getpid()}"
        os.rename(cache_dir, trash)


def _repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _prepare(root: Path, max_children: int) -> int:
    os.chdir(root)
    os.environ["MUTANT_UNDER_TEST"] = "mutant_generation"
    from mutmut.__main__ import (
        CatchOutput,
        PytestRunner,
        collect_or_load_stats,
        copy_also_copy_files,
        copy_src_dir,
        create_mutants,
        ensure_config_loaded,
        makedirs,
        run_forced_fail_test,
        tests_for_mutant_names,
    )
    from pathlib import Path as PPath

    ensure_config_loaded()
    makedirs(PPath("mutants"), exist_ok=True)
    path_before_pool = sys.path.copy()
    with CatchOutput(spinner_title="Generating mutants"):
        copy_src_dir()
        copy_also_copy_files()
        _purge_pycache_under(PPath("mutants"))
        stats = create_mutants(max_children)
        sys.path[:] = path_before_pool
        _purge_pycache_under(PPath("mutants"))
    print(
        f"    done ({stats.mutated} files mutated, {stats.ignored} ignored, {stats.unmodified} unmodified)"
    )
    runner = PytestRunner()
    runner.prepare_main_test_run()
    collect_or_load_stats(runner)
    os.environ["MUTANT_UNDER_TEST"] = ""
    with CatchOutput(spinner_title="Running clean tests") as output_catcher:
        tests = tests_for_mutant_names(())
        clean_exit = runner.run_tests(mutant_name=None, tests=tests)
        if clean_exit != 0:
            output_catcher.dump_output()
            print("Failed to run clean test")
            return 1
    print("    done")
    run_forced_fail_test(runner)
    return 0


def _load_stats(root: Path) -> dict:
    stats_path = root / "mutants" / "mutmut-stats.json"
    return json.loads(stats_path.read_text(encoding="utf-8"))


def _tests_for_mutant(stats: dict, mutant_name: str) -> list[str]:
    from mutmut.__main__ import mangled_name_from_mutant_name

    key = mangled_name_from_mutant_name(mutant_name)
    tests = stats.get("tests_by_mangled_function_name", {}).get(key, [])
    durations = stats.get("duration_by_test", {})
    return sorted(tests, key=lambda name: durations.get(name, 0.0))


def _run_mutant_pytest(python: Path, root: Path, mutant_name: str, tests: list[str]) -> int:
    venv = root / "teller-venv"
    env = os.environ.copy()
    env["MUTANT_UNDER_TEST"] = mutant_name
    env["PYTHONPATH"] = f"{root / 'mutants'}:{root}"
    env["VIRTUAL_ENV"] = str(venv)
    env["PATH"] = f"{venv / 'bin'}:{env.get('PATH', '')}"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env.setdefault("HYPOTHESIS_STORAGE_DIRECTORY", str(root / "artifacts/cache/hypothesis"))
    pytest_args = [
        str(python),
        "-m",
        "pytest",
        "-x",
        "-q",
        "-p",
        "no:hypothesis",
        "-p",
        "no:randomly",
        "-p",
        "no:random-order",
        "--rootdir",
        str(root),
        "--tb=no",
    ] + tests
    proc = subprocess.run(pytest_args, cwd=root / "mutants", env=env)
    return int(proc.returncode)


def _execute(root: Path, python: Path) -> int:
    os.chdir(root)
    import mutmut
    from mutmut.__main__ import SourceFileMutationData, ensure_config_loaded, load_stats, walk_source_files

    ensure_config_loaded()
    if not load_stats():
        print("mutmut-stats.json missing; run prepare first.")
        return 1
    stats = _load_stats(root)
    rerun_codes = {None, -11, -9}
    tried = 0
    for path in walk_source_files():
        if mutmut.config.should_ignore_for_mutation(path):
            continue
        meta = SourceFileMutationData(path=path)
        meta.load()
        if not meta.exit_code_by_key:
            continue
        for mutant_name, prior in list(meta.exit_code_by_key.items()):
            if prior not in rerun_codes and prior != 33:
                continue
            tests = _tests_for_mutant(stats, mutant_name)
            if not tests:
                meta.exit_code_by_key[mutant_name] = 33
                meta.save()
                continue
            start = time.monotonic()
            exit_code = _run_mutant_pytest(python, root, mutant_name, tests)
            meta.exit_code_by_key[mutant_name] = exit_code
            meta.durations_by_key[mutant_name] = time.monotonic() - start
            meta.save()
            tried += 1
            status = "killed" if exit_code in (1, 3) else "survived" if exit_code == 0 else str(exit_code)
            print(f"  {mutant_name}: {status} (exit {exit_code})")
    if tried == 0:
        print("No mutants executed (empty meta or all already verdicted).")
        return 1
    print(f"Executed {tried} mutant(s) via subprocess pytest.")
    return 0


def main(argv: list[str] | None = None) -> int:
    # New files/dirs from this process: no group/other access (aligns with umask 007 policy).
    os.umask(0o007)
    parser = argparse.ArgumentParser(description="macOS-safe mutmut driver")
    parser.add_argument("command", choices=["prepare", "execute"])
    parser.add_argument("--max-children", type=int, default=1)
    args = parser.parse_args(argv)
    root = _repo_root()
    python = Path(os.environ.get("TELLER_PYTHON", root / "teller-venv/bin/python3"))
    if not python.is_absolute():
        python = (root / python).resolve()
    else:
        python = python.expanduser()
    if args.command == "prepare":
        return _prepare(root, args.max_children)
    return _execute(root, python)


if __name__ == "__main__":
    raise SystemExit(main())
