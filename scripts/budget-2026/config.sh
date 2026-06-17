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
HYDRA_PROPOSAL_URL_BASE="https://hydra-voting.intersectmbo.org/votes/cardano-budget-2026"

WITHDRAWAL_ADDR="stake1784sdxt6jjennmstphgdu7l7c2scf5d02a6cve2dgn5s2kq5u3j9v"
DEPOSIT_RETURN_ADDR="stake1uyvjdz9rxsfsmv44rtk75k2rqyqskrga96dgdfrqjvjjpwsefcjnp"

# --- Addresses shown verbatim in the Rationale "Budget Management Tooling" section ---
TRSC_STAKE_ADDR="stake1784sdxt6jjennmstphgdu7l7c2scf5d02a6cve2dgn5s2kq5u3j9v"
TRSC_PAYMENT_ADDR="addr1x84sdxt6jjennmstphgdu7l7c2scf5d02a6cve2dgn5s2k8tq6vh499n88hqkrwsmealas4psng674m4sej5638fq4vqmxs59w"
PSSC_PAYMENT_ADDR="addr1x9d6k9z6t6fvsetj2djmerargk475lef9gfvshy4rwh4h7jm4v295h5jepjhy5m9hj86x3dtafljj2sjepwf2xa0t0aq048cay"

# --- References ---
# Link to the CSV listing all successful 2026 budget proposals (referenced from every
# metadata document). Use a hosted ipfs:// or https:// URI.
SUCCESSFUL_PROPOSALS_CSV_URL="https://REPLACEME.example/successful-proposals-2026.csv"
