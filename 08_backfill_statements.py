#! /usr/bin/env python3
import argparse, hashlib, logging, os, re, subprocess, tempfile
from datetime import date
from decimal import Decimal
from pathlib import Path
from sqlalchemy import text
import structlog

STATEMENTS_ROOT_ENV = "TELLER_BANK_STATEMENTS_ROOT"

log = structlog.get_logger()

CREDIT_PREFIXES = ('DEPOSIT', 'MOBILE DEPOSIT', 'INTEREST EARNED', 'INTEREST', 'ORIG:')
CREDIT_CONTAINS = ('RETURN', 'REBATE')
TYPE_MAP = [
    ('POS PURCHASE', 'card_payment'), ('ATM WITHDRAWAL', 'atm'), ('DEPOSIT', 'deposit'),
    ('MOBILE DEPOSIT', 'deposit'), ('INTEREST', 'interest'), ('VERIZON/', 'ach'),
    ('BILL PAY', 'ach'), ('WEB PAY', 'ach'), ('ORIG:', 'wire'), ('INCOMING WIRE FEE', 'fee'),
]
AMOUNT_RE = re.compile(r'((?:\d{1,3}(?:,\d{3})*|\d+)?\.\d{2})$')
ANY_AMOUNT_RE = re.compile(r'((?:\d{1,3}(?:,\d{3})*|\d+)?\.\d{2})')
DATE_RE = re.compile(r'^(\d{1,2})/(\d{2})(?:\s+|$)')
INTEREST_RE = re.compile(r'INTEREST EARNED\s+(\d{1,3}(?:,\d{3})*\.\d{2})')
# First Arkansas-style e-statement names often embed the account last four: EStatement_6414_D_...
FILENAME_LAST_FOUR_RE = re.compile(r'EStatement_(\d{4})_', re.I)
LAST_FOUR_OCR_RES = (
    re.compile(r'\*{2,}\s*(\d{4})\b'),
    re.compile(r'(?:account|acct)\s*#?\s*\*{0,4}\s*(\d{4})\b', re.I),
    re.compile(r'(?:ending|last)\s*(?:in|#|:)?\s*(\d{4})\b', re.I),
)

def _parse_tsv_words(tsv_text):
    raise NotImplementedError("_parse_tsv_words is no longer used")

def _build_tsv_lines(words):
    raise NotImplementedError("_build_tsv_lines is no longer used")

def _vision_ocr_pages(image_paths):
    if not image_paths:
        return []
    swift_code = """
import Foundation
import Vision
import AppKit

func ocrRows(_ path: String) throws -> [String] {
    let url = URL(fileURLWithPath: path)
    guard let nsImage = NSImage(contentsOf: url) else {
        throw NSError(domain: "vision_ocr", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to load image"])
    }
    var rect = NSRect(origin: .zero, size: nsImage.size)
    guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        throw NSError(domain: "vision_ocr", code: 2, userInfo: [NSLocalizedDescriptionKey: "failed to create cgimage"])
    }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = false
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([req])
    let observations = (req.results ?? []).compactMap { $0 as? VNRecognizedTextObservation }
    return observations.compactMap {
        guard let txt = $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines), !txt.isEmpty else { return nil }
        return "\\($0.boundingBox.midY)\\t\\($0.boundingBox.minX)\\t\\(txt.replacingOccurrences(of: "\\t", with: " "))"
    }
}

for (idx, path) in CommandLine.arguments.dropFirst().enumerated() {
    print("__VISION_PAGE__:\\(idx)")
    do { for row in try ocrRows(path) { print(row) } }
    catch {
        fputs("Vision OCR failed for \\(path): \\(error)\\n", stderr)
        exit(1)
    }
}
""".strip()
    out = subprocess.run(['swift', '-e', swift_code, *image_paths], capture_output=True, text=True, check=True).stdout
    pages, rows = [], []
    for line in out.splitlines():
        if line.startswith("__VISION_PAGE__:"):
            if rows:
                pages.append(rows)
                rows = []
            continue
        rows.append(line)
    if rows:
        pages.append(rows)
    normalized = []
    for page_rows in pages:
        points = []
        for row in page_rows:
            parts = row.split('\t', 2)
            if len(parts) != 3:
                continue
            try:
                y, x = float(parts[0]), float(parts[1])
            except ValueError:
                continue
            points.append((y, x, parts[2]))
        points.sort(key=lambda p: (-p[0], p[1]))
        lines = []
        for y, x, text_value in points:
            if not lines or abs(lines[-1]['y'] - y) > 0.008:
                lines.append({'y': y, 'chunks': [(x, text_value)]})
            else:
                lines[-1]['chunks'].append((x, text_value))
        page_lines = []
        for ln in lines:
            ln['chunks'].sort(key=lambda c: c[0])
            page_lines.append(' '.join(c[1] for c in ln['chunks']))
        normalized.append('\n'.join(page_lines))
    pages = normalized
    if len(pages) != len(image_paths):
        raise RuntimeError(f"Vision OCR returned {len(pages)} pages for {len(image_paths)} input images")
    return pages

def ocr_pdf(pdf_path):
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(['pdftoppm', '-png', '-r', '300', str(pdf_path), os.path.join(td, 'page')],
                       capture_output=True, check=True)
        image_paths = [os.path.join(td, img) for img in sorted(os.listdir(td))]
        return _vision_ocr_pages(image_paths)

def extract_statement_year(pages):
    for page in pages:
        m = re.search(r'Statement Date\s+(\d{2})/(\d{2})/(\d{2})', page)
        if m:
            return 2000 + int(m.group(3)), int(m.group(1))
    raise ValueError("Could not find Statement Date in PDF")

def extract_summary(pages):
    dep_total, wd_total, dep_count, wd_count = None, None, None, None
    for page in pages:
        m = re.search(r'Deposits\s*/\s*Misc Credits\s+(\d+)\s+([\d,.]+)', page)
        if m:
            dep_count, dep_total = int(m.group(1)), Decimal(m.group(2).replace(',', ''))
        m = re.search(r'Withdrawals\s*/\s*Misc Debits\s+(\d+)\s+([\d,.]+)', page)
        if m:
            wd_count, wd_total = int(m.group(1)), Decimal(m.group(2).replace(',', ''))
    return dep_count, dep_total, wd_count, wd_total

def _find_amount(lines):
    def _normalize_amount(raw):
        return f"0{raw}" if raw.startswith('.') else raw
    for i, line in enumerate(lines):
        m = AMOUNT_RE.search(line)
        if m:
            return _normalize_amount(m.group(1)), i, line[:m.start()].rstrip()
    for i, line in enumerate(lines):
        ms = list(ANY_AMOUNT_RE.finditer(line))
        if ms:
            m = ms[-1]
            return _normalize_amount(m.group(1)), i, (line[:m.start()] + line[m.end():]).replace('  ', ' ').strip()
    joined = ' '.join(lines)
    ms = list(ANY_AMOUNT_RE.finditer(joined))
    if ms:
        m = ms[-1]
        return _normalize_amount(m.group(1)), len(lines) - 1, joined[:m.start()].rstrip()
    for i, line in enumerate(lines):
        if 'RETURN CBA FEES' in line and re.search(r'\d{2}$', line):
            m = re.search(r'(\d{2})$', line)
            if m:
                return f"0.{m.group(1)}", i, line[:m.start()].rstrip()
    return None, -1, None

def parse_transactions(pages, year, stmt_month):
    all_lines = []
    for page in pages:
        in_section = False
        for line in page.splitlines():
            s = line.strip()
            has_header_terms = ('date' in s.lower() and 'activity' in s.lower() and 'description' in s.lower())
            if has_header_terms:
                in_section = True
            elif in_section and s:
                all_lines.append(s)
    normalized_lines = []
    i = 0
    while i < len(all_lines):
        s = all_lines[i]
        if re.fullmatch(r'\d{1,2}/\d{2}', s) and i + 1 < len(all_lines):
            normalized_lines.append(f"{s} {all_lines[i + 1]}")
            i += 2
            continue
        normalized_lines.append(s)
        i += 1
    groups, current = [], None
    for line in normalized_lines:
        dm = DATE_RE.match(line)
        if dm:
            if current:
                groups.append(current)
            tail = line[dm.end():].strip()
            current = {'month': int(dm.group(1)), 'day': int(dm.group(2)), 'lines': [tail] if tail else []}
        elif current:
            current['lines'].append(line)
    if current:
        groups.append(current)
    result = []
    for g in groups:
        raw_amount, amt_idx, trimmed = _find_amount(g['lines'])
        if raw_amount is None:
            log.warning("No amount found, skipping", lines=g['lines'][:2])
            continue
        desc_parts = []
        for i, line in enumerate(g['lines']):
            desc_parts.append(trimmed if i == amt_idx else line)
        description = ' '.join(p for p in desc_parts if p)
        amount_clean = raw_amount.replace(',', '')
        desc_upper = description.upper()
        is_cred = any(desc_upper.startswith(p) for p in CREDIT_PREFIXES) or any(p in desc_upper for p in CREDIT_CONTAINS)
        signed = amount_clean if is_cred else f"-{amount_clean}"
        result.append({'date': f"{year}-{g['month']:02d}-{g['day']:02d}",
                       'amount': signed, 'description': description, 'type': infer_type(description)})
    _rescue_buried_interest(result, groups, year, stmt_month)
    return result

def _rescue_buried_interest(result, groups, year, stmt_month):
    has_interest = any(t['description'].startswith('INTEREST') for t in result)
    if has_interest:
        return
    import calendar
    for g in groups:
        full_text = ' '.join(g['lines'])
        m = INTEREST_RE.search(full_text)
        if m:
            last_day = calendar.monthrange(year, stmt_month)[1]
            amt = m.group(1).replace(',', '')
            result.append({'date': f"{year}-{stmt_month:02d}-{last_day:02d}", 'amount': amt,
                           'description': 'INTEREST EARNED', 'type': 'interest'})
            log.info("Rescued buried INTEREST EARNED", amount=amt)
            return

def infer_type(description):
    for prefix, ttype in TYPE_MAP:
        if prefix in description:
            return ttype
    return 'unknown'

def make_txn_id(account_id, date_str, amount, description, occurrence=1):
    h = hashlib.sha256(f"{account_id}|{date_str}|{amount}|{description}|{occurrence}".encode()).hexdigest()[:20]
    return f"stmt_{h}"

def statements_root(cli_root):
    default = Path(__file__).resolve().parent / "bank_statements"
    root = (cli_root or os.environ.get(STATEMENTS_ROOT_ENV) or "").strip()
    path = Path(root).expanduser().resolve() if root else default
    return path

def list_institution_ids(session, only):
    if only:
        return [only]
    rows = session.execute(text(
        "SELECT DISTINCT institution_id FROM teller.account ORDER BY institution_id"
    )).fetchall()
    return [r[0] for r in rows]

def pdfs_for_institution(root: Path, institution_id: str):
    d = root / institution_id
    if not d.is_dir():
        return []
    return sorted(d.glob("*.pdf"))

def accounts_for_institution(session, institution_id):
    rows = session.execute(text(
        "SELECT account_id, name, last_four FROM teller.account WHERE institution_id = :iid ORDER BY name"
    ), {"iid": institution_id}).fetchall()
    if not rows:
        raise SystemExit(f"No account rows for institution_id={institution_id!r}")
    return rows

def extract_last_four_hint(pdf_path: Path, pages):
    m = FILENAME_LAST_FOUR_RE.search(pdf_path.name)
    if m:
        return m.group(1)
    head = "\n".join(pages[:3])
    for rx in LAST_FOUR_OCR_RES:
        mm = rx.search(head)
        if mm:
            return mm.group(1)
    return None

def match_statement_to_account(pdf_path: Path, pages, account_rows, account_id_override):
    if account_id_override:
        for r in account_rows:
            if r[0] == account_id_override:
                return r[0]
        raise SystemExit(
            f"--account-id {account_id_override!r} is not an account for this institution")
    if len(account_rows) == 1:
        return account_rows[0][0]
    hint = extract_last_four_hint(pdf_path, pages)
    if not hint:
        raise SystemExit(
            "Multiple accounts at this institution but could not read last four from "
            f"{pdf_path.name} (try a filename like EStatement_LAST4_... or fix OCR).")
    matches = [r for r in account_rows if r[2] == hint]
    if len(matches) == 1:
        log.info("Matched statement to account", pdf=pdf_path.name, last_four=hint, account_id=matches[0][0])
        return matches[0][0]
    if not matches:
        raise SystemExit(
            f"No teller.account with last_four={hint!r} for {pdf_path.name}; check DB vs statement.")
    raise SystemExit(f"Multiple accounts with last_four={hint!r} in DB (unexpected).")

def main():
    parser = argparse.ArgumentParser(description='Backfill transactions from bank statement PDFs')
    parser.add_argument('--institution-id', help='Limit to one teller.institution.institution_id; default: all in teller.account')
    parser.add_argument('--account-id', help='Optional: force all PDFs for --institution-id to this Teller account_id (skip auto-match)')
    parser.add_argument('--statements-root',
                        help=f'Statement PDF root (default: ./bank_statements next to this script; override with {STATEMENTS_ROOT_ENV})')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--debug', action='store_true')
    args = parser.parse_args()
    if args.account_id and not args.institution_id:
        raise SystemExit("--account-id requires --institution-id")
    structlog.configure(wrapper_class=structlog.make_filtering_bound_logger(
        logging.DEBUG if args.debug else logging.INFO))
    root = statements_root(args.statements_root)
    from teller.teller_db import get_session
    from teller.teller_persist import _upsert_transaction
    session = get_session()
    inserted_total, skipped_total, parsed_total = 0, 0, 0
    try:
        institution_ids = list_institution_ids(session, args.institution_id)
        if not institution_ids:
            raise SystemExit("No institution_id values found in teller.account")
        log.info("Institutions to process", count=len(institution_ids), root=str(root))
        for institution_id in institution_ids:
            pdfs = pdfs_for_institution(root, institution_id)
            if not pdfs:
                log.warning("Skipping institution (no PDFs)", institution_id=institution_id, expected_dir=str(root / institution_id))
                continue
            account_rows = accounts_for_institution(session, institution_id)
            acct_override = args.account_id if (args.institution_id == institution_id) else None
            by_account = {}
            for pdf_path in pdfs:
                log.info("Processing PDF", institution_id=institution_id, path=str(pdf_path))
                pages = ocr_pdf(pdf_path)
                account_id = match_statement_to_account(pdf_path, pages, account_rows, acct_override)
                year, month = extract_statement_year(pages)
                txns = parse_transactions(pages, year, month)
                dep_count, dep_total, wd_count, wd_total = extract_summary(pages)
                parsed_dep = sum(Decimal(t['amount']) for t in txns if Decimal(t['amount']) > 0)
                parsed_wd = sum(abs(Decimal(t['amount'])) for t in txns if Decimal(t['amount']) < 0)
                log.info("Parsed statement", institution_id=institution_id, account_id=account_id, year=year, month=month,
                         txn_count=len(txns), deposits=str(parsed_dep), withdrawals=str(parsed_wd),
                         expected_dep=str(dep_total), expected_wd=str(wd_total))
                if dep_total and parsed_dep != dep_total:
                    log.warning("Deposit total mismatch", institution_id=institution_id, parsed=str(parsed_dep), expected=str(dep_total))
                if wd_total and parsed_wd != wd_total:
                    log.warning("Withdrawal total mismatch", institution_id=institution_id, parsed=str(parsed_wd), expected=str(wd_total))
                by_account.setdefault(account_id, []).extend(txns)
            parsed_total += sum(len(v) for v in by_account.values())
            for account_id, all_txns in sorted(by_account.items(), key=lambda x: x[0]):
                log.info("Persisting account slice", institution_id=institution_id, account_id=account_id, txn_count=len(all_txns))
                row = session.execute(text(
                    "SELECT MIN(date) FROM teller.transaction WHERE account_id = :aid AND transaction_id LIKE 'txn_%%'"
                ), {"aid": account_id}).fetchone()
                earliest_api_date = row[0].isoformat() if row and row[0] else None
                log.info("Earliest API transaction", institution_id=institution_id, account_id=account_id, date=earliest_api_date)
                ins, sk = 0, 0
                seen_occurrences = {}
                for txn in all_txns:
                    key = (txn['date'], txn['amount'], txn['description'])
                    seen_occurrences[key] = seen_occurrences.get(key, 0) + 1
                    txn_id = make_txn_id(account_id, txn['date'], txn['amount'], txn['description'], seen_occurrences[key])
                    if earliest_api_date and date.fromisoformat(txn['date']) >= date.fromisoformat(earliest_api_date):
                        sk += 1
                        continue
                    if args.dry_run:
                        print(f"  {txn['date']} {txn['amount']:>10} {txn['description'][:80]}")
                        ins += 1
                        continue
                    _upsert_transaction(session, {
                        'id': txn_id, 'account_id': account_id, 'amount': txn['amount'],
                        'date': txn['date'], 'description': txn['description'], 'type': txn['type'],
                        'status': 'posted', 'running_balance': None,
                        'details': {'processing_status': 'complete', 'category': None, 'counterparty': None},
                        'links': {'self': f'stmt://{txn_id}',
                                  'account': f'https://api.teller.io/accounts/{account_id}'}
                    })
                    ins += 1
                inserted_total += ins
                skipped_total += sk
                if not args.dry_run and ins:
                    session.commit()
                    log.info("Database commit complete", institution_id=institution_id, account_id=account_id, inserted=ins, skipped=sk)
    finally:
        session.close()
    log.info("Backfill complete", inserted=inserted_total, skipped=skipped_total, total_parsed=parsed_total)

if __name__ == '__main__':
    main()
