// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// imports
import { LasmOwnable } from "./imports/LasmOwnable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Address } from "./libs/Address.sol";
import { FactorySales } from "./FactorySales.sol";
import { ICOBase } from "./imports/DTO.sol";
import { IVestingClaimingContract } from "./interfaces/IVestingClaimingContract.sol";
import { ILasm } from "./interfaces/ILasm.sol";

/**
 * @title Manager
 * @notice Manages the creation and administration of token sales rounds using the 1167 minimal proxy pattern.
 * @dev This contract facilitates the management of ICO rounds, including crowdsales and whitelist sales, 
 * by interacting with a factory contract. It ensures secure handling of token transfers, finalization of rounds, 
 * and setting minimum claim amounts. The contract supports pausing and unpausing of rounds and provides 
 * functionality for transferring and rescuing tokens. Key features include creating sales rounds, 
 * triggering claim periods, and updating token addresses securely.
 */

contract Manager is LasmOwnable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    struct RoundInfo {
        address roundAddress;
        uint8 roundType; // 0 for WhitelistSale, 1 for Crowdsale
        uint256 totalAmount;
        bool isFinalized;
    }

    IERC20 private _baseAsset;
    FactorySales public factorySales;
    
    IERC20 private _paymentToken;

    address private _crowdsaleImplementation;
    address private _whitelistSaleImplementation;
    address private _vestingClaimImplementation;
    address[] public icoAddresses;

    RoundInfo[] private _rounds;

    uint256 public constant ZERO = 0;
    uint256 public constant ONE = 1;

    // Events
    /**
     * @dev Emitted when the base token address is updated.
     * @param _oldBaseAsset The old base token address.
     * @param _baseAsset The new base token address.
     */
    event BaseTokenAddressUpdated(address indexed _oldBaseAsset, address indexed _baseAsset);

    /**
     * @dev Emitted when the payment token is updated.
     * @param _oldPaymentToken The old payment token.
     * @param _paymentToken The new payment token.
     */
    event PaymentTokenUpdated(address indexed _oldPaymentToken, address indexed _paymentToken);

    /**
     * @dev Emitted when a sales round is created.
     * @param _roundAddress The address of the sales round.
     * @param _amount The amount allocated for the round.
     */
    event SalesRoundCreated(address _roundAddress, uint256 indexed _amount);

    /**
     * @dev Emitted when a round is triggered.
     * @param _roundAddress The address of the triggered round.
     */
    event RoundTriggered(address indexed _roundAddress);

    /**
     * @dev Emitted when a round is finalized.
     * @param _roundAddress The address of the finalized round.
     */
    event RoundFinalized(address indexed _roundAddress);

    /**
     * @dev Emitted when a round is paused.
     * @param _roundAddress The address of the paused round.
     */
    event RoundPaused(address indexed _roundAddress);

    /**
     * @dev Emitted when a round is unpaused.
     * @param _roundAddress The address of the unpaused round.
     */
    event RoundUnPaused(address indexed _roundAddress);

    /**
     * @dev Emitted when the minimum claim for a round is changed.
     * @param _roundAddress The address of the round.
     * @param _minClaim The new minimum claim amount.
     */
    event RoundMinClaimChanged(address indexed _roundAddress, uint256 indexed _minClaim);

    /**
     * @dev Emitted when tokens or funds are withdrawn.
     * @param _owner The address of the owner initiating the withdrawal.
     * @param _destination The address receiving the tokens or funds.
     * @param _amount The amount withdrawn.
     */
    event Withdrawal(address indexed _owner, address indexed _destination, uint256 indexed _amount);

    // Errors
    error WrongRoundIndex();
    error InvalidAddressInteraction();
    error InvalidContractInteraction();
    error UpdatingTheSameAddress();
    error InsufficientContractBalance();
    error TokenAmountIsZero();
    error TransferringSalesTokensFailed();
    error DoesNotAcceptingEthers();
    error NotPermitted();

    // Modifiers
    /**
     * @dev Modifier to validate the round index.
     * @param _roundIndex The index of the round to validate.
     */
    modifier validRoundIndex(uint256 _roundIndex){
        if(_roundIndex >= _rounds.length) {
            revert WrongRoundIndex();
        }
        _;
    }

    /**
     * @dev Modifier to validate if an address is a contract.
     * @param _address The address to validate.
     */
    modifier validContract(address _address) {
        if(!_address.isContract()) {
            revert InvalidContractInteraction();
        }
        _;
    }

    /**
     * @dev Modifier to validate if an address is non-zero.
     * @param _address The address to validate.
     */
    modifier validAddress(address _address){
        if(_address == address(0)){
            revert InvalidAddressInteraction();
        }
        _;
    }

    // Constructor
    /**
     * @dev Initializes the contract with the specified addresses.
     * @param _baseAssetAddress The address of the base asset.
     * @param _usdtAddress The address of the USDT token.
     * @param _crowdsaleAddress The address of the crowdsale implementation.
     * @param _whitelistSaleAddress The address of the whitelist sale implementation.
     * @param _vestingClaimContractAddress The address of the vesting claim contract.
     */
    constructor(
        address _baseAssetAddress, 
        address _usdtAddress,  
        address _crowdsaleAddress, 
        address _whitelistSaleAddress,
        address _vestingClaimContractAddress
    ) {
        
        if(
            !_baseAssetAddress.isContract() ||
            !_usdtAddress.isContract() ||
            ! _crowdsaleAddress.isContract() ||
            ! _whitelistSaleAddress.isContract() ||
            ! _vestingClaimContractAddress.isContract()
        ) revert InvalidContractInteraction();

        _transferOwnership(_msgSender());
        
        _baseAsset = IERC20(_baseAssetAddress);
        _paymentToken = IERC20(_usdtAddress);
        _crowdsaleImplementation = _crowdsaleAddress;
        _whitelistSaleImplementation = _whitelistSaleAddress;
        _vestingClaimImplementation = _vestingClaimContractAddress;
        factorySales = new FactorySales(_crowdsaleImplementation, _whitelistSaleImplementation);
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
        revert NotPermitted();
    }
  
    // ICO Mechanics

    /**
     * @dev Initializes a sales round with the specified parameters.
     * @param amount The amount of tokens allocated for the round.
     * @param saleAddress The address of the sales round contract.
     * @param saleType The type of sales round (0 for WhitelistSale, 1 for Crowdsale).
     */
    function _initializeSale(
        uint256 amount,
        address saleAddress,
        uint8 saleType
    ) private {        
        _transferSaleTokens(saleAddress, amount);
        RoundInfo memory newRound = RoundInfo({
            roundAddress: saleAddress,
            roundType: saleType,
            totalAmount: amount,
            isFinalized: false
        });

        _rounds.push(newRound);
        icoAddresses.push(saleAddress);
    }

    /**
     * @dev Creates a new crowdsale round.
     * @param buyTime The start time for buying tokens.
     * @param lockTime The lock time for the tokens.
     * @param claimTime The time when tokens can be claimed.
     * @param tge The initial token generation event percentage.
     * @param installments The number of installments for token release.
     * @param minBuy The minimum buy amount.
     * @param maxBuy The maximum buy amount.
     * @param salePrice The price per token.
     * @param amount The amount of tokens allocated for the sale.
     */
    function createCrowdSale(
        uint256 buyTime,
        uint256 lockTime,
        uint256 claimTime,
        uint256 tge,
        uint256 installments,
        uint256 minBuy,
        uint256 maxBuy,
        uint256 salePrice,
        uint256 amount
    ) external whenNotPaused() onlyOwner() {

        ICOBase.DTO memory dto = ICOBase.DTO({
            wallet: _msgSender(), 
            manager: address(this), 
            token: _baseAsset,
            usdt: _paymentToken,
            minBuy: minBuy,
            maxBuy: maxBuy,
            tge:tge,
            installments:installments,
            salePrice: salePrice,
            buyTime: buyTime,
            lockTime: lockTime,
            claimTime: claimTime,
            merkleRoot: bytes32(0)
        });
            

        address roundClone = factorySales.createCrowdsale(dto);

        ILasm(address(_baseAsset)).excludeFromDividends(address(roundClone), true);
        ILasm(address(_baseAsset)).addRemoveFromTax(address(roundClone), true);

        _initializeSale(amount, address(roundClone), 1); // 1 indicates PublicSale
        emit SalesRoundCreated(address(roundClone), amount);
    }

    /**
     * @dev Creates a new whitelist sale round.
     * @param buyTime The start time for buying tokens.
     * @param lockTime The lock time for the tokens.
     * @param claimTime The time when tokens can be claimed.
     * @param tge The initial token generation event percentage.
     * @param installments The number of installments for token release.
     * @param minBuy The minimum buy amount.
     * @param maxBuy The maximum buy amount.
     * @param salePrice The price per token.
     * @param amount The amount of tokens allocated for the sale.
     * @param merkleRoot The Merkle root for whitelisted addresses.
     */
    function createWhitelistSale(        
        uint256 buyTime,
        uint256 lockTime,
        uint256 claimTime,
        uint256 tge,
        uint256 installments,
        uint256 minBuy,
        uint256 maxBuy,
        uint256 salePrice,
        uint256 amount,
        bytes32 merkleRoot
    ) external whenNotPaused() onlyOwner() {
        ICOBase.DTO memory dto = ICOBase.DTO({
            wallet: _msgSender(), 
            manager: address(this), 
            token: _baseAsset,
            usdt: _paymentToken,
            minBuy: minBuy,
            maxBuy: maxBuy,
            tge:tge,
            installments:installments,
            salePrice: salePrice,
            buyTime: buyTime,
            lockTime: lockTime,
            claimTime: claimTime,
            merkleRoot: merkleRoot
        });

        address roundClone = factorySales.createWhitelistSale(dto);

        ILasm(address(_baseAsset)).excludeFromDividends(address(roundClone),true);
        ILasm(address(_baseAsset)).addRemoveFromTax(address(roundClone), true);

        _initializeSale(amount, address(roundClone), 0);
        
        emit SalesRoundCreated(address(roundClone), amount);
    }

    /**
     * @dev Finalizes a sales round.
     * @param roundIndex The index of the round to finalize.
     */
    function finalizeRound(uint256 roundIndex) 
    external 
    whenNotPaused() 
    onlyOwner() 
    validRoundIndex(roundIndex) 
    {
        RoundInfo storage round = _rounds[roundIndex];
        factorySales.finalizeTheRound(round.roundAddress);
        round.isFinalized = true;
        emit RoundFinalized(round.roundAddress);
    }

    /**
     * @dev Sets the minimum claim amount for a round.
     * @param roundIndex The index of the round.
     * @param _minClaim The new minimum claim amount.
     */
    function setMinClaimForRound(uint256 roundIndex, uint256 _minClaim) 
    external 
    whenNotPaused() 
    onlyOwner() 
    validRoundIndex(roundIndex) 
    {
        RoundInfo storage round = _rounds[roundIndex];
        factorySales.setMinClaim(round.roundAddress, _minClaim);
        emit RoundMinClaimChanged(round.roundAddress, _minClaim);
    }

    /**
     * @dev Triggers the claim period for a round.
     * @param roundIndex The index of the round.
     */
    function triggerClaimPeriod(uint256 roundIndex) 
    external 
    whenNotPaused() 
    onlyOwner() 
    validRoundIndex(roundIndex) 
    {
        RoundInfo storage round = _rounds[roundIndex];    
        factorySales.triggerClaimPeriod(round.roundAddress);
        emit RoundTriggered(round.roundAddress);
    }

    /**
     * @dev Pauses a sales round.
     * @param roundIndex The index of the round to pause.
     */
    function pauseRound(uint256 roundIndex) 
    external 
    onlyOwner() 
    validRoundIndex(roundIndex) 
    {
        RoundInfo storage round = _rounds[roundIndex];        
        factorySales.pauseRound(round.roundAddress);
        emit RoundPaused(round.roundAddress);
    }

    /**
     * @dev Unpauses a sales round.
     * @param roundIndex The index of the round to unpause.
     */
    function unPauseRound(uint256 roundIndex) 
    external 
    onlyOwner() 
    validRoundIndex(roundIndex)
    {
        RoundInfo storage round = _rounds[roundIndex];        
        factorySales.unPauseRound(round.roundAddress);
        emit RoundUnPaused(round.roundAddress);
    }

    // Getters
     
    /**
     * @dev Returns the address of the FactorySales contract.
     * @return The address of the FactorySales contract.
     */
    function getFactorySalesAddress() external view returns (address) {
        return address(factorySales);
    }

    /**
     * @dev Returns the length of the rounds array.
     * @return The length of the rounds array.
     */
    function getRoundsLength() external view returns (uint256){
        return _rounds.length;
    }

    /**
     * @dev Returns the address of an ICO round.
     * @param roundIndex The index of the round.
     * @return The address of the ICO round.
     */
    function getICOInfo(uint256 roundIndex) external view validRoundIndex(roundIndex) returns (address) {
        return icoAddresses[roundIndex];
    }

    /**
     * @dev Returns the information of a sales round.
     * @param roundIndex The index of the round.
     * @return roundInfo The information of the sales round.
     */
    function roundSaleInfo(uint256 roundIndex) external view 
    onlyOwner validRoundIndex(roundIndex) returns (ICOBase.DTO memory roundInfo) {
        RoundInfo memory round = _rounds[roundIndex];
        return factorySales.getRoundInfo(round.roundAddress);
    }

    /**
     * @dev Returns the address of the base asset.
     * @return The address of the base asset.
     */
    function getBaseAsset() external view returns (address){
        return address(_baseAsset);
    }

    /**
     * @dev Returns the address of the payment token.
     * @return The address of the payment token.
     */
    function getPaymentToken() external view returns (address) {
        return address(_paymentToken);
    }

    /**
     * @dev Returns the USDT balance of the contract.
     * @return The USDT balance of the contract.
     */
    function totalUSDTBalance() external view returns (uint256){
        return _paymentToken.balanceOf(address(this));
    }
    
    /**
     * @dev Returns the balance of the base asset in the contract.
     * @return The balance of the base asset in the contract.
     */
    function totalBalance() external view returns (uint256){
        return _baseAsset.balanceOf(address(this));
    }

    // Administrator Functions

    /**
     * @dev Sets the address of the base token.
     * @param _tokenAddress The new base token address.
     */
    function setToken(address _tokenAddress)
    external 
    whenPaused() 
    validContract(_tokenAddress) 
    onlyOwner() 
    {   
        if(address(_baseAsset) == _tokenAddress) revert UpdatingTheSameAddress();
        emit BaseTokenAddressUpdated(address(_baseAsset), _tokenAddress);
        _baseAsset = IERC20(_tokenAddress);
    }

    /**
     * @dev Sets the address of the payment token.
     * @param _newPaymentToken The new payment token address.
     */
    function setPaymentToken(address _newPaymentToken)
    external 
    whenPaused() 
    validContract(_newPaymentToken) 
    onlyOwner() 
    {
        if(address(_paymentToken) == _newPaymentToken) revert UpdatingTheSameAddress();
        emit PaymentTokenUpdated(address(_paymentToken), _newPaymentToken);
        _paymentToken = IERC20(_newPaymentToken);
    }

    /**
     * @dev Transfers sale tokens to a recipient address.
     * @param recipient The recipient address.
     * @param _amount The amount of tokens to transfer.
     * @return success True if the transfer was successful.
     */
    function _transferSaleTokens(address recipient, uint256 _amount) 
    internal
    nonReentrant()
    validAddress(recipient)
    returns (bool success) 
    {
        uint256 _initialBalanceBefore = _baseAsset.balanceOf(address(this));

        if(_amount == ZERO) revert TokenAmountIsZero();

        if(_amount > _baseAsset.balanceOf(address(this))) {
            IVestingClaimingContract(_vestingClaimImplementation).claimTokensForICO();
            if(_initialBalanceBefore >= _baseAsset.balanceOf(address(this))) revert TransferringSalesTokensFailed();
        }

        if(_amount > _baseAsset.balanceOf(address(this))) revert InsufficientContractBalance();

        IERC20(_baseAsset).safeTransfer(recipient, _amount);

        return true;
    }

    /**
     * @dev Withdraws payment tokens to a destination address.
     * @param _destination The destination address.
     */
    function withDrawFunds(address _destination) 
    external 
    nonReentrant()
    validAddress(_destination)
    onlyOwner()
    {
        uint256 totalFunds = _paymentToken.balanceOf(address(this));
        if(totalFunds == ZERO) revert TokenAmountIsZero();
        _paymentToken.safeTransfer(_destination, totalFunds);
        emit Withdrawal(address(this), _destination, totalFunds);
    }

    /**
     * @dev Withdraws base asset tokens to a destination address.
     * @param _destination The destination address.
     */
    function withDrawTokens(address _destination) 
    external 
    nonReentrant()
    validAddress(_destination)
    onlyOwner()
    {
        uint256 totalTokens = _baseAsset.balanceOf(address(this));
        if(totalTokens == ZERO) revert TokenAmountIsZero();
        IERC20(_baseAsset).safeTransfer(_destination, totalTokens);
        emit Withdrawal(address(this), _destination, totalTokens);
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
        if(_amount == 0) revert TokenAmountIsZero();
        SafeERC20.safeTransfer(IERC20(_tokenAddress), _to, _amount);
        emit Withdrawal(_tokenAddress, _to, _amount);
    }

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyOwner() {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwner(){
        _unpause();
    }
}
