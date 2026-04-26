// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  ZPFTreasury — Proof of Alpha Protocol
//
//  Manages the 40% reinvestment bucket from each Zenith payout.
//  When the balance reaches the threshold for a new funded account,
//  it signals readiness and (in V3+) executes the purchase automatically.
//
//  Author: Samuel Esteban Imbrecht Bermudez — Zenith Corp
//  First defined: April 27, 2026
// ─────────────────────────────────────────────────────────────────────────────

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ZPFTreasury
 * @notice Accumulates reinvestment funds and signals when a new funded
 *         account can be purchased — the expansion trigger of the autonomous loop.
 *
 * @dev V1: Owner (Samuel) receives the signal and executes purchase manually.
 *      V2: Multisig executes purchase when threshold is met.
 *      V3: Smart contract executes purchase autonomously via prop firm API.
 */
contract ZPFTreasury is Ownable, ReentrancyGuard {

    IERC20 public immutable usdc;

    // ── Parameters ────────────────────────────────────────────────────────────

    /// @notice % of each payout deposited to treasury, in basis points. Default: 4000 (40%).
    uint256 public reinvestRateBPS = 4000;

    /// @notice USDC threshold that triggers a "ready to expand" signal.
    ///         Set to the cost of the next funded account challenge.
    uint256 public expansionThreshold;

    /// @notice Tracks total USDC deposited historically.
    uint256 public totalDeposited;

    /// @notice Tracks total USDC withdrawn for account purchases.
    uint256 public totalWithdrawn;

    /// @notice Number of funded accounts purchased via this treasury.
    uint256 public accountsPurchased;

    // ── Events ────────────────────────────────────────────────────────────────

    event TreasuryDeposit(uint256 payoutUSD, uint256 amountDeposited, uint256 newBalance);
    event ExpansionReady(uint256 balance, uint256 threshold, uint256 timestamp);
    event AccountPurchased(uint256 cost, uint256 remainingBalance, uint256 totalAccounts);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(address _usdc, uint256 _expansionThreshold) Ownable(msg.sender) {
        usdc               = IERC20(_usdc);
        expansionThreshold = _expansionThreshold;
    }

    // ── Core ──────────────────────────────────────────────────────────────────

    /**
     * @notice Receives the reinvestment portion of a payout.
     *         Called by BuybackBurn after attestation is verified.
     *
     * @param payoutUSD Total payout being distributed (×1e6).
     */
    function deposit(uint256 payoutUSD) external nonReentrant {
        uint256 amount = (payoutUSD * reinvestRateBPS) / 10_000;
        require(amount > 0, "Treasury: deposit amount is zero");

        usdc.transferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;

        uint256 currentBalance = usdc.balanceOf(address(this));
        emit TreasuryDeposit(payoutUSD, amount, currentBalance);

        // Signal expansion readiness if threshold met
        if (currentBalance >= expansionThreshold && expansionThreshold > 0) {
            emit ExpansionReady(currentBalance, expansionThreshold, block.timestamp);
        }
    }

    /**
     * @notice Marks a funded account purchase.
     *         V1: Called manually by owner after purchasing the account.
     *         V3: Called automatically by account purchase module.
     *
     * @param cost USDC cost of the purchased account challenge.
     * @param to   Address that received the USDC for purchase.
     */
    function recordAccountPurchase(uint256 cost, address to) external onlyOwner nonReentrant {
        require(usdc.balanceOf(address(this)) >= cost, "Treasury: insufficient balance");
        require(to != address(0), "Treasury: zero address");

        usdc.transfer(to, cost);
        totalWithdrawn  += cost;
        accountsPurchased += 1;

        emit AccountPurchased(cost, usdc.balanceOf(address(this)), accountsPurchased);
    }

    // ── View ──────────────────────────────────────────────────────────────────

    function currentBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /// @notice Returns true if treasury has enough USDC to buy a new account.
    function expansionReady() external view returns (bool) {
        return expansionThreshold > 0 && usdc.balanceOf(address(this)) >= expansionThreshold;
    }

    // ── Governance ────────────────────────────────────────────────────────────

    function setExpansionThreshold(uint256 newThreshold) external onlyOwner {
        emit ThresholdUpdated(expansionThreshold, newThreshold);
        expansionThreshold = newThreshold;
    }

    function setReinvestRate(uint256 newRateBPS) external onlyOwner {
        require(newRateBPS <= 6000, "Treasury: reinvest rate cannot exceed 60%");
        reinvestRateBPS = newRateBPS;
    }

    /// @notice Emergency USDC recovery. Only owner, with event.
    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Treasury: zero address");
        usdc.transfer(to, amount);
    }
}
