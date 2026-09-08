# CIP-179 link-authoring validation

The v5 link authoring path accepts decimal survey indices from 0 through 65535,
including leading zeros, without passing unbounded input to shell arithmetic.
An explicit `--network` binds every local node query to mainnet, preprod magic 1,
or Preview magic 2. Matching deposits alone do not establish network identity.

Run `python3 test/metadata_test.py` from this checkout. The 14 offline cases
execute the real authoring script with HTTP and cardano-cli fixtures. They cover
ordinary metadata without a survey, inline link context, bounds, stale or
contradictory deposit providers, and explicit node network selection. Bash, jq,
Python 3 and standard Unix tools are required. No live node or wallet is used.
Test output stays in ignored `.test-artifacts/`; the script respects `TMPDIR`.

This authors links; it does not establish a referenced survey's owner proof,
lifecycle or response validity. Actual node and ledger acceptance remain a
separate Preview deployment check.
