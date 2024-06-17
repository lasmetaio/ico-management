// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imports
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { TokenSaleBase } from "./TokenSaleBase.sol";

/**
 * @title Crowdsale
 * @notice Implements a general token sale extending the TokenSaleBase contract.
 * @dev This contract enables users to purchase tokens with USDT, ensuring the sale operates within specified 
 * limits. It manages token transfers, sale validation, state management, and event emission for purchases.
 * Initialization is restricted to a one-time setup with sale parameters, and purchase operations handle various 
 * edge cases such as insufficient allowances or token availability.
*/

contract Crowdsale is TokenSaleBase {
    using SafeERC20 for IERC20;

    bool private _initialized;
    
    /**
     * @dev Allows users to buy tokens with USDT.
     * @param usdtAmount The amount of USDT to spend.
     */
    function buyTokens(uint256 usdtAmount) external nonReentrant() whenNotPaused() {
        if (buyTime <= block.timestamp || isFinalized == true) { 
            revert BuyTimeExpired();
        }

        if (usdtAmount < minBuy || usdtAmount > maxBuy) {
            revert AmountOutOfRange(usdtAmount);
        }

        if (_msgSender() == address(this)) {
            revert InvalidContractInteraction();
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
     * @dev Initializes the crowdsale with the given parameters.
     * @param dto The data transfer object containing the sale parameters.
     */
    function initialize(DTO memory dto) public override {
        if (_initialized) {
            revert TokenSaleAlreadyFinalized();
        }
        TokenSaleBase.initialize(dto); 
        _initialized = true;
    }
}
