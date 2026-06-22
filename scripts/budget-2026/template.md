## Title
Withdraw {{WITHDRAW_AMOUNT}} ada for {{TITLE_NAME}} administered by Intersect

## Abstract

This Treasury Withdrawal funds {{FULL_TITLE}}.

This Treasury Withdrawal is submitted by Intersect on behalf of the vendor. The content for the following sections; Abstract, Motivation and Rationale have been sourced from the approved proposal submitted by the Vendor as part of the Intersect budget process.

## Motivation

{{PROJECT_HIGH_LEVEL}}

## Rationale

### Strategic Pillar Alignment

{{PILLAR_RATIONALE}}

### Intersect Budget Process

This proposal achieved the required 67% support threshold during the 2026 Intersect Budget Process Hydra Voting phase and has therefore been advanced for on-chain Treasury Withdrawal Governance Action submission in accordance with the approved Budget Process Framework.

### Net Change Limit Compliance

The requested amount does not at time of submission, on its own or in aggregate, breach the applicable [350M Net Change Limit](https://explorer.cardano.org/governance-action/gov_action1m3xx08yv788vfxqh6nfvrjtvmqpwezsy0ggaczctkyjmttc2wmxsq4jsr7q) covering Epoch 613 to Epoch 713.  
In accordance with the guardrail TREASURY-02a, this withdrawal does not exceed the NCL at the moment of submission.

### Audit & Oversight

Audit and oversight costs are included within the overhead applied to this proposal. The Intersect administration fee covers administrative oversight and is reflected within the cost of this proposal. Independent oversight will be provided through Intersect and technically capable third-party, including reporting obligations and milestone-based disbursement controls.

### Prior Treasury Funding Disclosure

{{PRIOR_FUNDING}}

### Budget Summary

{{BUDGET_BREAKDOWN}}
### Intersect Budget Management Tooling

To administrate treasury funds on-chain, Intersect will utilize the treasury management smart contract framework developed by Sundae Labs. A new instance of these smart contracts has been deployed for 2026, mirroring the contracts from the 2025 budget cycle.

- The 2026 Treasury Reserve Smart Contract stake address: `stake1784sdxt6jjennmstphgdu7l7c2scf5d02a6cve2dgn5s2kq5u3j9v`  
- The 2026 Treasury Reserve Smart Contract payment address: `addr1x84sdxt6jjennmstphgdu7l7c2scf5d02a6cve2dgn5s2k8tq6vh499n88hqkrwsmealas4psng674m4sej5638fq4vqmxs59w`
- The 2026 Project Specific Smart Contract payment address: `addr1x9d6k9z6t6fvsetj2djmerargk475lef9gfvshy4rwh4h7jm4v295h5jepjhy5m9hj86x3dtafljj2sjepwf2xa0t0aq048cay`

#### Specifics

Intersect will utilize a single Treasury Reserve Smart Contract (TRSC), with one Project-Specific Smart Contracts (PSSC). Intersect’s management consists of five ‘admin’ and three Intersect ‘leadership’ roles. An Oversight Committee consisting of six external, independent third-party entities will provide checks and balances on Intersect, and safeguard against errors and unilateral control. The administration of both TRSC and PSSC will be managed by Intersect, with external oversight on certain actions from the Oversight Committee.

The Oversight Committee consists of Sundae Labs, Cardano Foundation, Dquadrant, NMKR, Sundial and Eternl. Their role is to independently verify key administrative actions using on-chain logic, ensuring accuracy and consistency without exercising discretion over governance decisions.

For all details on Intersect’s configuration please see the 2025 [**Smart Contract Guide**](https://docs.intersectmbo.org/cardano-facilitation-services/cardano-budget/intersect-administration-services/smart-contracts-as-part-of-our-administration) on the knowledgebase.

The high level permissions are as follows:

* TRSC Fund and PSSC Modify  
  * Two of the five Intersect admins, two of the six trusted entities and one of the three Intersect leadership sign-off must authorize  
* TRSC Disburse  
  * Two of five Intersect admins, three of six trusted entities and two of three Intersect leadership sign-off must authorize  
* TRSC Pause and Resume  
  * Two of five Intersect admins, and one of three Intersect leadership sign-off must authorize  
* TRSC Sweep  
  * One of five Intersect admins, and one of three Intersect leadership sign-off must authorize  
* TRSC Reorganize  
  * Two of five Intersect admins and three of six trusted entities must authorize

#### Processes

Upon enactment of this governance action, funding for this project will be directed into the TRSC’s stake address. All instances of TRSC and PSSC can not be staked with a SPO and are delegated to the auto-abstain predefined DRep. From here funds will be withdrawn into a UTxO remaining at the TRSC payment address.

When the Legal contract is prepared and the vendor is ready, funding for this project will be transferred using the Fund action to the PSSC. All milestones will be outlined within the metadata.

A dashboard is available ([treasury.sundae.fi](http://treasury.sundae.fi)) for the community to audit the TRSC or PSSC and track metrics related to this withdrawn ada as well as being immutably verifiable on chain.

## References

* [Project Proposal via Intersect Budget Process Hydra Voting]({{HYDRA_PROPOSAL_LINK}})
* [Intersect Budget Process Hydra Voting Documentation](https://docs.hydra-voting.intersectmbo.org/)
* [Intersect Budget Process Hydra Voting Auditor Guide](https://docs.ekklesia.vote/audit/technical)
* [Intersect Budget Process Hydra Voting Final Audited Results (Gitbook)](https://docs.intersectmbo.org/intersect-knowledge-base/cardano-facilitation-services/cardano-budget-2026/2026-budget-process-final-audited-results)
* [Intersect Budget Process Hydra Voting Audit Report (PDF)](ipfs://bafkreibbn432apngjzth2kahjkhp2fgw6zmvwcjnl4w6gvz6j7yq5gyaiu)
* [Automating Accountability: Cardano's Smart Contract Framework Blog](ipfs://bafybeihqx4ae72z7suqfnxrpqpqithp43cai7o2uuewnqtezgaoyc3ptyq)
* [Sundae Labs Budget Management Smart Contracts Github Repository](https://github.com/SundaeSwap-finance/treasury-contracts)
* [Budget Management Smart Contracts TxPipe Audit Report](ipfs://bafybeiccnwejbgj43wo6hrlseckkkmprtoqc5cfuy2hesm6c6yealwho3e)
* [Budget Management Smart Contracts MLabs Audit Report](ipfs://bafybeiah5fnjhda5hemj3qvaehc4mre3qllqzw2l7mkdsguytn4ftgafw4)

## Authors
