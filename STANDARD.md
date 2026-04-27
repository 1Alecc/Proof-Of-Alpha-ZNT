# Proof of Alpha — Implementation Standard
> How to build a compliant PoA token system.
> Version 1.1.0 — April 27, 2026

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

### INV-6: Risk-Adjusted Alpha

A PoA burn event must reflect the **quality** of alpha, not only the quantity of profit. Raw P&L without risk adjustment converts PoA into "Proof of Luck."

The burn amount must be adjusted by a **Quality Multiplier** derived from the risk profile of the period:

```
Q = clamp( Calmar_ratio / CALMAR_TARGET, 0.5, 1.5 )

  Calmar_ratio   = period_return_pct / max_drawdown_pct
  CALMAR_TARGET  = 2.0  (earn at least 2× what you risk)

  Q < 1.0  → alpha below target quality → reduced burn
  Q = 1.0  → alpha at target quality    → normal burn
  Q > 1.0  → alpha above target quality → amplified burn

Effective_PnL = raw_PnL_USD × Q
```

**Floor of 0.5** prevents zero burns from mediocre but profitable periods.
**Cap of 1.5** rewards exceptional risk-adjusted performance.

The Calmar ratio and its components must be included in the attestation payload and verifiable from the original trade records.

---

### INV-7: Alpha Gate

Not all positive P&L qualifies as alpha. A PoA-compliant system must enforce a minimum quality threshold before any burn is triggered.

**A burn is only valid if all of the following conditions are met for the reporting period:**

| Metric | Minimum | Rationale |
|---|---|---|
| `alpha_score` | ≥ 0.65 | Composite gate — see formula below |
| Annualized Sharpe | ≥ 0.8 | Industry minimum for viable performance |
| Calmar ratio | ≥ 1.5 | Return must exceed 1.5× max drawdown |
| Profitable months | ≥ 60% | Consistency over time |
| Trade count (period) | ≥ 30 | Statistical significance minimum |
| Live track record | ≥ 3 months | No backtest, no demo — live capital only |
| Anti-martingale | Pass | See specification below |

**Alpha Score formula:**

```python
def alpha_score(sharpe, calmar, consistency, n_trades):
    # sharpe: annualized. calmar: period. consistency: 0-1. n_trades: int.
    s = min(sharpe / 2.0, 1.0)           # normalized: target 2.0
    c = min(calmar / 3.0, 1.0)           # normalized: target 3.0
    k = min(consistency, 1.0)            # already 0-1
    n = min(n_trades / 100, 1.0)         # normalized: target 100 trades
    return 0.30*s + 0.35*c + 0.25*k + 0.10*n
```

**Anti-Martingale Detection:**

A martingale strategy masks risk by doubling lot sizes after losses. It generates positive P&L temporarily before catastrophic drawdown. PoA systems must detect and reject this pattern:

```python
def is_martingale(lot_size_series, equity_series):
    # Calculate correlation between lot sizes and equity changes
    equity_changes = [equity_series[i] - equity_series[i-1]
                      for i in range(1, len(equity_series))]
    lots_lagged = lot_size_series[1:]
    correlation = pearson_correlation(lots_lagged, equity_changes)
    # Martingale signature: lots increase as equity DECREASES
    # → negative correlation between lot[t] and equity_delta[t]
    return correlation < -0.4
```

If `is_martingale()` returns `True`, the period attestation must be rejected regardless of P&L.

**Non-qualifying strategies (automatic rejection):**
- Grid systems with undefined maximum drawdown
- Averaging-down without position size limits
- Systems operating exclusively on demo accounts
- Track records with fewer than 3 months of live verified data

---

## PoA Data Format v1.0

All PoA-compliant systems must produce attestations in this standardized format. Non-standard formats are non-compliant and will not be accepted by a PoA-compatible smart contract.

### Trade Record (per trade)

```json
{
  "trade_id": "string",           // External ID from auditing institution
  "timestamp_open": "ISO-8601",
  "timestamp_close": "ISO-8601",
  "symbol": "string",             // e.g. "XAUUSD"
  "direction": "BUY | SELL",
  "entry_price": "number",
  "exit_price": "number",
  "lot_size": "number",
  "pnl_usd": "number",            // Realized P&L in USD
  "account_equity_before": "number",
  "source_id": "string"           // Identifies the alpha source (see Multi-Source)
}
```

### Period Report (per payout cycle, typically monthly)

```json
{
  "period_start": "ISO-8601",
  "period_end": "ISO-8601",
  "source_id": "string",
  "prop_firm_id": "string",
  "account_id": "string",
  "n_trades": "integer",
  "gross_pnl_usd": "number",
  "max_drawdown_pct": "number",
  "sharpe_annualized": "number",
  "calmar_ratio": "number",
  "consistency_score": "number",  // % profitable sub-periods
  "alpha_score": "number",        // Must be ≥ 0.65
  "quality_multiplier": "number", // Q = clamp(calmar/2.0, 0.5, 1.5)
  "effective_pnl_usd": "number",  // gross_pnl × quality_multiplier
  "lot_size_series": ["number"],  // For anti-martingale verification
  "equity_series": ["number"]     // For anti-martingale verification
}
```

### Verification Packet (on-chain submission)

```json
{
  "attestation_version": "1.1.0",
  "source_id": "string",
  "period_report_hash": "bytes32", // keccak256 of period report JSON
  "payout_document_hash": "bytes32", // SHA-256 of prop firm PDF
  "external_sequence_id": "string",  // Payout ID from institution
  "effective_pnl_usd_scaled": "uint256", // ×1e6 for on-chain precision
  "alpha_score_scaled": "uint256",   // ×1e4, must be ≥ 6500
  "quality_multiplier_scaled": "uint256", // ×1e4
  "ecdsa_signature": "bytes"
}
```

---

## Multi-Source Architecture

PoA is designed as an **open standard**, not a single-system primitive. Multiple independent alpha sources can contribute burns to the same PoA token, creating a portfolio of verified performance.

### Alpha Source Registration

To be registered as a burn source, an alpha source must:

1. **Demonstrate track record** — minimum 3 months live, alpha_score ≥ 0.65 for all periods
2. **Pass technical audit** — FIX Bridge or equivalent oracle deployed and verified
3. **Pass smart contract audit** — attestation pipeline reviewed by approved auditor
4. **Governance approval** — accepted by multisig (V1) or token holder vote (V3+)
5. **Register source_id** — unique identifier registered in `AlphaRegistry.sol`

### Source Isolation

Each alpha source operates with full isolation:

```solidity
mapping(string => bool) public registeredSources;
mapping(string => mapping(uint256 => bool)) public processedBySource;
// source_id → sequence_id → processed
```

A sequence ID processed by Source A cannot be replayed by Source B.

### Concentration Risk Limits

To prevent over-dependence on any single source (the founding problem this invariant solves):

| Active Sources | Max burn share per source |
|---|---|
| 1 | 100% (bootstrap period) |
| 2–3 | 70% |
| 4–9 | 50% |
| 10+ | 30% |

These limits prevent a single source's failure from collapsing the deflationary engine.

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

**Core invariants (INV-1 through INV-5 — unchanged from V1.0):**
- [ ] Burn is triggered only after external auditor confirmation
- [ ] `BurnExecuted` event contains `tradeRecordHash` linking to verifiable document
- [ ] No public mint function exists in the token contract
- [ ] `processedRecords` mapping prevents replay attacks
- [ ] Oracle submissions are authenticated (ECDSA, multisig, or ZK)
- [ ] Governance changes have a timelock
- [ ] Smart contracts have been audited by a recognized security firm

**V1.1.0 additions (INV-6 and INV-7):**
- [ ] Quality Multiplier Q is calculated per period and included in attestation
- [ ] Effective burn uses `raw_pnl × Q`, not raw P&L directly
- [ ] `alpha_score` ≥ 0.65 verified before any burn is accepted
- [ ] Sharpe ≥ 0.8 (annualized) verified for the period
- [ ] Calmar ratio ≥ 1.5 verified for the period
- [ ] Anti-martingale check passes (`lot_size_series` and `equity_series` provided)
- [ ] Minimum 30 trades in period — statistical significance enforced
- [ ] Minimum 3 months live track record before first burn accepted
- [ ] `attestation_version` field present and set to `"1.1.0"` or higher
- [ ] Period Report and Verification Packet match PoA Data Format v1.0
- [ ] If multi-source: `AlphaRegistry.sol` deployed, source_id registered and approved

---

## Versioning

| Standard Version | Date | Key Changes |
|---|---|---|
| V1.0 | April 27, 2026 | Initial definition — 5 core invariants |
| V1.1.0 | April 27, 2026 | INV-6 (Risk-Adjusted Alpha), INV-7 (Alpha Gate), PoA Data Format v1.0, Multi-Source Architecture |

---

## Attribution

If you implement the Proof of Alpha standard, we ask (but do not require) that you reference this repository as the origin of the primitive:

```
This project implements the Proof of Alpha Protocol (https://github.com/proof-of-alpha/protocol)
first defined by Samuel Esteban Imbrecht Bermudez — Zenith Corp, April 27, 2026.
```

---

*Proof of Alpha Standard V1.1.0 — April 27, 2026*
*© 2026 Samuel Esteban Imbrecht Bermudez — Zenith Corp*
*MIT License — Free to use, implement, and extend*
