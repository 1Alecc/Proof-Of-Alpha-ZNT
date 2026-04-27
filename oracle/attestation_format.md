# Attestation Format — Proof of Alpha Protocol
> The data structure that connects a verified trade to an on-chain burn.
> Version 1.0 — April 27, 2026

---

## What Is an Attestation?

An attestation is a signed, tamper-proof message issued by the Oracle Bridge that proves:

1. A real trade was executed and settled
2. The trade generated a verified positive P&L
3. The P&L was confirmed by a regulated external auditor (prop firm)
4. The message has not been replayed (unique sequenceId)
5. The issuer is the authorized ZPF Oracle signer

An attestation is the cryptographic bridge between institutional finance and the blockchain.

---

## Full Attestation Schema

```typescript
interface PoAAttestation {
  // Protocol
  version:          string;   // "1.0"
  protocolId:       string;   // "proof-of-alpha-v1"

  // Trade identity
  sequenceId:       bigint;   // FIX MsgSeqNum (Tag 34) — anti-replay key
  tradeId:          string;   // FIX ClOrdID (Tag 11) — unique trade identifier
  brokerID:         string;   // FIX BrokerID (Tag 375)

  // Financial data
  payoutUSD:        bigint;   // Realized P&L in USD × 1e6
  instrument:       string;   // e.g. "XAUUSD", "BTCUSD"
  executionPrice:   bigint;   // FIX LastPx (Tag 31) × 1e8
  executedQty:      bigint;   // FIX LastQty (Tag 32) × 1e8

  // Timestamps
  transactTime:     string;   // FIX TransactTime (Tag 60) — ISO 8601
  attestationTime:  number;   // Unix timestamp of attestation generation

  // Cryptographic proof
  tradeRecordHash:  string;   // 0x-prefixed bytes32 — SHA-256 of raw FIX message
  signature:        string;   // 0x-prefixed ECDSA signature
}
```

---

## Minimal On-Chain Fields

Only three fields are required by `OracleVerifier.sol`. Everything else is metadata.

```solidity
// The three fields that matter on-chain:
uint256 payoutUSD        // Financial magnitude of the burn
bytes32 tradeRecordHash  // Cryptographic anchor to the original trade
uint256 sequenceId       // Anti-replay guarantee
```

The full attestation JSON is stored off-chain (IPFS or ZPF Dashboard) and linked by `tradeRecordHash`.

---

## Verification Flow

```
Off-chain:
  Raw FIX message  →  SHA-256  →  tradeRecordHash (bytes32)

On-chain:
  keccak256(payoutUSD ++ tradeRecordHash ++ sequenceId)
  → ECDSA.recover(hash, signature)
  → must equal trustedSigner address

Anti-replay:
  processedSequenceIds[sequenceId] must be false
  → set to true after verification
```

---

## Example Attestation (Illustrative)

```json
{
  "version": "1.0",
  "protocolId": "proof-of-alpha-v1",
  "sequenceId": 48291,
  "tradeId": "ZENITH_XAUUSD_20260422_001",
  "brokerID": "THE5ERS_FIX_01",
  "payoutUSD": 124750000,
  "instrument": "XAUUSD",
  "executionPrice": 233842000000,
  "executedQty": 100000000,
  "transactTime": "2026-04-22T14:32:07.000Z",
  "attestationTime": 1745332327,
  "tradeRecordHash": "0xa3f2c1d8e4b7f9a2c3d5e8f1b4c7d9e2f5a8b1c4d7e0f3a6b9c2d5e8f1b4c7",
  "signature": "0x4a8b3d..."
}
```

`payoutUSD: 124750000` = $124.75 USD (×1e6)

---

## Dual-Ledger Verification

Every attestation has two independent verification chains:

```
Chain 1 — On-chain (Ethereum):
  BurnExecuted event
    └── tradeRecordHash: 0xa3f2c1...
    └── payoutUSD: 124750000
    └── zntBurned: 1247500000000000000000  (1,247.5 ZNT)
    └── sequenceId: 48291

Chain 2 — Off-chain (The 5%ers dashboard):
  Trade record for ZENITH_XAUUSD_20260422_001
    └── P&L: +$124.75
    └── SHA-256 of raw FIX message: a3f2c1d8...  ← matches tradeRecordHash
```

To fabricate a burn: both chains must be forged simultaneously.
Forging the on-chain record requires the Oracle's private key.
Forging the off-chain record requires access to The 5%ers' servers.

Both at once: impossible.

---

*Attestation Format V1.1.0 — April 27, 2026*
*© 2026 Samuel Esteban Imbrecht Bermudez — Zenith Corp*
