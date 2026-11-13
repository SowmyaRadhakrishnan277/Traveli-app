"""Small, dependency-free statistics for within-subjects experiments (lectures L5/L6).

Implements exactly what the analysis needs: descriptives with 95% CIs, paired t-test with
Cohen's d_z, Wilcoxon signed-rank as a robustness check, repeated-measures ANOVA (with
Greenhouse-Geisser correction), a normality diagnostic, and Bonferroni correction.
Verified against published critical values in test_stats.py.
"""
import math
from typing import Dict, List, Sequence

INF = float("inf")


# --- descriptives ---------------------------------------------------------------------------

def mean(xs: Sequence[float]) -> float:
    return sum(xs) / len(xs)


def sd(xs: Sequence[float]) -> float:
    """Sample standard deviation (n - 1)."""
    if len(xs) < 2:
        return 0.0
    m = mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


# --- distributions --------------------------------------------------------------------------

def _betacf(a: float, b: float, x: float) -> float:
    """Continued fraction for the incomplete beta function (modified Lentz)."""
    tiny, eps = 1e-300, 3e-14
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    d = 1.0 / (d if abs(d) > tiny else tiny)
    h = d
    for m in range(1, 400):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < eps:
            break
    return h


def betainc(a: float, b: float, x: float) -> float:
    """Regularised incomplete beta function I_x(a, b)."""
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    front = math.exp(math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log(1.0 - x))
    if x < (a + 1.0) / (a + b + 2.0):
        return front * _betacf(a, b, x) / a
    return 1.0 - front * _betacf(b, a, 1.0 - x) / b


def t_two_sided_p(t: float, df: float) -> float:
    if math.isinf(t):
        return 0.0
    return betainc(df / 2.0, 0.5, df / (df + t * t))


def f_sf(f: float, d1: float, d2: float) -> float:
    """Upper-tail probability of the F distribution."""
    if math.isinf(f):
        return 0.0
    if f <= 0:
        return 1.0
    return betainc(d2 / 2.0, d1 / 2.0, d2 / (d2 + d1 * f))


def normal_cdf(z: float) -> float:
    return 0.5 * (1.0 + math.erf(z / math.sqrt(2.0)))


def t_critical(df: float, alpha: float = 0.05) -> float:
    """Two-sided critical t, by bisection on the p-value."""
    lo, hi = 0.0, 1000.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if t_two_sided_p(mid, df) > alpha:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def ci95(xs: Sequence[float]) -> List[float]:
    n = len(xs)
    m = mean(xs)
    if n < 2:
        return [m, m]
    half = t_critical(n - 1) * sd(xs) / math.sqrt(n)
    return [m - half, m + half]


# --- tests ----------------------------------------------------------------------------------

def paired_t(a: Sequence[float], b: Sequence[float]) -> Dict[str, float]:
    """Paired t-test of a vs b (within-subjects design). d_z = mean difference / SD of differences."""
    diffs = [x - y for x, y in zip(a, b)]
    n = len(diffs)
    if n < 2:
        raise ValueError("need at least 2 pairs")
    md, s = mean(diffs), sd(diffs)
    if s == 0:
        t = 0.0 if md == 0 else math.copysign(INF, md)
        dz = 0.0 if md == 0 else math.copysign(INF, md)
        return {"n": n, "df": n - 1, "t": t, "p": 1.0 if md == 0 else 0.0, "mean_diff": md, "sd_diff": 0.0, "d_z": dz}
    t = md / (s / math.sqrt(n))
    return {"n": n, "df": n - 1, "t": t, "p": t_two_sided_p(t, n - 1), "mean_diff": md, "sd_diff": s, "d_z": md / s}


def wilcoxon_signed_rank(a: Sequence[float], b: Sequence[float]) -> Dict[str, float]:
    """Wilcoxon signed-rank (normal approximation with tie and continuity corrections).

    Non-parametric robustness check for when normality is doubtful (small n, bounded ratios).
    """
    diffs = [x - y for x, y in zip(a, b) if x != y]
    n = len(diffs)
    if n == 0:
        return {"n": 0, "w": 0.0, "z": 0.0, "p": 1.0}
    ordered = sorted(range(n), key=lambda i: abs(diffs[i]))
    ranks = [0.0] * n
    tie_term = 0.0
    i = 0
    while i < n:
        j = i
        while j + 1 < n and abs(diffs[ordered[j + 1]]) == abs(diffs[ordered[i]]):
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            ranks[ordered[k]] = avg
        size = j - i + 1
        tie_term += size ** 3 - size
        i = j + 1
    w_plus = sum(r for r, d in zip(ranks, diffs) if d > 0)
    expected = n * (n + 1) / 4.0
    variance = n * (n + 1) * (2 * n + 1) / 24.0 - tie_term / 48.0
    if variance <= 0:
        return {"n": n, "w": w_plus, "z": 0.0, "p": 1.0}
    shift = abs(w_plus - expected) - 0.5
    z = math.copysign(max(shift, 0.0) / math.sqrt(variance), w_plus - expected)
    return {"n": n, "w": w_plus, "z": z, "p": min(1.0, 2.0 * (1.0 - normal_cdf(abs(z))))}


def jarque_bera(xs: Sequence[float]) -> Dict[str, float]:
    """Normality diagnostic (skewness and kurtosis). Indicative only for small n."""
    n = len(xs)
    m = mean(xs)
    m2 = sum((x - m) ** 2 for x in xs) / n
    if m2 == 0:
        return {"skew": 0.0, "excess_kurtosis": 0.0, "jb": 0.0, "p": 1.0}
    skew = (sum((x - m) ** 3 for x in xs) / n) / m2 ** 1.5
    kurt = (sum((x - m) ** 4 for x in xs) / n) / m2 ** 2 - 3.0
    jb = n / 6.0 * (skew ** 2 + kurt ** 2 / 4.0)
    return {"skew": skew, "excess_kurtosis": kurt, "jb": jb, "p": math.exp(-jb / 2.0)}


def rm_anova(data: Sequence[Sequence[float]]) -> Dict[str, float]:
    """One-way repeated-measures ANOVA. data[subject][condition].

    Reports the uncorrected p and the Greenhouse-Geisser corrected p (sphericity is rarely met).
    """
    n, k = len(data), len(data[0])
    if n < 2 or k < 2:
        raise ValueError("need at least 2 subjects and 2 conditions")
    grand = mean([x for row in data for x in row])
    cond = [mean([row[j] for row in data]) for j in range(k)]
    subj = [mean(row) for row in data]
    ss_cond = n * sum((c - grand) ** 2 for c in cond)
    ss_subj = k * sum((s - grand) ** 2 for s in subj)
    ss_total = sum((x - grand) ** 2 for row in data for x in row)
    ss_err = ss_total - ss_cond - ss_subj
    df1, df2 = k - 1, (k - 1) * (n - 1)
    if ss_err <= 1e-12:
        f = INF if ss_cond > 1e-12 else 0.0
    else:
        f = (ss_cond / df1) / (ss_err / df2)

    # Greenhouse-Geisser epsilon from the double-centred covariance matrix of the conditions.
    cov = [[sum((row[i] - cond[i]) * (row[j] - cond[j]) for row in data) / (n - 1) for j in range(k)] for i in range(k)]
    row_m = [mean(r) for r in cov]
    col_m = [mean([cov[i][j] for i in range(k)]) for j in range(k)]
    all_m = mean(row_m)
    centred = [[cov[i][j] - row_m[i] - col_m[j] + all_m for j in range(k)] for i in range(k)]
    denom = (k - 1) * sum(v * v for r in centred for v in r)
    eps = (sum(centred[i][i] for i in range(k)) ** 2 / denom) if denom > 1e-18 else 1.0
    eps = max(1.0 / (k - 1), min(1.0, eps))
    return {
        "n": n, "k": k, "df1": df1, "df2": df2, "F": f,
        "p": f_sf(f, df1, df2), "epsilon_gg": eps,
        "p_gg": f_sf(f, eps * df1, eps * df2),
        "partial_eta_sq": ss_cond / (ss_cond + ss_err) if (ss_cond + ss_err) > 0 else 0.0,
    }


def bonferroni(p: float, comparisons: int) -> float:
    return min(1.0, p * comparisons)


def cohen_label(d: float) -> str:
    """Conventional thresholds (Cohen): 0.2 small, 0.5 medium, 0.8 large."""
    a = abs(d)
    if a < 0.2:
        return "negligible"
    if a < 0.5:
        return "small"
    if a < 0.8:
        return "medium"
    return "large"
