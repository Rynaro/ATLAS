# ATLAS Design Rationale

This document maps each ATLAS architectural decision to the research or
engineering constraint that motivated it. It is a companion to `ATLAS.md`
(the authoritative spec) and `CHANGELOG.md` (release history).

---

## I-1 — Read-only tool surface

**Decision:** The ACI exposes only `view_file`, `search_symbol`, `search_text`,
`list_dir`, `graph_query`, `test_dry_run`, `memex_read`. No `edit`, `write`,
`shell.write`, or `git.commit`.

**Rationale:** ATLAS is positioned upstream of mutation agents (SPECTRA, APIVR-Δ).
Allowing writes — even "safe" ones like saving notes — creates two risks: (1)
accidental codebase mutation under long-horizon context rot, and (2) scope
creep that pulls the scout into implementation. A hard harness-level read-only
surface survives model swaps and prompt injection; a model-level instruction
does not.

**Source:** `ATLAS.md §1`, `tools/bounded-aci-spec.md`

---

## I-2 — Bounded ACI (≤100 / ≤50 / ≤200)

**Decision:** `view_file` ≤100 lines; `search_text` ≤50 matches; `list_dir`
≤200 entries. Overflow returns a pagination cursor, never a silently truncated result.

**Rationale:** Unbounded reads are the primary cause of context saturation in
long-horizon explorer agents. The SWE-agent and Claude Code Plan Mode
literatures both show that large file dumps flood the context window and
degrade downstream reasoning quality. The specific numbers (100 / 50 / 200)
are empirically derived from the canary-mission evaluation set: they admit
the 95th-percentile task without overflow while keeping single-call token
cost predictable.

**Source:** `ATLAS.md §1 I-2`, `tools/bounded-aci-spec.md §2`

---

## I-3 — 90/10 deterministic/probabilistic

**Decision:** Symbol lookup → AST/Tree-sitter → `rg` → directory walk before
any LLM-authored search. LLM inference is the synthesis layer, not the
retrieval layer.

**Rationale:** Deterministic tools (symbol indexes, AST parsers, ripgrep)
have O(1) token cost for retrieval and produce exact results. LLM-authored
search is expensive and probabilistically correct at best. The 90/10 split
targets a search-efficiency ratio η ≥ 0.25 (relevant-tokens ÷ total-tokens)
which is difficult to achieve if the model is generating queries rather than
executing structured lookups.

**Source:** `ATLAS.md §1 I-3`, `evals/canary-missions.md §5`

---

## I-4 — Operator pattern (subagents return one FINDING)

**Decision:** When ≥2 independent sub-questions exist, scatter to ephemeral
subagents. Each returns exactly one structured `FINDING` object. Raw
transcripts never merge into the parent context.

**Rationale:** Merging raw subagent transcripts into the parent context
defeats the purpose of spawning subagents — it imports all their token cost
and noise. The structured `FINDING` format (path anchor + confidence tier +
one-paragraph claim) is the minimal sufficient unit for the parent to reason
about. Keeping transcripts separate also enables per-FINDING confidence
assessment without entanglement.

**Source:** `ATLAS.md §1 I-4`, `skills/locate/SKILL.md §3`

---

## I-5 — AgentFold at phase boundaries

**Decision:** At every A→T, T→L, L→A, A→S transition, fold the trajectory.
Raw excerpts go to Memex (SHA-256 keyed content-addressable store); working
memory keeps only IDs + anchors + confidence tiers (target ≤2000 tokens).

**Rationale:** AgentFold is the primary mechanism for managing context growth
under long-horizon missions. Without it, the working context accumulates all
raw excerpts from previous phases and saturates before Synthesize runs. The
Memex pattern (store-once, reference-by-ID) enables lossless compression:
the model can re-fetch any excerpt by ID without keeping it in hot context.
The ≤2000 token working-memory target is chosen so the always-loaded profile
(agent.md ≤1000 tokens) + working memory (≤2000 tokens) + active skill
(≤200 tokens) fit comfortably within a 4k always-loaded slot.

**Source:** `ATLAS.md §1 I-5`, `skills/abstract/SKILL.md`

---

## I-6 — Telemetry-driven compaction (60% / 85% thresholds)

**Decision:** At `context_used_pct ≥ 60%` trigger an async fold immediately.
At `context_used_pct ≥ 85%` halt and force a checkpoint.

**Rationale:** Proactive compaction at 60% allows one full phase to run
after the fold trigger before hitting the 85% hard stop. Waiting until 85%
to start folding leaves insufficient headroom for the fold itself to
complete. The 15-point gap (60→85) is calibrated on the canary mission set:
the median phase produces ~2000 tokens of new context; 15% of a 32k context
window is ~4800 tokens, which is sufficient for two median phases plus the
fold overhead.

**Source:** `ATLAS.md §1 I-6`, `agent.md §Telemetry`

---

## I-7 — Evidence-anchored claims

**Decision:** Every factual statement in every artifact carries
`path:line_start-line_end` + confidence tier `H|M|L`. Unanchored claims fail
schema validation.

**Rationale:** Unanchored claims are the primary source of hallucination in
code-exploration agents. When a claim carries a `path:line` anchor, the
downstream agent (SPECTRA or APIVR-Δ) can re-read the source and verify
independently. The three confidence tiers (`H` = directly observed, `M` =
short inference, `L` = plausible but unanchored) give the downstream agent
a signal to weight claims accordingly. Schema validation of anchors makes
this a mechanical check, not a model-level request.

**Source:** `ATLAS.md §1 I-7`, `schemas/scout-report.v1.json`

---

## I-8 — Explicit stop conditions

**Decision:** ATLAS halts when the `DECISION_TARGET` declared in `mission.md`
is answerable. It does not continue exploring because it "might find
something useful."

**Rationale:** Explorer agents without explicit stop conditions tend to
over-explore. Over-exploration saturates the context window, inflates token
cost, and produces scout reports that are too verbose for downstream agents
to consume efficiently. The `DECISION_TARGET` is the only criterion that
matters: once it is answerable with sufficient confidence, the mission is
complete. The three-strike halt (I-8 companion: three consecutive
`L`-confidence probes) enforces the same principle at the sub-question level.

**Source:** `ATLAS.md §1 I-8`, `ATLAS.md §2.1`

---

## Progressive disclosure — skill loading design

**Decision:** Skills are loaded one at a time, per phase, and unloaded at
the phase boundary. Phase A (Assess) has no SKILL.md — it runs off the
always-loaded `agent.md`.

**Rationale:** Keeping all four phase skills in context simultaneously
consumes ~800 tokens of always-loaded budget (4 × ~200 tokens) with no
benefit — at any given moment only one phase is active. Progressive
disclosure keeps the always-loaded footprint at `agent.md` + one skill at a
time. Phase A deliberately has no skill file so that mission refusal (the
most critical safety check) cannot be skipped even if a skill fails to load.

**Source:** `agent.md §Progressive disclosure`, `ATLAS.md §2`

---

## Three-strike halt in Phase L

**Decision:** Three consecutive low-confidence (`L`) probes on one
sub-question → record in `GAPS` and move on.

**Rationale:** Persistent low-confidence probing is a signal that the
sub-question is either ill-formed or the codebase lacks the evidence to
answer it. Continuing wastes tool-call budget and context space. Recording
in `GAPS` makes the absence of evidence explicit in the scout report, which
is more useful to downstream agents than an inconclusive probe loop. The
"three-strike" threshold is a practical trade-off: one strike could be noise;
three consecutive failures indicates a genuine gap.

**Source:** `ATLAS.md §2.3`, `skills/locate/SKILL.md`
