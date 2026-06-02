import importlib.util
import unittest
from pathlib import Path


def load_module():
    repo_root = Path(__file__).resolve().parents[2]
    script_path = repo_root / "08_backfill_bank_statements.py"
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

    def test_reconstruct_lines_groups_rows_in_reading_order(self):
        # R030-T01: Two clearly separated rows reconstruct top-to-bottom, left-to-right.
        points = [
            (0.90, 0.50, "world"),
            (0.90, 0.10, "hello"),
            (0.50, 0.10, "second"),
            (0.50, 0.40, "line"),
        ]
        self.assertEqual(self.module.reconstruct_lines(points), ["hello world", "second line"])

    def test_reconstruct_lines_merges_jitter_but_splits_tight_rows(self):
        # R030-T02: Within-line jitter stays merged while tightly spaced rows still separate.
        points = [
            (0.9000, 0.10, "a"),
            (0.8997, 0.50, "b"),
            (0.8600, 0.10, "c"),
            (0.8600, 0.50, "d"),
        ]
        self.assertEqual(self.module.reconstruct_lines(points), ["a b", "c d"])

    def test_adaptive_line_epsilon_honors_floor_and_scales(self):
        # R030-T03: Sparse gaps fall back to the floor; dense gaps scale epsilon by the median.
        self.assertEqual(self.module._adaptive_line_epsilon([], min_epsilon=0.004), 0.004)
        self.assertEqual(self.module._adaptive_line_epsilon([0.9, 0.9], min_epsilon=0.004), 0.004)
        scaled = self.module._adaptive_line_epsilon([1.0, 0.8, 0.6], min_epsilon=0.004, gap_factor=0.5)
        self.assertAlmostEqual(scaled, 0.1)


if __name__ == "__main__":
    unittest.main()
