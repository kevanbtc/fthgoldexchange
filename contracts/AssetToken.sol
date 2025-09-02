// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./PreciousAssetVault.sol";

/**
 * @title AssetToken
 * @dev ERC20 fractional ownership tokens backed by NFT vault assets
 * Allows fractional trading of expensive precious assets
 */
contract AssetToken is ERC20, ERC20Permit, AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
    
    // Backing NFT vault contract
    PreciousAssetVault public immutable vaultContract;
    
    // NFT token ID that backs this ERC20 token
    uint256 public immutable backingTokenId;
    
    // Total fractional supply (immutable after creation)
    uint256 public immutable maxSupply;
    
    // Minimum transfer amount to prevent dust
    uint256 public minTransferAmount;
    
    // Fee structure
    uint256 public transferFeeBps = 5; // 0.05% transfer fee
    uint256 public constant MAX_FEE_BPS = 100; // 1% maximum fee
    
    // Fee recipient (FTH treasury)
    address public feeRecipient;
    
    // Redemption tracking
    mapping(address => uint256) public redemptionRequests;
    uint256 public totalRedemptionRequests;
    bool public redemptionEnabled = true;
    
    event FractionalMinted(address indexed to, uint256 amount, uint256 backingTokenId);
    event FractionalBurned(address indexed from, uint256 amount, uint256 backingTokenId);
    event RedemptionRequested(address indexed user, uint256 amount);
    event RedemptionFulfilled(address indexed user, uint256 amount);
    event TransferFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    
    modifier validAmount(uint256 amount) {
        require(amount >= minTransferAmount, "Amount below minimum");
        _;
    }
    
    modifier redemptionAllowed() {
        require(redemptionEnabled, "Redemption currently disabled");
        _;
    }
    
    constructor(
        string memory name,
        string memory symbol,
        address _vaultContract,
        uint256 _backingTokenId,
        uint256 _maxSupply,
        uint256 _minTransferAmount,
        address _feeRecipient
    ) ERC20(name, symbol) ERC20Permit(name) {
        require(_vaultContract != address(0), "Invalid vault contract");
        require(_maxSupply > 0, "Invalid max supply");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        vaultContract = PreciousAssetVault(_vaultContract);
        backingTokenId = _backingTokenId;
        maxSupply = _maxSupply;
        minTransferAmount = _minTransferAmount;
        feeRecipient = _feeRecipient;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        _grantRole(COMPLIANCE_OFFICER_ROLE, msg.sender);
    }
    
    /**
     * @dev Mint fractional tokens backed by NFT vault asset
     */
    function mint(address to, uint256 amount) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
        validAmount(amount)
        nonReentrant 
    {
        require(totalSupply() + amount <= maxSupply, "Exceeds max supply");
        require(vaultContract.ownerOf(backingTokenId) == address(this), "NFT not owned by contract");
        
        // Verify backing asset still exists and is valid
        require(!vaultContract.isRedeemed(backingTokenId), "Backing asset redeemed");
        require(vaultContract.isValidCertification(backingTokenId), "Invalid certification");
        
        _mint(to, amount);
        
        emit FractionalMinted(to, amount, backingTokenId);
    }
    
    /**
     * @dev Burn fractional tokens
     */
    function burn(uint256 amount) 
        external 
        validAmount(amount) 
        nonReentrant 
    {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        _burn(msg.sender, amount);
        
        emit FractionalBurned(msg.sender, amount, backingTokenId);
    }
    
    /**
     * @dev Request redemption of physical asset (proportional)
     */
    function requestRedemption(uint256 amount) 
        external 
        redemptionAllowed 
        validAmount(amount) 
        nonReentrant 
    {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(redemptionRequests[msg.sender] == 0, "Pending redemption exists");
        
        // Check if user owns enough tokens for meaningful redemption
        uint256 ownership = (amount * 10000) / totalSupply(); // Basis points
        require(ownership >= 100, "Minimum 1% ownership required for redemption");
        
        // Lock tokens for redemption
        redemptionRequests[msg.sender] = amount;
        totalRedemptionRequests += amount;
        
        // Transfer tokens to contract
        _transfer(msg.sender, address(this), amount);
        
        emit RedemptionRequested(msg.sender, amount);
    }
    
    /**
     * @dev Fulfill redemption request (admin only)
     */
    function fulfillRedemption(address user) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
    {
        uint256 amount = redemptionRequests[user];
        require(amount > 0, "No pending redemption");
        
        // Clear redemption request
        redemptionRequests[user] = 0;
        totalRedemptionRequests -= amount;
        
        // Burn the locked tokens
        _burn(address(this), amount);
        
        // If this represents the full asset, transfer NFT for physical redemption
        if (totalSupply() == 0) {
            // Transfer NFT to user for physical redemption
            vaultContract.safeTransferFrom(address(this), user, backingTokenId);
        }
        
        emit RedemptionFulfilled(user, amount);
    }
    
    /**
     * @dev Cancel redemption request
     */
    function cancelRedemption() external nonReentrant {
        uint256 amount = redemptionRequests[msg.sender];
        require(amount > 0, "No pending redemption");
        
        redemptionRequests[msg.sender] = 0;
        totalRedemptionRequests -= amount;
        
        // Return tokens to user
        _transfer(address(this), msg.sender, amount);
    }
    
    /**
     * @dev Transfer with fees
     */
    function transfer(address to, uint256 amount) 
        public 
        override 
        validAmount(amount) 
        returns (bool) 
    {
        uint256 fee = (amount * transferFeeBps) / 10000;
        uint256 netAmount = amount - fee;
        
        if (fee > 0) {
            _transfer(msg.sender, feeRecipient, fee);
        }
        
        return super.transfer(to, netAmount);
    }
    
    /**
     * @dev TransferFrom with fees
     */
    function transferFrom(address from, address to, uint256 amount) 
        public 
        override 
        validAmount(amount) 
        returns (bool) 
    {
        uint256 fee = (amount * transferFeeBps) / 10000;
        uint256 netAmount = amount - fee;
        
        if (fee > 0) {
            _transfer(from, feeRecipient, fee);
        }
        
        return super.transferFrom(from, to, netAmount);
    }
    
    /**
     * @dev Get current asset value per token
     */
    function getAssetValuePerToken() external view returns (uint256) {
        if (totalSupply() == 0) return 0;
        
        uint256 totalAssetValue = vaultContract.getAssetValue(backingTokenId);
        return totalAssetValue / totalSupply();
    }
    
    /**
     * @dev Get backing asset information
     */
    function getBackingAssetInfo() external view returns (
        IAssetTypes.AssetSpecification memory spec,
        IAssetTypes.CertificationData memory cert,
        bool isValid
    ) {
        spec = vaultContract.getAssetSpecification(backingTokenId);
        cert = vaultContract.getCertificationData(backingTokenId);
        isValid = vaultContract.isValidCertification(backingTokenId) && 
                  !vaultContract.isRedeemed(backingTokenId);
    }
    
    /**
     * @dev Admin functions
     */
    function setTransferFee(uint256 feeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(feeBps <= MAX_FEE_BPS, "Fee too high");
        uint256 oldFee = transferFeeBps;
        transferFeeBps = feeBps;
        emit TransferFeeUpdated(oldFee, feeBps);
    }
    
    function setFeeRecipient(address newRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRecipient != address(0), "Invalid recipient");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }
    
    function setMinTransferAmount(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minTransferAmount = amount;
    }
    
    function setRedemptionEnabled(bool enabled) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        redemptionEnabled = enabled;
    }
    
    function pause() external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Compliance checks before transfers
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        // Skip compliance checks for minting/burning and internal transfers
        if (from == address(0) || to == address(0) || from == address(this) || to == address(this)) {
            return;
        }
        
        // Verify KYC for recipient
        require(
            vaultContract.complianceFramework().verifyKYC(to), 
            "Recipient KYC required"
        );
        
        super._beforeTokenTransfer(from, to, amount);
    }
    
    /**
     * @dev Get redemption info for user
     */
    function getRedemptionInfo(address user) external view returns (
        uint256 pendingAmount,
        uint256 userBalance,
        uint256 ownershipPercent,
        bool canRedeem
    ) {
        pendingAmount = redemptionRequests[user];
        userBalance = balanceOf(user);
        
        if (totalSupply() > 0) {
            ownershipPercent = (userBalance * 10000) / totalSupply(); // Basis points
        }
        
        canRedeem = redemptionEnabled && 
                   userBalance >= minTransferAmount && 
                   ownershipPercent >= 100 && // 1% minimum
                   pendingAmount == 0;
    }
}