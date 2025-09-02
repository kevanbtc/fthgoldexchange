// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./PreciousAssetVault.sol";
import "./ComplianceRegistry.sol";
import "./OracleManager.sol";

/**
 * @title AtomicEscrow
 * @dev Atomic Delivery-vs-Payment system for precious asset trading
 * Zero-risk trading with automatic escrow and compliance checking
 */
contract AtomicEscrow is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    bytes32 public constant ESCROW_OPERATOR_ROLE = keccak256("ESCROW_OPERATOR_ROLE");
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    enum EscrowStatus {
        PENDING,
        FUNDED,
        READY,
        EXECUTED,
        CANCELLED,
        DISPUTED,
        EXPIRED
    }
    
    enum AssetType {
        ERC20_TOKEN,
        ERC721_NFT,
        NATIVE_ETH,
        PRECIOUS_ASSET_NFT
    }
    
    struct EscrowTrade {
        uint256 tradeId;
        address buyer;
        address seller;
        EscrowStatus status;
        
        // Buyer's payment
        AssetType paymentType;
        address paymentToken;    // ERC20 address or address(0) for ETH
        uint256 paymentAmount;
        bool paymentDeposited;
        
        // Seller's asset
        AssetType assetType;
        address assetContract;   // NFT contract address
        uint256 assetTokenId;    // NFT token ID
        bool assetDeposited;
        
        // Trade parameters
        uint256 tradeValue;      // USD value of the trade
        uint256 deadline;        // Trade expiration timestamp
        uint256 createdAt;
        
        // Compliance data
        bool complianceApproved;
        bytes32 complianceHash;
        
        // Fee structure
        uint256 buyerFee;        // Fee paid by buyer (basis points)
        uint256 sellerFee;       // Fee paid by seller (basis points)
        bool feesCollected;
        
        // Dispute resolution
        bool disputeRaised;
        address disputeInitiator;
        string disputeReason;
        uint256 disputeDeadline;
        
        // Oracle verification
        bool oracleVerified;
        uint256 oraclePrice;
        uint256 oracleTimestamp;
    }
    
    // Contract references
    PreciousAssetVault public immutable assetVault;
    ComplianceRegistry public immutable complianceRegistry;
    OracleManager public immutable oracleManager;
    
    // Fee recipient (FTH treasury)
    address public feeRecipient;
    
    // Default fees (basis points)
    uint256 public defaultBuyerFeeBps = 25;  // 0.25%
    uint256 public defaultSellerFeeBps = 25; // 0.25%
    uint256 public constant MAX_FEE_BPS = 500; // 5% maximum
    
    // Trade storage
    mapping(uint256 => EscrowTrade) public trades;
    uint256 private _nextTradeId = 1;
    
    // User trade tracking
    mapping(address => uint256[]) public userTrades;
    
    // Emergency circuit breaker
    bool public emergencyPaused = false;
    
    // Dispute resolution timeouts
    uint256 public disputeTimeout = 7 days;
    uint256 public tradeTimeout = 30 days;
    
    event TradeCreated(
        uint256 indexed tradeId,
        address indexed buyer,
        address indexed seller,
        uint256 paymentAmount,
        uint256 assetTokenId,
        uint256 deadline
    );
    
    event PaymentDeposited(
        uint256 indexed tradeId,
        address indexed buyer,
        uint256 amount
    );
    
    event AssetDeposited(
        uint256 indexed tradeId,
        address indexed seller,
        uint256 tokenId
    );
    
    event TradeExecuted(
        uint256 indexed tradeId,
        address indexed buyer,
        address indexed seller,
        uint256 paymentAmount,
        uint256 assetTokenId
    );
    
    event TradeCancelled(
        uint256 indexed tradeId,
        address indexed initiator,
        string reason
    );
    
    event DisputeRaised(
        uint256 indexed tradeId,
        address indexed initiator,
        string reason
    );
    
    event ComplianceStatusUpdated(
        uint256 indexed tradeId,
        bool approved,
        bytes32 complianceHash
    );
    
    event FeesCollected(
        uint256 indexed tradeId,
        uint256 buyerFee,
        uint256 sellerFee
    );
    
    modifier tradeExists(uint256 tradeId) {
        require(tradeId < _nextTradeId && trades[tradeId].tradeId != 0, "Trade does not exist");
        _;
    }
    
    modifier onlyTradeParty(uint256 tradeId) {
        EscrowTrade memory trade = trades[tradeId];
        require(msg.sender == trade.buyer || msg.sender == trade.seller, "Not authorized");
        _;
    }
    
    modifier notExpired(uint256 tradeId) {
        require(block.timestamp <= trades[tradeId].deadline, "Trade expired");
        _;
    }
    
    modifier notEmergencyPaused() {
        require(!emergencyPaused, "Emergency pause active");
        _;
    }
    
    constructor(
        address _assetVault,
        address _complianceRegistry,
        address _oracleManager,
        address _feeRecipient
    ) {
        require(_assetVault != address(0), "Invalid asset vault");
        require(_complianceRegistry != address(0), "Invalid compliance registry");
        require(_oracleManager != address(0), "Invalid oracle manager");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        assetVault = PreciousAssetVault(_assetVault);
        complianceRegistry = ComplianceRegistry(_complianceRegistry);
        oracleManager = OracleManager(_oracleManager);
        feeRecipient = _feeRecipient;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ESCROW_OPERATOR_ROLE, msg.sender);
        _grantRole(COMPLIANCE_OFFICER_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }
    
    /**
     * @dev Create new atomic trade escrow
     */
    function createTrade(
        address seller,
        address paymentToken,    // ERC20 token or address(0) for ETH
        uint256 paymentAmount,
        address assetContract,   // NFT contract
        uint256 assetTokenId,
        uint256 tradeDeadline
    ) external whenNotPaused notEmergencyPaused nonReentrant returns (uint256 tradeId) {
        require(seller != address(0) && seller != msg.sender, "Invalid seller");
        require(paymentAmount > 0, "Invalid payment amount");
        require(assetContract != address(0), "Invalid asset contract");
        require(tradeDeadline > block.timestamp + 1 hours, "Deadline too soon");
        require(tradeDeadline <= block.timestamp + tradeTimeout, "Deadline too far");
        
        // Verify both parties have valid KYC
        require(complianceRegistry.verifyKYC(msg.sender), "Buyer KYC required");
        require(complianceRegistry.verifyKYC(seller), "Seller KYC required");
        
        // Verify seller owns the asset
        require(IERC721(assetContract).ownerOf(assetTokenId) == seller, "Seller doesn't own asset");
        
        // Get asset value for compliance checks
        uint256 assetValue;
        if (assetContract == address(assetVault)) {
            assetValue = assetVault.getAssetValue(assetTokenId);
            require(assetVault.isValidCertification(assetTokenId), "Invalid asset certification");
        }
        
        tradeId = _nextTradeId++;
        
        EscrowTrade storage trade = trades[tradeId];
        trade.tradeId = tradeId;
        trade.buyer = msg.sender;
        trade.seller = seller;
        trade.status = EscrowStatus.PENDING;
        
        // Payment details
        trade.paymentType = paymentToken == address(0) ? AssetType.NATIVE_ETH : AssetType.ERC20_TOKEN;
        trade.paymentToken = paymentToken;
        trade.paymentAmount = paymentAmount;
        
        // Asset details
        trade.assetType = assetContract == address(assetVault) ? 
                         AssetType.PRECIOUS_ASSET_NFT : AssetType.ERC721_NFT;
        trade.assetContract = assetContract;
        trade.assetTokenId = assetTokenId;
        
        trade.tradeValue = assetValue > 0 ? assetValue : paymentAmount;
        trade.deadline = tradeDeadline;
        trade.createdAt = block.timestamp;
        
        // Calculate fees
        trade.buyerFee = defaultBuyerFeeBps;
        trade.sellerFee = defaultSellerFeeBps;
        
        // Track user trades
        userTrades[msg.sender].push(tradeId);
        userTrades[seller].push(tradeId);
        
        emit TradeCreated(tradeId, msg.sender, seller, paymentAmount, assetTokenId, tradeDeadline);
        
        return tradeId;
    }
    
    /**
     * @dev Buyer deposits payment
     */
    function depositPayment(uint256 tradeId) 
        external 
        payable 
        tradeExists(tradeId) 
        notExpired(tradeId) 
        notEmergencyPaused 
        nonReentrant 
    {
        EscrowTrade storage trade = trades[tradeId];
        require(msg.sender == trade.buyer, "Only buyer can deposit payment");
        require(trade.status == EscrowStatus.PENDING, "Invalid trade status");
        require(!trade.paymentDeposited, "Payment already deposited");
        
        if (trade.paymentType == AssetType.NATIVE_ETH) {
            require(msg.value == trade.paymentAmount, "Incorrect ETH amount");
        } else {
            require(msg.value == 0, "No ETH required for token payment");
            IERC20(trade.paymentToken).safeTransferFrom(
                msg.sender, 
                address(this), 
                trade.paymentAmount
            );
        }
        
        trade.paymentDeposited = true;
        
        // Check if ready for execution
        if (trade.assetDeposited) {
            trade.status = EscrowStatus.READY;
            _performComplianceCheck(tradeId);
        } else {
            trade.status = EscrowStatus.FUNDED;
        }
        
        emit PaymentDeposited(tradeId, msg.sender, trade.paymentAmount);
    }
    
    /**
     * @dev Seller deposits asset
     */
    function depositAsset(uint256 tradeId) 
        external 
        tradeExists(tradeId) 
        notExpired(tradeId) 
        notEmergencyPaused 
        nonReentrant 
    {
        EscrowTrade storage trade = trades[tradeId];
        require(msg.sender == trade.seller, "Only seller can deposit asset");
        require(trade.status == EscrowStatus.PENDING || trade.status == EscrowStatus.FUNDED, 
                "Invalid trade status");
        require(!trade.assetDeposited, "Asset already deposited");
        
        // Transfer NFT to escrow
        IERC721(trade.assetContract).safeTransferFrom(
            msg.sender,
            address(this),
            trade.assetTokenId
        );
        
        trade.assetDeposited = true;
        
        // Check if ready for execution
        if (trade.paymentDeposited) {
            trade.status = EscrowStatus.READY;
            _performComplianceCheck(tradeId);
        }
        
        emit AssetDeposited(tradeId, msg.sender, trade.assetTokenId);
    }
    
    /**
     * @dev Execute atomic trade (automatic when all conditions met)
     */
    function executeTrade(uint256 tradeId) 
        external 
        tradeExists(tradeId) 
        notExpired(tradeId) 
        notEmergencyPaused 
        nonReentrant 
    {
        EscrowTrade storage trade = trades[tradeId];
        require(trade.status == EscrowStatus.READY, "Trade not ready for execution");
        require(trade.paymentDeposited && trade.assetDeposited, "Missing deposits");
        require(trade.complianceApproved, "Compliance not approved");
        
        // Final oracle verification for precious assets
        if (trade.assetType == AssetType.PRECIOUS_ASSET_NFT) {
            _performOracleVerification(tradeId);
            require(trade.oracleVerified, "Oracle verification failed");
        }
        
        trade.status = EscrowStatus.EXECUTED;
        
        // Collect fees first
        _collectFees(tradeId);
        
        // Transfer asset to buyer
        IERC721(trade.assetContract).safeTransferFrom(
            address(this),
            trade.buyer,
            trade.assetTokenId
        );
        
        // Transfer payment to seller
        uint256 sellerPayment = trade.paymentAmount - 
                               (trade.paymentAmount * trade.sellerFee) / 10000;
        
        if (trade.paymentType == AssetType.NATIVE_ETH) {
            (bool success,) = payable(trade.seller).call{value: sellerPayment}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(trade.paymentToken).safeTransfer(trade.seller, sellerPayment);
        }
        
        emit TradeExecuted(
            tradeId,
            trade.buyer,
            trade.seller,
            trade.paymentAmount,
            trade.assetTokenId
        );
    }
    
    /**
     * @dev Cancel trade (before execution)
     */
    function cancelTrade(uint256 tradeId, string calldata reason) 
        external 
        tradeExists(tradeId) 
        onlyTradeParty(tradeId) 
        nonReentrant 
    {
        EscrowTrade storage trade = trades[tradeId];
        require(trade.status != EscrowStatus.EXECUTED, "Trade already executed");
        require(trade.status != EscrowStatus.CANCELLED, "Trade already cancelled");
        
        trade.status = EscrowStatus.CANCELLED;
        
        // Refund buyer payment
        if (trade.paymentDeposited) {
            if (trade.paymentType == AssetType.NATIVE_ETH) {
                (bool success,) = payable(trade.buyer).call{value: trade.paymentAmount}("");
                require(success, "ETH refund failed");
            } else {
                IERC20(trade.paymentToken).safeTransfer(trade.buyer, trade.paymentAmount);
            }
        }
        
        // Return asset to seller
        if (trade.assetDeposited) {
            IERC721(trade.assetContract).safeTransferFrom(
                address(this),
                trade.seller,
                trade.assetTokenId
            );
        }
        
        emit TradeCancelled(tradeId, msg.sender, reason);
    }
    
    /**
     * @dev Raise dispute
     */
    function raiseDispute(uint256 tradeId, string calldata reason) 
        external 
        tradeExists(tradeId) 
        onlyTradeParty(tradeId) 
    {
        EscrowTrade storage trade = trades[tradeId];
        require(trade.status == EscrowStatus.READY || trade.status == EscrowStatus.FUNDED, 
                "Invalid status for dispute");
        require(!trade.disputeRaised, "Dispute already raised");
        
        trade.disputeRaised = true;
        trade.disputeInitiator = msg.sender;
        trade.disputeReason = reason;
        trade.disputeDeadline = block.timestamp + disputeTimeout;
        trade.status = EscrowStatus.DISPUTED;
        
        emit DisputeRaised(tradeId, msg.sender, reason);
    }
    
    /**
     * @dev Resolve dispute (admin only)
     */
    function resolveDispute(
        uint256 tradeId, 
        bool favorBuyer, 
        string calldata resolution
    ) external onlyRole(ESCROW_OPERATOR_ROLE) tradeExists(tradeId) {
        EscrowTrade storage trade = trades[tradeId];
        require(trade.status == EscrowStatus.DISPUTED, "No active dispute");
        
        if (favorBuyer) {
            // Refund buyer, return asset to seller
            if (trade.paymentDeposited) {
                if (trade.paymentType == AssetType.NATIVE_ETH) {
                    (bool success,) = payable(trade.buyer).call{value: trade.paymentAmount}("");
                    require(success, "ETH refund failed");
                } else {
                    IERC20(trade.paymentToken).safeTransfer(trade.buyer, trade.paymentAmount);
                }
            }
            
            if (trade.assetDeposited) {
                IERC721(trade.assetContract).safeTransferFrom(
                    address(this),
                    trade.seller,
                    trade.assetTokenId
                );
            }
        } else {
            // Execute trade in seller's favor
            this.executeTrade(tradeId);
        }
        
        trade.status = EscrowStatus.CANCELLED;
    }
    
    /**
     * @dev Internal functions
     */
    function _performComplianceCheck(uint256 tradeId) internal {
        EscrowTrade storage trade = trades[tradeId];
        
        // Check transaction compliance
        bool isCompliant = complianceRegistry.isTransactionCompliant(
            trade.buyer,
            trade.seller,
            1, // quantity
            trade.tradeValue,
            IComplianceFramework.JurisdictionType.US // Default jurisdiction
        );
        
        if (isCompliant) {
            // Perform AML check
            bytes32 sourceHash = keccak256(abi.encodePacked(
                trade.tradeId,
                trade.buyer,
                trade.paymentAmount
            ));
            
            bool amlApproved = complianceRegistry.performAMLCheck(
                trade.buyer,
                trade.paymentAmount,
                sourceHash
            );
            
            trade.complianceApproved = amlApproved;
            trade.complianceHash = sourceHash;
        }
        
        emit ComplianceStatusUpdated(tradeId, trade.complianceApproved, trade.complianceHash);
        
        // Auto-execute if all conditions met
        if (trade.complianceApproved && 
            trade.paymentDeposited && 
            trade.assetDeposited) {
            this.executeTrade(tradeId);
        }
    }
    
    function _performOracleVerification(uint256 tradeId) internal {
        EscrowTrade storage trade = trades[tradeId];
        
        if (trade.assetContract == address(assetVault)) {
            IAssetTypes.AssetSpecification memory spec = assetVault.getAssetSpecification(trade.assetTokenId);
            
            try oracleManager.getLatestPrice(spec.assetType) returns (
                OracleManager.AssetPrice memory price
            ) {
                trade.oraclePrice = price.price;
                trade.oracleTimestamp = price.timestamp;
                trade.oracleVerified = !price.isStale && price.confidence >= 5000;
            } catch {
                trade.oracleVerified = false;
            }
        } else {
            trade.oracleVerified = true; // Non-precious assets don't need oracle verification
        }
    }
    
    function _collectFees(uint256 tradeId) internal {
        EscrowTrade storage trade = trades[tradeId];
        
        if (!trade.feesCollected) {
            uint256 buyerFeeAmount = (trade.paymentAmount * trade.buyerFee) / 10000;
            uint256 sellerFeeAmount = (trade.paymentAmount * trade.sellerFee) / 10000;
            
            if (trade.paymentType == AssetType.NATIVE_ETH) {
                (bool success,) = payable(feeRecipient).call{value: buyerFeeAmount + sellerFeeAmount}("");
                require(success, "Fee collection failed");
            } else {
                IERC20(trade.paymentToken).safeTransfer(feeRecipient, buyerFeeAmount + sellerFeeAmount);
            }
            
            trade.feesCollected = true;
            
            emit FeesCollected(tradeId, buyerFeeAmount, sellerFeeAmount);
        }
    }
    
    /**
     * @dev Administrative functions
     */
    function setFees(uint256 buyerFeeBps, uint256 sellerFeeBps) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(buyerFeeBps <= MAX_FEE_BPS && sellerFeeBps <= MAX_FEE_BPS, "Fees too high");
        defaultBuyerFeeBps = buyerFeeBps;
        defaultSellerFeeBps = sellerFeeBps;
    }
    
    function setFeeRecipient(address newRecipient) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newRecipient != address(0), "Invalid recipient");
        feeRecipient = newRecipient;
    }
    
    function setTimeouts(uint256 _disputeTimeout, uint256 _tradeTimeout) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_disputeTimeout >= 1 days && _disputeTimeout <= 30 days, "Invalid dispute timeout");
        require(_tradeTimeout >= 1 days && _tradeTimeout <= 90 days, "Invalid trade timeout");
        disputeTimeout = _disputeTimeout;
        tradeTimeout = _tradeTimeout;
    }
    
    function emergencyPause() external onlyRole(EMERGENCY_ROLE) {
        emergencyPaused = true;
    }
    
    function emergencyUnpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergencyPaused = false;
    }
    
    /**
     * @dev View functions
     */
    function getTrade(uint256 tradeId) external view returns (EscrowTrade memory) {
        return trades[tradeId];
    }
    
    function getUserTrades(address user) external view returns (uint256[] memory) {
        return userTrades[user];
    }
    
    function getTradesByStatus(EscrowStatus status, uint256 offset, uint256 limit) 
        external 
        view 
        returns (uint256[] memory tradeIds) 
    {
        uint256[] memory result = new uint256[](limit);
        uint256 count = 0;
        uint256 skipped = 0;
        
        for (uint256 i = 1; i < _nextTradeId && count < limit; i++) {
            if (trades[i].status == status) {
                if (skipped >= offset) {
                    result[count] = i;
                    count++;
                } else {
                    skipped++;
                }
            }
        }
        
        // Resize array to actual count
        assembly {
            mstore(result, count)
        }
        
        return result;
    }
    
    /**
     * @dev Emergency functions
     */
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    // Handle NFT transfers
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}