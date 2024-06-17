// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imports
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { TokenSaleBase } from "./TokenSaleBase.sol";

/**
 * @title WhitelistSale
 * @notice Implements a whitelisted token sale extending the TokenSaleBase contract.
 * @dev This contract facilitates the purchase of tokens by whitelisted users, ensuring only those with valid 
 * Merkle proofs can participate. It handles token transfers, validates inputs, manages the sale state, and 
 * emits events for token purchases. Initialization is restricted to a one-time setup with sale parameters.
 */

contract WhitelistSale is TokenSaleBase {
    using SafeERC20 for IERC20;
    
    bytes32 public merkleRoot;
    bool private _initialized;

    /**
     * @dev Allows whitelisted users to buy tokens with USDT.
     * @param usdtAmount The amount of USDT to spend.
     * @param proof The Merkle proof for whitelisting.
     */
    function buyTokens(uint256 usdtAmount, bytes32[] calldata proof) 
        external 
        nonReentrant() 
        whenNotPaused() 
    {
        if (buyTime <= block.timestamp || isFinalized == true) { 
            revert BuyTimeExpired();
        }

        if (usdtAmount < minBuy || usdtAmount > maxBuy) {
            revert AmountOutOfRange(usdtAmount);
        }

        if (_msgSender() == address(this)) {
            revert InvalidContractInteraction();
        }

        if (!isWhiteListed(_msgSender(), proof)) {
            revert NotWhiteListed();
        }

        uint256 tokensToBuy = (usdtAmount * E18) / (salePrice * E6);
        tokensToBuy *= E6;

        uint256 allowed = paymentToken.allowance(_msgSender(), address(this));
        if (allowed < usdtAmount) {
            revert InsufficientPaymentTokenAllowance();
        } 

        uint256 availableTokens = baseAsset.balanceOf(address(this));
        uint256 tokensRemaining = availableTokens - tokenPurchased;

        if (tokensRemaining < tokensToBuy) {
            revert InsufficientTokens(tokensToBuy, tokensRemaining);
        }

        paymentToken.safeTransferFrom(_msgSender(), address(this), usdtAmount);
        tokenPurchased += tokensToBuy;
        weiRaised += usdtAmount;

        msgValue[_msgSender()] += usdtAmount;
        purchase[_msgSender()] += tokensToBuy;

        emit TokensPurchased(_msgSender(), usdtAmount, tokensToBuy);
    }

    /**
     * @dev Initializes the whitelist sale with the given parameters.
     * @param dto The data transfer object containing the sale parameters.
     */
    function initialize(DTO memory dto) public override {
        if (_initialized) {
            revert TokenSaleAlreadyFinalized();
        }
        TokenSaleBase.initialize(dto);
        merkleRoot = dto.merkleRoot;
        _initialized = true;
    }

    /**
     * @dev Checks if an account is whitelisted.
     * @param _account The account to check.
     * @param proof The Merkle proof for whitelisting.
     * @return True if the account is whitelisted, false otherwise.
     */
    function isWhiteListed(address _account, bytes32[] calldata proof) 
        public 
        view
        returns (bool) 
    {
        bytes32 leaf = keccak256(abi.encodePacked(_account));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }
}