# Governance Scripts

This repository holds shell scripts that Intersect uses to engage in Cardano on-chain governance.

## Navigation

### Scripts

#### Governance (CIP-100+) Metadata Scripts

- [metadata-create.sh](./scripts/metadata-create.sh)
  - Creates governance action CIP-108+ (including [Intersect CIP108 schemas](https://github.com/IntersectMBO/governance-actions/tree/main/schemas)) JSONLD file
  - Takes an inputted markdown file in expected shape

- [metadata-validate.sh](./scripts/metadata-validate.sh)
  - Compares governance metadata against the established schema(s)
  - Supports CIP100, CIP108, CIP119, CIP136 and [Intersect CIP108 schemas](https://github.com/IntersectMBO/governance-actions/tree/main/schemas)
  - Applies a spell check to CIP108 metadata fields

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
  - Allows user to pin JSONLD file(s) on a number of pinning services
  - Optionally allows the user to check file's discoverability first

#### CIP-108 Scripts

- [cip-108-create-human-readable.sh](./scripts/cip-108-create-human-readable.sh)
  - Creates a markdown file from CIP108 metadata

#### CIP-100 Author Scripts

- [author-create.sh](./scripts/author-create.sh)
  - Adds an author witness to CIP100/CIP108 metadata
- [author-validate.sh](./scripts/author-validate.sh)
  - Checks the correctness of CIP100/CIP108 metadata with a author(s) witness(es)

#### (archive) 2025 Budget Scripts

Note: These are really only useful for archival reasons.

- [budget-metadata-validate.sh](./scripts/archive/budget-metadata-validate.sh)
  - Runs correctness and validity checks for budget treasury withdrawal CIP108 metadata.
  - Uses a combination of the other scripts
- [budget-metadata-create.sh](./scripts/archive/budget-metadata-create.sh)
  - Creates Intersect budget metadata file from a `.docx`
  - This expects certain structure within the `.docx`
- [budget-action-create.sh](./scripts/archive/budget-action-create.sh)
  - Creates Intersect budget treasury withdrawal file from a .jsonld

#### Other Scripts

- [hash.sh](./scripts/hash.sh)
  - Performs a blake2b-256 hash on provided file
- [pdf-remove-metadata.sh](./scripts/pdf-remove-metadata.sh)
  - Removes PDF metadata from PDF files

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
  - Used by: `metadata-create.sh`, `metadata-validate.sh`, `ipfs-check.sh`, `ipfs-pin.sh`, `author-validate.sh`, `query-live-actions.sh`
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
