# Immutable Bridge Withdrawal Queue Audit

## Summary

This repository contains a security audit and proof-of-concept (PoC) test suite for the `RootERC20BridgeFlowRate` smart contract, which is part of an Ethereum bridge implementation. The audit focuses on a critical Denial of Service (DoS) vulnerability in the withdrawal queue logic, where an attacker can permanently lock user funds by spamming the queue with thousands of small withdrawals.

## Key Findings

- **Critical DoS**: Unbounded iteration in `findPendingWithdrawals` and `finaliseQueuedWithdrawalsAggregated` allows an attacker to exhaust the gas limit for any victim, making their funds permanently inaccessible.
- **Attack Cost**: The attack is cheap (≈0.03 ETH) and can be repeated for any user.
- **Patched Implementation**: The repository includes a patched contract (`RootERC20BridgeFlowRatePatched`) with strict input guards, as well as comprehensive tests demonstrating both the vulnerability and the fix.

## Structure

- `src/`: Core contract code, including both vulnerable and patched versions.
- `test/QueueBombVulnerable.t.sol`: Failing PoC tests against the vulnerable contract.
- `test/QueueBombPatched.t.sol`: Passing tests against the patched contract.
- `extras/`: Non-essential scripts, legacy tests, and environment files (excluded from git).
- `WithdrawalQueue_DoS_Report.md`: Full Immunefi-style bug report and technical writeup.

## Usage

### Build

```sh
forge build
```

### Test (Vulnerable and Patched)

```sh
# Run all tests
forge test -vv

# Run only the vulnerable PoC suite
forge test --match-contract QueueBombVulnerableTest -vv

# Run only the patched suite
forge test --match-contract QueueBombPatchedTest -vv
```

### Format

```sh
forge fmt
```

### Anvil (local node)

```sh
anvil
```

## References

- [src/root/flowrate/RootERC20BridgeFlowRate.sol](./src/root/flowrate/RootERC20BridgeFlowRate.sol) – Vulnerable contract
- [src/root/flowrate/RootERC20BridgeFlowRatePatched.sol](./src/root/flowrate/RootERC20BridgeFlowRatePatched.sol) – Patched contract

## About

This repository is intended for security research, responsible disclosure, and as a reference for best practices in smart contract queue design. For questions or collaboration, please open an issue or contact the repository maintainer.

---

## Foundry Toolkit

**Foundry** is a fast, portable, and modular toolkit for Ethereum application development written in Rust.

- **Forge**: Ethereum testing framework
- **Cast**: Swiss army knife for EVM interaction
- **Anvil**: Local Ethereum node
- **Chisel**: Solidity REPL

See [Foundry Book](https://book.getfoundry.sh/) for full documentation.
