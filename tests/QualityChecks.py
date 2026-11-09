import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))


class QualityChecks(unittest.TestCase):
    def test_sign_and_identifier_loss_are_visible(self):
        from evaluate_corpus import score
        result = score("Pay -12.50 for AB-007.", "Pay 12.50 for AB007.", ["-12.50", "AB-007"])
        self.assertEqual(result["missing_protected"], ["-12.50", "AB-007"])
        self.assertGreater(result["character_edits"], 0)

    def test_word_error_rate_is_separate_from_case_fidelity(self):
        from evaluate_corpus import score
        result = score("iPhone is ready.", "IPhone is ready.", ["iPhone"])
        self.assertEqual(result["normalized_wer"], 0)
        self.assertEqual(result["missing_protected"], ["iPhone"])

    def test_longer_identifier_is_not_an_exact_match(self):
        from evaluate_corpus import score
        self.assertEqual(score("AB007", "AB0070", ["AB007"])["missing_protected"], ["AB007"])


if __name__ == "__main__":
    unittest.main()
