# Intersect 2025 Budget Treasury Withdrawals

Here we intend to document the scripts used within the technical processes of building and verifying the treasury withdrawal actions.

## Steps

### Pre-Requisites

Have authored your treasury withdrawal metadata.
This is done via Google docs.

### 1. Download `.docx` into working directory

For Intersect [governance-actions](https://github.com/IntersectMBO/governance-actions) will be used as working directory.

### 2. Create the metadata documents

Convert the `.docx` to [intersect's metadata standard](https://github.com/IntersectMBO/governance-actions/tree/main/schemas)
this is a modified CIP-108 document.

With the `metadata-create` script taking the data from the doc and creating a `.jsonld`.

```shell
./scripts/metadata-create.sh my-metadata.docx
```

### 3. Sanity check the metadata

Generate a markdown representation from the created `.jsonld`
and manually compare against the `.docx`.

```shell
./scripts/cip-108-create-human-readable.sh my-metadata.jsonld
```

### 4. Formally validate the metadata

Ensure that the metadata documents are correct.

automated checks:
- compliance with CIP schema(s)
- compliance with Intersect schema
- spelling check

```shell
./scripts/metadata-validate.sh
```

### 5. Budget specific tests to validate the metadata

Then do specific budget checks:
- is author valid?
- expected withdrawal and deposit address?
- addresses are key-based or script-based?
- manually confirm the withdrawal amount

```shell
./scripts/budget-metadata-validate.sh
```

### 6. Sign with author's key

If metadata passes all the checks.
Sign it with the Intersect author key

(this will be done via an air-gapped setup)

```shell
./scripts/author-create.sh
```

### 6. Verify the witnesses

Check the author witnesses.

```shell
./scripts/verify-author-witness.sh
```

### . Host on IPFS

Host the author witnessed metadata on IPFS.

```shell
./scripts/ipfs.sh
```

### . Create the action files

todo

### . Check action files

todo

### . Build the transactions

todo

### . check the transactions

todo