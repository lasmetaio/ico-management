// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imports
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ICOBase
 * @notice A base contract providing data structures for ICO rounds.
 * @dev Utilizes SafeERC20 for safe token transfers and operations.
*/

contract ICOBase {
    using SafeERC20 for IERC20;

    /**
     * @dev Struct representing the information of an ICO round.
     * @param roundContract The address of the round contract.
     * @param _wallet The wallet address associated with the round.
     * @param _manager The manager address for the round.
     * @param _minBuy The minimum amount that can be bought in the round.
     * @param _maxBuy The maximum amount that can be bought in the round.
     * @param _salePrice The sale price of the tokens.
     * @param _buyTime The start time for buying tokens.
     * @param _limitationtime The time limit for the round.
     * @param _claimTime The time when tokens can be claimed.
     * @param _totalAmount The total amount of tokens available in the round.
     * @param _totalSold The total amount of tokens sold in the round.
     * @param _totalFunds The total funds raised in the round.
     * @param _isFinalized Whether the round is finalized.
     * @param _paused Whether the round is paused.
     */
    struct RoundInfoDTO {
        address roundContract;
        address _wallet;
        address _manager;
        uint256 _minBuy;
        uint256 _maxBuy;
        uint256 _salePrice;
        uint256 _buyTime;
        uint256 _limitationtime;
        uint256 _claimTime;
        uint256 _totalAmount;
        uint256 _totalSold;
        uint256 _totalFunds;
        bool _isFinalized;
        bool _paused;
    }

    /**
     * @dev Struct representing the data transfer object for initializing an ICO round.
     * @param wallet The wallet address for the ICO round.
     * @param manager The manager address for the ICO round.
     * @param token The ERC20 token being sold in the ICO.
     * @param usdt The USDT token used for payments in the ICO.
     * @param minBuy The minimum amount that can be bought in the ICO.
     * @param maxBuy The maximum amount that can be bought in the ICO.
     * @param salePrice The sale price of the tokens.
     * @param buyTime The start time for buying tokens.
     * @param lockTime The lock time for the tokens.
     * @param claimTime The time when tokens can be claimed.
     * @param tge The initial token generation event percentage.
     * @param installments The number of installments for token release.
     * @param merkleRoot The Merkle root for whitelisted addresses.
     */
    struct DTO {
        address wallet;
        address manager;
        IERC20 token;
        IERC20 usdt;
        uint256 minBuy;
        uint256 maxBuy;
        uint256 salePrice;
        uint256 buyTime;
        uint256 lockTime;
        uint256 claimTime;
        uint256 tge;
        uint256 installments;
        bytes32 merkleRoot;
    }
}
