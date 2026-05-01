# Governance Scripts

This repository holds shell scripts that Intersect uses to engage in Cardano on-chain governance.

## Navigation

### Scripts

#### Governance (CIP-100+) Metadata Scripts

- [metadata-create.sh](./scripts/metadata-create.sh)
  - Creates a governance-action JSON-LD file (CIP-108 body + CIP-169 extension + CIP-116 ProposalProcedure on-chain format, including [Intersect CIP108 schemas](https://github.com/IntersectMBO/governance-actions/tree/main/schemas))
  - Requires a `.md` input file with H2 sections (`## Title`, `## Abstract`, `## Motivation`, `## Rationale`, `## References`, `## Authors`)
  - Requires `--governance-action-type <info|treasury|ppu>` and `--deposit-return-addr <stake-address>`
  - Optional `--language <BCP-47-tag>` sets the JSON-LD `@context.@language` (default: `en`)

- [metadata-validate.sh](./scripts/metadata-validate.sh)
  - Requires at least one schema source (`--cip100` / `--cip108` / `--cip119` / `--cip136` / `--cip169` / `--intersect-schema` / `--schema <URL>`); errors early otherwise
  - Supports CIP100, CIP108, CIP119, CIP136, CIP169 and [Intersect CIP108 schemas](https://github.com/IntersectMBO/governance-actions/tree/main/schemas)
  - Enforces `body.title` length ≤ 80 and `body.abstract` length ≤ 2500 characters when those fields are present
  - Applies an aspell spell check to CIP108 metadata fields; the personal dictionary is fetched at runtime from the `main` branch of this repo — no local copy needed. Skip with `--no-spell-check`.
  - Checks that every URI in the document (structured `uri`/`url` fields plus markdown links / bare URLs in `title` / `abstract` / `motivation` / `rationale`) is reachable; `ipfs://<cid>` is resolved via `$IPFS_GATEWAY_URI` (fallback `https://ipfs.io`). Skip with `--no-check-links`.
  - Runs a structural integrity check beyond the published schemas: `authors` must be non-empty (CIP-100 declares `authors` as required but does not enforce `minItems: 1`). Pass `--draft` during the create-then-sign workflow to downgrade the empty-`authors` failure to a warning; omit `--draft` for the post-signing pass so the strict check fires. Numeric-shape on `body.onChain.deposit` and treasury `rewards[].value` is enforced by the CIP-169 schema's `UInt64` pattern when `--cip169` is passed.

- [metadata-canonize.sh](./scripts/metadata-canonize.sh)
  - Uses cardano-singer to produce a blake2b-256 hash digest of a given metadata canonized body
  - This is useful when trying to create author signatures

#### Governance Action Scripts

- [action-create-info.sh](./scripts/action-create-info.sh)
  - Creates a info governance action from a Intersect metadata
  - Uses a local cardano node socket file

- [action-create-tw.sh](./scripts/action-create-tw.sh)
  - Creates a treasury withdrawal governance action from a Intersect metadata
  - Uses a local cardano node socket file

#### IPFS Scripts

- [ipfs-check.sh](./scripts/ipfs-check.sh)
  - Checks if a file is accessible via free IPFS gateways
- [ipfs-pin.sh](./scripts/ipfs-pin.sh)
  - Pins file(s) across local IPFS node, Pinata, Blockfrost, and NMKR (enabled by default; disable individually with `--no-local`, `--no-pinata`, `--no-blockfrost`, `--no-nmkr`)
  - Accepts a single file by default. To recursively pin a directory you must explicitly pass `--directory` (think of it as the equivalent of `rm -r`); without it, a directory path is rejected to prevent accidental bulk uploads. Combine with `--just-jsonld` to limit the walk to `.jsonld` files. The walk skips `.git`/`.svn`/`.hg`, symlinks, and any file whose name matches a sensitive pattern (`*.skey`, `*.vkey`, `.env*`, `id_rsa*`, `*.pem`, `*.p12`, `*.pfx`).

#### CIP-108 Scripts

- [cip-108-markdown.sh](./scripts/cip-108-markdown.sh)
  - Creates a markdown file from CIP108 metadata

#### CIP-100 Author Scripts

- [author-create.sh](./scripts/author-create.sh)
  - Adds an author witness to CIP100/CIP108 metadata
- [author-validate.sh](./scripts/author-validate.sh)
  - Checks the correctness of CIP100/CIP108 metadata with a author(s) witness(es)
  - Also compares each author's public key against Intersect's well-known key; pass `--no-intersect` to skip

#### Other Scripts

- [hash.sh](./scripts/hash.sh)
  - Prints a BLAKE2b-256 hash of the given file using both `b2sum` and `cardano-cli`, so the two outputs can be compared
- [pdf-remove-metadata.sh](./scripts/pdf-remove-metadata.sh)
  - Removes PDF metadata from PDF files

#### Archived Scripts

Note: These are really only useful for archival reasons.

- [budget-metadata-validate.sh](./scripts/archive/budget-metadata-validate.sh)
  - Runs correctness and validity checks for budget treasury withdrawal CIP108 metadata.
  - Uses a combination of the other scripts
- [budget-metadata-create.sh](./scripts/archive/budget-metadata-create.sh)
  - Creates Intersect budget metadata file from a `.docx`
  - This expects certain structure within the `.docx`
- [budget-action-create.sh](./scripts/archive/budget-action-create.sh)
  - Creates Intersect budget treasury withdrawal file from a .jsonld
- [query-live-actions.sh](./scripts/archive/query-live-actions.sh)
  - Fetches active governance actions from Koios and prints their DRep vote summary

### Documentation

- [2025 Budget Treasury Withdrawals](./docs/2025-budget-withdrawals.md)
  - Documents the scripts and high level process to create the treasury withdrawal governance actions for the Intersect 2025 budget.

## Dependencies

In order to run all of these scripts you will need the following binaries/packages installed:

### Required Binaries/Packages

#### Core Dependencies

- **[ajv-cli](https://www.npmjs.com/package/ajv-cli)** (`ajv`)
  - Used by: `metadata-validate.sh`
  - JSON schema validation

- **aspell**
  - Used by: `metadata-validate.sh`
  - Spell checking for metadata fields

- **b2sum**
  - Used by: `action-create-info.sh`, `action-create-tw.sh`, `hash.sh`
  - BLAKE2b-256 hashing

- **cardano-cli**
  - Used by: `action-create-info.sh`, `action-create-tw.sh`, `author-create.sh`, `hash.sh`, `budget-action-create.sh`, `budget-metadata-validate.sh`
  - Cardano CLI tools for governance actions and address operations

- **[cardano-signer](https://github.com/gitmachtl/cardano-signer)**
  - Used by: `metadata-canonize.sh`, `metadata-validate.sh`, `author-create.sh`, `author-validate.sh`
  - Canonization and signing of governance metadata

- **curl**
  - Used by: `metadata-create.sh`, `metadata-validate.sh`, `ipfs-check.sh`, `ipfs-pin.sh`, `author-validate.sh`, `archive/query-live-actions.sh`
  - HTTP requests for downloading schemas and API calls

- **[ipfs](https://docs.ipfs.eth.link/install/command-line/)**
  - Used by: `action-create-info.sh`, `action-create-tw.sh`, `ipfs-check.sh`, `ipfs-pin.sh`, `budget-action-create.sh`
  - IPFS file operations (adding, pinning, checking)

- **jq**
  - Used by: Most scripts
  - JSON processing and manipulation

- **[pandoc](https://pandoc.org/)**
  - Used by: `metadata-create.sh`, `budget-metadata-create.sh`
  - Document conversion (DOCX to Markdown, Markdown processing)

#### Optional/Additional Dependencies

- **perl**
  - Used by: `budget-metadata-create.sh`
  - Text processing and regex operations

- **qpdf**
  - Used by: `pdf-remove-metadata.sh`
  - PDF manipulation and linearization

- **exiftool**
  - Used by: `pdf-remove-metadata.sh`
  - PDF metadata removal

- **bc**
  - Used by: `action-create-tw.sh`
  - Arithmetic calculations (ADA amount formatting)

- **base64**
  - Used by: `ipfs-pin.sh`
  - Base64 encoding for NMKR API

- **awk**, **sed** (standard Unix utilities)
  - Used by: Multiple scripts
  - Text processing

## Environment Variables

### Cardano Node Configuration

The following scripts require a local Cardano node connection:
- `action-create-info.sh`
- `action-create-tw.sh`
- `budget-action-create.sh`

**Required Variables:**
- **`CARDANO_NODE_SOCKET_PATH`**
  - Path to the Cardano node socket file
  - Example: `/path/to/cardano-node.socket` or `./node.socket`
  - Used for querying governance state and creating governance actions

- **`CARDANO_NODE_NETWORK_ID`**
  - Network identifier for the Cardano network
  - Values: `764824073` or `mainnet` for mainnet, or testnet identifier for testnet
  - Used to determine network type (mainnet vs testnet)

**Note:** The scripts check that these variables are set and will exit with an error if they are missing.

### IPFS Pinning Service Secrets

The `ipfs-pin.sh` script supports multiple IPFS pinning services. The following environment variables are required only if you want to use the corresponding service:

- **`PINATA_API_KEY`**
  - Required if using Pinata pinning service
  - Get your API key from [Pinata](https://www.pinata.cloud/)

- **`BLOCKFROST_API_KEY`**
  - Required if using Blockfrost pinning service
  - Get your API key from [Blockfrost](https://blockfrost.io/)

- **`NMKR_API_KEY`**
  - Required if using NMKR pinning service
  - Get your API key from [NMKR](https://nmkr.io/)

- **`NMKR_USER_ID`**
  - Required if using NMKR pinning service
  - Your NMKR user ID

### Optional Environment Variables

- **`IPFS_GATEWAY_URI`**
  - Mentioned in script comments but not currently used in the code
  - May be used in future versions for custom IPFS gateway configuration

### Setting Environment Variables

Create a `.env` file in the `scripts/` directory, based on [example](./scripts/.env.example) and source it:

```shell
source ./scripts/.env
```

## License

See [License](./LICENSE).
