# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| v1.0.x | âœ… Active |

---

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

If you discover a vulnerability in the Proof of Alpha Protocol â€” including the smart contracts, oracle bridge specification, or attestation format â€” please report it privately:

**Email:** `samuelimbrechtberm@gmail.com`
**Subject line:** `[SECURITY] Proof of Alpha â€” <brief description>`

### What to include

- Description of the vulnerability
- Steps to reproduce or proof of concept
- Affected component (ZNTToken, BuybackBurn, OracleVerifier, ZPFTreasury, oracle spec)
- Potential impact assessment
- Your suggested fix (optional but appreciated)

### Response timeline

| Step | Timeframe |
|---|---|
| Acknowledgement | Within 48 hours |
| Initial assessment | Within 7 days |
| Fix or mitigation | Within 30 days (critical: 7 days) |
| Public disclosure | After fix is deployed + 30 day grace period |

We follow **coordinated disclosure** â€” we ask that you give us reasonable time to fix before publishing.

---

## Scope

### In scope

- `contracts/ZNTToken.sol` â€” ERC-20 burn logic, access control
- `contracts/BuybackBurn.sol` â€” DEX swap, attestation handling
- `contracts/OracleVerifier.sol` â€” ECDSA verification, anti-replay
- `contracts/ZPFTreasury.sol` â€” fund management, threshold logic
- Oracle bridge attestation format (`oracle/attestation_format.md`)
- Anti-replay mechanism design
- Signature construction vulnerabilities

### Out of scope

- The Zenith algorithmic trading system (private, not part of this repo)
- Issues in OpenZeppelin contracts (report to them directly)
- Gas optimization suggestions (not security issues)
- Issues requiring physical access to the broker's FIX server

---

## Known Design Decisions (Not Vulnerabilities)

These are intentional design choices that may appear to be issues:

**Upgradeable proxy (ERC-1967):** The contract is intentionally upgradeable in V1-V3. This is documented in the whitepaper. Upgradeability is constrained by governance timelocks and will be progressively removed as the protocol matures toward V4.

**Trusted signer (V1):** The oracle relies on a single trusted signer in V1. This is documented as a known centralization tradeoff. V2+ introduces multisig and V3 moves to trustless TLS proof.

**Owner control of burn rate:** The burn rate is adjustable within hardcoded bounds (20%-50%). This is by design and visible on-chain.

---

## Bug Bounty

A formal bug bounty program will be announced before mainnet deployment of ZNT (planned 2027).

Critical vulnerabilities reported before the program launches will be recognized publicly and rewarded retroactively at the discretion of the ZPF Foundation.

---

## Hall of Fame

Security researchers who responsibly disclose valid vulnerabilities will be credited here.

*(No entries yet â€” v1.0.0 pre-mainnet)*

---

*Proof of Alpha Protocol â€” Security Policy V1.0*
*Â© 2026 Samuel Esteban Imbrecht Bermudez â€” Zenith Corp*
