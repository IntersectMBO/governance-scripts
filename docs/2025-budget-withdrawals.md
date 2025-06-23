# Draft --  Intersect 2025 Budget Treasury Withdrawals

Here we intend to document the scripts used within the technical processes of building and verifying the treasury withdrawal actions.

## Steps

### Pre-Requisites

Have authored your treasury withdrawal metadata.
This can be done via Google docs, or some collaborative document platform.

### 1. Create the metadata documents

convert the Google docs to .JSONLD

tbd how to do this and tbd how much can be automated

### 2. Check metadata documents

Ensure that the metadata documents are correct.

```shell
./scripts/validate-budget-metadata.sh
```

automated checks
- compliance with CIPs
- check on IPFS ?
- compliance with budget schema
- spelling check
- probably more

### 3. Manual check

- lets look over and make sure we are happy

### 4. Sign with author's key

If metadata passes all the checks.
Sign it with the Intersect author key

using script

```shell
./scripts/create-author-witness.sh
```

Copy the authored one back.

### 5. Verify the witnesses

Check the author witnesses.

```shell
./scripts/verify-author-witness.sh
```

### 6. Host on IPFS

Host the author witnessed metadata on IPFS.

```shell
./scripts/ipfs.sh
```

### 7. Create the action files

todo
