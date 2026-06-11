#!/usr/bin/env bash
# shellcheck shell=bash
#
# Static configuration for the Intersect 2026 budget treasury-withdrawal pipeline.
# The budget-* scripts source this file automatically.

HYDRA_API_BASE="https://hydra-voting.intersectmbo.org/api/v0"

# Hydra vote (cycle) id for the 2026 budget process. Used by budget-proposals-fetch.sh
# to enumerate proposals via $HYDRA_API_BASE/proposals?vote=$HYDRA_VOTE_ID.
HYDRA_VOTE_ID="69dfeabdc3904a3d239858da"

# TODO: confirm the exact public path against the live site before submitting
# (the validator does a link-reachability check on references).
HYDRA_PROPOSAL_URL_BASE="https://hydra-voting.intersectmbo.org/votes/cardano-budget-2026/proposals"

WITHDRAWAL_ADDR="stake_test1uz6ljatyc7w52z44hskd5pu5cvw7qemwz6re3ux4pmdqumcn2qyrx"
DEPOSIT_RETURN_ADDR="stake_test1uz6ljatyc7w52z44hskd5pu5cvw7qemwz6re3ux4pmdqumcn2qyrx"

# --- Addresses shown verbatim in the Rationale "Budget Management Tooling" section ---
TRSC_STAKE_ADDR="stake_test1uz6ljatyc7w52z44hskd5pu5cvw7qemwz6re3ux4pmdqumcn2qyrx"
TRSC_PAYMENT_ADDR="addr_test1qr0ghja2nh9qp5zpss3p5wdkav07afsyl9k5vnuw8ssysna4l96kf3uag59tt0pvmgrefscaupnku958nrcd2rk6pehsd045pm"
PSSC_PAYMENT_ADDR="addr_test1qr0ghja2nh9qp5zpss3p5wdkav07afsyl9k5vnuw8ssysna4l96kf3uag59tt0pvmgrefscaupnku958nrcd2rk6pehsd045pm"

# --- References ---
# Link to the CSV listing all successful 2026 budget proposals (referenced from every
# metadata document). Use a hosted ipfs:// or https:// URI.
SUCCESSFUL_PROPOSALS_CSV_URL="https://REPLACEME.example/successful-proposals-2026.csv"
