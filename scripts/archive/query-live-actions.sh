#!/bin/bash

# Dependencies: curl, jq
API_BASE="https://api.koios.rest/api/v1"

# Get all proposals from Koios 
echo "Fetching proposal list from Koios..."
proposals=$(curl -s -X GET "$API_BASE/proposal_list" -H "accept: application/json")

# Filter for proposals that are still active (not ratified, enacted, dropped, expired)
active_proposals=$(echo "$proposals" | jq -c '.[] | select(
  (.ratified_epoch == null) and
  (.enacted_epoch == null) and
  (.dropped_epoch == null) and
  (.expired_epoch == null)
)')

echo "Fetching voting summaries and titles for active proposals..."

results=()

while IFS= read -r proposal; do
  pid=$(echo "$proposal" | jq -r .proposal_id)

  # Extract the title from meta_json.body.title (fallback to "No Title" if missing)
  title=$(echo "$proposal" | jq -r '.meta_json.body.title // "No Title found"')

  # Fetch the voting summary
  summary=$(curl -s -X GET "$API_BASE/proposal_voting_summary?_proposal_id=$pid" -H "accept: application/json")

  if [[ $(echo "$summary" | jq 'length') -gt 0 ]]; then
    row=$(echo "$summary" | jq -r --arg id "$pid" --arg title "$title" '
      .[0] | {
        proposal_id: $id,
        title: $title,
        drep_yes_pct,
        drep_no_pct,
        drep_abstain_votes_cast,
        drep_yes_votes_cast,
        drep_no_votes_cast
      }'
    )
    results+=("$row")
  fi
done <<< "$(echo "$active_proposals")"

# Sort and display the results by drep_yes_pct (descending)
echo -e "\nSorted Active Proposals by drep_yes_pct:"
printf '%s\n' "${results[@]}" | jq -s 'sort_by(.drep_yes_pct | tonumber) | reverse[]'