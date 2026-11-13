# Prompt experiment: does an explicit distance constraint make AI itineraries more compact?

Applies lectures L5 (experimental design) and L6 (statistics for HCAI) to Traveli's AI itinerary feature.

## Research question

Traveli's AI planner is told to "keep each day geographically compact". Does making that constraint
explicit and measurable ("within about 3 km of each other") change how far apart the stops of a day are,
without making the model suggest more places that do not exist?

*(Weak questions like "is the new prompt any good?" are not testable; this one names the outcome, the
comparison and the threshold.)*

## Hypotheses

| | Statement | Decision rule |
|---|---|---|
| **H1 (primary, confirmatory)** | The *compact* prompt gives a shorter mean distance between consecutive stops than the *baseline* prompt. | Paired t-test, two-sided, alpha = .025. Counts as **important** only if the saving is at least **0.5 km**. |
| **H2 (guardrail, confirmatory)** | The *compact* prompt does not lower the verified-place rate by more than 0.05 compared with baseline. | Non-inferiority: the lower bound of the 95% CI of (compact − baseline) must be above −0.05. |
| Exploratory | *Minimal* prompt (ablation) vs baseline; latency; usable-day rate; order effects; region differences. | Reported with Bonferroni-corrected p-values; no claims. |

Both hypotheses are falsifiable and operationalised. Alpha is .05 split over the two confirmatory
hypotheses (Bonferroni).

### Deviation disclosed: a pilot informed the hypotheses

Before writing this document I ran a pilot (2 destinations, 1 day, 3 prompts) only to check that the
pipeline worked. All six pilot days had a verified-place rate of 100%, a **ceiling effect**. A ceiling
makes verified rate useless as a primary outcome, so I made distance the primary outcome (H1) and kept
verified rate as a guardrail (H2). The pilot data are not part of the analysis. Anyone judging the results
should know the hypotheses were not fixed completely blind.

### Deviation disclosed: an aborted first run

A first full run was aborted after about five trials because MapKit throttled searches (about 50 per
minute) and every later trial failed its destination lookup. No data from it were used. Fixes before the
real run: a rate limiter with retry on throttling, a cache for the destination-centre lookup (the same city
is looked up once per prompt), and latency measured on the model call only so waiting on the rate limiter
cannot distort it. None of these depend on the outcome of any hypothesis test.

## Variables

| Role | Variable | Type | Levels / unit |
|---|---|---|---|
| Independent | Prompt variant | nominal | `baseline`, `compact`, `minimal` (see `PromptVariant.swift`) |
| Dependent (H1) | Mean distance between consecutive stops | ratio | km, straight line |
| Dependent (H2) | Verified-place rate | ratio | verified ÷ suggested, 0–1 |
| Dependent (exploratory) | Latency per day | ratio | seconds, model call only (map lookups excluded: they depend on network and rate limits, not the prompt) |
| Dependent (exploratory) | Usable-day rate | ratio | share of days with ≥ 2 verified stops |
| Control | Device, OS, model version, trip length (3 days), dates, no preferences text, fresh model session per day | | held constant |
| Random | Destination | | 20 cities (the "subjects") |
| Confounder guarded against | Order of conditions (warm-up, throttling) | | counterbalanced, see below |

All dependent variables are ratio data, so parametric tests are appropriate if the differences are roughly
normal. A Jarque-Bera diagnostic and a Wilcoxon signed-rank test are reported as robustness checks.

## Design

- **Within-subjects**: every destination is planned under all three prompts. This removes the large
  destination-to-destination variation (Tokyo vs Reykjavik) from the comparison and gives more power with
  20 subjects than a between-subjects design would.
- **Counterbalancing**: a cyclic Latin square (`LatinSquare` in `ExperimentRunner.swift`) rotates the
  order of prompts per destination, so each prompt appears in each position equally often. The
  transfer-effect risk here is small (a new model session per day, no memory), but warm-up and rate limiting
  can still create order effects; the report prints means per position to check.
- **Unit of analysis**: the destination. Days of one trip are averaged first, so correlated days are not
  counted as independent observations (pseudo-replication).
- **Destinations**: 20 cities across Europe, Asia, the Americas, Africa and Oceania, chosen to cover regions
  rather than only well-mapped tourist cities (this also seeds the fairness audit of lecture L13).
- **Sample size**: n = 20 destinations is a practical limit (about 15 minutes of model time), not a power
  calculation; with n = 20 the test can reliably detect roughly d_z ≥ 0.65.

## Analysis plan

1. Per-trial values; trials with any failed map lookup are **excluded** (a throttled search is not evidence
   that the model invented a place).
2. Descriptives per prompt: mean, SD, 95% CI (t-based).
3. Omnibus repeated-measures ANOVA across the three prompts with Greenhouse-Geisser correction (sphericity
   is rarely met).
4. Pairwise paired t-tests, Cohen's d_z as effect size, Bonferroni correction for the three comparisons.
5. Confirmatory decisions exactly as in the hypotheses table. **Significant is not the same as important**,
   so H1 also needs the 0.5 km practical threshold.
6. Report in the lecture's format, e.g. `t(19) = −3.45, p = .003, d_z = −0.77 (medium)`.

Statistics are implemented in `stats.py` (no dependencies) and checked against published critical values in
`test_stats.py`.

## Threats to validity

- **Internal**: order effects (counterbalanced); throttling (excluded and counted); prompt wording differs
  in more than one way between variants, so a difference shows *the prompt* matters, not *which sentence*.
- **External**: one on-device model version on one device, 20 cities. Results do not generalise to other
  models. The model is probabilistic, so a single run per cell adds noise; the within-subjects design and CI
  make that noise visible rather than hiding it.
- **Construct**: straight-line distance is a proxy for "compact". It ignores rivers, hills and transit. It
  also says nothing about whether a plan is enjoyable or safe.
- **Measurement**: a real place missing from Apple Maps counts as "not found", which can penalise
  less-mapped regions (examined in the by-region table).

## Ethics and privacy

No participants and no personal data. Everything runs on the researcher's own device with Apple's
on-device model; the only network use is Apple Maps place lookups with place names.

## Reproduce

```bash
# 1. Run the experiment (slow, ~15 min; needs Apple Intelligence in the simulator or on a device)
TEST_RUNNER_TRAVELI_RUN_EXPERIMENT=1 \
TEST_RUNNER_TRAVELI_EXPERIMENT_OUT=$PWD/Evaluation/results/experiment.csv \
TEST_RUNNER_TRAVELI_EXPERIMENT_DESTINATIONS=20 TEST_RUNNER_TRAVELI_EXPERIMENT_DAYS=3 \
xcodebuild test -project Traveli.xcodeproj -scheme Traveli \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:TraveliTests/PromptExperimentTests -test-timeouts-enabled NO

# 2. Analyse
python3 Evaluation/analyze.py Evaluation/results/experiment.csv --out Evaluation/results

# 3. Check the statistics code
python3 -m unittest discover -s Evaluation -p "test_*.py"
```

Results: [`results/report.md`](results/report.md).
