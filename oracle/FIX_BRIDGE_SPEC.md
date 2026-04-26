# FIX Oracle Bridge — Interface Specification
> Public interface for the ZPF FIX-to-Blockchain Oracle Bridge.
> This document describes the inputs, outputs, and security properties.
> The internal implementation (private key management, broker credentials) is not disclosed.
> Version 1.0 — April 27, 2026

---

## Overview

The FIX Oracle Bridge is a Python service that maintains a persistent FIX Protocol session with a broker or prop firm, monitors for realized profit events, and generates cryptographically-signed attestations that are submitted to the ZNT smart contract to trigger a Proof of Alpha burn.

**FIX Protocol** (Financial Information eXchange) is the institutional messaging standard used by brokers, exchanges, and prop firms since 1992. It is the language of institutional finance.

---

## Why FIX, Not an API

| Property | REST/Webhook API | **FIX Protocol** |
|---|---|---|
| Authentication | API key | SenderCompID + password + TLS |
| Data format | JSON (variable) | ISO 15022 (standardized since 1992) |
| Delivery | Pull or webhook | Push — real-time |
| Falsifiability | Possible | Impossible with TLS pinning |
| Availability | Depends on API uptime | Session-based TCP — persistent |
| Institutional recognition | None | Universal |

---

## FIX Message of Interest — ExecutionReport

```
Tag 35 = 8          → Message type: ExecutionReport
Tag 34              → MsgSeqNum — unique per session (anti-replay key)
Tag 11  ClOrdID     → Unique trade identifier
Tag 31  LastPx      → Execution price
Tag 32  LastQty     → Executed quantity
Tag 60  TransactTime → Exact execution timestamp (ISO 8601)
Tag 150 ExecType    → 2=Fill / 1=PartialFill / 3=DoneForDay
Tag 375 BrokerID    → Verified broker identity
Tag 715 ClearingDate → Settlement date
Tag 730 SettlPrice  → Settlement price (realized P&L anchor)
```

A burn event is triggered **only** on `ExecType=Fill` (Tag 150 = 2) with a positive calculated P&L.
Partial fills and losing trades do not trigger burns.

---

## Attestation Format

The FIX Bridge generates a signed attestation containing the following fields:

```json
{
  "version": "1.0",
  "timestamp": 1745712000,
  "payoutUSD": 124750000,
  "tradeRecordHash": "0xa3f2c1...",
  "sequenceId": 48291,
  "brokerID": "THE5ERS_FIX_01",
  "sessionID": "SENDER/TARGET",
  "signature": "0x4a8b3d..."
}
```

| Field | Type | Description |
|---|---|---|
| `version` | string | Attestation format version |
| `timestamp` | uint64 | Unix timestamp of the trade execution |
| `payoutUSD` | uint256 | Realized P&L in USD, multiplied by 1e6 for precision |
| `tradeRecordHash` | bytes32 | SHA-256 of the complete raw FIX ExecutionReport message |
| `sequenceId` | uint256 | FIX MsgSeqNum (Tag 34) — unique per session |
| `brokerID` | string | Broker/prop firm identifier from Tag 375 |
| `sessionID` | string | FIX session identifier (SenderCompID/TargetCompID) |
| `signature` | bytes | ECDSA signature over (payoutUSD, tradeRecordHash, sequenceId) |

---

## Signature Construction

The signature is computed over the following ABI-encoded message:

```python
import hashlib
from eth_account import Account
from eth_account.messages import encode_defunct

# Construct the payload to sign (matches OracleVerifier.sol)
msg_hash = Web3.keccak(
    Web3.to_bytes(payout_usd) +          # uint256 — ×1e6
    bytes.fromhex(trade_record_hash) +    # bytes32 — SHA-256 of FIX message
    Web3.to_bytes(sequence_id)            # uint256 — FIX MsgSeqNum
)

# Sign with ZPF Oracle private key
signed = Account.sign_message(encode_defunct(msg_hash), private_key=ORACLE_PRIVATE_KEY)
signature = signed.signature.hex()
```

The `ORACLE_PRIVATE_KEY` corresponds to the `trustedSigner` address registered in `OracleVerifier.sol`. It is never disclosed.

---

## TLS Certificate Pinning

The FIX session is established over TLS with the broker's server. The bridge pins the broker's TLS certificate fingerprint:

```python
BROKER_TLS_FINGERPRINT = "sha256/[broker_cert_fingerprint_here]"

ssl_context = ssl.create_default_context()
ssl_context.verify_mode = ssl.CERT_REQUIRED
# Pin to known broker certificate
ssl_context.load_verify_locations(BROKER_CERT_PATH)
```

**Security property:** No one can forge FIX messages from outside the broker's infrastructure. The TLS connection can only be established with the real broker server.

**On-chain verifiability (V3):** TLS Notary / DECO protocol will be used to generate a ZK-proof that a given TLS session occurred with the broker's certified server — without revealing private session data.

---

## P&L Calculation

The bridge calculates realized P&L per trade as follows:

```python
def calculate_pnl(execution_report) -> float:
    """
    Calculates realized P&L from a FIX ExecutionReport.
    Returns USD value of profit for the completed trade.
    """
    last_px  = float(execution_report.get_field(fix.LastPx()))
    last_qty = float(execution_report.get_field(fix.LastQty()))
    side     = execution_report.get_field(fix.Side())  # 1=Buy, 2=Sell
    symbol   = execution_report.get_field(fix.Symbol())

    # P&L calculation is symbol-specific (pip value, lot size, etc.)
    # Details depend on instrument and broker normalization
    pnl = _compute_instrument_pnl(symbol, last_px, last_qty, side)

    return pnl  # positive = profit, negative = loss
```

Only trades where `pnl > 0` generate attestations. Losing trades are ignored.

---

## Anti-Replay Design

FIX Protocol assigns a monotonically increasing sequence number to every message (`MsgSeqNum`, Tag 34). This is a property of the FIX session — the broker maintains it independently.

The bridge includes this `sequenceId` in every attestation.
The `OracleVerifier` contract maintains a `processedSequenceIds` mapping.

```
sequenceId 48291 → processed: true  (cannot be resubmitted)
sequenceId 48292 → processed: false (valid for next attestation)
```

Attempting to replay an old attestation will revert:
```
require(!processedSequenceIds[sequenceId], "OracleVerifier: sequence ID already processed");
```

---

## Submission to Blockchain

After generating and signing the attestation, the bridge submits it to `BuybackBurn.executeBuybackAndBurn()`:

```python
tx = buyback_burn.functions.executeBuybackAndBurn(
    payout_usd,         # uint256 — ×1e6
    trade_record_hash,  # bytes32
    sequence_id,        # uint256
    signature           # bytes
).build_transaction({
    "from":     ORACLE_ADDRESS,
    "gas":      250_000,
    "maxFeePerGas": w3.eth.gas_price * 2,
    "nonce":    w3.eth.get_transaction_count(ORACLE_ADDRESS),
})

signed_tx = w3.eth.account.sign_transaction(tx, private_key=ORACLE_PRIVATE_KEY)
tx_hash   = w3.eth.send_raw_transaction(signed_tx.rawTransaction)
```

---

## Oracle Evolution Roadmap

| Version | Oracle | Trust Model | Status |
|---|---|---|---|
| V1 | Multisig 3/5 manual attestation | Centralized — transparent | 2027 |
| V2 | FIX Bridge + ECDSA signature | Semi-automated — authenticated | 2028 |
| V3 | FIX Bridge + TLS Notary / DECO | Trustless — cryptographic TLS proof | 2029 |
| V4 | ZK-Proof of FIX session | Mathematically irrefutable | 2030+ |

---

## Reference Implementation

The FIX Oracle Bridge uses [QuickFIX/Python](https://github.com/quickfix/quickfix) for the FIX session layer and [Web3.py](https://web3py.readthedocs.io) for blockchain interaction.

The internal implementation is private. This document describes the public interface only.

---

*FIX Oracle Bridge Specification V1.0 — April 27, 2026*
*© 2026 Samuel Esteban Imbrecht Bermudez — Zenith Corp*
