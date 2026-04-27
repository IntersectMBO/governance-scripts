# Security & Footgun Review — governance-scripts

## Context

`governance-scripts` is operational tooling (Intersect MBO and third-party DReps) to **construct, validate, hash, sign, host, and submit Cardano governance actions** (info, treasury withdrawal, parameter change). The metadata it produces is anchored on-chain by hash; an error here can result in the **wrong treasury withdrawal recipient/amount, the wrong vote target, signature mismatches, or a hash that disagrees with what the user thinks they signed**.

The user asked for a deep review of "potential security or otherwise potentially dangerous behaviours which may cause users to make incorrect governance actions."

## Scope (locked with user)

- **Deliverable:** single markdown report, file at repo root, *untracked* (don't `git add`).
- **Threat model:** (1) honest operator processing hostile third-party metadata, (2) honest operator + honest authors, but tooling fails to catch human error, (3) third-party DRep running scripts on their own machine (local-privilege concerns).
- **Remediation depth:** identify each finding + propose one or two remediations. No code drafted in this pass.
- **Coverage:** include LOW/polish items.
- **Beyond `scripts/`:** also review `docs/*.md` procedures and `.github/` (CI). NOT in scope: `SECURITY.md` vs reality comparison; `scripts/archive/*`.
- **Extra focus:** hashing / canonicalization (user-flagged area of concern).
- **Verification:** every CRITICAL/HIGH finding must be empirically reproduced on this machine before it goes into the final report; LOW/MEDIUM may rely on code-reading but are tagged `[unverified]` if so.

## Report file

- Path: `/Users/ryan/cardano/ga-submission/governance-scripts/SECURITY-REVIEW-2026-04.md`
- Intentionally placed at repo root for visibility, but **not committed** (per user). `.gitignore` does not currently exclude it; user just doesn't `git add` it. If they later want it ignored permanently, they can add it to `.gitignore` themselves.

## Work plan

### Step 1 — Verify CRITICAL/HIGH findings empirically

Reproduce each on this machine with the actual scripts and fixtures. For each, capture the exact command and output and embed in the report.

Findings to verify (one section in the report per item):

1. **VERIFIED 2026-04-26. FIXED 2026-04-26 in `scripts/metadata-validate.sh`.** Originally: `metadata-validate.sh` reported "No validation errors found." (exit 0) for `test/lool.jsonld` despite `authors: []` and `"deposit": "null"`, and also for hand-crafted variants `"deposit": "abc"` and `"deposit": "-1e12"`. The schema check (`ajv` against the CIP-108 schema) does not constrain the type or numeric form of `deposit`/`value`, and `metadata-validate.sh` itself did not assert authors-presence or numeric-shape.

   Original reproductions (all exit 0, all print `No validation errors found.`):
   ```
   $ jq -r '.body.onChain.deposit' test/lool.jsonld
   null
   $ bash scripts/metadata-validate.sh test/lool.jsonld --cip108 --no-spell-check --no-check-links
   ... No validation errors found.
   $ jq '.body.onChain.deposit = "-1e12"' test/lool.jsonld > /tmp/lool-bad.jsonld \
       && bash scripts/metadata-validate.sh /tmp/lool-bad.jsonld --cip108 --no-spell-check --no-check-links
   ... No validation errors found.
   $ jq '.body.onChain.deposit = "abc"' test/lool.jsonld > /tmp/lool-abc.jsonld \
       && bash scripts/metadata-validate.sh /tmp/lool-abc.jsonld --cip108 --no-spell-check --no-check-links
   ... No validation errors found.
   ```

   Downstream caveat (partial mitigation): `action-create-tw.sh:165-169` defines `check_field` as `[ -z "$field_value" ] || [ "$field_value" = "null" ]`. Because `jq -r` on the JSON value `"null"` outputs the bareword string `null`, the literal-`"null"` deposit *is* caught at action-creation time. However, that defence is narrow — it only catches the exact empty-or-bareword-`null` case. `"abc"`, `"-1"`, `"1e12"`, `" 100 "`, and any other malformed string slip past `check_field` and only fail later inside `cardano-cli` (with an error message that may not clearly point at the metadata field).

   Why it was dangerous: a user who ran `metadata-validate.sh` and saw the green "No validation errors found." line — which is the only step the docs frame as "validation" — had no signal that:
   (a) their metadata was unsigned (`authors: []`), or
   (b) the deposit/value strings were not numeric.
   Both classes of error failed later or on-chain, and the cause/effect link back to the metadata file was not obvious.

   **Fix shipped:** a new "Structural integrity checks" stage runs after the ajv schema loop whenever any `--cip100/108/119/136/169` or `--intersect-schema` flag is in use. It enforces:
   - `authors` array is non-empty (FAIL by default; downgraded to WARN under the new `--draft` flag, for the create-then-sign workflow's first-pass validation). This fills a real gap in CIP-100, which declares `authors` as a required array but does **not** set `minItems: 1`.
   - A new `STRUCT_CHECK_FAILED` flag is wired into the final-result branch alongside `VALIDATION_FAILED` and `URI_CHECK_FAILED`, so structural failures cause exit 1 and the green "No validation errors found." line is never printed when they fire.

   **Numeric-shape check on `body.onChain.deposit` and `rewards[].value` deliberately NOT added.** An earlier draft of this fix included one — it is redundant. CIP-169's schema already defines `UInt64` as `"pattern": "^(0|[1-9][0-9]*)$"` and references it from `deposit` and every `rewards[].value`, so when the docs' standard `--cip108 --cip169` invocation is used, ajv catches a non-numeric deposit at `/body/onChain/deposit` with `must match pattern "^(0|[1-9][0-9]*)$"`. A user who runs `--cip108` alone (omitting `--cip169`) loses this coverage, but that's a misconfiguration the structural-check stage shouldn't paper over — the docs and the README both pair `--cip108 --cip169`, and `--cip108` alone has no way to express on-chain content anyway. Keeping the in-script numeric check would have duplicated logic and given the misleading impression that `--cip108` alone is sufficient.

   Post-fix verification (2026-04-26):
   ```
   $ bash scripts/metadata-validate.sh test/lool.jsonld --cip108 --cip169 --no-spell-check --no-check-links
   ... /tmp/metadata.json invalid                       # CIP-169 ajv catches deposit
   ... instancePath: '/body/onChain/deposit',
   ... message: 'must match pattern "^(0|[1-9][0-9]*)$"'
   ... [FAIL] authors: array is empty.                  # in-script catches authors
   ... One or more validation errors were found.        # exit 1

   $ bash scripts/metadata-validate.sh test/lool.jsonld --cip108 --cip169 --no-spell-check --no-check-links --draft
   ... /tmp/metadata.json invalid                       # CIP-169 still catches deposit
   ... [WARN] authors: array is empty. Acceptable under --draft; re-run without --draft after signing.
   ... One or more validation errors were found.        # exit 1

   $ # Hand-fixed copy: 1 author + numeric deposit
   $ bash scripts/metadata-validate.sh /tmp/lool-good.jsonld --cip108 --cip169 --no-spell-check --no-check-links
   ... /tmp/metadata.json valid
   ... [OK]   authors: 1 entry
   ... No validation errors found.                      # exit 0
   ```

   Schema-side remediation (NOT implemented in this change, deferred): the only remaining schema-side gap is CIP-100's missing `"minItems": 1` on `authors`. Recommend filing an upstream issue against `cardano-foundation/CIPs` (CIP-100). Once that lands, the in-script structural stage can be removed entirely. Until then, the in-script check is the practical mitigation.

   Procedure-doc follow-up (DONE): `docs/info-action-procedure.md` and `docs/treasury-withdrawal-procedure.md` updated 2026-04-26 to use `--draft` for the pre-signing pass (step 6) and bare invocation for the post-signing pass (step 9), with explanatory text on why each is required.
2. `metadata-validate.sh` does not flag `"value": "1000000000000"` (1M ADA) or warn on magnitude.
3. **VERIFIED 2026-04-26. FIXED 2026-04-26 in `scripts/action-create-tw.sh`.** Originally: `action-create-tw.sh:235-247` defined `is_stake_address_mainnet()` whose only address check was `[[ "$address" =~ ^stake1 ]]` (or `^stake_test1`) — a human-readable-part match that accepts any garbage in the bech32 data section. A single-character transcription error (`...fjar` → `...fjas`) on `body.onChain.reward_account` or `rewards[0].key` therefore flowed through to deeper `cardano-cli` invocations, where it surfaced with an error not clearly tied back to the metadata field.

   **Fix shipped:** added `validate_stake_address()` helper that runs `cardano-cli address info --address "$address"` (a purely-local BIP-173 bech32 checksum verifier — no node required) and rejects anything that either fails parsing or returns an address `type` other than `"stake"`. Called on both metadata-extracted addresses (`body.onChain.reward_account` and `body.onChain.gov_action.rewards[0].key`) before the existing prefix and header-byte checks; the user-supplied `--deposit-return-addr` / `--withdrawal-addr` are covered transitively because the existing equality check already rejects any input that doesn't equal the metadata field.

   Post-fix verification (2026-04-26):
   ```
   # 1. Corrupted bech32 checksum (last char flipped):
   $ bash scripts/action-create-tw.sh /tmp/lool-bad-addr.jsonld --deposit-return-addr stake1uy...fjas --withdrawal-addr stake1uy...fjar
   ... Error: metadata body.onChain.reward_account is not a valid bech32 address: stake1uy...fjas
   ... cardano-cli rejected it: Invalid address: "stake1uy...fjas"

   # 2. Real payment address (bech32-valid, but wrong type):
   $ bash scripts/action-create-tw.sh /tmp/lool-payment.jsonld ... --withdrawal-addr addr1qx2fxv2um...wfgse35a3x
   ... Error: metadata body.onChain.gov_action.rewards[0].key is bech32-valid but is not a stake address (type=payment): addr1qx2fxv2um...
   ```

   Schema-side / upstream remediation (NOT implemented, deferred): CIP-169's `RewardAddress` definition uses `"pattern": "^(stake1[02-9ac-hj-np-z]{53}|stake_test1[02-9ac-hj-np-z]{53})$"` — this constrains length and the bech32 character set, but is **not** a checksum check. ajv cannot validate bech32 checksums (no JSON Schema construct for it), so the in-script `cardano-cli` call is the right layer. No upstream issue to file.

   Same-class follow-up (NOT implemented in this change): `scripts/action-create-info.sh` accepts the same `--deposit-return-addr` and reads `body.onChain.reward_account` from the metadata. Recommend porting `validate_stake_address()` there too — straight copy-paste, same call site.

3a. **VERIFIED 2026-04-27. FIXED 2026-04-27 in `scripts/action-create-tw.sh`** — deposit-magnitude footgun. The script trusted `body.onChain.deposit` blindly; a misplaced zero (10,000 ADA instead of 100,000 ADA, or 1,000,000 ADA instead of 100,000) flowed through unchallenged. The current Cardano governance action deposit is fixed at 100,000 ADA = 100,000,000,000 lovelace, so any other value is overwhelmingly likely a typo on a hand-edited metadata file or a stale value copied from before the deposit parameter was set.

   **Fix shipped:** after the existing `check_field "deposit"`, the script now compares `deposit_amount` against the constant `EXPECTED_DEPOSIT_LOVELACE="100000000000"` and prints a yellow warning to stderr if they differ. **Warning, not error** — future protocol parameter updates could legitimately change this value, and on-chain validation is still the source of truth; we just want a visible nudge before the user proceeds.

   Earlier draft of this fix (a hard-fail `check_uint64_string` enforcing CIP-116's `^(0|[1-9][0-9]*)$` on `deposit` and `rewards[0].value`) was reverted: that pattern check is already enforced by CIP-169's schema via ajv when the docs' standard `--cip108 --cip169` invocation is used in `metadata-validate.sh`, so duplicating it here would be redundant. The magnitude check is the genuinely novel signal.

   Post-fix verification (2026-04-27):
   ```
   deposit="100000000000"   → (no warning, proceeds)             # the canonical 100k ADA
   deposit="10000000000"    → Warning: ... = 10000000000 lovelace, expected 100000000000 ...
   deposit="1000000000000"  → Warning: ... = 1000000000000 lovelace, expected 100000000000 ...
   deposit="50000000000"    → Warning: ... = 50000000000 lovelace, expected 100000000000 ...
   ```

   No equivalent magnitude warning added on `rewards[0].value` — that's the actual treasury withdrawal amount, which is genuinely variable per proposal and has no canonical "expected" value.

   **Same warning ported to `scripts/action-create-info.sh` (2026-04-27)** for symmetry, inserted right after the existing `check_field "deposit"`. Note that `action-create-info.sh` *also* has a stricter chain-query check later (line ~184-194: queries `cardano-cli conway query protocol-parameters | jq -r '.govActionDeposit'` and hard-fails on mismatch). The two are complementary: the warning fires immediately offline and gives an early visual nudge; the chain query is the authoritative confirmation.

3b. **VERIFIED 2026-04-27. FIXED 2026-04-27 in `scripts/action-create-tw.sh` and `scripts/action-create-info.sh`** — chain-query parity + layout consistency.

   Originally: `action-create-info.sh` had an authoritative deposit check (`cardano-cli conway query protocol-parameters | jq -r '.govActionDeposit'` + hard-fail on mismatch) that `action-create-tw.sh` was missing entirely. TW therefore relied solely on the offline magnitude warning from 3a, which would silently miss the case where the protocol-parameter deposit had been updated to a value other than 100,000 ADA. Info's existing block was also placed downstream of the address-comparison logic (separated from the magnitude warning) and contained a typo ("smame") and a redundant `if [ ! -z "$deposit" ]` wrapper that was already guaranteed by the preceding `check_field "deposit"`.

   **Fix shipped:**
   - **TW:** added the chain-query block immediately after the magnitude warning.
   - **Info:** added the same block in the same position (immediately after the magnitude warning) and removed the older downstream duplicate (which had the "smame" typo and the redundant guard).

   Both scripts now have identical, adjacent magnitude-warning + chain-query stanzas. The magnitude warning is the offline-friendly hint; the chain query is the authoritative source of truth (catches a deposit-parameter update that would invalidate the hardcoded constant).

   Post-fix verification (2026-04-27): with a bogus `CARDANO_NODE_SOCKET_PATH`, both scripts now print `"Checking that deposit matches the current protocol parameter"` exactly once before cardano-cli fails on the unreachable socket and `set -e` exits.

4. `metadata-validate.sh` does not fetch a reference URL and verify a declared `referenceHash` against the actual content. Construct a reference with a wrong hash and confirm validation passes.
5. `metadata-create.sh` fetches `@context` from `Ryun1/CIPs` `refs/heads/cip-governance-metadata-extension` — confirm by reading lines 6–7 of the script. Pinning is by branch name, not commit SHA.
6. `metadata-validate.sh --schema <URL>` accepts an arbitrary URL with no scheme/domain check (`metadata-validate.sh:140-143, 446`). Test by passing `http://127.0.0.1:0/x.json`; confirm the curl is attempted as-is.
7. **VERIFIED 2026-04-27. FIXED 2026-04-27 in `scripts/ipfs-pin.sh`.** Originally: three curl invocations (Pinata `Authorization: Bearer $PINATA_API_KEY`, Blockfrost `project_id: $BLOCKFROST_API_KEY`, NMKR `Authorization: Bearer $NMKR_API_KEY`) passed each API key via `-H "..."` in argv, where it was visible to any user on the system via `ps -ef`, captured in shell history, and persisted in any verbose curl logs.

   **Fix shipped:** added a `write_auth_header_file()` helper that writes one HTTP header line to a `mktemp`-created file (mode 600) and returns the path. Each of the three curl calls now uses the file form `curl -H @"$header_file"` (curl >= 7.55) so the secret never appears in argv. A new `SECRET_TMP_FILES` array tracks the temp files, and a `cleanup_secret_files()` function wired to `trap ... EXIT INT TERM` removes them on any exit path.

   Post-fix verification (2026-04-27) — used a curl shim that records its argv and the contents of any `@file` argument:
   ```
   Pinata     argv: -H @/var/folders/.../ipfs-pin-auth.N5rVKR        # tmp file path, no secret
              file: Authorization: Bearer SECRET-PINATA-XYZ123       # secret only in mode-600 file
   Blockfrost argv: -H @/var/folders/.../ipfs-pin-auth.WLcSXB
              file: project_id: SECRET-BLOCKFROST-XYZ123
   NMKR       argv: -H @/var/folders/.../ipfs-pin-auth.F8BLZs
              file: Authorization: Bearer SECRET-NMKR-XYZ123

   Assertion: no SECRET-* string appears in any argv block.   PASS
   Post-exit leftover ipfs-pin-auth.* files in tmp dirs:      0       (trap fired)
   ```

   Out-of-scope (NOT fixed): the response body that the script prints on error (lines 220-222, 249-251, 295-297) may contain rate-limit-headers or echoed credentials in some pinning-service error formats. Lower priority — those are vendor-controlled error responses, hard to predict, and only fire on the API call failing. Recommend adding a redaction sed pass over `$response` before the `jq .` echo if any vendor is found to echo back the auth value.
8. Symlink-through-extension-check: `ln -s /etc/passwd /tmp/evil.jsonld; metadata-canonize.sh /tmp/evil.jsonld` succeeds. Confirm.
9. `preflight.sh` exits 0 when `cardano-signer` is a different version than the pinned `1.27.0` — verify this is WARN-not-FAIL by reading the version-check branch and (if installed version differs) running it.

### Step 2 — Hashing / canonicalization deep dive (extra focus)

Beyond the inventory, walk the actual canonicalization path end-to-end:

- Read `scripts/metadata-canonize.sh:28` and `scripts/author-validate.sh:110` line-by-line — they both contain a perl regex that escapes raw control characters in `cardano-signer` output. Why does it exist? Could the two implementations diverge? Diff their regexes.
- For a metadata file that has Unicode (NFC vs NFD forms, BOM, or a stray U+200B), check whether the canonicalized hash is stable across (a) re-saving the file, (b) running on a different machine, (c) running with a different `cardano-signer` version. At minimum, document the hash for `test/lool.jsonld` on this machine; flag any non-determinism observed.
- Confirm that the bytes `cardano-signer canonize` hashes are the JSON-LD body **after** RDF normalization, not the file bytes. Document the divergence between `hash.sh` (raw file) and `metadata-canonize.sh` (canonicalized body) prominently — a user who confuses the two would compute the wrong on-chain hash.
- Look for any path where the user is shown a hash that does **not** match what will go on-chain.

### Step 3 — Inventory remaining MEDIUM/LOW findings (code-reading is fine; tag `[unverified]`)

From Phase 1 exploration, working list:

- ~~No `hashAlgorithm` enum check (anything other than `blake2b-256` would silently flow through).~~ **CLOSED 2026-04-27 — not a real gap; CIP schemas already enforce.** CIP-100 and CIP-108 both pin `hashAlgorithm` (top-level *and* per-reference `referenceHash.hashAlgorithm`) to `"enum": ["blake2b-256"]` via ajv. Verified with `.hashAlgorithm = "sha256"` against `--cip108`: ajv reports `instancePath: '/hashAlgorithm', schemaPath: '#/definitions/hashAlgorithm/enum'` and the script exits 1. The only scenario in which the enum *isn't* enforced is `--schema <URL>` with a custom or permissive schema — but that is an explicit user opt-out, and (consistent with the same call made on the CIP-116 numeric-shape and the wider structural-integrity checks) we shouldn't second-guess a user who deliberately swapped in their own schema. An earlier draft of this fix added an in-script backstop; reverted as redundant.
- Curl `--location` follows redirects without bound or destination check on every reference URL probe.
- No `http://` warning when references use plaintext.
- All schema/dictionary downloads chase branch heads, no caching, no hash pinning.
- Numeric type confusion is broader than `"null"`: `"1e12"`, `" 100 "`, `"-1"` likely all pass.
- Unicode / homoglyph / control-char / leading-trailing whitespace in `title`/`abstract` not flagged. Length-only check.
- Signing key path echoed to stdout in `author-create.sh:109`.
- ~~`ipfs-pin.sh` recursive directory mode would upload any `.jsonld` symlink target.~~ **VERIFIED 2026-04-27. FIXED 2026-04-27 in `scripts/ipfs-pin.sh`.** Two distinct gaps tracked under this item; on inspection the recursive-mode story turned out to be more nuanced than the original write-up suggested:
  - **Single-file mode (real vulnerability):** `[ -f "$input_path" ]` follows symlinks, so `bash ipfs-pin.sh symlink-to-secret.jsonld` would silently upload the symlink's target (e.g. `/etc/passwd`, `~/.cardano/keys/*.skey`) to public IPFS. **Fix:** added `[ -L "$input_path" ]` rejection in the single-file branch with a clear "pass the real file path instead" error.
  - **Recursive mode (already partially safe, now belt-and-braces):** `find -type f` matches regular files only — a symlink is type `l` and is excluded by default — so the original review's claim that recursive mode "would upload any `.jsonld` symlink target" was overstated. However: (a) the implicit safety would silently break under any future edit that swapped `find` for `find -L` or any change to the type filter, and (b) `find` *did* descend into `.git/` and pinned everything inside, which is a separate and more impactful leak (entire repo history, refs, hooks). **Fix:** added explicit `! -type l` to the find filter (defense-in-depth, makes the intent visible), and added a `-prune` clause for `.git`, `.svn`, and `.hg` metadata directories so the recursive walk no longer descends into them.

  Post-fix verification (2026-04-27):
  ```
  Test 1 — single-file with symlink:
  $ ln -sf /etc/passwd /tmp/ipfs-pin-test/symlink.jsonld
  $ bash scripts/ipfs-pin.sh /tmp/ipfs-pin-test/symlink.jsonld ...
  Error: '/tmp/ipfs-pin-test/symlink.jsonld' is a symbolic link. Refusing to pin a symlink target — pass the real file path instead.

  Test 2 — recursive on a directory containing real.jsonld + 2 symlinks + .git/objects/some-hash + .git/config:
  $ bash scripts/ipfs-pin.sh /tmp/ipfs-pin-test ...
  Found 1 files to process       # only real.jsonld; symlinks and .git/* both pruned
  Processing file: /tmp/ipfs-pin-test/real.jsonld
  ```

  **Sensitive-filename deny gate (HIGH, ADDED 2026-04-27 after the symlink fix landed.)** Even with `.git/*` pruned and symlinks rejected, a recursive `bash ipfs-pin.sh ~/.cardano/governance-stuff` would still upload any `*.skey` / `*.vkey` / `.env*` / `id_rsa` / `*.pem` files in the tree — publishing a Cardano signing key or environment credentials permanently to public IPFS. Fixed by adding `is_sensitive_filename()` (regex `\.(skey|vkey|env)$|^\.env(\..*)?$|^id_(rsa|ed25519|ecdsa|dsa)(\.pub)?$|\.(pem|p12|pfx)$`) and a hard refusal at the top of `pin_single_file()` so both single-file and recursive paths are protected at the same chokepoint. Verified with `payment.skey` (refused), `stake.vkey` (refused), `.env` (refused), and `real.jsonld` (proceeded normally).

  **NMKR JSON injection (LOW, ADDED 2026-04-27.)** The NMKR upload built its request body via a heredoc with `"name": "$(basename "$file")"` — a filename containing `"` or `\` would produce malformed JSON, and a filename containing `$(...)` would be shell-evaluated. Fixed by building the body with `jq -n --arg name "..." --arg b64 "..." '{...}'` so all interpolation is properly escaped, and switching `-d @-` to `--data-binary @-` so curl doesn't strip newlines. Verified with a filename containing a literal `"`.

  **Explicit `--directory` opt-in (HIGH, ADDED 2026-04-27.)** Even with all the above filters in place, `bash ipfs-pin.sh ~/some-project` would still walk the tree and pin everything that survived the deny gates — usually hundreds of files, against the user's pinning-service quotas, irrevocably. This is the "I pointed it at the wrong thing" footgun. Fixed by adding a required `--directory` flag: a directory path without the flag is rejected with a clear error pointing at the flag and explaining what it does (compared to `rm -r`); a directory path *with* the flag prints a yellow warning ("Pinning is publishing: anything uploaded becomes permanently retrievable from public IPFS gateways") and proceeds. The flag is also rejected when the path is a single file (catches the inverse typo).

  Verified four cases:
  ```
  dir/  (no flag)       → Error: '...' is a directory.  Pass --directory to confirm ...
  dir/  --directory     → Warning: --directory is set — this will recursively pin ...
                            Found N files to process    (proceeds)
  file  --directory     → Error: --directory was set, but '...' is a single file.
  file  (no flag)       → unchanged: single-file upload
  ```

  Still out-of-scope (NOT fixed): `node_modules/`, `__pycache__/`, `.direnv/` aren't in the prune list. These are operational hygiene rather than security — recommend adding as a follow-up if recursive mode is run against project trees regularly.
- `metadata-validate.sh:444` cosmetic typo `{$user_schema_url}`.
- No rate limiting on IPFS gateway probes.
- Aspell dictionary fetched at runtime each run.

### Step 4 — Review `docs/*.md` procedures

Read:
- `docs/info-action-procedure.md`
- `docs/treasury-withdrawal-procedure.md`

For each: flag any step that gives the user a false sense of safety, omits a critical check, or instructs an unsafe order of operations (e.g., "build action before signing the metadata," "skip author signature for testing"). Cross-reference with the validation gaps above — if the docs tell users to rely on `metadata-validate.sh` as the green light, that compounds finding A2 (empty `authors: []` passes).

### Step 5 — Review `.github/`

~~Confirmed: only `.github/pull_request_template.md` exists. **No CI workflows.** This is itself a finding — the validation scripts that gate correctness for governance metadata are never run automatically on PRs that modify the scripts themselves. A PR that disables a check (or introduces a regression in canonicalization) would not be caught by CI. Recommendation: add a workflow that, at minimum, runs `metadata-validate.sh` against the test fixtures on every PR. Surface this as a HIGH finding.~~

**FIXED 2026-04-27** by adding `.github/workflows/ci.yml` plus a small drift-detection harness at `test/cip-examples/`.

The workflow runs on `pull_request` and `push` to `main`, paths-filtered to `scripts/**`, `test/**`, `.github/workflows/**` so unrelated doc-only PRs don't pay the build cost. Two jobs:

1. **`lint`** — `shellcheck --severity=error scripts/*.sh` and `bash -n` on every script. Locks in the syntactic / `set -e`-interaction class of regressions. Severity is `error` only for now (don't fail on warnings/info); tighten once existing notices are addressed.

2. **`canonize`** — Installs `cardano-signer` 1.27.0 from its release tarball (cached by version key in `runner.tool_cache`, so first PR pays ~30s and subsequent PRs are instant), then runs `bash test/cip-examples/verify.sh`. The verifier:
   - Reads `test/cip-examples/sources.tsv` — five upstream CIP example fixtures pinned **by commit SHA** (not branch) on `cardano-foundation/CIPs`: two CIP-108 examples (treasury-withdrawal, no-confidence), one CIP-119 (drep), two CIP-136 (treasury-withdrawal-unconstitutional, parameter-change-abstain).
   - Downloads each, re-canonizes via `cardano-signer canonize --cip100` (with `--disable-safemode` for CIP-119 and CIP-136 documents — cardano-signer 1.27.0 doesn't recognise those body shapes as CIP-108-compatible, but canonization is still deterministic).
   - Compares the resulting blake2b-256 hash against a checked-in golden in the same TSV.
   - Drift in any of: cardano-signer version, the perl control-char escape behaviour, the pinned upstream file (should be impossible under SHA pinning), or our wrapper scripts will surface as a CI failure with a "do not just bump the golden — investigate" message.

   **Why no schema-validation step on the upstream examples?** The published upstream examples currently do not conform to their own published schemas (e.g. CIP-100's `witnessAlgorithm` enum is `["ed25519"]` only, but CIP-108 example documents use `"CIP-0008"`; CIP-108's schema requires `name` on each author, but the examples omit it). That's an upstream inconsistency outside this repo's scope to fix. Per-author validation regressions in our own scripts are still observable via the existing `test/lool.jsonld` fixture, which conforms; the CI harness can be extended to run `metadata-validate.sh` against `test/*.jsonld` as a follow-up if desired.

   The full list of fixtures and their goldens is in `test/cip-examples/sources.tsv`. The verifier is also runnable locally (`bash test/cip-examples/verify.sh`) — useful when bumping the cardano-signer version or pinning a new upstream SHA.

### Step 6 — Compose the final report

Write `SECURITY-REVIEW-2026-04.md` at the repo root with this structure:

1. **Summary** — one paragraph; threat model in scope; count of findings by severity.
2. **CRITICAL** — could cause an incorrect on-chain action. For each: file:line, what it does, **reproduction** (exact command + observed output from Step 1/2), why it's dangerous, 1–2 proposed remediations.
3. **HIGH** — supply-chain integrity, secret exposure, missing CI gating.
4. **MEDIUM** — silent fallbacks, missing input checks, environmental brittleness.
5. **LOW** — polish, ergonomic improvements, cosmetic typos.
6. **Hashing / canonicalization deep dive** — separate section as an appendix; results from Step 2.
7. **Out of scope / not reviewed** — explicit list (`SECURITY.md` vs reality, `scripts/archive/*`, anything I haven't touched) so the user knows what's *not* covered.

Findings table at the top with columns: # | severity | finding | file:line | proposed remediation.

## Critical files referenced in the review

- `scripts/metadata-create.sh` (lines 6-7: un-pinned remote @context fetch; line 247: output path; line 727: hardcoded blake2b-256)
- `scripts/metadata-validate.sh` (lines 140-143, 446: arbitrary --schema URL; lines 208-236: schema validation; lines 274-381: link/URI validation; line 444: cosmetic typo; lines 393-446: schema downloads)
- `scripts/metadata-canonize.sh` (line 28: perl control-char escape; line 13: extension check)
- `scripts/action-create-tw.sh` (lines 169, 185-186, 194-195: deposit/value extraction; line 238: stake addr regex; line 202: tag check)
- `scripts/action-create-info.sh` (line 92: extension check)
- `scripts/author-create.sh` (lines 103-151: signing key handling; line 109: key path echo)
- `scripts/author-validate.sh` (line 85: Intersect author key fetch; line 110: perl control-char escape — duplicate of metadata-canonize.sh:28)
- `scripts/ipfs-pin.sh` (lines 117, 213-291, 322-327: API key headers, base64 payload, recursive find)
- `scripts/ipfs-check.sh` (lines 122-127: hardcoded gateways)
- `scripts/preflight.sh` (lines 128-134, 192-222: WARN-not-FAIL on version mismatch, env not sourced)
- `scripts/hash.sh` (lines 42-45: dual b2sum + cardano-cli)
- `docs/info-action-procedure.md`, `docs/treasury-withdrawal-procedure.md` (procedure language review)
- `.github/` (CI gap)
- `test/lool.jsonld` (lines 83, 99, 105-106: empty authors, `"deposit": "null"`, 1M ADA value — used as the canonical reproduction fixture)

## Verification — how to confirm the final report is correct

The report is "correct" if:

1. Every CRITICAL/HIGH finding has a copy-pasteable command and an observed output captured under "Reproduction."
2. The deep-dive section documents the actual hash produced by `metadata-canonize.sh test/lool.jsonld` on this machine, plus any divergence noted between the perl-escape implementations.
3. The user can read any single finding standalone and act on it without needing the rest of the report (each finding is self-contained: file:line, what, why, fix).
4. The "out of scope" section is explicit so the user is not surprised by gaps.
