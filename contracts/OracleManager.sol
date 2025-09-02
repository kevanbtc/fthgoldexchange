// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IAssetTypes.sol";

/**
 * @title OracleManager
 * @dev Manages price feeds and verification oracles for all precious assets
 * Supports Chainlink price feeds and custom verification oracles
 */
contract OracleManager is AccessControl, ReentrancyGuard, IAssetTypes {
    bytes32 public constant ORACLE_OPERATOR_ROLE = keccak256("ORACLE_OPERATOR_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    
    // Chainlink price feed aggregators for different assets
    mapping(uint256 => AggregatorV3Interface) public priceFeedsChainlink;
    
    // Custom price feeds for assets not on Chainlink
    mapping(uint256 => PriceFeedData) public customPriceFeeds;
    
    // Asset verification oracles (for Proof of Reserve)
    mapping(uint256 => address) public verificationOracles;
    
    // Emergency price overrides (admin only)
    mapping(uint256 => EmergencyPrice) public emergencyPrices;
    
    // Price staleness threshold (24 hours default)
    uint256 public maxPriceAge = 24 hours;
    
    // Price deviation threshold for alerts (5% default)
    uint256 public deviationThreshold = 500; // 5% in basis points
    
    struct PriceFeedData {
        uint256 price;          // Price in USD with 8 decimals
        uint256 timestamp;      // Last update timestamp
        address updater;        // Address that provided the update
        uint256 confidence;     // Confidence score (0-10000 basis points)
        bool isActive;          // Whether this feed is active
    }
    
    struct EmergencyPrice {
        uint256 price;
        uint256 timestamp;
        bool isActive;
        string reason;
    }
    
    struct AssetPrice {
        uint256 price;          // Price in USD (8 decimals)
        uint256 timestamp;      // Price timestamp
        uint256 confidence;     // Confidence level
        bool isStale;          // Whether price is stale
        string source;         // Price source identifier
    }
    
    event PriceFeedUpdated(
        uint256 indexed assetType,
        uint256 price,
        uint256 timestamp,
        string source
    );
    
    event EmergencyPriceSet(
        uint256 indexed assetType,
        uint256 price,
        string reason
    );
    
    event VerificationOracleUpdated(
        uint256 indexed assetType,
        address indexed oracle
    );
    
    event PriceDeviation(
        uint256 indexed assetType,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 deviationPercent
    );
    
    modifier validAssetType(uint256 assetType) {
        require(assetType < 100, "Invalid asset type"); // Assuming max 100 asset types
        _;
    }
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_OPERATOR_ROLE, msg.sender);
        _grantRole(PRICE_UPDATER_ROLE, msg.sender);
    }
    
    /**
     * @dev Set Chainlink price feed for an asset type
     */
    function setChainlinkPriceFeed(
        uint256 assetType, 
        address aggregator
    ) external onlyRole(ORACLE_OPERATOR_ROLE) validAssetType(assetType) {
        require(aggregator != address(0), "Invalid aggregator address");
        
        priceFeedsChainlink[assetType] = AggregatorV3Interface(aggregator);
        
        // Test the aggregator
        try priceFeedsChainlink[assetType].latestRoundData() {
            // Success
        } catch {
            revert("Invalid Chainlink aggregator");
        }
    }
    
    /**
     * @dev Update custom price feed
     */
    function updateCustomPrice(
        uint256 assetType,
        uint256 price,
        uint256 confidence
    ) external onlyRole(PRICE_UPDATER_ROLE) validAssetType(assetType) nonReentrant {
        require(price > 0, "Invalid price");
        require(confidence <= 10000, "Invalid confidence");
        
        PriceFeedData storage feed = customPriceFeeds[assetType];
        uint256 oldPrice = feed.price;
        
        // Check for significant price deviation
        if (oldPrice > 0) {
            uint256 deviation = oldPrice > price ? 
                ((oldPrice - price) * 10000) / oldPrice :
                ((price - oldPrice) * 10000) / oldPrice;
                
            if (deviation > deviationThreshold) {
                emit PriceDeviation(assetType, oldPrice, price, deviation);
            }
        }
        
        feed.price = price;
        feed.timestamp = block.timestamp;
        feed.updater = msg.sender;
        feed.confidence = confidence;
        feed.isActive = true;
        
        emit PriceFeedUpdated(assetType, price, block.timestamp, "custom");
    }
    
    /**
     * @dev Get latest price for asset type
     */
    function getLatestPrice(uint256 assetType) 
        external 
        view 
        validAssetType(assetType) 
        returns (AssetPrice memory) 
    {
        // Check emergency price first
        EmergencyPrice memory emergencyPrice = emergencyPrices[assetType];
        if (emergencyPrice.isActive && 
            block.timestamp - emergencyPrice.timestamp <= maxPriceAge) {
            return AssetPrice({
                price: emergencyPrice.price,
                timestamp: emergencyPrice.timestamp,
                confidence: 10000, // Emergency prices are 100% confident
                isStale: false,
                source: "emergency"
            });
        }
        
        // Try Chainlink first
        AggregatorV3Interface chainlinkFeed = priceFeedsChainlink[assetType];
        if (address(chainlinkFeed) != address(0)) {
            try chainlinkFeed.latestRoundData() returns (
                uint80 roundId,
                int256 price,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            ) {
                if (price > 0 && updatedAt > 0) {
                    bool isStale = block.timestamp - updatedAt > maxPriceAge;
                    return AssetPrice({
                        price: uint256(price),
                        timestamp: updatedAt,
                        confidence: isStale ? 5000 : 10000, // Reduce confidence if stale
                        isStale: isStale,
                        source: "chainlink"
                    });
                }
            } catch {
                // Fall through to custom feed
            }
        }
        
        // Use custom price feed
        PriceFeedData memory customFeed = customPriceFeeds[assetType];
        if (customFeed.isActive && customFeed.price > 0) {
            bool isStale = block.timestamp - customFeed.timestamp > maxPriceAge;
            return AssetPrice({
                price: customFeed.price,
                timestamp: customFeed.timestamp,
                confidence: isStale ? customFeed.confidence / 2 : customFeed.confidence,
                isStale: isStale,
                source: "custom"
            });
        }
        
        revert("No price feed available for asset type");
    }
    
    /**
     * @dev Get asset value based on weight and current price
     */
    function calculateAssetValue(
        uint256 assetType,
        uint256 weight, // in grams for metals, carats for stones
        uint256 purity  // purity multiplier (e.g., 750 for 18k gold)
    ) external view returns (uint256 valueUSD) {
        AssetPrice memory priceData = this.getLatestPrice(assetType);
        require(!priceData.isStale, "Price feed is stale");
        require(priceData.confidence >= 5000, "Price confidence too low");
        
        // Calculate base value
        uint256 baseValue = (weight * priceData.price) / 1e8; // Price has 8 decimals
        
        // Apply purity adjustment for metals
        AssetCategory category = getAssetCategory(assetType);
        if (category == AssetCategory.PRECIOUS_METAL && purity > 0) {
            baseValue = (baseValue * purity) / 1000; // Purity in parts per thousand
        }
        
        return baseValue;
    }
    
    /**
     * @dev Set verification oracle for asset verification
     */
    function setVerificationOracle(
        uint256 assetType,
        address oracle
    ) external onlyRole(ORACLE_OPERATOR_ROLE) validAssetType(assetType) {
        verificationOracles[assetType] = oracle;
        emit VerificationOracleUpdated(assetType, oracle);
    }
    
    /**
     * @dev Set emergency price override
     */
    function setEmergencyPrice(
        uint256 assetType,
        uint256 price,
        string calldata reason
    ) external onlyRole(DEFAULT_ADMIN_ROLE) validAssetType(assetType) {
        require(price > 0, "Invalid emergency price");
        
        emergencyPrices[assetType] = EmergencyPrice({
            price: price,
            timestamp: block.timestamp,
            isActive: true,
            reason: reason
        });
        
        emit EmergencyPriceSet(assetType, price, reason);
    }
    
    /**
     * @dev Clear emergency price override
     */
    function clearEmergencyPrice(uint256 assetType) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        validAssetType(assetType) 
    {
        emergencyPrices[assetType].isActive = false;
    }
    
    /**
     * @dev Update oracle parameters
     */
    function setMaxPriceAge(uint256 maxAge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(maxAge >= 1 hours && maxAge <= 7 days, "Invalid max age");
        maxPriceAge = maxAge;
    }
    
    function setDeviationThreshold(uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(threshold >= 100 && threshold <= 5000, "Invalid threshold"); // 1% to 50%
        deviationThreshold = threshold;
    }
    
    /**
     * @dev Batch price updates for efficiency
     */
    function batchUpdatePrices(
        uint256[] calldata assetTypes,
        uint256[] calldata prices,
        uint256[] calldata confidences
    ) external onlyRole(PRICE_UPDATER_ROLE) nonReentrant {
        require(
            assetTypes.length == prices.length && 
            prices.length == confidences.length,
            "Array length mismatch"
        );
        
        for (uint256 i = 0; i < assetTypes.length; i++) {
            this.updateCustomPrice(assetTypes[i], prices[i], confidences[i]);
        }
    }
    
    /**
     * @dev Get price feed status
     */
    function getPriceFeedStatus(uint256 assetType) 
        external 
        view 
        returns (
            bool hasChainlink,
            bool hasCustom,
            bool hasEmergency,
            uint256 lastUpdate,
            bool isStale
        ) 
    {
        hasChainlink = address(priceFeedsChainlink[assetType]) != address(0);
        hasCustom = customPriceFeeds[assetType].isActive;
        hasEmergency = emergencyPrices[assetType].isActive;
        
        // Get the most recent update time
        uint256 chainlinkUpdate = 0;
        if (hasChainlink) {
            try priceFeedsChainlink[assetType].latestRoundData() returns (
                uint80, int256, uint256, uint256 updatedAt, uint80
            ) {
                chainlinkUpdate = updatedAt;
            } catch {}
        }
        
        uint256 customUpdate = customPriceFeeds[assetType].timestamp;
        uint256 emergencyUpdate = emergencyPrices[assetType].timestamp;
        
        lastUpdate = chainlinkUpdate;
        if (customUpdate > lastUpdate) lastUpdate = customUpdate;
        if (emergencyUpdate > lastUpdate) lastUpdate = emergencyUpdate;
        
        isStale = block.timestamp - lastUpdate > maxPriceAge;
    }
    
    /**
     * @dev Helper function to determine asset category
     */
    function getAssetCategory(uint256 assetType) internal pure returns (AssetCategory) {
        if (assetType < 10) return AssetCategory.PRECIOUS_METAL;
        if (assetType < 50) return AssetCategory.PRECIOUS_STONE;
        if (assetType < 80) return AssetCategory.RARE_EARTH;
        return AssetCategory.COLLECTIBLE;
    }
    
    /**
     * @dev Emergency functions
     */
    function pausePriceFeed(uint256 assetType) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        validAssetType(assetType) 
    {
        customPriceFeeds[assetType].isActive = false;
    }
    
    function resumePriceFeed(uint256 assetType) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        validAssetType(assetType) 
    {
        customPriceFeeds[assetType].isActive = true;
    }
}