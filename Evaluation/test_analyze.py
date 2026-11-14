"""Tests the analysis pipeline on small synthetic datasets (clearly fake, built in the test).

Run: python3 -m unittest discover -s Evaluation -p "test_*.py"
"""
import os
import tempfile
import unittest

import analyze


def make_rows(compact_saving, noise=0.1, destinations=12, search_error_on=None):
    """Synthetic CSV rows. compact leg = baseline leg - compact_saving + deterministic zero-mean noise."""
    rows = []
    orders = [["baseline", "compact", "minimal"], ["compact", "minimal", "baseline"], ["minimal", "baseline", "compact"]]
    for i in range(destinations):
        base_leg = 3.0 + 0.4 * (i % 4)
        wiggle = ((i % 3) - 1) * noise
        for position, variant in enumerate(orders[i % 3], 1):
            leg = {"baseline": base_leg, "compact": base_leg - compact_saving + wiggle, "minimal": base_leg + 1.0}[variant]
            for day in (1, 2):
                errors = 1 if search_error_on == ("City%d" % i, variant) and day == 2 else 0
                rows.append({
                    "destination": "City%d" % i, "region": ["Europe", "Asia"][i % 2], "variant": variant,
                    "position": str(position), "day": str(day), "suggested": "3", "verified": "3",
                    "rejected_not_found": "0", "rejected_duplicate": "0", "search_errors": str(errors),
                    "verified_rate": "1.0000", "mean_leg_km": "%.4f" % (leg + (0.2 if day == 2 else -0.2)),
                    "latency_s": "2.000", "usable": "1",
                })
    return rows


def run_analysis(rows):
    with tempfile.TemporaryDirectory() as out:
        report = analyze.analyse(rows, out)
        files = sorted(os.listdir(out))
    return report, files


class TrialBuildingTests(unittest.TestCase):
    def test_days_are_averaged_within_a_trial(self):
        trials, excluded = analyze.build_trials(make_rows(1.0, destinations=3))
        self.assertEqual(excluded, [])
        self.assertEqual(len(trials), 9)  # 3 destinations x 3 variants: one observation per cell, not per day
        # The two days were base+0.2 and base-0.2, so the trial mean is exactly the base value.
        self.assertAlmostEqual(trials[("City0", "baseline")]["mean_leg_km"], 3.0, places=6)

    def test_trials_with_failed_lookups_are_excluded_not_counted_against_the_model(self):
        rows = make_rows(1.0, destinations=4, search_error_on=("City1", "compact"))
        trials, excluded = analyze.build_trials(rows)
        self.assertEqual(excluded, [("City1", "compact")])
        self.assertNotIn(("City1", "compact"), trials)
        self.assertIn(("City1", "baseline"), trials)

    def test_destinations_missing_a_variant_are_dropped_listwise(self):
        trials, _ = analyze.build_trials(make_rows(1.0, destinations=4, search_error_on=("City1", "compact")))
        kept, matrix = analyze.paired_columns(trials, ["baseline", "compact", "minimal"], "mean_leg_km")
        self.assertEqual(kept, ["City0", "City2", "City3"])
        self.assertTrue(all(len(row) == 3 for row in matrix))


class VerdictTests(unittest.TestCase):
    def test_clear_saving_is_supported(self):
        report, files = run_analysis(make_rows(compact_saving=1.5))
        self.assertIn("SUPPORTED: compact days are shorter by 1.50 km", report)
        self.assertIn("NON-INFERIORITY SHOWN", report)
        for name in ("report.md" if False else "summary.json", "chart_mean_leg_km.svg", "chart_verified_rate.svg"):
            self.assertIn(name, files)

    def test_no_difference_is_not_supported(self):
        report, _ = run_analysis(make_rows(compact_saving=0.0, noise=0.3))
        self.assertIn("NOT SUPPORTED: no reliable difference", report)

    def test_longer_days_are_reported_as_contradicting_the_hypothesis(self):
        report, _ = run_analysis(make_rows(compact_saving=-1.5))
        self.assertIn("CONTRADICTED: compact days were longer", report)

    def test_tiny_but_significant_saving_is_not_called_important(self):
        report, _ = run_analysis(make_rows(compact_saving=0.2, noise=0.02))
        self.assertIn("below the 0.5 km practical threshold: not important", report)

    def test_report_states_exclusions_and_sensitivity(self):
        report, _ = run_analysis(make_rows(0.0, noise=0.3, search_error_on=("City2", "minimal")))
        self.assertIn("excluded because a map lookup failed (infrastructure, not model, error): 1", report)
        self.assertIn("Sensitivity:", report)

    def test_near_zero_effect_does_not_print_an_absurd_sample_size(self):
        report, _ = run_analysis(make_rows(0.0, noise=0.3))
        self.assertIn("more than 1,000 destinations", report)
        self.assertNotRegex(report, r"\d{6,} destinations")

    def test_ceiling_is_reported_when_present(self):
        report, _ = run_analysis(make_rows(1.0))
        self.assertIn("confirms it", report)


if __name__ == "__main__":
    unittest.main()
