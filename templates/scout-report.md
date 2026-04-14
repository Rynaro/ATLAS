# SCOUT REPORT — ATLAS Phase S

> The single artifact downstream agents consume. Hard cap: 3000 tokens.

---

## 1. Mission recap

**MISSION-ID:** `<mission-id>`
**GOAL:** <verbatim from mission.md>
**DECISION_TARGET:** <verbatim>
**SCOPE:** <globs>
**STATUS:** `completed | partial | blocked`

---

## 2. Topology summary

> ≤10 bullets. Each carries a `path` reference.

- <structural fact> · `<path>`
- <structural fact> · `<path>`
- ...

---

## 3. Answer to DECISION_TARGET

> Prose. Every factual clause ends with a `[FINDING-XXX]` reference.
> Confidence language flows with tier.

### DT-1 — <sub-question>

<answer prose with inline citations>

### DT-2 — <sub-question>

<answer prose with inline citations>

### DT-3 — <sub-question>

<answer prose with inline citations, or: "Not resolved; see [GAP-003].">

---

## 4. Recommended next actions

> Ranked. Every item has a handoff label and concrete anchors.

### R-1 · priority: `high | medium | low` · `→ <recipient>`

<one-paragraph description>

- **References:** `FINDING-XXX`, `GAP-XXX`
- **Estimated timebox:** `up to N days` (when applicable)

### R-2 · priority: ... · `→ <recipient>`

...

### R-3 · priority: ... · `→ <recipient>`

...

**Handoff label legend:**
- `→ SPECTRA` — needs spec before implementation
- `→ APIVR-Δ` — spec clear; ready for implementation loop
- `→ human` — blocked on a judgment call
- `→ ATLAS` — deserves a follow-up scout mission (max 1 recursion)

---

## 5. Risks & gaps

| ID | Description | Tier | Proposed mitigation |
|----|-------------|------|---------------------|
| GAP-<n> | <short> | H/M/L | <mitigation or "needs decision"> |
| RISK-<n> | <short> | H/M/L | <mitigation> |

---

## 6. Telemetry

```
phase            | tokens_in | tokens_out | tool_calls
A (Assess)       | <n>       | <n>        | <n>
T (Traverse)     | <n>       | <n>        | <n>
L (Locate)       | <n>       | <n>        | <n>
A (Abstract)     | <n>       | <n>        | <n>
S (Synthesize)   | <n>       | <n>        | <n>
TOTAL            | <n>       | <n>        | <n>

fold_ratio:       <float>   # target ≤ 0.1
η (efficiency):   <float>   # target ≥ 0.25
```

---

## 7. Handoff block

```
<handoff>
  <primary_recipient><SPECTRA|APIVR-Δ|human></primary_recipient>
  <fallback_recipient>human</fallback_recipient>
  <report_path>artifacts/ATLAS/scout-report-<mission-id>.md</report_path>
  <memex_root>artifacts/ATLAS/memex/<mission-id>/</memex_root>
  <critical_gaps><GAP-ids></critical_gaps>
  <open_questions>
    - <R-N summary>
  </open_questions>
</handoff>
```
