// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAssetTypes - Asset Classification System
 * @dev Defines all supported precious assets with standardized categories
 */
interface IAssetTypes {
    
    enum AssetCategory {
        PRECIOUS_METAL,
        PRECIOUS_STONE,
        RARE_EARTH,
        COLLECTIBLE
    }
    
    enum MetalType {
        GOLD,           // 24K, 22K, 18K, 14K
        SILVER,         // 999, 925 Sterling
        PLATINUM,       // 950, 900
        PALLADIUM,      // Investment grade
        RHODIUM,        // Industrial/Investment
        IRIDIUM,        // Rare applications
        RUTHENIUM,      // Industrial catalyst
        OSMIUM          // Ultra-rare
    }
    
    enum StoneType {
        DIAMOND,        // Natural, Lab-grown
        EMERALD,        // Colombian, Zambian, Brazilian
        RUBY,           // Burmese, Thai, African
        SAPPHIRE,       // Kashmir, Ceylon, Australian
        ALEXANDRITE,    // Color-changing chrysoberyl
        PARAIBA,        // Paraiba Tourmaline
        JADEITE,        // Imperial Jade
        TANZANITE,      // Blue Zoisite
        PAINITE,        // Ultra-rare borate mineral
        RED_BERYL       // Bixbite - rarest gem
    }
    
    enum GoldPurity {
        K24,    // 999.9 fine gold
        K22,    // 916 fine gold
        K18,    // 750 fine gold
        K14,    // 585 fine gold
        K10     // 417 fine gold
    }
    
    enum SilverPurity {
        FINE_999,       // 99.9% pure
        STERLING_925,   // 92.5% silver
        COIN_900,       // 90% silver (coins)
        BRITANNIA_958   // 95.8% silver
    }
    
    enum DiamondGrade {
        FL,     // Flawless
        IF,     // Internally Flawless  
        VVS1,   // Very Very Slightly Included 1
        VVS2,   // Very Very Slightly Included 2
        VS1,    // Very Slightly Included 1
        VS2,    // Very Slightly Included 2
        SI1,    // Slightly Included 1
        SI2,    // Slightly Included 2
        I1,     // Included 1
        I2,     // Included 2
        I3      // Included 3
    }
    
    enum ColorGrade {
        D, E, F,        // Colorless
        G, H, I, J,     // Near Colorless
        K, L, M,        // Faint Yellow
        N_TO_R,         // Very Light Yellow
        S_TO_Z          // Light Yellow
    }
    
    struct AssetSpecification {
        AssetCategory category;
        uint256 assetType;      // MetalType or StoneType enum value
        uint256 purity;         // Purity/Grade enum value
        uint256 weight;         // In grams (metals) or carats (stones)
        uint256 dimensions;     // Encoded dimensions
        bytes32 certificateHash; // Hash of certification documents
        address certifyingBody; // Authorized certification entity
        bool isInsured;         // Insurance coverage status
        uint256 insuranceValue; // Insured value in USD
    }
    
    struct CertificationData {
        string certificateNumber;
        string certifyingAuthority;
        uint256 certificationDate;
        uint256 expiryDate;
        bytes32 documentHash;
        bool isValid;
    }
    
    event AssetSpecificationUpdated(
        uint256 indexed tokenId,
        AssetCategory category,
        uint256 assetType,
        uint256 purity
    );
    
    event CertificationVerified(
        uint256 indexed tokenId,
        address indexed certifyingBody,
        bytes32 certificateHash
    );
    
    function getAssetSpecification(uint256 tokenId) 
        external 
        view 
        returns (AssetSpecification memory);
    
    function getCertificationData(uint256 tokenId) 
        external 
        view 
        returns (CertificationData memory);
    
    function isValidCertification(uint256 tokenId) 
        external 
        view 
        returns (bool);
    
    function getAssetValue(uint256 tokenId) 
        external 
        view 
        returns (uint256 valueUSD);
}