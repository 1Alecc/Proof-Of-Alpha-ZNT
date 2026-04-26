// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  OracleVerifier — Proof of Alpha Protocol
//
//  Anti-fraud layer between the FIX Oracle Bridge and the burn engine.
//  Two responsibilities:
//    1. Verify ECDSA signature from the trusted ZPF Oracle signer
//    2. Prevent replay attacks via FIX sequence number registry
//
//  Author: Samuel Esteban Imbrecht Bermudez — Zenith Corp
//  First defined: April 27, 2026
// ─────────────────────────────────────────────────────────────────────────────

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title OracleVerifier
 * @notice Validates attestations submitted by the ZPF FIX Oracle Bridge.
 *
 *         An attestation is valid if and only if:
 *           a) It is signed by the registered `trustedSigner`
 *           b) The `sequenceId` has not been processed before
 *
 *         Both conditions must be true. Failure on either reverts.
 */
contract OracleVerifier is Ownable {
    using ECDSA for bytes32;

    // ── State ─────────────────────────────────────────────────────────────────

    /// @notice The ZPF Oracle Bridge's signing key (public address).
    address public trustedSigner;

    /**
     * @notice Registry of processed sequence IDs.
     *         Once registered, a sequenceId can never be used again.
     *         This prevents replay attacks — resending an old FIX message
     *         to trigger a duplicate burn is impossible.
     */
    mapping(uint256 => bool) public processedSequenceIds;

    // ── Events ────────────────────────────────────────────────────────────────

    event AttestationVerified(
        uint256 payoutUSD,
        bytes32 tradeRecordHash,
        uint256 sequenceId,
        address signer
    );

    event TrustedSignerUpdated(address indexed oldSigner, address indexed newSigner);

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(address _trustedSigner) Ownable(msg.sender) {
        require(_trustedSigner != address(0), "OracleVerifier: zero address");
        trustedSigner = _trustedSigner;
    }

    // ── Core ──────────────────────────────────────────────────────────────────

    /**
     * @notice Verifies a PoA attestation from the FIX Oracle Bridge.
     *         Reverts if the signature is invalid or the sequenceId is replayed.
     *
     * @param payoutUSD       Verified payout in USD (×1e6)
     * @param tradeRecordHash SHA-256 of the original FIX ExecutionReport
     * @param sequenceId      FIX MsgSeqNum (Tag 34) — unique per message
     * @param sig             ECDSA signature from the ZPF Oracle Bridge
     */
    function verify(
        uint256 payoutUSD,
        bytes32 tradeRecordHash,
        uint256 sequenceId,
        bytes calldata sig
    ) external {

        // Anti-replay: each FIX sequence ID processable exactly once
        require(
            !processedSequenceIds[sequenceId],
            "OracleVerifier: sequence ID already processed"
        );
        processedSequenceIds[sequenceId] = true;

        // Reconstruct the message hash the bridge signed
        bytes32 msgHash = keccak256(abi.encodePacked(
            payoutUSD,
            tradeRecordHash,
            sequenceId
        ));

        // Recover signer from signature
        address recovered = MessageHashUtils.toEthSignedMessageHash(msgHash).recover(sig);
        require(
            recovered == trustedSigner,
            "OracleVerifier: invalid signature"
        );

        emit AttestationVerified(payoutUSD, tradeRecordHash, sequenceId, recovered);
    }

    // ── View ──────────────────────────────────────────────────────────────────

    /// @notice Returns true if a sequenceId has already been processed.
    function isProcessed(uint256 sequenceId) external view returns (bool) {
        return processedSequenceIds[sequenceId];
    }

    // ── Governance ────────────────────────────────────────────────────────────

    /**
     * @notice Updates the trusted signer address.
     *         Use with a timelock in production to prevent surprise key rotations.
     */
    function setTrustedSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "OracleVerifier: zero address");
        emit TrustedSignerUpdated(trustedSigner, newSigner);
        trustedSigner = newSigner;
    }
}
