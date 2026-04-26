// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  ZNT Token — Zenith Token
//  Proof of Alpha Protocol — Canonical ERC-20 Implementation
//
//  Reference implementation for the ZPF - The Zenith Project of Financial System
//  First defined: April 27, 2026
//  Author: Samuel Esteban Imbrecht Bermudez — Zenith Corp
// ─────────────────────────────────────────────────────────────────────────────

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title ZNTToken
 * @notice ERC-20 deflationary token. Supply is fixed at deploy.
 *         No mint function. The only direction of supply is down.
 *
 * @dev Implements the Proof of Alpha Protocol (PoA).
 *      Burns are triggered exclusively by verified prop firm payouts
 *      via the BuybackBurn module — never by arbitrary callers.
 *
 *      Deployed as an ERC-1967 upgradeable proxy to allow oracle evolution
 *      without changing the token contract address.
 */
contract ZNTToken is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ── Constants ────────────────────────────────────────────────────────────

    /// @notice Maximum and initial supply. Immutable after deploy.
    uint256 public constant MAX_SUPPLY = 21_000_000 * 1e18;

    /// @notice Dead address. Tokens sent here are permanently unretrievable.
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // ── State ─────────────────────────────────────────────────────────────────

    /// @notice The only address authorized to call burn().
    address public buybackBurnModule;

    /// @notice Total ZNT burned to date (informational).
    uint256 public totalBurned;

    // ── Events ────────────────────────────────────────────────────────────────

    /**
     * @notice Emitted on every burn event.
     * @param pnlUSD         Realized P&L of the triggering trade (×1e6 for precision)
     * @param zntBurned      ZNT permanently destroyed in this event
     * @param supplyAfter    Total supply remaining after this burn
     * @param tradeRecordHash SHA-256 of the original trade record from the prop firm
     * @param sequenceId     Unique sequence ID from the auditing institution (anti-replay)
     * @param oracle         Address that submitted the attestation
     */
    event BurnExecuted(
        uint256 pnlUSD,
        uint256 zntBurned,
        uint256 supplyAfter,
        bytes32 tradeRecordHash,
        uint256 sequenceId,
        address indexed oracle
    );

    event BuybackModuleUpdated(address indexed oldModule, address indexed newModule);

    // ── Initializer ───────────────────────────────────────────────────────────

    /**
     * @notice One-time initialization. Called by the proxy on deploy.
     *         This is the only moment tokens are created — never again.
     */
    function initialize(
        address initialOwner,
        address _buybackBurnModule
    ) public initializer {
        __ERC20_init("Zenith Token", "ZNT");
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();

        buybackBurnModule = _buybackBurnModule;

        // The one and only mint. Supply cannot grow after this point.
        _mint(initialOwner, MAX_SUPPLY);
    }

    // ── Core — Burn ───────────────────────────────────────────────────────────

    /**
     * @notice Burns ZNT by transferring to the dead address.
     *         Only callable by the authorized BuybackBurn module.
     *
     * @param amount          ZNT to burn (in wei)
     * @param pnlUSD          Realized P&L that triggered this burn (×1e6)
     * @param tradeRecordHash SHA-256 of the original trade record
     * @param sequenceId      Sequence ID from the external auditor
     */
    function burn(
        uint256 amount,
        uint256 pnlUSD,
        bytes32 tradeRecordHash,
        uint256 sequenceId
    ) external nonReentrant {
        require(msg.sender == buybackBurnModule, "ZNT: unauthorized caller");
        require(amount > 0, "ZNT: burn amount must be > 0");
        require(balanceOf(buybackBurnModule) >= amount, "ZNT: insufficient balance");

        _transfer(buybackBurnModule, DEAD, amount);
        totalBurned += amount;

        emit BurnExecuted(
            pnlUSD,
            amount,
            totalSupply() - amount,
            tradeRecordHash,
            sequenceId,
            msg.sender
        );
    }

    // ── Governance ────────────────────────────────────────────────────────────

    /**
     * @notice Updates the authorized BuybackBurn module.
     *         In V2+, this requires a 48h timelock.
     */
    function setBuybackModule(address newModule) external onlyOwner {
        require(newModule != address(0), "ZNT: zero address");
        emit BuybackModuleUpdated(buybackBurnModule, newModule);
        buybackBurnModule = newModule;
    }

    // ── View ──────────────────────────────────────────────────────────────────

    /// @notice Returns the circulating supply (excluding tokens at dead address).
    function circulatingSupply() external view returns (uint256) {
        return totalSupply() - balanceOf(DEAD);
    }
}
