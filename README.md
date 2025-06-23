# Governance Scripts

This repository holds shell scripts that Intersect uses to engage in Cardano on-chain governance.

## Navigation

### Scripts

#### 2025 Budget Scripts

- [budget-check-metadata.sh](./scripts/budget-check-metadata.sh) 
  - Runs correctness and validity checks for budget treasury withdrawal CIP108 metadata.
  - Uses a combination of the other scripts

#### IPFS Scripts

- [ipfs-check.sh](./scripts/ipfs-check.sh)
  - Checks if a file is accessible via free IPFS gateways
- [ipfs-pin.sh](./scripts/ipfs-check.sh)
  - Allows user to pin a file on a number of pinning services
  - Optionally allows the user to check file's discoverability first

#### CIP-108 Scripts

- [cip-108-create-human-readable.sh](./scripts/cip-108-create-human-readable.sh)
  - Creates a markdown file from CIP108 metadata
- [cip-108-validate.sh](./scripts/cip-108-validate.sh)
  - Compares CIP-108 metadata against the established schema
  - Applies a spell check to CIP108 metadata 

#### Other Scripts

- [create-author-witness.sh](./scripts/create-author-witness.sh)
  - Adds an author witness to CIP100/CIP108 metadata
- [verify-author-witness.sh](./scripts/verify-author-witness.sh)
  - Checks the correctness of CIP100/CIP108 metadata with a author(s) witness(es)
- [hash.sh](./scripts/hash.sh)
  - Performs a blake2b-256 hash on provided file

### Documentation

- [2025 Budget Treasury Withdrawals](./docs/2025-budget-withdrawals.md)
  - Documents the scripts and high level process to create the treasury withdrawal governance actions for the Intersect 2025 budget.

## Dependencies

In order to run all of these scripts you will need

- [ajv-cli](https://www.npmjs.com/package/ajv-cli)
- aspell
- b2sum
- cardano-cli
- [cardano-signer](https://github.com/gitmachtl/cardano-signer)
- [ipfs](https://docs.ipfs.eth.link/install/command-line/)
- jq

## License

See [License](./LICENSE).
