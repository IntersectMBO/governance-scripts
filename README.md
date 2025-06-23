# Governance Scripts

This repository holds shell scripts that Intersect uses to engage in Cardano on-chain governance.

## Navigation

### Scripts

- [create-author-witness.sh](./scripts/create-author-witness.sh)
  - Adds an author witness to CIP100/CIP108 metadata
- [create-human-readable-from-json.sh](./scripts/create-human-readable-from-json.sh)
  - Creates a markdown file from CIP108 metadata
- [hash.sh](./scripts/hash.sh)
  - Performs a blake2b-256 hash 
- [ipfs.sh](./scripts/ipfs.sh)
  - Checks if a file is accessible via IPFS
  - Allows user to pin a file on a number of pinning services 
- [validate-cip-108.sh](./scripts/ipfs.sh)
  - Compares CIP108 metadata against the established schema
  - Applies a spell check to CIP108 metadata 
- [verify-author-witness.sh](./scripts/verify-author-witness.sh)
  - Checks the correctness of CIP108 metadata with a author(s) witness(es) 
- [check-budget-metadata.sh](./scripts/check-budget-metadata.sh) 
  - Runs correctness and validity checks for budget treasury withdrawal CIP108 metadata. 

### Documentation

- [2025 Budget Treasury Withdrawals](./docs/2025-budget-withdrawals.md)
  - Documents the scripts and high level process to create the treasury withdrawal governance actions for the Intersect 2025 budget.

## License

See [License](./LICENSE).
