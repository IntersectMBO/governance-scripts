# Intersect 2026 Budget — Treasury Withdrawal Pipeline

Automation layer that turns the ~15 approved 2026 budget proposals into CIP-108/CIP-169
treasury-withdrawal governance actions, sourcing per-proposal data from the hydra voting API
and filling the standardised metadata template.

## Files

| File | Purpose |
|------|---------|
| `config.sh` | Static config: hydra API base, the single Intersect withdrawal + deposit-return stake addresses, the smart-contract addresses shown in the Rationale, and the successful-proposals CSV link. **Fill in the REPLACEME values before real runs.** |
| `template.md` | Tokenised metadata template (`{{TOKEN}}` placeholders), kept compatible with `metadata-create.sh` (plain `## H2` headers, `* [label](url)` references). |
| `proposals.json` | The list of proposals to process: `{ id, name, title? }` per item. `id` is the hydra proposal `_id`; `name` is the human-readable project name, used in the on-chain title (hard-capped at 80 chars — see below) and slugified for the output filenames; `title` (optional) is the full proposal title, kept only for human readability and otherwise ignored. If two entries slug to the same filename (e.g. one proposer with several projects), the duplicates get a `-2`, `-3`… suffix and a warning — give them distinct `name`s to avoid it. |
| `output/` | Generated `.md`, `.jsonld`, `.jsonld.action`, `.jsonld.action.json` artifacts. |

## Workflow

All scripts live in this directory (`scripts/budget-2026/`); run them from the repo root.

```bash
# 0. (optional) Generate a candidate proposals.json from the budget vote, then
#    prune it to the winning proposals and copy it to proposals.json
./scripts/budget-2026/budget-proposals-fetch.sh
#    -> writes proposals.candidate.json (all submissions; the API has no "successful" filter)

# 1. Build all unsigned metadata (hydra -> .md -> .jsonld)
./scripts/budget-2026/budget-metadata-build-all.sh

# 2. Validate all metadata (pre-signing / draft)
./scripts/budget-2026/budget-metadata-validate-all.sh

# 3. MANUAL: author-sign each .jsonld
#    ./scripts/author-create.sh scripts/budget-2026/output/<name>.jsonld ...

# 4. (optional) re-validate strictly, now that authors are present
./scripts/budget-2026/budget-metadata-validate-all.sh --strict

# 5. Pin to IPFS + build the on-chain actions (needs a live node + ipfs)
./scripts/budget-2026/budget-action-build-all.sh
```

Build a single item directly (handy for testing):

```bash
./scripts/budget-2026/budget-metadata-build.sh 69fdc9b261c4f060e2fef6c9 --name "Dano Finance"
```

## Title length note

`body.title` is hard-capped at 80 characters by `metadata-validate.sh`. The title is composed as
`Withdraw <amount> ada for <name> administered by Intersect`, where `<name>` is the `name` from
`proposals.json` (**truncated** if needed to fit 80 chars). The full, untruncated proposal title is
always preserved at the top of the Abstract.
