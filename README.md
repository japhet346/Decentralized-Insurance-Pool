# 🛡️ Decentralized Insurance Pool (Clarity Smart Contract)

A decentralized mutual insurance system built in Clarity for the Stacks blockchain. This smart contract enables risk-pooled insurance, member-based governance, and trustless claims management.

---

## ✨ Features

- Create and manage insurance pools
- Join pools by paying premiums
- Submit and vote on claims
- Risk scoring and dynamic premium calculation
- Transparent, community-governed claims processing

---

## 🧱 Core Concepts

- **Pools:** Each pool has a base premium and funds accumulated from members.
- **Members:** Must join a pool to participate and vote. Risk scores affect premiums.
- **Claims:** Submitted by members and resolved via member voting.
- **Voting:** Each member can vote once per claim during the voting window (~24 blocks).
- **Risk Adjustment:** Owner can adjust risk scores and pool-wide risk multipliers.

---

## 🔧 Functions

### Pool Management
- `create-pool(name, base-premium)`
- `join-pool(pool-id, initial-premium)`
- `pay-premium(pool-id, amount)`

### Claims
- `submit-claim(pool-id, amount, description)`
- `vote-on-claim(claim-id, approve)`
- `finalize-claim(claim-id)`

### Admin (Owner Only)
- `update-risk-score(pool-id, member, new-score)`
- `adjust-pool-multiplier(pool-id, new-multiplier)`

### Read-Only
- `get-pool(pool-id)`
- `get-member(pool-id, member)`
- `get-claim(claim-id)`
- `get-member-vote(claim-id, voter)`
- `calculate-premium(pool-id, member)`
- `get-pool-stats(pool-id)`
- `get-contract-balance()`


## 🚧 Error Codes

| Code | Meaning              |
|------|----------------------|
| 100  | Owner-only function  |
| 101  | Not a member         |
| 102  | Insufficient funds   |
| 103  | Claim not found      |
| 104  | Already voted        |
| 105  | Voting closed        |
| 106  | Invalid amount       |
| 107  | Pool not found       |
| 108  | Already a member     |

---
