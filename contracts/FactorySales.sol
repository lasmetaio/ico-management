// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imports
import { LasmOwnable } from "./imports/LasmOwnable.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { Address } from "./libs/Address.sol";
import { ISales, ICOBase } from "./interfaces/ISales.sol"; 

/**
 * @title FactorySales
 * @notice This contract manages the creation and administration of sales rounds using the 1167 minimal proxy pattern.
 * @dev Utilizes OpenZeppelin libraries for address validation, cloning, and contract ownership. 
 * It ensures secure and efficient deployment of crowdsale and whitelist sale contracts, 
 * allowing for controlled initialization, pausing, and finalization of sales rounds.
 */

contract FactorySales is ICOBase, Context, LasmOwnable {
    using Address for address;

    address private _crowdsaleImplementation;
    address private _whitelistSaleImplementation;
    address private _manager;

    // Events
    /**
     * @dev Emitted when a crowdsale is deployed.
     * @param _instance The address of the deployed crowdsale instance.
     */
    event CrowdsaleDeployed(address indexed _instance);

    /**
     * @dev Emitted when a whitelist sale is deployed.
     * @param _instance The address of the deployed whitelist sale instance.
     */
    event WhitelistSaleDeployed(address indexed _instance);

    /**
     * @dev Emitted when the sales manager is initialized.
     * @param _manager The address of the sales manager.
     */
    event SalesManagerInited(address indexed _manager);

    /**
     * @dev Emitted when a sales round is paused.
     * @param _saleAddress The address of the paused sales round.
     */
    event SalesRoundPaused(address indexed _saleAddress);

    /**
     * @dev Emitted when a sales round is unpaused.
     * @param _saleAddress The address of the unpaused sales round.
     */
    event SalesRoundUnPaused(address indexed _saleAddress);

    /**
     * @dev Emitted when pausing a sales round fails.
     * @param _saleAddress The address of the sales round that failed to pause.
     */
    event SalesRoundPausingFailed(address indexed _saleAddress);

    /**
     * @dev Emitted when unpausing a sales round fails.
     * @param _saleAddress The address of the sales round that failed to unpause.
     */
    event SalesRoundUnPauseFailed(address indexed _saleAddress);

    /**
     * @dev Emitted when the minimum claim amount is updated.
     * @param _minClaim The new minimum claim amount.
     */
    event MinClaimUpdated(uint256 indexed _minClaim);

    /**
     * @dev Emitted when the sales wallet is updated.
     * @param _wallet The new sales wallet address.
     */
    event SalesWalletUpdated(address indexed _wallet);

    /**
     * @dev Emitted when a sales round is finalized.
     * @param _saleAddress The address of the finalized sales round.
     */
    event SalesFinalized(address indexed _saleAddress);

    /**
     * @dev Emitted when the claim period is triggered for a sales round.
     * @param _saleAddress The address of the sales round.
     */
    event SalesClaimTriggered(address indexed _saleAddress);

    // Errors
    error InvalidAddressInteraction();
    error InvalidContractInteraction();
    error SalesRoundInitializationFailed();
    error MinClaimUpdateFailed();
    error SalesWalletUpdateFailed();
    error SalesFinalizationFailed();
    error SalesClaimTriggerFailed();
    error FailedToFetchRoundInfo();

    // Modifiers
    /**
     * @dev Modifier to validate if an address is a contract.
     * @param _address The address to validate.
     */
    modifier validContract(address _address) {
        if (!_address.isContract()) {
            revert InvalidContractInteraction();
        }
        _;
    }

    /**
     * @dev Modifier to validate if an address is non-zero.
     * @param _address The address to validate.
     */
    modifier validAddress(address _address) {
        if (_address == address(0)) {
            revert InvalidAddressInteraction();
        }
        _;
    }

    /**
     * @dev Initializes the FactorySales contract with the given implementation addresses.
     * @param __crowdsaleImplementation The address of the crowdsale implementation contract.
     * @param __whitelistSaleImplementation The address of the whitelist sale implementation contract.
     */
    constructor(address __crowdsaleImplementation, address __whitelistSaleImplementation) {
        if (
            !__crowdsaleImplementation.isContract() ||
            !__whitelistSaleImplementation.isContract()
        ) revert InvalidContractInteraction();

        _crowdsaleImplementation = __crowdsaleImplementation;
        _whitelistSaleImplementation = __whitelistSaleImplementation;

        _manager = _msgSender();
    }

    /**
     * @dev Creates a new whitelist sale.
     * @param dto The data transfer object containing the sale parameters.
     * @return The address of the created whitelist sale.
     */
    function createWhitelistSale(ICOBase.DTO calldata dto) external onlyOwner() returns (address) {
        address clone = Clones.clone(_whitelistSaleImplementation);
        try ISales(clone).initialize(dto) {
            emit WhitelistSaleDeployed(clone);
        } catch {
            revert SalesRoundInitializationFailed();
        }
        return clone;
    }

    /**
     * @dev Creates a new crowdsale.
     * @param dto The data transfer object containing the sale parameters.
     * @return The address of the created crowdsale.
     */
    function createCrowdsale(ICOBase.DTO calldata dto) external onlyOwner() returns (address) {
        address clone = Clones.clone(_crowdsaleImplementation);
        try ISales(clone).initialize(dto) {
            emit CrowdsaleDeployed(clone);
        } catch {
            revert SalesRoundInitializationFailed();
        }
        return clone;
    }

    /**
     * @dev Sets the minimum claim amount for a sale.
     * @param _saleAddress The address of the sale.
     * @param _minClaim The new minimum claim amount.
     */
    function setMinClaim(address _saleAddress, uint256 _minClaim)
    external
    validContract(_saleAddress)
    onlyOwner() {
        try ISales(_saleAddress).setMinClaim(_minClaim) {
            emit MinClaimUpdated(_minClaim);
        } catch {
            revert MinClaimUpdateFailed();
        }
    }

    /**
     * @dev Sets the wallet address for a sale.
     * @param _saleAddress The address of the sale.
     * @param _wallet The new wallet address.
     * @return True if the operation was successful.
     */
    function setWallet(address _saleAddress, address _wallet)
    external
    validContract(_saleAddress)
    validAddress(_wallet)
    onlyOwner()
    returns (bool) {
        try ISales(_saleAddress).setWallet(_wallet) {
            emit SalesWalletUpdated(_wallet);
        } catch {
            revert SalesWalletUpdateFailed();
        }
        return true;
    }

    /**
     * @dev Finalizes a sales round.
     * @param _saleAddress The address of the sale.
     * @return True if the operation was successful.
     */
    function finalizeTheRound(address _saleAddress)
    external
    validContract(_saleAddress)
    onlyOwner()
    returns (bool) {
        try ISales(_saleAddress).finalizeSale() {
            emit SalesFinalized(_saleAddress);
        } catch {
            revert SalesFinalizationFailed();
        }
        return true;
    }

    /**
     * @dev Triggers the claim period for a sales round.
     * @param _saleAddress The address of the sale.
     * @return True if the operation was successful.
     */
    function triggerClaimPeriod(address _saleAddress)
    external
    validContract(_saleAddress)
    onlyOwner()
    returns (bool) {
        try ISales(_saleAddress).triggerClaimPeriod() {
            emit SalesClaimTriggered(_saleAddress);
        } catch {
            revert SalesClaimTriggerFailed();
        }
        return true;
    }

    /**
     * @dev Checks if a sales round is finalized.
     * @param _saleAddress The address of the sale.
     * @return True if the sale is finalized.
     */
    function isRoundFinalized(address _saleAddress)
    external
    validContract(_saleAddress)
    returns (bool) {
        return ISales(_saleAddress).isSaleFinalized();
    }

    /**
     * @dev Returns the round information of a sale.
     * @param _saleAddress The address of the sale.
     * @return The round information as a DTO.
     */
    function getRoundInfo(address _saleAddress)
    external
    view
    validContract(_saleAddress)
    returns (ICOBase.DTO memory) {
        try ISales(_saleAddress).getRoundInfo() returns (ICOBase.DTO memory roundInfo) {
            return roundInfo;
        } catch {
            revert FailedToFetchRoundInfo();
        }
    }

    /**
     * @dev Returns the amount of tokens purchased in a sale.
     * @param _saleAddress The address of the sale.
     * @return The amount of tokens purchased.
     */
    function getTokenPurchased(address _saleAddress)
    external
    view
    validContract(_saleAddress)
    returns (uint256) {
        return ISales(_saleAddress).getTokenPurchased();
    }

    /**
     * @dev Returns the amount of wei raised in a sale.
     * @param _saleAddress The address of the sale.
     * @return The amount of wei raised.
     */
    function getWeiRaised(address _saleAddress)
    external
    view
    validContract(_saleAddress)
    returns (uint256) {
        return ISales(_saleAddress).getWeiRaised();
    }

    /**
     * @dev Pauses a sales round.
     * @param _saleAddress The address of the sale.
     */
    function pauseRound(address _saleAddress)
    external
    validContract(_saleAddress)
    onlyOwner() {
        try ISales(_saleAddress).pause() {
            emit SalesRoundPaused(_saleAddress);
        } catch {
            emit SalesRoundPausingFailed(_saleAddress);
        }
    }

    /**
     * @dev Unpauses a sales round.
     * @param _saleAddress The address of the sale.
     */
    function unPauseRound(address _saleAddress)
    external
    onlyOwner()
    validContract(_saleAddress) {
        try ISales(_saleAddress).unpause() {
            emit SalesRoundUnPaused(_saleAddress);
        } catch {
            emit SalesRoundUnPauseFailed(_saleAddress);
        }
    }
}