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
CREDIT_CONTAINS = ('RETURN',)
TYPE_MAP = [
    ('POS PURCHASE', 'card_payment'), ('ATM WITHDRAWAL', 'atm'), ('DEPOSIT', 'deposit'),
    ('MOBILE DEPOSIT', 'deposit'), ('INTEREST', 'interest'), ('VERIZON/', 'ach'),
    ('BILL PAY', 'ach'), ('WEB PAY', 'ach'), ('ORIG:', 'wire'), ('INCOMING WIRE FEE', 'fee'),
]
AMOUNT_RE = re.compile(r'(\d{1,3}(?:,\d{3})*\.\d{2})$')
DOT_AMOUNT_RE = re.compile(r'(\.\d{2})$')
ANY_AMOUNT_RE = re.compile(r'(\d{1,3}(?:,\d{3})*\.\d{2})')
DATE_RE = re.compile(r'^(\d{1,2})/(\d{2})\s')
INTEREST_RE = re.compile(r'INTEREST EARNED\s+(\d{1,3}(?:,\d{3})*\.\d{2})')
# First Arkansas-style e-statement names often embed the account last four: EStatement_6414_D_...
FILENAME_LAST_FOUR_RE = re.compile(r'EStatement_(\d{4})_', re.I)
LAST_FOUR_OCR_RES = (
    re.compile(r'\*{2,}\s*(\d{4})\b'),
    re.compile(r'(?:account|acct)\s*#?\s*\*{0,4}\s*(\d{4})\b', re.I),
    re.compile(r'(?:ending|last)\s*(?:in|#|:)?\s*(\d{4})\b', re.I),
)

def ocr_pdf(pdf_path):
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(['pdftoppm', '-png', '-r', '300', str(pdf_path), os.path.join(td, 'page')],
                       capture_output=True, check=True)
        pages = []
        for img in sorted(os.listdir(td)):
            r = subprocess.run(['tesseract', os.path.join(td, img), 'stdout'],
                               capture_output=True, text=True, check=True)
            pages.append(r.stdout)
    return pages

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
    for i, line in enumerate(lines):
        m = AMOUNT_RE.search(line)
        if m:
            return m.group(1), i, line[:m.start()].rstrip()
        m = DOT_AMOUNT_RE.search(line)
        if m:
            return '0' + m.group(1), i, line[:m.start()].rstrip()
    for i, line in enumerate(lines):
        ms = list(ANY_AMOUNT_RE.finditer(line))
        if ms:
            m = ms[-1]
            return m.group(1), i, (line[:m.start()] + line[m.end():]).replace('  ', ' ').strip()
    joined = ' '.join(lines)
    ms = list(ANY_AMOUNT_RE.finditer(joined))
    if ms:
        m = ms[-1]
        return m.group(1), len(lines) - 1, joined[:m.start()].rstrip()
    return None, -1, None

def parse_transactions(pages, year, stmt_month):
    all_lines = []
    for page in pages:
        in_section = False
        for line in page.splitlines():
            s = line.strip()
            if 'Date Activity Description' in s:
                in_section = True
            elif in_section and s:
                all_lines.append(s)
    groups, current = [], None
    for line in all_lines:
        dm = DATE_RE.match(line)
        if dm:
            if current:
                groups.append(current)
            current = {'month': int(dm.group(1)), 'day': int(dm.group(2)), 'lines': [line[dm.end():].strip()]}
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
        is_cred = any(description.startswith(p) for p in CREDIT_PREFIXES) or \
                  any(p in description for p in CREDIT_CONTAINS)
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

def make_txn_id(account_id, date_str, amount, description):
    h = hashlib.sha256(f"{account_id}|{date_str}|{amount}|{description}".encode()).hexdigest()[:20]
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
    from teller_db import get_session
    from teller_persist import _upsert_transaction
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
                for txn in all_txns:
                    txn_id = make_txn_id(account_id, txn['date'], txn['amount'], txn['description'])
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
