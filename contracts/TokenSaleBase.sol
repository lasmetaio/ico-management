// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imports
import { LasmOwnable } from "./imports/LasmOwnable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Address } from "./libs/Address.sol";
import { Math } from "./libs/Math.sol";
import { ICOBase } from "./imports/DTO.sol";

/**
 * @title TokenSaleBase
 * @notice Abstract base contract for token sales using the 1167 minimal proxy pattern.
 * @dev Implements functionality for purchasing and claiming tokens, managing sale parameters, and interacting with 
 * ERC-20 tokens. The contract supports multiple rounds of token sales, each with configurable parameters like 
 * minimum and maximum buy amounts, sale price, and claim periods. It ensures secure token transfers and validates 
 * contract interactions. The contract can be paused and unpaused by the owner and integrates with a vesting 
 * claiming contract for token distribution. Administrative functions allow the owner to finalize sales, trigger 
 * claim periods, and rescue tokens if needed.
 */

abstract contract TokenSaleBase is ICOBase, LasmOwnable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using Math for uint256;

    IERC20 public baseAsset;
    IERC20 public paymentToken;

    address private _operator;
    address private _manager;
    address private _wallet;

    uint256 public constant ZERO = 0;
    uint256 public constant ONE = 1;
    uint256 public constant TEN = 10;
    uint256 public constant HUNDRED = 100;
    uint256 public constant E12 = 1e12;
    uint256 public constant E18 = 1e18;
    uint256 public constant E6 = 1e6;
    uint256 public minBuy;
    uint256 public maxBuy;
    uint256 public salePrice;
    uint256 public minClaim = HUNDRED * E18;
    uint256 public tge = TEN;
    uint256 public installments = 12;

    uint256 public weiRaised;
    uint256 public tokenPurchased;

    uint256 public buyTime;        
    uint256 public limitationtime; 
    uint256 public claimTime;
    uint256 public claimDiff;
        
    mapping(address => uint256) public purchase;
    mapping(address => uint256) public claimed;
    mapping(address => uint256) public msgValue;
    
    mapping(address => uint256) public userRecentclaim;
    mapping(address => bool) public userTGEClaim;

    mapping(address => uint256) private _lastActionTime;

    // Events
    /**
     * @dev Emitted when tokens are purchased.
     * @param purchaser The address of the purchaser.
     * @param value The value of the purchase.
     * @param amount The amount of tokens purchased.
     */
    event TokensPurchased(address indexed purchaser, uint256 indexed value, uint256 indexed amount);

    /**
     * @dev Emitted when tokens are claimed.
     * @param claimant The address of the claimant.
     * @param amount The amount of tokens claimed.
     */
    event TokenClaimed(address indexed claimant, uint256 indexed amount);

    /**
     * @dev Emitted when the token sale is finalized.
     */
    event TokenSaleFinalized();

    /**
     * @dev Emitted when funds are transferred.
     * @param _contract The address of the contract.
     * @param _wallet The address of the wallet.
     * @param remainingTokensInTheContract The remaining tokens in the contract.
     */
    event FundsTransferred(
        address indexed _contract, 
        address indexed _wallet, 
        uint256 indexed remainingTokensInTheContract
    );

    /**
     * @dev Emitted when tokens are withdrawn.
     * @param baseAsset The address of the base asset.
     * @param _to The address of the recipient.
     * @param _amount The amount withdrawn.
     */
    event Withdrawal(address indexed baseAsset, address indexed _to, uint256 indexed _amount);

    // Errors
    error BuyTimeExpired();
    error ClaimPeriodNotStarted();
    error LockTimeNotExceeded();
    error InsufficientTokens(uint256 requested, uint256 available);
    error IDONotFinalized();
    error NoTokensToClaim();
    error InsufficientTokensForClaim(uint256 requested, uint256 available);
    error InsufficientPaymentTokenAllowance();
    error MinAmountToTokenClaimRequired();
    error TokenAmountIsZero();
    error AmountOutOfRange(uint256 amount);
    error AmountOutOfMinBuyRange(uint256 amount);
    error AmountOutOfMaxBuyRange(uint256 amount);
    error ClaimPeriodAlreadyTriggered();
    error NotWhiteListed();
    error TokenSaleInProgress();
    error TokenSaleAlreadyFinalized();
    error InvalidContractInteraction();
    error InvalidAddressInteraction();
    error DoesNotAcceptingEthers();
    error OnlyOperator();

    bool public isFinalized = false;
    bool public claimPeriodTriggered = false;
    bool private _initialized;

    // Modifiers
    /**
     * @dev Modifier to make a function callable only by the operator.
     */
    modifier onlyOperator(){
        if (_msgSender() != _operator) revert OnlyOperator();
        _;
    }

    /**
     * @dev Modifier to validate if an address is a contract.
     * @param _address The address to validate.
     */
    modifier validContract(address _address) {
        if (!Address.isContract(_address)) revert InvalidContractInteraction();
        _;
    }

    /**
     * @dev Modifier to validate if an address is non-zero.
     * @param _address The address to validate.
     */
    modifier validAddress(address _address) {
        if (_address.isZeroAddress()) revert InvalidAddressInteraction();
        _;
    }

    // Initialization
    /**
     * @dev Initializes the sale with the given parameters.
     * @param dto The data transfer object containing the sale parameters.
     */
    function initialize(DTO memory dto) public virtual {
        if (_initialized) revert TokenSaleAlreadyFinalized();
        if (!address(dto.token).isContract()) revert InvalidContractInteraction();

        _manager = dto.manager;
        _operator = _msgSender();
        _wallet = dto.wallet;

        if (!_manager.isContract()) revert InvalidContractInteraction();
        if (!_operator.isContract()) revert InvalidContractInteraction();
        if (_wallet.isZeroAddress()) revert InvalidAddressInteraction();

        _transferOwnership(_wallet);

        baseAsset = dto.token;
        paymentToken = dto.usdt;
        minBuy = dto.minBuy;
        maxBuy = dto.maxBuy;
        minClaim = minClaim;
        tge = dto.tge;
        installments = dto.installments;
        salePrice = dto.salePrice;
        buyTime = block.timestamp + dto.buyTime;
        limitationtime = buyTime + dto.lockTime + dto.claimTime;
        claimTime = dto.claimTime;
        claimDiff = dto.claimTime / installments;

        _initialized = true; 
    }

    /**
     * @dev Disallow direct ether transfers.
     */
    receive() external payable {
        revert DoesNotAcceptingEthers();
    }

    /**
     * @dev Disallow direct ether transfers.
     */
    fallback() external payable {
        revert DoesNotAcceptingEthers();
    }

    // Mechanics
    /**
     * @dev Returns the pending tokens for an account.
     * @param account The address of the account.
     * @return The amount of pending tokens and whether it includes TGE tokens.
     */
    function pendingTokens(address account) public view returns (uint256, bool) {
        if (!claimPeriodTriggered) revert ClaimPeriodNotStarted();
        
        if (purchase[account] == claimed[account]) {
            return (ZERO, true);
        } else if (block.timestamp >= claimTime) {
            return (purchase[account] - claimed[account], !userTGEClaim[account]);
        } else {
            uint256 initialAmount = userTGEClaim[account] ? ZERO : purchase[account] * tge / HUNDRED;
            bool isTge = !userTGEClaim[account];

            uint256 timeElapsed = block.timestamp - limitationtime;
            uint256 installmentMod = timeElapsed.floor(claimDiff);
           
            if (installmentMod == ZERO && !userTGEClaim[account]) {
                return (initialAmount, isTge);
            }

            uint256 perInstallment = (purchase[account] * (HUNDRED - tge) / HUNDRED) / installments;
            uint256 totalClaimable = perInstallment * installmentMod + initialAmount;

            if (claimed[account] == ZERO) {
                return (totalClaimable, isTge);
            }

            return (totalClaimable > claimed[account] ? perInstallment + initialAmount : ZERO, isTge);
        }
    }

    /**
     * @dev Claims tokens for the sender.
     */
    function claim() public virtual nonReentrant() whenNotPaused() {
        if (!claimPeriodTriggered) revert ClaimPeriodNotStarted();
        if (block.timestamp < limitationtime) revert LockTimeNotExceeded();

        if (!isFinalized) {
            revert IDONotFinalized();
        }
    
        (uint256 tokenAmount, bool isTge) = pendingTokens(_msgSender());
        if (tokenAmount <= 0) {
            revert NoTokensToClaim();
        }

        if (tokenAmount < minClaim) {
            revert MinAmountToTokenClaimRequired();
        }
    
        uint256 availableTokens = baseAsset.balanceOf(address(this));
        if (availableTokens < tokenAmount) {
            revert InsufficientTokensForClaim(tokenAmount, availableTokens);
        }
    
        claimed[_msgSender()] += tokenAmount;
        baseAsset.safeTransfer(_msgSender(), tokenAmount);
        userRecentclaim[_msgSender()] = block.timestamp;

        if (isTge) userTGEClaim[_msgSender()] = true;
    
        emit TokenClaimed(_msgSender(), tokenAmount);
    }    

    // Getters
    /**
     * @dev Returns whether the sale is finalized.
     * @return True if the sale is finalized, false otherwise.
     */
    function isSaleFinalized() external view returns (bool) {
        return isFinalized;
    }

    /**
     * @dev Returns the total amount of tokens purchased.
     * @return The total amount of tokens purchased.
     */
    function getTokenPurchased() external view returns (uint256) {
        return tokenPurchased;
    }

    /**
     * @dev Returns the total amount of wei raised.
     * @return The total amount of wei raised.
     */
    function getWeiRaised() external view returns (uint256) {
        return weiRaised;
    }

    /**
     * @dev Returns the operator address.
     * @return The operator address.
     */
    function getOperator() external view returns (address) {
        return _operator;
    }

    /**
     * @dev Returns the base asset address.
     * @return The base asset address.
     */
    function getBaseAsset() external view returns (address) {
        return address(baseAsset);
    }

    /**
     * @dev Returns the payment token address.
     * @return The payment token address.
     */
    function getPaymentToken() external view returns (address) {
        return address(paymentToken);
    }

    /**
     * @dev Returns the manager address.
     * @return The manager address.
     */
    function getManager() external view returns (address) {
        return address(_manager);
    }

    /**
     * @dev Returns the contract's balance of base assets.
     * @return The contract's balance of base assets.
     */
    function balance() external view returns (uint256) {
        return baseAsset.balanceOf(address(this));
    }

    /**
     * @dev Returns the USDT balance of a given owner.
     * @param _owner The address of the owner.
     * @return The USDT balance of the owner.
     */
    function usdtBalance(address _owner) external view returns (uint256) {
        return paymentToken.balanceOf(_owner);
    }

    /**
     * @dev Returns the round information.
     * @return The round information as a RoundInfoDTO.
     */
    function getRoundInfo() external view returns (RoundInfoDTO memory) {
        return ICOBase.RoundInfoDTO({
            roundContract: address(this),
            _wallet: _operator,
            _manager: _manager,
            _minBuy: minBuy,
            _maxBuy: maxBuy,
            _salePrice: salePrice,
            _buyTime: buyTime,
            _limitationtime: limitationtime,
            _claimTime: claimTime,
            _totalAmount: baseAsset.balanceOf(address(this)),
            _totalSold: tokenPurchased,
            _totalFunds: weiRaised,
            _isFinalized: isFinalized,
            _paused: paused()
        });
    }

    /**
     * @dev Returns the current price of tokens.
     * @return The current price of tokens.
     */
    function getPrice() public view returns (uint256) {
        uint256 tokens = ONE * E12 / salePrice;
        return tokens * E12;
    }

    /**
     * @dev Returns the manager and operator addresses.
     * @return The manager and operator addresses.
     */
    function getPermissions() public view returns (address, address) {
        return (_manager, _operator);
    }

    // Setters
    /**
     * @dev Sets the wallet address.
     * @param _newWallet The new wallet address.
     */
    function setWallet(address _newWallet) public onlyOwner() validAddress(_newWallet) {
        _transferOwnership(_newWallet);
        _operator = _newWallet;
    }

    /**
     * @dev Sets the minimum claim amount.
     * @param _minClaim The new minimum claim amount.
     * @return The updated minimum claim amount.
     */
    function setMinClaim(uint256 _minClaim) public onlyOperator() returns (uint256) {
        minClaim = _minClaim * E18;
        return minClaim;
    }

    // Internal Functions
    /**
     * @dev Forwards the remaining funds to the manager.
     */
    function _forwardFunds() internal {
        uint256 remainingTokensInTheContract = baseAsset.balanceOf(address(this)) - tokenPurchased;
        baseAsset.safeTransfer(_manager, remainingTokensInTheContract); 
        emit FundsTransferred(address(this), _manager, remainingTokensInTheContract);
        uint256 totalFunds = paymentToken.balanceOf(address(this));
        paymentToken.safeTransfer(_manager, totalFunds); 
        emit FundsTransferred(address(this), _manager, totalFunds);
    }

    // Administration
    /**
     * @dev Finalizes the sale.
     */
    function finalizeSale() public nonReentrant() onlyOperator() {
        if (isFinalized) revert TokenSaleAlreadyFinalized();
        isFinalized = true;
        _forwardFunds();
        emit TokenSaleFinalized();
    }

    /**
     * @dev Triggers the claim period for the sale.
     */
    function triggerClaimPeriod() public nonReentrant() onlyOperator() {
        if (!isFinalized) revert IDONotFinalized();
        if (claimPeriodTriggered) revert ClaimPeriodAlreadyTriggered();
        claimPeriodTriggered = true;
        limitationtime = block.timestamp;
        claimTime = limitationtime + claimTime;
    }

    /**
     * @dev Rescues tokens from the contract.
     * @param _tokenAddress The address of the token to rescue.
     * @param _to The address to send the rescued tokens to.
     * @param _amount The amount of tokens to rescue.
     */
    function rescueTokens(address _tokenAddress, address _to, uint256 _amount) 
    external 
    validContract(_tokenAddress)
    validAddress(_to) 
    onlyOwner() 
    {
        if (_amount == 0) revert TokenAmountIsZero();
        SafeERC20.safeTransfer(IERC20(_tokenAddress), _to, _amount);
        emit Withdrawal(_tokenAddress, _to, _amount);
    }

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyOperator() {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOperator() {
        _unpause();
    }
}
