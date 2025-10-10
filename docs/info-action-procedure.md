# Info Action Procedure

Here we intend to document the script and steps within to build a new Info action.

## Steps

### 1. Author new metadata via Google Docs

Using the Google Docs template:

- [governance-action-metadata-template](https://docs.google.com/document/d/1ry0ci4Ktno_O-fS8-g-Ht1BcEnV1FXLWa2iAUIt8-dI/edit?tab=t.0)

### 2. Export markdown file

Export your metadata from Google Docs as markdown file.

### 3. Set environment variables

Set secrets, you can use the `.env` file for this.

```shell
source ./scripts/.env
```

Optionally you can some variables to be reused.

```shell
export DEPOSIT_RETURN_ADDR="my-address"
```

Make sure that `CARDANO_NODE_NETWORK_ID` and `CARDANO_NODE_SOCKET_PATH` are set.
These are needed to build the governance action file.

### 4. Create the metadata document

Convert the `.md` to [intersect's metadata standard](https://github.com/IntersectMBO/governance-actions/tree/main/schemas) (this is a modified CIP-108 document).

With the `metadata-create` script taking the data from the doc and creating a `.jsonld`.

```shell
./scripts/metadata-create.sh my-metadata.md --governance-action-type info --deposit-return-addr $DEPOSIT_RETURN_ADDR
```

### 5. Sanity check the metadata

Generate a(nother) markdown representation from the created `.jsonld`
and manually compare against the `.docx`.

```shell
./scripts/cip-108-create-human-readable.sh my-metadata.jsonld
```

### 6. Validate the metadata

We can then run our validation script to check

- compliance with CIP schema(s)
- compliance with Intersect schemas
- spelling check

```shell
./scripts/metadata-validate.sh ./my-metadata-directory --cip108
```

If running with Intersect schema this will give us an error for missing author, this is okay.

### 7. Add author witness(es)

If metadata passes all the above validations.
We can sign it with author key(s).

You can either pass the `my-metadata.jsonld` to authors to sign, using something like `./scripts/author-create.sh`.
Or you can run `./scripts/metadata-canonize.sh` and share the canonized body hash to sign via standard cardano wallets.

### 7. Verify the author's witness(es)

Just to double check that all is good now, with author.

```shell
./scripts/author-validate.sh my-metadata.jsonld
```

### 8. Final validation

Just to double check that all is good now.

- compliance with CIP schema(s)
- compliance with Intersect schemas
- spelling check

```shell
./scripts/metadata-validate.sh ./my-metadata-directory --cip108 --intersect-schema
```

### 9. Host on IPFS

Pin the metadata to different IPFS pinning services.

```shell
./scripts/ipfs-pin.sh ./my-metadata-directory --only-ipfs
```

### 10. Verify IPFS hosting

This will now additionally check that the file is accessible via IPFS.

```shell
./scripts/ipfs-check.sh my-metadata.jsonld
```

### 11. Create the action file

Now we can create an Info governance action file from our metadata.

```shell
./scripts/action-create-info.sh my-metadata.jsonld --deposit-return-addr $DEPOSIT_RETURN_ADDR
```
