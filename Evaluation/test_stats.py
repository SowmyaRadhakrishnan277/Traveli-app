"""Checks the hand-written statistics against published critical values and identities.

Run: python3 -m unittest discover -s Evaluation -p "test_*.py"
"""
import math
import unittest

import stats


class DistributionTests(unittest.TestCase):
    def test_t_critical_values_match_tables(self):
        # Two-sided 5% critical values from standard t tables.
        for df, expected in [(1, 12.706), (4, 2.776), (9, 2.262), (15, 2.131), (44, 2.015), (1000, 1.962)]:
            self.assertAlmostEqual(stats.t_critical(df), expected, places=2, msg="df=%s" % df)

    def test_t_p_values_at_critical_points(self):
        self.assertAlmostEqual(stats.t_two_sided_p(2.7764, 4), 0.05, places=3)
        self.assertAlmostEqual(stats.t_two_sided_p(4.6041, 4), 0.01, places=3)
        self.assertAlmostEqual(stats.t_two_sided_p(63.6567, 1), 0.01, places=3)
        self.assertAlmostEqual(stats.t_two_sided_p(0.0, 10), 1.0, places=9)

    def test_f_critical_values_and_t_squared_identity(self):
        self.assertAlmostEqual(stats.f_sf(3.1504, 2, 60), 0.05, places=3)
        self.assertAlmostEqual(stats.f_sf(4.0847, 1, 40), 0.05, places=3)
        for t, df in [(1.3, 7), (2.5, 20), (0.4, 3)]:
            self.assertAlmostEqual(stats.f_sf(t * t, 1, df), stats.t_two_sided_p(t, df), places=9)

    def test_betainc_basics(self):
        for x in (0.1, 0.5, 0.9):
            self.assertAlmostEqual(stats.betainc(1, 1, x), x, places=10)
            self.assertAlmostEqual(stats.betainc(2.5, 4, x), 1 - stats.betainc(4, 2.5, 1 - x), places=10)

    def test_ci95_uses_t_not_normal(self):
        lo, hi = stats.ci95([1, 2, 3, 4, 5])
        self.assertAlmostEqual(hi - 3, 2.776 * stats.sd([1, 2, 3, 4, 5]) / math.sqrt(5), places=2)
        self.assertAlmostEqual(lo + hi, 6.0, places=9)


class PowerTests(unittest.TestCase):
    def test_normal_ppf_known_values(self):
        self.assertAlmostEqual(stats.normal_ppf(0.975), 1.95996, places=4)
        self.assertAlmostEqual(stats.normal_ppf(0.80), 0.84162, places=4)
        self.assertAlmostEqual(stats.normal_ppf(0.5), 0.0, places=9)

    def test_required_n_matches_published_tables_closely(self):
        # Exact (noncentral t) values: d=0.5 -> 34, d=0.8 -> 15, d=0.2 -> 199 for power .80, alpha .05.
        for d, exact in [(0.5, 34), (0.8, 15), (0.2, 199)]:
            self.assertLessEqual(abs(stats.required_n_paired(d) - exact), 2, "d=%s" % d)

    def test_smaller_effects_and_stricter_alpha_need_more_subjects(self):
        self.assertGreater(stats.required_n_paired(0.3), stats.required_n_paired(0.6))
        self.assertGreater(stats.required_n_paired(0.5, alpha=0.025), stats.required_n_paired(0.5))
        self.assertGreater(stats.required_n_paired(0.5, power=0.9), stats.required_n_paired(0.5))


class PairedTests(unittest.TestCase):
    def test_paired_t_worked_example(self):
        result = stats.paired_t([2, 4, 6, 8, 10], [1, 2, 3, 4, 5])  # differences 1..5
        self.assertAlmostEqual(result["t"], 4.2426, places=3)
        self.assertEqual(result["df"], 4)
        self.assertAlmostEqual(result["p"], 0.0132, places=3)
        self.assertAlmostEqual(result["d_z"], 3 / math.sqrt(2.5), places=6)

    def test_identical_samples_give_p_one(self):
        result = stats.paired_t([1, 2, 3], [1, 2, 3])
        self.assertEqual((result["t"], result["p"], result["d_z"]), (0.0, 1.0, 0.0))

    def test_constant_difference_is_infinitely_significant(self):
        result = stats.paired_t([2, 3, 4], [1, 2, 3])
        self.assertEqual(result["p"], 0.0)
        self.assertTrue(math.isinf(result["d_z"]))

    def test_wilcoxon_all_positive_n10(self):
        result = stats.wilcoxon_signed_rank(list(range(1, 11)), [0] * 10)
        self.assertEqual(result["w"], 55.0)
        self.assertAlmostEqual(result["p"], 0.0059, places=3)

    def test_wilcoxon_handles_ties_and_zero_differences(self):
        result = stats.wilcoxon_signed_rank([1, 2, 2, 5, 5], [1, 1, 1, 1, 6])
        self.assertEqual(result["n"], 4)
        self.assertGreaterEqual(result["p"], 0.0)
        self.assertLessEqual(result["p"], 1.0)

    def test_bonferroni_caps_at_one(self):
        self.assertAlmostEqual(stats.bonferroni(0.02, 3), 0.06)
        self.assertEqual(stats.bonferroni(0.6, 3), 1.0)


class AnovaTests(unittest.TestCase):
    def test_two_conditions_equals_paired_t_squared(self):
        data = [[5.0, 4.0], [7.0, 5.5], [6.0, 5.8], [9.0, 6.0], [4.0, 4.5], [8.0, 6.1]]
        anova = stats.rm_anova(data)
        t = stats.paired_t([r[0] for r in data], [r[1] for r in data])
        self.assertAlmostEqual(anova["F"], t["t"] ** 2, places=8)
        self.assertAlmostEqual(anova["p"], t["p"], places=8)
        self.assertAlmostEqual(anova["epsilon_gg"], 1.0, places=9)
        self.assertAlmostEqual(anova["p_gg"], anova["p"], places=9)

    def test_clear_effect_is_significant_and_corrected_p_is_not_smaller(self):
        data = [[10 + s % 3, 14 + s % 2, 18 + (s * 7) % 3] for s in range(12)]
        anova = stats.rm_anova(data)
        self.assertLess(anova["p"], 0.001)
        self.assertGreaterEqual(anova["p_gg"], anova["p"])
        self.assertEqual((anova["df1"], anova["df2"]), (2, 22))
        self.assertTrue(0 < anova["partial_eta_sq"] <= 1)

    def test_no_effect_is_not_significant(self):
        data = [[5.0, 5.1, 4.9], [6.0, 5.9, 6.2], [7.0, 7.2, 6.8], [5.5, 5.4, 5.6]]
        self.assertGreater(stats.rm_anova(data)["p"], 0.05)


class DiagnosticTests(unittest.TestCase):
    def test_symmetric_data_has_zero_skew(self):
        result = stats.jarque_bera([1, 2, 3, 4, 5, 6, 7])
        self.assertAlmostEqual(result["skew"], 0.0, places=9)

    def test_skewed_data_has_positive_skew(self):
        self.assertGreater(stats.jarque_bera([1, 1, 1, 2, 2, 3, 20])["skew"], 1.0)

    def test_effect_size_labels(self):
        self.assertEqual([stats.cohen_label(d) for d in (0.1, 0.3, 0.6, -1.2)],
                         ["negligible", "small", "medium", "large"])


if __name__ == "__main__":
    unittest.main()
