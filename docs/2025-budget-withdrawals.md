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
### 5. Validate the metadata

automated formal checks:
- compliance with CIP schema(s)
- compliance with Intersect schema
- spelling check

Then do specific budget checks:
- is author valid?
- is metadata discoverable on ipfs?
- Metadata has correct `governanceActionType`
- Title does not contain the term 'ada'
- Title length is acceptable
- Abstract length is acceptable
- Withdrawal amount in the title matches the metadata
- Provided deposit return address matches the metadata
- Provided withdrawal address matches the metadata
- All IPFS references are discoverable via IPFS

```shell
./scripts/budget-metadata-validate.sh ./my-metadata-directory
```

### 6. Sign with author's key

If metadata passes all the checks.
Sign it with the Intersect author key

(this will be done via an air-gapped setup)

```shell
./scripts/author-create.sh my-metadata.jsonld intersect-key.skey
```

### 7. Verify the author's witness

Check the author witness.

Ensure it is from the expected intersect key.

```shell
./scripts/author-validate.sh my-metadata.jsonld
```

### 8. Host on IPFS

Pin the metadata to different IPFS pinning services.

You'll need to set the secrets for these pinning services first.

```shell
source ./scripts/.env

./scripts/ipfs-pin.sh my-metadata.jsonld
```

### 9. Check metadata is accessible via IPFS

Hit a couple of gateways and see if it is accessible.

```shell
./scripts/ipfs-check.sh my-metadata.jsonld
```

### 10. Create the action file

Now we can create a governance action file from our metadata.

This does require `CARDANO_NODE_NETWORK_ID` and `CARDANO_NODE_SOCKET_PATH` to be set.

This performs some validations
- can check against some known deposit return and withdrawal address
- checks that metadata fields are present and look right
- compares the addresses against the local node
- checks if withdrawal address is script-based
- checks if withdrawal address and deposit address are registered
- checks if withdrawal address is not vote delegated or is delegated to auto-abstain
- checks that the metadata is hosted on ipfs
- has user manually confirm the addresses and the amount

```shell
./scripts/ipfs-check.sh my-metadata.jsonld --withdraw-to-script --deposit-return-addr <stake address> --withdrawal-addr <stake address>
```

### 11. Share the action file

Share the action file and the .json representation publicly.

Have people check that this looks good.
You dont want to mess this up.

Checks;
- withdrawal and stake address are correct
- withdrawal address is script-based
- withdrawal amount is correct
- metadata compliance with .docx
- hash and URI match

### 12. Check action file

Automated checks.

Checks;
- withdrawal and stake address are correct
- withdrawal address is script-based
- withdrawal amount is correct -- can auto-check against title
- metadata accessible via IPFS
- metadata compliance with .docx
- hash and URI match
- manually have the user confirm aspects too

```shell
./scripts/action-validate.sh my-action.action
```

### 13. Build the transaction

todo

### . check the transactions

todo