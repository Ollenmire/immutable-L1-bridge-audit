# Immutable Bridge Withdrawal Queue Audit

## Overview

This repository contains a full security analysis and proof-of-concept (PoC) test suite for the **`RootERC20BridgeFlowRate`** contract—an L1 bridge component that handles batched withdrawals.  
Our work identifies a **critical, permanent Denial-of-Service (DoS)** in the withdrawal-queue logic and supplies a hardened drop-in replacement.

---

## Key Findings

| Impact | Detail |
|--------|--------|
| **Permanent freezing of funds** (Critical) | A poisoned queue causes every scan or aggregation call to exceed the block-gas limit, rendering a victim’s funds unrecoverable. |
| **Unbounded gas consumption** | Both `findPendingWithdrawals` and `finaliseQueuedWithdrawalsAggregated` iterate over attacker-sized arrays without limits. |
| **Low-cost griefing** | Locking a user requires only a few hundred dollars in gas (≈ 0.1 ETH for 10 000 junk withdrawals). |
| **Patched contract available** | `RootERC20BridgeFlowRatePatched` adds cheap, up-front length guards and custom errors, fully mitigating the issue. |

---

## Repository Layout

```

src/
├─ .../RootERC20BridgeFlowRate.sol          ← vulnerable implementation
└─ .../RootERC20BridgeFlowRatePatched.sol   ← fixed implementation
test/
├─ QueueBombVulnerable.t.sol               ← PoC that fails (out-of-gas)
└─ QueueBombPatched.t.sol                  ← Same scenarios, now pass
docs/
└─ WithdrawalQueue\_DoS\_Report.md           ← full Immunefi-style write-up

````

---

## Quick Start

> **Prerequisites:** [Foundry](https://book.getfoundry.sh/) ( `curl -L https://foundry.paradigm.xyz | bash` ).

### Build contracts

```bash
forge build
````

### Run tests

```bash
# Full suite (vulnerable + patched)
forge test -vv

# Only the failing PoC against the vulnerable contract
forge test --match-contract QueueBombVulnerableTest -vv

# Only the patched contract tests
forge test --match-contract QueueBombPatchedTest -vv
```

All tests execute entirely in Foundry’s in-memory VM—**no local node, Anvil instance, or mainnet-fork is required**.

### Auto-format

```bash
forge fmt
```

---

## Report Highlights

* **Attack threshold:** 8 000–10 000 junk withdrawals are enough to exceed today’s 25–30 M gas practical tx limit.
* **Attack cost:** ≈ 0.09–0.11 ETH (USD 200–400) to brick any single user’s queue.
* **Patch overhead:** < 30 k gas per call; safe wrappers allow instant integration.
* **Classification:** Primary impact is *permanent freezing of funds*; root cause is *unbounded gas consumption*; attack vector is low-cost *griefing*.

For full technical reasoning, gas tables, and balance checks, see **`docs/WithdrawalQueue_DoS_Report.md`**.

---

## Contact & Responsible Disclosure

This repository is provided for security research, education, and responsible disclosure.
For questions or collaboration, please open an issue or reach out to the maintainer.

---

## Foundry Toolkit Reference

Foundry is a Rust-based, blazing-fast toolkit for Ethereum development:

| Tool       | Purpose                                         |
| ---------- | ----------------------------------------------- |
| **Forge**  | Test runner & coverage                          |
| **Cast**   | Swiss-army knife for EVM calls                  |
| **Anvil**  | Local Ethereum node (not required for this PoC) |
| **Chisel** | Solidity REPL                                   |

See the [Foundry Book](https://book.getfoundry.sh/) for full documentation.

### What changed & why
1. **Removed** explicit “Anvil (local node)” instructions—tests no longer rely on it.  
2. **Synced language** with the final report (8 000-10 000 withdrawals, 0.09–0.11 ETH cost, permanent DoS).  
3. **Flattened directory list**: `extras/` dropped, new `docs/` folder referenced.  
4. **Added at-a-glance table** for key findings and toolkit usage.  
5. **Clarified no-fork requirement** so newcomers don’t spin up unnecessary infra.
