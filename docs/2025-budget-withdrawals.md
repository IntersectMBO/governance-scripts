# Intersect 2025 Budget Treasury Withdrawals

Here we intend to document the scripts used within the technical processes of building and verifying the treasury withdrawal actions.

## Steps

### Pre-Requisites

Have authored your treasury withdrawal metadata.
This is done via Google docs.

### 1. Download `.docx` into working directory

For Intersect [governance-actions](https://github.com/IntersectMBO/governance-actions) will be used as a working directory.

### 2. Set environment variables

Set secrets, you can use the `.env` file for this.

```shell
source ./scripts/.env
```

Set some useful variables

```shell
export DEPOSIT_RETURN_ADDR="stake1uyvjdz9rxsfsmv44rtk75k2rqyqskrga96dgdfrqjvjjpwsefcjnp"
export WITHDRAWAL_ADDR="stake17xzc8pt7fgf0lc0x7eq6z7z6puhsxmzktna7dluahrj6g6ghh5qjr"
```

Make sure that `CARDANO_NODE_NETWORK_ID` and `CARDANO_NODE_SOCKET_PATH` are set.

### 3. Create the metadata documents

Convert the `.docx` to [intersect's metadata standard](https://github.com/IntersectMBO/governance-actions/tree/main/schemas) (this is a modified CIP-108 document).

With the `metadata-create` script taking the data from the doc and creating a `.jsonld`.

```shell
./scripts/metadata-create.sh my-metadata.docx --deposit-return-addr $DEPOSIT_RETURN_ADDR
```

### 4. Sanity check the metadata

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

We will pass `--no-author` as we know there is no author witness yet.

We will pass `--no-ipfs` as we know we didn't put it on ipfs yet.

We will also pass in our known deposit address and withdrawal address.

```shell
./scripts/budget-metadata-validate.sh ./my-metadata-directory --no-author --no-ipfs --deposit-return-addr $DEPOSIT_RETURN_ADDR --withdrawal-addr $WITHDRAWAL_ADDR
```

### 6. Sign with author's key

If metadata passes all the checks.
Sign it with the Intersect author key

(this will be done via an air-gapped setup)

```shell
./scripts/author-create.sh ./my-metadata-directory intersect-key.skey --author-name "Intersect"
```

### 7. Verify the author's witness

Check the author witness via the same script
as we know it checks everything.

Ensure it is from the expected intersect key

We will pass `--no-ipfs` as we know we didn't put it on ipfs yet.

```shell
./scripts/budget-metadata-validate.sh ./my-metadata-directory --no-ipfs --deposit-return-addr $DEPOSIT_RETURN_ADDR --withdrawal-addr $WITHDRAWAL_ADDR
```

### 8. Host on IPFS

Pin the metadata to different IPFS pinning services.

```shell
./scripts/ipfs-pin.sh ./my-metadata-directory
```

### 9. Verify IPFS hosting

We can use `budget-metadata-validate.sh` now without the `--no-ipfs` flag

This will now additionally check that the file is accessible via IPFS and that all the references (if they are using IPFS) are also accessible.

```shell
./scripts/budget-metadata-validate.sh ./my-metadata-directory --deposit-return-addr $DEPOSIT_RETURN_ADDR --withdrawal-addr $WITHDRAWAL_ADDR
```

### 10. Create the action file

Now we can create a governance action file from our metadata.

This performs some validations
- can check against some known deposit return and withdrawal address
- checks that metadata fields are present
- compares the addresses against the local node
- checks if withdrawal address is script-based
- checks if withdrawal address and deposit address are registered
- checks if withdrawal address is not vote delegated or is delegated to auto-abstain
- checks that the metadata is hosted on ipfs
- has user manually confirm the addresses and the amount

```shell
./scripts/action-create-tw.sh my-metadata.jsonld --withdraw-to-script --deposit-return-addr $DEPOSIT_RETURN_ADDR --withdrawal-addr $WITHDRAWAL_ADDR
```

### 11. Share the action file

Share the action file and the `.action.json` representation publicly.

Have people check that this looks good.

You **don not** want to mess this up!

Checks;
- withdrawal and stake address are correct
- withdrawal address is script-based
- withdrawal amount is correct
- metadata compliance with .docx
- hash and URI match

### 12. Submit test actions to testnets

Manually submit the action to other networks.

We want to check that the metadata is picked up properly.

### 13. Build the mainnet transaction

Manually, dependent on where the deposit is from.

### 14. Check the transactions

Manually, review and double check all key details.