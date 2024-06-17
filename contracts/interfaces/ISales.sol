// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ICOBase } from "../imports/DTO.sol";

interface ISales {
    /**
     * @dev Initializes the sale with the given parameters.
     * @param dto The data transfer object containing the sale parameters.
     */
    function initialize(ICOBase.DTO memory dto) external;

    /**
     * @dev Sets the wallet address for the sale.
     * @param _wallet The new wallet address.
     */
    function setWallet(address _wallet) external;

    /**
     * @dev Sets the minimum claim amount for the sale.
     * @param _minClaim The new minimum claim amount.
     */
    function setMinClaim(uint256 _minClaim) external;

    /**
     * @dev Finalizes the sale.
     */
    function finalizeSale() external;

    /**
     * @dev Triggers the claim period for the sale.
     */
    function triggerClaimPeriod() external;

    /**
     * @dev Returns whether the sale is finalized.
     * @return A boolean indicating if the sale is finalized.
     */
    function isSaleFinalized() external returns (bool);

    /**
     * @dev Returns the amount of tokens purchased in the sale.
     * @return The amount of tokens purchased.
     */
    function getTokenPurchased() external view returns (uint256);

    /**
     * @dev Returns the amount of wei raised in the sale.
     * @return The amount of wei raised.
     */
    function getWeiRaised() external view returns (uint256);

    /**
     * @dev Returns the round information of the sale.
     * return The round information as a DTO.
     */
    function getRoundInfo() external view returns (ICOBase.DTO memory roundInfoDTO);

    /**
     * @dev Pauses the sale.
     */
    function pause() external;

    /**
     * @dev Unpauses the sale.
     */
    function unpause() external;
}