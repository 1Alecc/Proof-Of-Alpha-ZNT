// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  BuybackBurn — Proof of Alpha Protocol
//
//  Receives signed attestations from the FIX Oracle Bridge.
//  Validates them via OracleVerifier, then:
//    1. Swaps USDC → ZNT on a DEX (Uniswap V2 compatible)
//    2. Sends all purchased ZNT to ZNTToken.burn()
//
//  Author: Samuel Esteban Imbrecht Bermudez — Zenith Corp
//  First defined: April 27, 2026
// ─────────────────────────────────────────────────────────────────────────────

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IZNTToken {
    function burn(
        uint256 amount,
        uint256 pnlUSD,
        bytes32 tradeRecordHash,
        uint256 sequenceId
    ) external;
}

interface IOracleVerifier {
    function verify(
        uint256 payoutUSD,
        bytes32 tradeRecordHash,
        uint256 sequenceId,
        bytes calldata sig
    ) external;
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}

/**
 * @title BuybackBurn
 * @notice The engine of the Proof of Alpha burn mechanism.
 *
 *         Flow:
 *           executeBuybackAndBurn() called with FIX Bridge attestation
 *           → OracleVerifier validates signature + anti-replay
 *           → 30% of payoutUSD used to buy ZNT on DEX
 *           → All purchased ZNT sent to dead address via ZNTToken.burn()
 */
contract BuybackBurn is Ownable, ReentrancyGuard {

    // ── Immutable references ──────────────────────────────────────────────────
    IZNTToken        public immutable znt;
    IUniswapV2Router public immutable dex;
    IOracleVerifier  public           oracle;
    IERC20           public immutable usdc;

    // ── Parameters ────────────────────────────────────────────────────────────

    /// @notice % of payout directed to buyback, in basis points. Default: 3000 (30%).
    uint256 public burnRateBPS = 3000;

    /// @notice Max slippage on DEX swap, in basis points. Default: 200 (2%).
    uint256 public maxSlippageBPS = 200;

    /// @notice Swap deadline window in seconds. Default: 300 (5 min).
    uint256 public swapDeadline = 300;

    address public immutable usdcAddress;
    address public immutable zntAddress;

    // ── Events ────────────────────────────────────────────────────────────────

    event BuybackExecuted(
        uint256 payoutUSD,
        uint256 usdUsedForBurn,
        uint256 zntBought,
        uint256 sequenceId
    );

    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event BurnRateUpdated(uint256 oldRate, uint256 newRate);

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(
        address _znt,
        address _dex,
        address _oracle,
        address _usdc
    ) Ownable(msg.sender) {
        znt         = IZNTToken(_znt);
        dex         = IUniswapV2Router(_dex);
        oracle      = IOracleVerifier(_oracle);
        usdc        = IERC20(_usdc);
        usdcAddress = _usdc;
        zntAddress  = _znt;

        // Pre-approve DEX to spend USDC from this contract
        IERC20(_usdc).approve(_dex, type(uint256).max);
    }

    // ── Core ──────────────────────────────────────────────────────────────────

    /**
     * @notice Main entry point. Called by the FIX Oracle Bridge.
     *
     * @param payoutUSD       Verified payout amount in USD (×1e6)
     * @param tradeRecordHash SHA-256 of the original trade document
     * @param sequenceId      Unique sequence ID (anti-replay)
     * @param sig             ECDSA signature from the trusted ZPF Oracle signer
     */
    function executeBuybackAndBurn(
        uint256 payoutUSD,
        bytes32 tradeRecordHash,
        uint256 sequenceId,
        bytes calldata sig
    ) external nonReentrant {

        // 1. Verify attestation — reverts if invalid or replayed
        oracle.verify(payoutUSD, tradeRecordHash, sequenceId, sig);

        // 2. Calculate USDC amount for buyback
        uint256 usdcForBurn = (payoutUSD * burnRateBPS) / 10_000;
        require(usdcForBurn > 0, "BuybackBurn: burn amount is zero");
        require(
            usdc.balanceOf(address(this)) >= usdcForBurn,
            "BuybackBurn: insufficient USDC balance"
        );

        // 3. Buy ZNT on DEX with slippage protection
        uint256 zntBought = _buyZNT(usdcForBurn);
        require(zntBought > 0, "BuybackBurn: zero ZNT received from DEX");

        // 4. Burn all purchased ZNT
        znt.burn(zntBought, payoutUSD, tradeRecordHash, sequenceId);

        emit BuybackExecuted(payoutUSD, usdcForBurn, zntBought, sequenceId);
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    function _buyZNT(uint256 usdcAmount) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = usdcAddress;
        path[1] = zntAddress;

        uint256[] memory amounts = dex.swapExactTokensForTokens(
            usdcAmount,
            _minOut(usdcAmount, path),
            path,
            address(this),
            block.timestamp + swapDeadline
        );

        return amounts[1];
    }

    function _minOut(uint256 usdcAmount, address[] memory path) internal view returns (uint256) {
        uint256[] memory expected = dex.getAmountsOut(usdcAmount, path);
        return (expected[1] * (10_000 - maxSlippageBPS)) / 10_000;
    }

    // ── Governance ────────────────────────────────────────────────────────────

    function setOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "BuybackBurn: zero address");
        emit OracleUpdated(address(oracle), newOracle);
        oracle = IOracleVerifier(newOracle);
    }

    function setBurnRate(uint256 newRateBPS) external onlyOwner {
        require(newRateBPS <= 5000, "BuybackBurn: rate cannot exceed 50%");
        emit BurnRateUpdated(burnRateBPS, newRateBPS);
        burnRateBPS = newRateBPS;
    }

    function setMaxSlippage(uint256 newSlippageBPS) external onlyOwner {
        require(newSlippageBPS <= 500, "BuybackBurn: slippage cannot exceed 5%");
        maxSlippageBPS = newSlippageBPS;
    }

    /// @notice Emergency USDC withdrawal to treasury. Only owner.
    function withdrawUSDC(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "BuybackBurn: zero address");
        usdc.transfer(to, amount);
    }
}
