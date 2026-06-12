# 2026 Budget Treasury Withdrawal Procedure

Here we document the batch flow for building the ~15 treasury withdrawal governance actions of the
Intersect 2026 budget process. Per-proposal data is pulled from the [hydra voting](https://hydra-voting.intersectmbo.org/votes/cardano-budget-2026)
API and merged into a shared metadata template, so all 15 are built, validated and actioned together.

This wraps the single-item tooling described in [treasury-withdrawal-procedure.md](./treasury-withdrawal-procedure.md);
read that first to understand each underlying step. All budget-specific files live in `scripts/budget-2026/`.

> Note: like the single-item flow, this is only set up for treasury withdrawals with a single
> withdrawal address and amount per action.

## One-time setup

### 1. Fill in the config

Edit `scripts/budget-2026/config.sh` and replace every `REPLACEME` value:

- `WITHDRAWAL_ADDR` — the single funds-receiving stake address (2026 Treasury Reserve Smart Contract stake address), reused by all actions
- `DEPOSIT_RETURN_ADDR` — stake address for the governance-action deposit refund
- `TRSC_STAKE_ADDR` / `TRSC_PAYMENT_ADDR` / `PSSC_PAYMENT_ADDR` — shown verbatim in the Rationale
- `SUCCESSFUL_PROPOSALS_CSV_URL` — link to the successful-proposals CSV (hosted `ipfs://` or `https://` URI)
- `HYDRA_PROPOSAL_URL_BASE` — confirm the public proposal-page path before submitting (the validator checks reference links are reachable)

### 2. List the proposals

`scripts/budget-2026/proposals.json` holds one entry per withdrawal:

```json
[
  { "id": "69fdc9b261c4f060e2fef6c9", "name": "Dano Finance", "title": "Dano Finance: DeFi Kernel, American Options, and Orderbook SDK" }
]
```

- `id` — the hydra proposal `_id` (from `…/api/v0/proposals/<id>`)
- `name` — human-readable project name; used in the on-chain title (truncated to 80 chars) and slugified for the output filenames (e.g. `dano-finance.jsonld`)
- `title` *(optional)* — the full proposal title, kept only for readability (e.g. to tell apart multiple projects from the same proposer); not used by the scripts

To avoid hand-copying IDs, generate a candidate list from the vote (uses `HYDRA_VOTE_ID`
from config), then **prune it to the winning proposals** and copy it into place:

```shell
./scripts/budget-2026/budget-proposals-fetch.sh
# prints an overview of all submissions and writes proposals.candidate.json
# edit it down to the winners, then:
mv scripts/budget-2026/proposals.candidate.json scripts/budget-2026/proposals.json
```

> Note: the hydra API lists **every** submission and has no "successful/passed" filter,
> so you must select the winners yourself (the successful-proposals CSV is the source of truth).

### 3. Set environment variables

```shell
source ./scripts/.env
```

Make sure `CARDANO_NODE_NETWORK_ID` and `CARDANO_NODE_SOCKET_PATH` are set (needed for step 6).

## Build the metadata

### 4. Build all metadata

For each proposal, this fetches the hydra data, fills `scripts/budget-2026/template.md`, and runs
`metadata-create.sh` to produce an **unsigned** `.jsonld` in `scripts/budget-2026/output/`.

```shell
./scripts/budget-2026/budget-metadata-build-all.sh
```

The on-chain title is composed as `Withdraw <amount> ada for <name> administered by Intersect`. Because
`body.title` is capped at 80 characters, `<name>` is truncated to fit; the **full** proposal title is
always preserved at the top of the Abstract. The withdrawal amount comes from `metaData.totalBudget`
(ADA) in the hydra API.

> Build a single proposal directly while testing:
> `./scripts/budget-2026/budget-metadata-build.sh <proposal-id> --name "<name>"`

### 5. Validate all metadata

Runs `metadata-validate.sh` (CIP-108 / CIP-169 / Intersect schema) on every file, plus a budget
cross-check that the ada figure in the title matches the on-chain withdrawal amount. Pre-signing, so
it runs `--draft` by default:

```shell
./scripts/budget-2026/budget-metadata-validate-all.sh
```

Pass extra `metadata-validate.sh` flags after `--`, e.g. `-- --no-link-check`. After signing
(step 6), re-run strictly with `--strict` to enforce the non-empty-authors check.

### 6. Sign each metadata file (manual)

Author signing is **not** batched. Sign each `.jsonld` in `scripts/budget-2026/output/` with the author
key(s), as in the single-item procedure:

```shell
./scripts/author-create.sh scripts/budget-2026/output/<name>.jsonld
./scripts/author-validate.sh scripts/budget-2026/output/<name>.jsonld
```

Then re-validate strictly:

```shell
./scripts/budget-2026/budget-metadata-validate-all.sh --strict
```

## Build the actions

### 7. Build all actions

For each **signed** `.jsonld`, this pins the metadata to IPFS (`ipfs-pin.sh`) and creates the treasury
withdrawal action (`action-create-tw.sh`) using the addresses from `config.sh`. It requires a live
node and refuses to run while the config still holds placeholder addresses.

```shell
./scripts/budget-2026/budget-action-build-all.sh
```

Use `--no-ipfs-pin` if the metadata is already hosted. Each action is written as
`<name>.jsonld.action` (with a `.action.json` view) in `scripts/budget-2026/output/`.

### 8. Submit on testnet first

As with all actions, submit on a testnet before mainnet to confirm explorers pick up and render each
action's metadata correctly. Include an action file in a transaction with:

```shell
cardano-cli latest transaction build --proposal-file scripts/budget-2026/output/<name>.jsonld.action ...
```
