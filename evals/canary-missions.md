# Canary Missions — ATLAS

> v1.13.0 DSL-format missions for `eidolons canary atlas`. The full 15-mission
> regression battery (C-01..C-15) is preserved below as historical reference
> and will be ported to DSL form in a follow-up wave.

---

## Mission: smoke-default

### Prompt

You are the ATLAS exploration agent. A task arrives:

> Trace where the function `User.normalize_email/1` is defined and every call site that invokes it. The codebase is a typical Phoenix application. You have never seen this project before.

Walk through the ATLAS cycle (Abstract → Traverse → Locate → Abstract → Synthesize) at the outline level. Do NOT execute tools or read files — describe what each phase produces, what skills you would invoke, and what artefacts the Synthesize phase emits. Conclude with a Scout Report sketch including a `DECISION_TARGET` answer and at least one `FINDING-` entry.

### Expected output shape

A markdown response that walks the ATLAS cycle phase by phase. Each phase has a heading. The Synthesize phase produces a Scout Report sketch with: a one-line `DECISION_TARGET` answer (file paths or symbol references), one or more `FINDING-<n>` entries with anchors, an explicit `GAP` marker for anything the agent could not answer in scope, and a handoff label naming the primary recipient. The response references the methodology's skill files (abstract / locate / synthesize) by name.

### Validation criteria

- MUST contain heading: `## Mission Brief`
- MUST contain phrase: `FINDING-`
- MUST contain phrase: `DECISION_TARGET`
- MUST mention paths: `skills/abstract.md`, `skills/locate.md`, `skills/synthesize.md`
- SHOULD contain phrase: `GAP`
- SHOULD contain phrase: `handoff`
- SHOULD have token count between 800 and 3000

---

## Mission: memory-round-trip

### Prompt

You are the ATLAS exploration agent with CRYSTALIUM installed and a prior
crystal already stored (layer: episodic, author_agent: atlas, content:
"RecordVote flow stores results in cast_vote_records via synchronous
FlowObject — no background job path — FINDING-009 from ATLAS mission
ATLAS-038"). A new task arrives:

> Trace all callers of `RecordVote#call` and confirm whether any async
> path exists. The codebase is a typical Rails application.

Walk through the ATLAS memory integration: what recall call fires at mission
intake (Phase A), what prior crystal it should surface, what the ingest call
looks like after the scout-report envelope is emitted (Phase S), and what the
session_end call closes. Then describe what happens when CRYSTALIUM is absent.
Do NOT execute tools — describe the memory calls, their parameters, and their
expected outcomes at each hook.

### Expected output shape

A markdown response covering four sections: (1) Phase A recall call with
parameters and expected hit (the prior crystal about RecordVote), (2) how the
prior crystal influences the mission (what the agent does differently), (3)
Phase S ingest call with envelope + payload parameters confirming
`author_agent=atlas` and T1 tier, followed by `session_end`, (4) graceful-skip
behavior when CRYSTALIUM is absent (mission completes normally, no hard-fail).

### Validation criteria

- MUST contain phrase: `mcp__crystalium__recall`
- MUST contain phrase: `mcp__crystalium__ingest`
- MUST contain phrase: `mcp__crystalium__session_end`
- MUST contain phrase: `author_agent`
- MUST contain phrase: `"atlas"`
- MUST contain phrase: `graceful` OR `unavailable` OR `absent`
- MUST contain phrase: `T1`
- SHOULD contain phrase: `from.eidolon`
- SHOULD contain phrase: `episodic`
- SHOULD contain phrase: `session_end`

---

## Mission: scatter-gather

### Prompt

You are the ATLAS exploration agent. A task arrives against a large monorepo
whose `map.md` reports 9 modules and ~140 files in scope:

> Audit the authorization path of every public HTTP endpoint AND, independently,
> trace every writer to the `audit_log` table. These are two unrelated concerns
> spread across different modules.

The surface exceeds 5 modules and 25 files, and the mission has two
topologically-disjoint sub-questions. Decide whether to escalate to the
Scatter-Gather Locate sub-mode and, if so, walk through its mechanics. Do NOT
execute tools — describe the activation check, the fan-out plan, each
sub-mission's shape, and how the branch findings are merged back. Conclude with
a one-line note on what would have kept you in serial Locate instead.

### Expected output shape

A markdown response that (1) checks the both-flags activation trigger against
the stated surface size and disjoint sub-questions, (2) derives a bounded
fan-out plan capped at 5 branches with per-branch budgets, (3) describes each
branch as a clean-context subagent returning exactly one structured object with
no transcript, (4) describes the merge+dedup contract including the `[DISPUTED]`
behavior on contradiction and the flow into the existing Phase A fold, and (5)
states an explicit when-NOT-to-scatter condition. References the methodology's
skill file by name.

### Validation criteria

- MUST contain phrase: `Scatter-Gather` OR `scatter`
- MUST contain phrase: `both-flags` OR `both flags`
- MUST mention paths: `skills/scatter.md`
- MUST contain phrase: `5 branches` OR `5-branch` OR `cap`
- MUST contain phrase: `no transcript` OR `one structured` OR `Operator`
- MUST contain phrase: `DISPUTED` OR `dedup`
- MUST contain phrase: `TRANCE` OR `gated` OR `not default`
- SHOULD contain phrase: `clean-context` OR `clean context`
- SHOULD contain phrase: `serial` OR `when NOT to scatter`
- SHOULD have token count between 800 and 3000

---

## Mission: delta-rescout

### Prompt

You are the ATLAS exploration agent. A prior scout-report.md already exists for
this surface (recorded at commit `abc1234`), with its Memex excerpt store
intact, and several findings such as:

> FINDING-014 (H): `RecordVote#call` is the sole writer to `cast_vote_records`
> — app/flows/vote_casting/record_vote.rb:42-78.

The code has since advanced to `HEAD`. A task arrives:

> Re-establish currency of the prior scout against HEAD without re-running the
> full mission.

Walk through the delta re-scout (incremental mode): how you compute the changed
surface, which Phase you re-run and over what scope, how you decide a prior
finding is stale, what you re-probe, what you carry forward verbatim, and how
the delta report labels each finding. Do NOT execute tools. Be explicit that
this NARROWS but does not CLOSE the always-on-live-index gap.

### Expected output shape

A markdown response covering: (1) the changed-surface computation
(`git diff` intersected with the prior `MAP-MODULES`), (2) Phase T re-run over
the changed surface ONLY, (3) the stale-by-anchor-intersection rule, (4)
re-probe of stale findings and verbatim carry-forward of unchanged ones from
Memex with provenance preserved, (5) the per-finding delta labels FRESH /
UNCHANGED / RE-VERIFIED / NEWLY-STALE with originating commit, and (6) an
explicit honest-scope statement that the delta narrows (does not close) the
live-index gap. References the methodology's skill file by name.

### Validation criteria

- MUST contain phrase: `delta` OR `re-scout` OR `rescout`
- MUST mention paths: `skills/rescout.md`
- MUST contain phrase: `git diff` OR `changed surface` OR `CHANGED-SURFACE`
- MUST contain phrase: `STALE` OR `stale`
- MUST contain phrase: `verbatim` OR `carry forward` OR `carried forward`
- MUST contain phrase: `FRESH` OR `UNCHANGED` OR `RE-VERIFIED` OR `NEWLY-STALE`
- MUST contain phrase: `narrow` OR `does not close` OR `not close`
- SHOULD contain phrase: `Memex`
- SHOULD contain phrase: `provenance`
- SHOULD contain phrase: `live-index` OR `live index` OR `always-on`
- SHOULD have token count between 800 and 3000

---

## Legacy mission catalog (pre-DSL)

> The 15-mission battery below predates the v1.13.0 DSL. It is kept here as a
> reference for the eventual full port. The v1.13.0 validator parses only the
> `## Mission: <id>` blocks above this divider.

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

Recommended: run the canary suite on every change to `SPEC.md`, any skill
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
