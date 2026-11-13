#!/usr/bin/env python3
"""Analyse the prompt experiment (see EXPERIMENT.md).

    python3 Evaluation/analyze.py Evaluation/results/experiment.csv --out Evaluation/results

Unit of analysis is the destination (the "subject"): each destination is planned under every
prompt variant, and per-day values are averaged within a (destination, variant) trial so days of
one trip are not treated as independent observations.
"""
import argparse
import csv
import json
import math
import os
import sys
from collections import defaultdict
from itertools import combinations
from typing import Dict, List, Optional, Tuple

import stats as st

VARIANT_ORDER = ["baseline", "compact", "minimal"]
METRICS = [
    ("mean_leg_km", "Mean distance between stops (km)"),
    ("verified_rate", "Verified-place rate"),
    ("latency_s", "Latency per day (s)"),
    ("usable", "Usable-day rate"),
]
NON_INFERIORITY_MARGIN = -0.05   # verified-rate points
PRACTICAL_LEG_KM = 0.5           # smallest distance saving worth caring about
CONFIRMATORY_ALPHA = 0.05 / 2    # Bonferroni over the two confirmatory hypotheses

Trial = Dict[str, Optional[float]]


def fmt_p(p: float) -> str:
    return "< .001" if p < 0.001 else "= " + ("%.3f" % p).lstrip("0")


def num(x: float, places: int = 2) -> str:
    return "inf" if math.isinf(x) else ("%.*f" % (places, x))


def load(path: str) -> List[Dict[str, str]]:
    with open(path, newline="") as handle:
        return list(csv.DictReader(handle))


def to_float(value: str) -> Optional[float]:
    return float(value) if value not in ("", None) else None


def build_trials(rows: List[Dict[str, str]]) -> Tuple[Dict[Tuple[str, str], Trial], List[Tuple[str, str]]]:
    """Average days within each (destination, variant) trial. Trials with any failed map lookup are excluded."""
    grouped: Dict[Tuple[str, str], List[Dict[str, str]]] = defaultdict(list)
    for row in rows:
        grouped[(row["destination"], row["variant"])].append(row)
    trials: Dict[Tuple[str, str], Trial] = {}
    excluded: List[Tuple[str, str]] = []
    for key, days in grouped.items():
        if any(int(d["search_errors"]) > 0 for d in days):
            excluded.append(key)
            continue
        trial: Trial = {"region": days[0]["region"], "position": float(days[0]["position"])}  # type: ignore
        for metric, _ in METRICS:
            values = [v for v in (to_float(d[metric]) for d in days) if v is not None]
            trial[metric] = st.mean(values) if values else None
        trials[key] = trial
    return trials, sorted(excluded)


def paired_columns(trials, variants: List[str], metric: str) -> Tuple[List[str], List[List[float]]]:
    """Destinations that have a valid value for this metric under every variant (listwise deletion)."""
    destinations = sorted({d for d, _ in trials})
    kept, matrix = [], []
    for dest in destinations:
        values = [trials.get((dest, v), {}).get(metric) for v in variants]
        if all(v is not None for v in values):
            kept.append(dest)
            matrix.append(values)
    return kept, matrix


def diff_ci(a: List[float], b: List[float]) -> List[float]:
    diffs = [x - y for x, y in zip(a, b)]
    n, m, s = len(diffs), st.mean(diffs), st.sd(diffs)
    half = st.t_critical(n - 1) * s / math.sqrt(n)
    return [m - half, m + half]


def describe(matrix: List[List[float]], variants: List[str]) -> List[Dict[str, object]]:
    out = []
    for j, variant in enumerate(variants):
        col = [row[j] for row in matrix]
        lo, hi = st.ci95(col)
        out.append({"variant": variant, "n": len(col), "mean": st.mean(col), "sd": st.sd(col), "ci_low": lo, "ci_high": hi})
    return out


def t_line(result: Dict[str, float]) -> str:
    return "t(%d) = %s, p %s, d_z = %s (%s)" % (
        result["df"], num(result["t"]), fmt_p(result["p"]), num(result["d_z"]), st.cohen_label(result["d_z"]))


def svg_bars(title: str, descriptives: List[Dict[str, object]], unit: str) -> str:
    width, height, left, bottom, top = 520, 300, 60, 50, 40
    ymax = max(float(d["ci_high"]) for d in descriptives) * 1.15 or 1.0
    plot_h = height - bottom - top
    bar_w = (width - left - 20) / (len(descriptives) * 1.6)
    colors = ["#64748b", "#0f766e", "#b45309"]
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" font-family="-apple-system,Helvetica,Arial,sans-serif" font-size="12">' % (width, height),
             '<rect width="100%" height="100%" fill="white"/>',
             '<text x="%d" y="22" font-size="14" font-weight="600">%s</text>' % (left, title)]
    for tick in range(0, 5):
        value = ymax * tick / 4
        y = top + plot_h - plot_h * tick / 4
        parts.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#e2e8f0"/>' % (left, width - 10, y, y))
        parts.append('<text x="%d" y="%.1f" text-anchor="end" fill="#475569">%.2f</text>' % (left - 6, y + 4, value))
    for i, d in enumerate(descriptives):
        x = left + 20 + i * bar_w * 1.6
        h = plot_h * float(d["mean"]) / ymax
        y = top + plot_h - h
        cx = x + bar_w / 2
        lo = top + plot_h - plot_h * float(d["ci_low"]) / ymax
        hi = top + plot_h - plot_h * float(d["ci_high"]) / ymax
        parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (x, y, bar_w, h, colors[i % len(colors)]))
        parts.append('<line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="#0f172a" stroke-width="1.5"/>' % (cx, cx, lo, hi))
        parts.append('<line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="#0f172a" stroke-width="1.5"/>' % (cx - 5, cx + 5, hi, hi))
        parts.append('<line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="#0f172a" stroke-width="1.5"/>' % (cx - 5, cx + 5, lo, lo))
        parts.append('<text x="%.1f" y="%d" text-anchor="middle" fill="#0f172a">%s</text>' % (cx, height - 28, d["variant"]))
        parts.append('<text x="%.1f" y="%.1f" text-anchor="middle" fill="#0f172a" font-weight="600">%.2f</text>' % (cx, max(hi - 6, 34), float(d["mean"])))
    parts.append('<text x="%d" y="%d" fill="#475569">Mean with 95%% CI (%s), n = %d destinations</text>' % (left, height - 8, unit, descriptives[0]["n"]))
    parts.append("</svg>")
    return "\n".join(parts)


def analyse(rows: List[Dict[str, str]], out_dir: str) -> str:
    trials, excluded = build_trials(rows)
    present = {v for _, v in trials}
    variants = [v for v in VARIANT_ORDER if v in present] + sorted(present - set(VARIANT_ORDER))
    summary: Dict[str, object] = {"variants": variants, "excluded_trials": [list(k) for k in excluded]}
    lines: List[str] = []
    add = lines.append

    destinations_all = sorted({r["destination"] for r in rows})
    add("# Prompt experiment results\n")
    add("Generated by `Evaluation/analyze.py`. Design and hypotheses: [`EXPERIMENT.md`](../EXPERIMENT.md).\n")
    add("- Destinations planned: %d, prompt variants: %s, day-rows: %d" % (len(destinations_all), ", ".join(variants), len(rows)))
    add("- Trials excluded because a map lookup failed (infrastructure, not model, error): %d" % len(excluded))
    for dest, variant in excluded:
        add("  - %s / %s" % (dest, variant))
    add("")

    # ---- descriptives + omnibus + pairwise ------------------------------------------------
    metric_results: Dict[str, Dict[str, object]] = {}
    for metric, label in METRICS:
        kept, matrix = paired_columns(trials, variants, metric)
        add("## %s\n" % label)
        if len(kept) < 3:
            add("Not enough complete destinations (n = %d) to analyse.\n" % len(kept))
            continue
        desc = describe(matrix, variants)
        add("n = %d destinations with complete data.\n" % len(kept))
        add("| Variant | Mean | SD | 95% CI |")
        add("|---|---|---|---|")
        for d in desc:
            add("| %s | %s | %s | [%s, %s] |" % (d["variant"], num(float(d["mean"]), 3), num(float(d["sd"]), 3), num(float(d["ci_low"]), 3), num(float(d["ci_high"]), 3)))
        add("")
        entry: Dict[str, object] = {"n": len(kept), "descriptives": desc, "pairwise": []}
        if len(variants) >= 3:
            anova = st.rm_anova(matrix)
            add("Repeated-measures ANOVA: F(%d, %d) = %s, p %s; Greenhouse-Geisser (epsilon = %s) p %s; partial eta^2 = %s.\n" % (
                anova["df1"], anova["df2"], num(anova["F"]), fmt_p(anova["p"]), num(anova["epsilon_gg"]), fmt_p(anova["p_gg"]), num(anova["partial_eta_sq"])))
            entry["anova"] = anova
        pairs = list(combinations(range(len(variants)), 2))
        add("| Comparison | Mean diff | Paired t-test | p (Bonferroni x%d) | Wilcoxon p |" % len(pairs))
        add("|---|---|---|---|---|")
        for i, j in pairs:
            a, b = [r[i] for r in matrix], [r[j] for r in matrix]
            t = st.paired_t(a, b)
            w = st.wilcoxon_signed_rank(a, b)
            adj = st.bonferroni(t["p"], len(pairs))
            add("| %s vs %s | %s | %s | %s | %s |" % (variants[i], variants[j], num(t["mean_diff"], 3), t_line(t), fmt_p(adj).replace("= ", ""), fmt_p(w["p"]).replace("= ", "")))
            entry["pairwise"].append({"a": variants[i], "b": variants[j], **t, "p_bonferroni": adj, "wilcoxon_p": w["p"]})  # type: ignore
        norm = st.jarque_bera([x - y for x, y in zip([r[0] for r in matrix], [r[1] for r in matrix])])
        add("\nNormality check on %s-vs-%s differences: skew = %s, excess kurtosis = %s (Jarque-Bera p %s; indicative at this n)." % (variants[0], variants[1], num(norm["skew"]), num(norm["excess_kurtosis"]), fmt_p(norm["p"])))
        add("")
        metric_results[metric] = entry
        summary[metric] = entry
        if metric in ("mean_leg_km", "verified_rate"):
            with open(os.path.join(out_dir, "chart_%s.svg" % metric), "w") as handle:
                handle.write(svg_bars(label, desc, "destination means"))

    # ---- confirmatory hypotheses ----------------------------------------------------------
    add("## Confirmatory hypotheses (alpha = %.3f each, Bonferroni over 2)\n" % CONFIRMATORY_ALPHA)
    verdicts: Dict[str, str] = {}
    if "baseline" in variants and "compact" in variants:
        kept, m = paired_columns(trials, ["compact", "baseline"], "mean_leg_km")
        if len(kept) >= 3:
            a, b = [r[0] for r in m], [r[1] for r in m]
            t = st.paired_t(a, b)
            w = st.wilcoxon_signed_rank(a, b)
            lo, hi = diff_ci(a, b)
            if t["p"] < CONFIRMATORY_ALPHA and t["mean_diff"] < 0:
                verdict = "SUPPORTED: compact days are shorter by %s km (a practically important saving)." % num(-t["mean_diff"], 2) if -t["mean_diff"] >= PRACTICAL_LEG_KM else \
                    "Statistically significant, but the saving (%s km) is below the %.1f km practical threshold: not important." % (num(-t["mean_diff"], 2), PRACTICAL_LEG_KM)
            elif t["p"] < CONFIRMATORY_ALPHA:
                verdict = "CONTRADICTED: compact days were longer."
            else:
                verdict = "NOT SUPPORTED: no reliable difference at this sample size."
            add("**H1 (primary).** The compact prompt shortens the mean distance between stops compared with baseline (n = %d).\n" % len(kept))
            add("- compact - baseline = %s km, 95%% CI [%s, %s]; %s; Wilcoxon p %s" % (num(t["mean_diff"], 3), num(lo, 3), num(hi, 3), t_line(t), fmt_p(w["p"])))
            add("- **%s**\n" % verdict)
            verdicts["H1"] = verdict
        kept, m = paired_columns(trials, ["compact", "baseline"], "verified_rate")
        if len(kept) >= 3:
            a, b = [r[0] for r in m], [r[1] for r in m]
            t = st.paired_t(a, b)
            lo, hi = diff_ci(a, b)
            verdict = ("NON-INFERIORITY SHOWN: the lower CI bound (%s) is above the %.2f margin." if lo > NON_INFERIORITY_MARGIN else
                       "NON-INFERIORITY NOT SHOWN: the lower CI bound (%s) is not above the %.2f margin.") % (num(lo, 3), NON_INFERIORITY_MARGIN)
            add("**H2 (guardrail).** The compact prompt does not reduce the verified-place rate by more than 0.05 (n = %d).\n" % len(kept))
            add("- compact - baseline = %s, 95%% CI [%s, %s]; %s" % (num(t["mean_diff"], 3), num(lo, 3), num(hi, 3), t_line(t)))
            add("- **%s**\n" % verdict)
            verdicts["H2"] = verdict
    summary["verdicts"] = verdicts

    # ---- order effects and regions --------------------------------------------------------
    add("## Order check (counterbalancing)\n")
    add("Mean by position within a destination's order; large differences would suggest order effects.\n")
    add("| Position | Trials | Latency (s) | Verified rate | Mean leg (km) |")
    add("|---|---|---|---|---|")
    for position in (1.0, 2.0, 3.0):
        group = [t for t in trials.values() if t["position"] == position]
        if group:
            def col(key):
                vals = [t[key] for t in group if t[key] is not None]
                return num(st.mean(vals), 3) if vals else "-"
            add("| %d | %d | %s | %s | %s |" % (position, len(group), col("latency_s"), col("verified_rate"), col("mean_leg_km")))
    add("")

    add("## By region (exploratory; small n per cell)\n")
    regions = sorted({t["region"] for t in trials.values()})
    add("| Region | Destinations | " + " | ".join("%s verified / leg km" % v for v in variants) + " |")
    add("|---|---|" + "---|" * len(variants))
    for region in regions:
        dests = sorted({d for (d, _), t in trials.items() if t["region"] == region})
        cells = []
        for v in variants:
            group = [trials[(d, v)] for d in dests if (d, v) in trials]
            vr = [t["verified_rate"] for t in group if t["verified_rate"] is not None]
            lg = [t["mean_leg_km"] for t in group if t["mean_leg_km"] is not None]
            cells.append("%s / %s" % (num(st.mean(vr), 2) if vr else "-", num(st.mean(lg), 2) if lg else "-"))
        add("| %s | %d | %s |" % (region, len(dests), " | ".join(cells)))
    add("")

    add("## Threats to validity\n")
    add("- **External validity:** destinations are a convenience sample of 20 cities; one device, one OS and one on-device model version. Results describe this model, not language models in general.")
    add("- **Ceiling effects:** verified rate may sit near 100%, leaving little room to differ; that is why it is a guardrail rather than the primary outcome.")
    add("- **Distance is a proxy:** straight-line distance between stops is not travel time and says nothing about whether the plan is pleasant or safe.")
    add("- **Map coverage:** a place that exists but is missing from Apple Maps counts as 'not found', which may penalise less-mapped regions.")
    add("")

    with open(os.path.join(out_dir, "summary.json"), "w") as handle:
        json.dump(summary, handle, indent=2, default=str)
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv")
    parser.add_argument("--out", default=".", help="directory for report.md, summary.json and charts")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    report = analyse(load(args.csv), args.out)
    with open(os.path.join(args.out, "report.md"), "w") as handle:
        handle.write(report + "\n")
    print(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
