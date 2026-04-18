#! /usr/bin/env python3
import unittest


def main():
    suite = unittest.defaultTestLoader.discover("tests", pattern="test_teller_reclassification_api.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    main()
