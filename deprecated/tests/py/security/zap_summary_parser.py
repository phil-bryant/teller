#!/usr/bin/env python3
import json
import pathlib
import re
import sys


def extract_count(content: str, risk_code: str) -> int:
    pattern = (
        r'class="risk-' + re.escape(risk_code) + r'".*?'
        r"<td[^>]*>\s*<div>\s*([0-9]+)\s*</div>"
    )
    match = re.search(pattern, content, flags=re.IGNORECASE | re.DOTALL)
    if not match:
        return 0
    return int(match.group(1))


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: zap_summary_parser.py <zap_html> <summary_json>")
    html_path = pathlib.Path(sys.argv[1])
    summary_path = pathlib.Path(sys.argv[2])
    content = html_path.read_text(encoding="utf-8", errors="replace") if html_path.exists() else ""
    summary = {
        "high": extract_count(content, "3"),
        "medium": extract_count(content, "2"),
        "low": extract_count(content, "1"),
        "informational": extract_count(content, "0"),
    }
    summary["total"] = summary["high"] + summary["medium"] + summary["low"] + summary["informational"]
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
