# Canary Missions — ATLAS Evaluation Dataset

> A small, hand-curated set of missions with known-good answers. Used to
> regression-test an ATLAS implementation across model swaps and harness
> changes. 15 missions; pass rate target ≥ 80%.

Each mission ships with:

- `mission.md` (the input)
- `expected/answer.md` (the known-good answer to `DECISION_TARGET`)
- `expected/findings.min` (minimum FINDING-IDs that a correct run must produce)
- `expected/handoff.yaml` (expected primary recipient label)

Scoring is **binary per mission** on three criteria:

1. `DECISION_TARGET` answer matches `expected/answer.md` on its enumerable
   claims (exact match of listed files/symbols/paths).
2. All `expected/findings.min` IDs have a counterpart finding (by content,
   not by ID number) in the run's `findings.md`.
3. `handoff.primary_recipient` matches.

A mission passes only if all three criteria pass.

---

## Mission catalog (reference)

| ID | Domain | Difficulty | Skills exercised |
|----|--------|------------|-----------------|
| C-01 | Single-file symbol trace | easy | search_symbol, windowed read |
| C-02 | Route → controller → flow chain | easy | graph_query, AST |
| C-03 | Find all writers to a specific DB table | medium | graph_query (writers_to) |
| C-04 | Authorization policy audit across N endpoints | medium | scatter subagents |
| C-05 | Identify untested public API | medium | graph + test dry-run |
| C-06 | Deprecated symbol usage sweep | easy | search_symbol + ruled_out |
| C-07 | Cross-module dependency cycle detection | hard | graph_query |
| C-08 | Background-job retry policy inventory | medium | grep scoped to workers/ |
| C-09 | Feature-flag coverage for a rollout | medium | text search + graph |
| C-10 | Migration impact assessment (no apply) | hard | graph + heatmap |
| C-11 | PII handling path trace | hard | scatter, escalation triggers |
| C-12 | Identify all code paths that bypass authorization | hard | negative results critical |
| C-13 | N+1 query discovery via static patterns | medium | AST pattern |
| C-14 | Circular import detection across packages | hard | graph, multi-language |
| C-15 | Event-handler fan-out mapping | medium | graph + heatmap |

---

## Metrics collected per run

```
mission_id:        <id>
status:            pass | fail
decision_correct:  bool
findings_recall:   float   # |expected ∩ actual| / |expected|
handoff_correct:   bool
tokens_total:      int
tool_calls_total:  int
wall_clock_s:      int
fold_ratio:        float   # Abstract phase
η:                 float   # search efficiency
failure_class:     NONE | UNDER_SCOPED | OVER_EXPLORED | DEAD_END |
                   HALLUCINATED_ANCHOR | FOLD_DROPPED_CONSTRAINT | HANDOFF_MISLABEL
```

---

## CI gate

Recommended: run the canary suite on every change to `ATLAS.md`, any skill
file, or any template. Fail the PR if:

- Aggregate pass rate drops below last merged main by ≥ 10%.
- Any previously passing mission regresses to fail.
- Mean `fold_ratio` rises above 0.15 (Abstract phase is under-compressing).
- Mean `η` drops below 0.20 (Locate phase is inefficient).

---

## Authoring new canaries

Good canary missions share these properties:

- `DECISION_TARGET` is a finite, enumerable question ("list all X that do Y").
- Ground truth is stable across reasonable code refactors (anchor on
  behavior, not on line numbers).
- Exercises exactly one or two ATLAS skills — isolates the signal.
- At least 3 canaries should include at least one intentional `GAP`
  (un-answerable within scope) so the agent's honesty is tested.
- At least 2 canaries should have `expected/handoff.primary_recipient: human`
  to verify the agent doesn't silently hand a safety-sensitive question to an
  automated downstream.

**Anti-pattern canaries to avoid:** trivia about repo history, questions
whose answers require running the full app, or questions whose correctness
depends on model-specific stylistic choices.
