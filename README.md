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

#### 2025 Budget Scripts

Note: These are really only useful for archival reasons.

- [budget-metadata-validate.sh](./scripts/budget-metadata-validate.sh)
  - Runs correctness and validity checks for budget treasury withdrawal CIP108 metadata.
  - Uses a combination of the other scripts
- [budget-metadata-create.sh](./scripts/budget-metadata-create.sh)
  - Creates Intersect budget metadata file from a `.docx`
  - This expects certain structure within the `.docx`

#### Other Scripts

- [hash.sh](./scripts/hash.sh)
  - Performs a blake2b-256 hash on provided file
- [pdf-remove-metadata.sh](./scripts/pdf-remove-metadata.sh)
  - Removes PDF metadata from PDF files

### Documentation

- [2025 Budget Treasury Withdrawals](./docs/2025-budget-withdrawals.md)
  - Documents the scripts and high level process to create the treasury withdrawal governance actions for the Intersect 2025 budget.

## Dependencies

In order to run all of these scripts you will need

- [ajv-cli](https://www.npmjs.com/package/ajv-cli)
- aspell
- b2sum
- cardano-cli
- [cardano-signer](https://github.com/gitmachtl/cardano-signer)
- [ipfs](https://docs.ipfs.eth.link/install/command-line/)
- jq

probably more I have missed...

## Environment Variables

### Cardano Node

The scripts that uses node variables are `action-create-xxx.sh`.

These expect `CARDANO_NODE_NETWORK_ID` and `CARDANO_NODE_SOCKET_PATH` to be set.
So you'll need a local cardano node socket path.

### Secrets

The only script that uses secrets is `ipfs-pin.sh`.

Secrets can be stored via `./scripts/.env` and based on `./scripts/.env.example`.

This is setup so you can run:

```shell
source ./scripts/.env
```

## License

See [License](./LICENSE).
