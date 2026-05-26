import importlib.util
import unittest
from pathlib import Path


def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "20_backfill_bank_statements.py"
    spec = importlib.util.spec_from_file_location("backfill_bank_statements", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load 20_backfill_bank_statements module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class BackfillParsingTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module()

    def test_make_txn_id_is_deterministic(self):
        txn_a = self.module.make_txn_id("acc_1", "2026-01-01", "-12.34", "Coffee", occurrence=1)
        txn_b = self.module.make_txn_id("acc_1", "2026-01-01", "-12.34", "Coffee", occurrence=1)
        txn_c = self.module.make_txn_id("acc_1", "2026-01-01", "-12.34", "Coffee", occurrence=2)
        self.assertEqual(txn_a, txn_b)
        self.assertNotEqual(txn_a, txn_c)
        self.assertTrue(txn_a.startswith("stmt_"))

    def test_parse_transactions_assigns_sign_and_type(self):
        pages = [
            "\n".join(
                [
                    "Date Activity Description Amount",
                    "01/02 POS PURCHASE COFFEE SHOP 12.34",
                    "01/03 DEPOSIT PAYROLL 100.00",
                ]
            )
        ]
        txns = self.module.parse_transactions(pages, 2026, 1)
        self.assertEqual(len(txns), 2)
        self.assertEqual(txns[0]["amount"], "-12.34")
        self.assertEqual(txns[0]["type"], "card_payment")
        self.assertEqual(txns[1]["amount"], "100.00")
        self.assertEqual(txns[1]["type"], "deposit")

    def test_match_statement_to_account_uses_override(self):
        rows = [("acc_a", "Checking", "1111"), ("acc_b", "Savings", "2222")]
        matched = self.module.match_statement_to_account(Path("dummy.pdf"), ["irrelevant"], rows, "acc_b")
        self.assertEqual(matched, "acc_b")

    def test_match_statement_to_account_uses_last_four_hint(self):
        rows = [("acc_a", "Checking", "1111"), ("acc_b", "Savings", "2222")]
        matched = self.module.match_statement_to_account(
            Path("EStatement_2222_D_20260131.pdf"),
            ["header text"],
            rows,
            None,
        )
        self.assertEqual(matched, "acc_b")


if __name__ == "__main__":
    unittest.main()
