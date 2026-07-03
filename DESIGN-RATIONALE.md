# ATLAS Design Rationale

This document maps each ATLAS architectural decision to the research or
engineering constraint that motivated it. It is a companion to `SPEC.md`
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

**Source:** `SPEC.md §1`, `tools/bounded-aci-spec.md`

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

**Source:** `SPEC.md §1 I-2`, `tools/bounded-aci-spec.md §2`

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

**Source:** `SPEC.md §1 I-3`, `evals/canary-missions.md §5`

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

**Source:** `SPEC.md §1 I-4`, `skills/locate/SKILL.md §3`

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

**Source:** `SPEC.md §1 I-5`, `skills/abstract/SKILL.md`

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

**Source:** `SPEC.md §1 I-6`, `agent.md §Telemetry`

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

**Source:** `SPEC.md §1 I-7`, `schemas/scout-report.v1.json`

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

**Source:** `SPEC.md §1 I-8`, `SPEC.md §2.1`

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

**Source:** `agent.md §Progressive disclosure`, `SPEC.md §2`

---

## I-9 — ECL-conformant handoffs

**Decision:** Phase S MUST emit a v2.0 ECL envelope sidecar
(`scout-report.envelope.json`) adjacent to the `scout-report.md`. The
envelope is a **terminal Phase-S artefact** — in the same class as the
scout report itself — not a tool call. Envelope schema is vendored at
`schemas/ecl-envelope.v2.json`; per-Eidolon profile at
`schemas/scout-report-profile.v1.json`. ATLAS declares targeting ECL v2.0
via a `ECL_VERSION` file at the repo root. Adoption is opt-in; existing
consumers may ignore the sidecar without loss of scout-report functionality.

**Rationale:** Inter-Eidolon handoffs are currently implicit — ATLAS emits a
freeform `<handoff>` XML block in the scout report, which downstream agents
(SPECTRA, APIVR-Δ) parse by convention. ECL v2.0 (ECL §1, §3) standardises
this: the envelope carries a machine-readable identity (`from`/`to`), a
`performative` (`PROPOSE` for ATLAS→SPECTRA), and an integrity checksum
(`sha256`) that downstream tooling can verify without re-reading the report.
Making the envelope a terminal artefact (not a tool) preserves the I-1
read-only constraint — ATLAS's ACI has no `write` primitive; the envelope is
an output of the Synthesize phase in exactly the same way `scout-report.md`
is, written by the harness after the LLM signs off on the content. The
per-Eidolon profile (ECL §3) provides a typed frontmatter contract
(`scope.entrypoints`, `findings_count`, etc.) that lets the central ECL
registry validate ATLAS handoffs without coupling to ATLAS's body schema.

**ISE grade (ECL v2.0 §6.5) — why `self-attested`, not `validated` or
`unverified`:** ATLAS's exit gate (`skills/synthesize.md`) mechanically checks
every claim for a `FINDING-XXX` + `path:line` anchor before a scout report
ships (I-7) — that is real internal validation, ruling out `unverified`.
But no other Eidolon or external gate re-checks those claims before the
envelope is emitted, ruling out `validated` (spec-mandated *external* gates)
and `human-reviewed`. `self-attested` is the accurate middle grade: evidence
is anchored, but the anchoring is ATLAS's own. `ise.receiver_authorization`
is set to `{auto_route: true, auto_merge: false, auto_deploy: false}` for the
same reason — SPECTRA may pull a scout report into its own intake
automatically, but nothing downstream should merge or deploy on the strength
of an unverified-by-a-third-party read-only exploration alone.

**Source:** `ECL_VERSION`, `SPEC.md §1 I-9`, `SPEC.md §2.5`,
ECL spec §1 (envelope shape) + §3 (per-Eidolon profile contracts) + §6.5 (ISE).

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

**Source:** `SPEC.md §2.3`, `skills/locate/SKILL.md`

---

## Scatter-Gather Locate mode (G1 operationalization)

**Decision:** Promote the diffuse Operator-pattern scatter primitives (I-4;
`locate.md` Operator section; `agent.md` P0 rule 7) into a *first-class named
sub-mode* — `skills/scatter.md` + `SPEC.md §2.3.1` — with a both-flags
activation trigger (surface > 5 modules OR > 25 files AND ≥ 2
topologically-disjoint sub-questions), a hard 5-branch fan-out cap, a
deterministic graph-derived partition, per-branch budgets summing to ≤ parent,
and a merge+dedup contract (highest-confidence merge on path/overlapping-line,
`[DISPUTED]` on contradiction) that feeds the existing Phase A fold. GATED,
never default; below threshold the mode is inert and Locate stays serial.

**Rationale:** The primitives existed but were diffuse — no fan-out cap, no
merge/dedup contract, no surface-size trigger, no stop condition — so the
parallelism was a heuristic, not a mechanism. Making it mechanical is the lever
the team is graded on. Read/explore parallelism is safe-by-construction for
ATLAS because it never writes the codebase (I-1): worktree-style clean-context
isolation here is a *trajectory-contamination* guard (each branch sees only its
scope-slice, never another branch's path), not a write-conflict guard. The
orchestrator-worker sweet spot is ~5 workers, hence the cap; budgets are
*partitioned* not *multiplied* so scatter adds parallelism without a fresh
budget; the partition is graph-derived (not LLM-guessed) to preserve the I-3
deterministic-first discipline; and contradictions are surfaced (`[DISPUTED]`)
rather than silently resolved, preserving evidence honesty. The merged list
reuses the already-built AgentFold aggregator — no new machinery.

**Honest scope.** The TRANCE-not-default gating, the 5-branch cap, and the
both-flags auto-trigger are *prose* interpreted by the host LLM, not
mechanically enforced; mechanical orchestration enforcement is a nexus-level
routing-kernel concern. Whether a host actually runs branches concurrently is a
runtime property — on a host without a subagent spawner the mode degrades to
serial Locate with correctness preserved.

**Source:** `SPEC.md §1 I-4 / §2.3.1`, `skills/scatter.md`,
`skills/locate.md` (Operator section), `agent.md` P0 rule 7.

---

## Delta re-scout (incremental mode)

**Decision:** Add a read-only, evidence-anchored *delta* re-scout
(`skills/rescout.md` + `SPEC.md §2.6`): reuse a prior scout-report + Memex store
+ a `git diff` range to re-probe ONLY the changed surface, carry unchanged
findings forward verbatim, and label each finding
FRESH / UNCHANGED / RE-VERIFIED / NEWLY-STALE with its originating commit.

**Rationale:** ATLAS's standing limitation is that it is a *separate step* with
no always-on live index, so a scout goes stale the moment the code moves. The
full A→T→L→A→S cycle is wasteful when only a few files changed. The delta mode
narrows the staleness penalty: the changed surface is computed deterministically
(`git diff` ∩ prior `MAP-MODULES`), Phase T re-runs over that surface only, and
only findings whose `path:line` anchors intersect a changed hunk are re-probed —
everything else is carried verbatim from Memex, which *preserves provenance*,
ATLAS's read-only + evidence-anchored differentiator.

**Honest scope (anti-over-claim).** This **narrows, does not close** the
live-index gap. It is a faster evidence-anchored *re-run*, not an always-on
index; a true live index is an atlas-aci runtime / nexus integration concern,
not a methodology property. The spec and skill both state this explicitly so the
score claim stays evidence-disciplined.

**Source:** `SPEC.md §2.6 / §0 non-goals`, `skills/rescout.md`.

---

## Graph-first decomposition (raise η, derive the scatter partition)

**Decision:** Extend the Tier-2 graph-query section of `skills/locate.md` with
an explicit `graph_query` verb vocabulary (`callers_of`, `implementers_of`,
`writers_to`, `importers_of`, depth-bounded `transitive_callers`,
`callgraph_slice`) and prescribe that the Scatter-Gather partition is derived
from a single `callgraph_slice(scope)` rather than LLM-guessed clustering.

**Rationale:** Each graph verb is an O(1) index lookup with exact results;
pushing relational sub-questions onto them before any windowed read is the
single biggest lever on search-efficiency η (I-3). Deriving the scatter
partition from the call-graph makes the fan-out plan a *structural fact* instead
of an inference, which both raises partition quality (truly disjoint clusters →
low cross-branch dedup) and keeps the deterministic-first discipline intact.

**Source:** `SPEC.md §1 I-3`, `skills/locate.md` (Tier-2), `tools/bounded-aci-spec.md §graph_query`.

---

## ESL discover hop — propose, never make

**Decision:** Add `skills/esl-hop.md`, ATLAS's opt-in Eidolons Spec Lifecycle
(ESL) hop. When a scout mission surfaces a change-worthy finding (a defect, a
spec/impl drift, or a gap) in an ESL-enabled consumer project (`.spectra/`
present), Phase S frames the `scout-report.md` + envelope it already emits as
a proposal to open an ESL change at `proposed`, and hands it to SPECTRA over
the existing, unmodified `atlas-to-spectra` edge. ATLAS never calls a
tonberry write verb (`propose`, `transition`, `archive`, `verify`) itself —
SPECTRA's own `esl-hop` owns `right_size → propose → specify` on receipt.

**Rationale:** ATLAS is the furthest-upstream Eidolon in the ESL chain, and
its P0 refusal boundary (read-only; no `edit`/`write`/`commit`/`deploy`/
`migrate`/`refactor`/`fix`) is the single most safety-critical invariant in
the whole methodology (I-1). Every other Eidolon's `esl-hop` is a *maker* or
*checker* role bound to a tonberry write verb; giving ATLAS the same shape
would mean acquiring a `mcp__tonberry__propose` call — a de facto write
against `.spectra/changes/`, which is exactly the boundary ATLAS exists to
never cross. The discover hop resolves this by making ATLAS's contribution
purely evidentiary: it reuses the artifact and edge it already has (no new
`artifact.kind`, no new contract), and lets SPECTRA — which already owns
`proposed → specify` — be the one Eidolon that actually opens the
`change.json` record. This keeps ESL adoption additive on both ends: ATLAS
gains a discovery-to-lifecycle path without acquiring a single new tool, and
SPECTRA's existing hop needs no change to receive it.

**Source:** `skills/esl-hop.md`, `agent.md` (skill-load table, S phase row),
`SPEC.md §6`, `contracts/atlas-to-spectra.yaml` (in `Rynaro/eidolons-ecl`,
unmodified).
