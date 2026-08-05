# Research

Data-driven decisions behind the pipeline. Every non-obvious constant (JOIN window,
Filter-1 cutoff, normalization coefficients) is backed by a reproducible query and
committed results — so the repo shows *why* each number was chosen, not just the number.

Each writeup follows the same shape: **question → query → result table → decision**.

| Study | Question | Decision / Output |
|---|---|---|
| `metadata_coverage.md` | What % of events seen in the last 15 min have an `events` row within the last day? | 1-day metadata JOIN window; ~3% without metadata dropped |
| `top_n_cutoff.md` | Where does the per-window article count fall to ~1? | Filter-1 cutoff ≈ 200 events |
| `normalization_coefficients.md` | Per-country baseline media volume → `normalizing_coef` | seeded in `../../data-pipeline/sql/init_db.sql` (all `1.0` for now), clamped to [0.2, 5.0], applied at Filter 2 |

_(Temporal dedup was checked ad-hoc — an article never recurs across 15-min windows, so summing per-window counts can't double-count. Result was trivially clean, so it's not written up as a study.)_

_Status: studies to be written (see the **Open Research & TODO** section in the root README)._
