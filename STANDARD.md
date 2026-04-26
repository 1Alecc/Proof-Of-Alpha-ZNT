# Proof of Alpha — Implementation Standard
> How to build a compliant PoA token system.
> Version 1.0 — April 27, 2026

---

## Overview

This document specifies the requirements for a Proof of Alpha (PoA) compliant token implementation. A system is PoA-compliant if and only if it satisfies all **Core Invariants** defined below.

PoA is not a specific contract or codebase — it is a **standard** that can be implemented across different chains, oracle providers, and trading infrastructure, as long as the fundamental guarantees are preserved.

---

## Core Invariants (Required)

### INV-1: External Verification

The entity generating trading performance **cannot** be the sole source of truth for burn events.

An independent, regulated third party — whose business model depends on accurate performance verification — must confirm the trading profit before any burn is triggered.

**Compliant examples:**
- Regulated prop firm (The 5%ers, FTMO, etc.)
- Licensed brokerage with auditable settlement records
- Regulated exchange with verified trade history

**Non-compliant:**
- Self-reported P&L from a private wallet
- Unverified API from a non-regulated platform
- Manual attestation with no external audit

---

### INV-2: Immutable Audit Trail

Every burn event **must** include a cryptographic reference to the original trade record. The on-chain event and the off-chain record must independently verify each other.

**Required fields in BurnExecuted event:**
```solidity
event BurnExecuted(
    uint256 pnlUSD,        // Realized P&L (×1e6 for precision)
    uint256 tokensBurned,  // Tokens permanently destroyed
    uint256 newSupply,     // Total supply after this burn
    bytes32 tradeRecordHash, // SHA-256 or keccak256 of original trade document
    uint256 sequenceId,    // Unique ID from the auditing institution (anti-replay)
    address indexed oracle // Oracle address that submitted the attestation
);
```

The `tradeRecordHash` must be verifiable against a public or auditable document from the third-party institution.

---

### INV-3: Fixed Supply / No Mint

A PoA token **cannot** have a publicly callable mint function after deployment.

The initial supply is set at deploy time and cannot increase. Supply can only decrease through burns.

```solidity
// COMPLIANT — no public mint
contract PoAToken is ERC20 {
    constructor(uint256 initialSupply) {
        _mint(msg.sender, initialSupply); // one-time only
    }
    // No mint() function exposed publicly
}

// NON-COMPLIANT — has mint
contract NotPoA is ERC20 {
    function mint(address to, uint256 amount) external onlyOwner { ... }
}
```

---

### INV-4: Anti-Replay Protection

Each trade record from the external auditor **must** trigger at most one burn event. The smart contract must maintain a registry of processed records and reject duplicates.

```solidity
mapping(uint256 => bool) public processedRecords;

function executeBurn(..., uint256 sequenceId, ...) external {
    require(!processedRecords[sequenceId], "PoA: record already processed");
    processedRecords[sequenceId] = true;
    // ... proceed with burn
}
```

The `sequenceId` must come from the external auditing institution (e.g., FIX MsgSeqNum, broker trade ID, prop firm payout ID) — not generated internally.

---

### INV-5: Oracle Authentication

The entity submitting attestations to the smart contract must be cryptographically authenticated. Anonymous or unauthenticated oracle submissions are non-compliant.

**Compliant oracle patterns:**
- ECDSA signature from a registered trusted signer
- Multisig (M-of-N) from a defined set of independent signers
- Chainlink Any API with verified data source
- ZK-Proof of TLS session (most trustless — V3+)

**Non-compliant:**
- Any address can submit burns without authentication
- Oracle address hardcoded without upgrade mechanism
- Single EOA with no timelock or governance

---

## Recommended Architecture

```
[Trading System] → generates verified P&L
        ↓
[External Auditor] → independently confirms and documents
        ↓
[Oracle Bridge] → extracts proof, signs attestation
        ↓
[OracleVerifier.sol] → validates signature + anti-replay
        ↓
[BurnEngine.sol] → executes DEX swap + token burn
        ↓
[PoAToken.sol] → transfers to dead address, emits BurnExecuted
```

---

## Recommended Parameters

These are not required by the standard but are recommended for economic soundness:

| Parameter | Recommended | Notes |
|---|---|---|
| Burn rate | 20–40% of payout | Too low: symbolic. Too high: starves reinvestment. |
| DEX slippage cap | ≤ 3% | Protects against MEV/sandwich attacks |
| Swap deadline | ≤ 10 minutes | Prevents stale transaction execution |
| Governance timelock | ≥ 24 hours | Prevents surprise parameter changes |
| Oracle upgrade path | Multisig → Chainlink → ZK | Progressive decentralization |

---

## Oracle Bridge Specification

See [oracle/FIX_BRIDGE_SPEC.md](oracle/FIX_BRIDGE_SPEC.md) for the full FIX Protocol oracle reference implementation used by ZNT.

Alternative oracle sources are valid under this standard, provided they satisfy INV-1 (external verification) and INV-5 (authentication).

---

## Compliance Checklist

Before claiming PoA compliance, verify:

- [ ] Burn is triggered only after external auditor confirmation
- [ ] `BurnExecuted` event contains `tradeRecordHash` linking to verifiable document
- [ ] No public mint function exists in the token contract
- [ ] `processedRecords` mapping prevents replay attacks
- [ ] Oracle submissions are authenticated (ECDSA, multisig, or ZK)
- [ ] Governance changes have a timelock
- [ ] Smart contracts have been audited by a recognized security firm

---

## Versioning

| Standard Version | Date | Key Changes |
|---|---|---|
| V1.0 | April 27, 2026 | Initial definition — 5 core invariants |

---

## Attribution

If you implement the Proof of Alpha standard, we ask (but do not require) that you reference this repository as the origin of the primitive:

```
This project implements the Proof of Alpha Protocol (https://github.com/proof-of-alpha/protocol)
first defined by Samuel Esteban Imbrecht Bermudez — Zenith Corp, April 27, 2026.
```

---

*Proof of Alpha Standard V1.0 — April 27, 2026*
*© 2026 Samuel Esteban Imbrecht Bermudez — Zenith Corp*
*MIT License — Free to use, implement, and extend*
