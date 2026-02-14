# Slither Security Audit Report

**Project:** Phenomenon Foundry  
**Tool:** Slither (Trail of Bits / Crytic)  
**Date:** Generated via automated audit  
**Contracts Analyzed:** Phenomenon.sol, GameplayEngine.sol, PhenomenonTicketEngine.sol (+ dependencies)  
**Total Findings:** 141

---

## Executive Summary

Slither identified findings across several categories. Below are the **high and medium** severity items that warrant attention. Low/informational findings (naming conventions, style) are summarized at the end.

---

## High & Medium Severity Findings

### 1. Unchecked ERC20 Transfer Return Values (Medium)

**Detector:** `unchecked-transfer`  
**Reference:** [Slither Wiki](https://github.com/crytic/slither/wiki/Detector-Documentation#unchecked-transfer)

Some tokens (e.g., USDT) do not return a boolean from `transfer`/`transferFrom`. Ignoring return values can hide failures.

| Location           | Function                                              |
| ------------------ | ----------------------------------------------------- |
| Phenomenon.sol:313 | `registerProphet` – `IERC20(GAME_TOKEN).transferFrom` |
| Phenomenon.sol:448 | `depositGameTokens` – `transferFrom`                  |
| Phenomenon.sol:453 | `returnGameTokens` – `transfer`                       |
| Phenomenon.sol:465 | `transferOwnerTokens` – `transfer`                    |
| Phenomenon.sol:471 | `ownerTokenTransfer` – `transfer`                     |

**Recommendation:** Use OpenZeppelin's `SafeERC20` or explicitly check return values for non-standard tokens.

---

### 2. Arbitrary `from` in transferFrom (Medium)

**Detector:** `arbitrary-send-erc20`  
**Reference:** [Slither Wiki](https://github.com/crytic/slither/wiki/Detector-Documentation#arbitrary-from-in-transferfrom)

`transferFrom(from, to, amount)` with an arbitrary `from` can be abused if callers can choose the `from` address.

| Location           | Function                                                                |
| ------------------ | ----------------------------------------------------------------------- |
| Phenomenon.sol:313 | `registerProphet(address _prophet)` – transferFrom `_prophet`           |
| Phenomenon.sol:448 | `depositGameTokens(address from, uint256 amount)` – transferFrom `from` |

**Recommendation:** Ensure `from` is always the caller or a trusted/controlled address. Add access control if `from` can be user-specified.

---

### 3. Weak PRNG (Medium)

**Detector:** `weak-prng`  
**Reference:** [Slither Wiki](https://github.com/crytic/slither/wiki/Detector-Documentation#weak-PRNG)

| Location               | Issue                                                                             |
| ---------------------- | --------------------------------------------------------------------------------- |
| GameplayEngine.sol:159 | `block.timestamp % numberOfProphets` used for initial prophet turn in `startGame` |

**Recommendation:** Use a verifiable randomness source (e.g., Chainlink VRF) for game-critical randomness. `block.timestamp` is predictable by miners/validators.

---

### 4. Missing Zero-Address Validation (Low–Medium)

**Detector:** `missing-zero-check`  
**Reference:** [Slither Wiki](https://github.com/crytic/slither/wiki/Detector-Documentation#missing-zero-address-validation)

Critical addresses assigned without zero checks:

| Location                      | Parameter                         |
| ----------------------------- | --------------------------------- |
| GameplayEngine.sol:66         | `_router`                         |
| Phenomenon.sol:136            | `_gameToken`                      |
| Phenomenon.sol:156            | `newOwner` in `changeOwner`       |
| Phenomenon.sol:160            | `newGameplayEngine`               |
| Phenomenon.sol:164            | `newTicketEngine`                 |
| Phenomenon.sol:176            | `_gameToken` in `changeGameToken` |
| PhenomenonTicketEngine.sol:62 | `newOwner`                        |

**Recommendation:** Add `require(addr != address(0))` (or equivalent) for all critical address parameters.

---

### 5. Missing Events for Access Control & State Changes (Low)

**Detector:** `events-access`, `events-maths`  
**Reference:** [Slither Wiki](https://github.com/crytic/slither/wiki/Detector-Documentation#missing-events-access-control)

| Location                      | Change                                 |
| ----------------------------- | -------------------------------------- |
| Phenomenon.sol:157            | `changeOwner` – owner change           |
| PhenomenonTicketEngine.sol:63 | `changeOwner` – owner change           |
| GameplayEngine.sol:403        | `changeDonHostedSecretsSlotID`         |
| GameplayEngine.sol:407        | `changeDonHostedSecretsVersion`        |
| Phenomenon.sol:196            | `setRandomnessSeed`                    |
| Phenomenon.sol:405            | `increaseTotalTickets`                 |
| Phenomenon.sol:409            | `decreaseTotalTickets`                 |
| Phenomenon.sol:443            | `applyProtocolFee`                     |
| Phenomenon.sol:464            | `transferOwnerTokens` – balance change |
| PhenomenonTicketEngine.sol:67 | `setTicketMultiplier`                  |

**Recommendation:** Emit events for all significant state changes to support off-chain monitoring and auditing.

---

### 6. Reentrancy (Benign)

**Detector:** `reentrancy-benign`  
**Reference:** [Slither Wiki](https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities)

Benign reentrancy patterns identified in `GameplayEngine.sendRequest` and related flows. State updates occur after external calls in some paths.

**Recommendation:** Review CEI (Checks-Effects-Interactions) pattern. Consider ReentrancyGuard on external-facing functions if call graphs allow re-entry.

---

### 7. Uninitialized State / Local Variables (Informational)

**Detector:** `uninitialized-state`, `uninitialized-local`

| Variable                                 | Location                                  |
| ---------------------------------------- | ----------------------------------------- |
| `GameplayEngine.s_lastFunctionRequestId` | Written by external call, not constructor |
| `GameplayEngine.encryptedSecretsUrls`    | Never initialized                         |
| `GameplayEngine.sendRequest.req`         | Local variable                            |
| `Phenomenon.registerProphet.newProphet`  | Local struct                              |

**Recommendation:** Ensure all state is initialized before use. Some may be intentionally set by external systems (e.g., Chainlink).

---

### 8. External Calls in Loop

**Detector:** `calls-loop`  
**Reference:** [Slither Wiki](https://github.com/crytic/slither/wiki/Detector-Documentation/#calls-inside-a-loop)

`GameplayEngine.fulfillRequest` makes external calls inside a loop:  
`updateProphetsRemaining`, `updateProphetLife`, `updateProphetArgs`.

**Recommendation:** Monitor gas and consider batching if the loop can grow. Current game size (4–9 prophets) may be acceptable.

---

### 9. Cyclomatic Complexity

**Detector:** `cyclomatic-complexity`

`GameplayEngine.fulfillRequest` has high cyclomatic complexity (13).

**Recommendation:** Refactor into smaller helper functions to improve readability and testability.

---

## Informational / Style Findings

### Naming Conventions

- Events should use CapWords (e.g., `ProphetEnteredGame` instead of `prophetEnteredGame`).
- Parameters and variables should use mixedCase (Slither flags many `s_`-prefixed and other non-standard names).

### State Variable Optimizations

- `GameplayEngine.router` and `GameplayEngine.donID` could be `immutable` if set only in constructor.
- Some variables Slither suggests as `constant` are actually mutable by design (e.g., `s_lastFunctionRequestId`).

### Boolean Comparisons

- Use `!condition` instead of `condition == false` for clarity.

---

## How to Re-run Slither

```bash
# Using uv (recommended)
uvx --from slither-analyzer slither . --filter-paths "lib|test"

# With JSON output
uvx --from slither-analyzer slither . --filter-paths "lib|test" --json slither-report.json
```

Configuration is in `slither.config.json`.

---

## References

- [Slither Detector Documentation](https://github.com/crytic/slither/wiki/Detector-Documentation)
- [Trail of Bits – Slither](https://github.com/crytic/slither)
- [Secureum – Slither](https://secureum.substack.com/)
