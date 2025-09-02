// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IAssetTypes.sol";
import "../interfaces/IComplianceFramework.sol";

/**
 * @title PreciousAssetVault
 * @dev NFT vault for tokenizing physical precious assets with full compliance
 * Each NFT represents a physical asset stored in certified vaults
 */
contract PreciousAssetVault is 
    ERC721, 
    ERC721URIStorage, 
    AccessControl, 
    ReentrancyGuard, 
    Pausable,
    IAssetTypes 
{
    bytes32 public constant VAULT_OPERATOR_ROLE = keccak256("VAULT_OPERATOR_ROLE");
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");
    bytes32 public constant CERTIFIER_ROLE = keccak256("CERTIFIER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    
    uint256 private _nextTokenId = 1;
    
    // Asset specifications for each token
    mapping(uint256 => AssetSpecification) private _assetSpecs;
    
    // Certification data for each token
    mapping(uint256 => CertificationData) private _certificationData;
    
    // Vault information for each token
    mapping(uint256 => VaultInfo) private _vaultInfo;
    
    // Oracle price feeds for different asset types
    mapping(uint256 => address) public priceOracles;
    
    // Compliance framework contract
    IComplianceFramework public complianceFramework;
    
    // Authorized vault operators
    mapping(address => bool) public authorizedVaults;
    
    // Asset redemption status
    mapping(uint256 => bool) public isRedeemed;
    
    struct VaultInfo {
        address vaultOperator;
        string vaultLocation;
        bytes32 storageReceipt;
        uint256 storageDate;
        bool isActive;
        uint256 insurancePolicyId;
        address insuranceProvider;
    }
    
    event AssetTokenized(
        uint256 indexed tokenId,
        address indexed owner,
        AssetCategory category,
        uint256 assetType,
        uint256 weight,
        address vaultOperator
    );
    
    event AssetRedeemed(
        uint256 indexed tokenId,
        address indexed owner,
        address indexed vaultOperator
    );
    
    event VaultStatusUpdated(
        address indexed vaultOperator,
        bool isAuthorized
    );
    
    event PriceOracleUpdated(
        uint256 indexed assetType,
        address indexed oracle
    );
    
    event InsuranceUpdated(
        uint256 indexed tokenId,
        uint256 policyId,
        address provider,
        uint256 value
    );
    
    modifier onlyAuthorizedVault() {
        require(authorizedVaults[msg.sender], "Not authorized vault operator");
        _;
    }
    
    modifier tokenExists(uint256 tokenId) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        _;
    }
    
    modifier notRedeemed(uint256 tokenId) {
        require(!isRedeemed[tokenId], "Asset already redeemed");
        _;
    }
    
    constructor(address _complianceFramework) ERC721("FTH Precious Asset Vault", "FTHPAV") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_OPERATOR_ROLE, msg.sender);
        _grantRole(COMPLIANCE_OFFICER_ROLE, msg.sender);
        
        complianceFramework = IComplianceFramework(_complianceFramework);
    }
    
    /**
     * @dev Mint new asset token representing physical precious asset
     */
    function mintAssetToken(
        address to,
        AssetSpecification calldata spec,
        CertificationData calldata cert,
        VaultInfo calldata vault,
        string calldata tokenURI
    ) external onlyRole(VAULT_OPERATOR_ROLE) whenNotPaused nonReentrant returns (uint256) {
        require(authorizedVaults[vault.vaultOperator], "Vault not authorized");
        require(complianceFramework.verifyKYC(to), "KYC verification required");
        require(cert.isValid && cert.expiryDate > block.timestamp, "Invalid certification");
        
        uint256 tokenId = _nextTokenId++;
        
        // Store asset specification
        _assetSpecs[tokenId] = spec;
        _certificationData[tokenId] = cert;
        _vaultInfo[tokenId] = vault;
        
        // Mint NFT
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        
        emit AssetTokenized(
            tokenId,
            to,
            spec.category,
            spec.assetType,
            spec.weight,
            vault.vaultOperator
        );
        
        emit CertificationVerified(
            tokenId,
            cert.certifyingAuthority != "" ? address(uint160(uint256(keccak256(bytes(cert.certifyingAuthority))))) : address(0),
            cert.documentHash
        );
        
        return tokenId;
    }
    
    /**
     * @dev Redeem physical asset and burn NFT
     */
    function redeemAsset(uint256 tokenId) 
        external 
        tokenExists(tokenId) 
        notRedeemed(tokenId) 
        nonReentrant 
    {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(complianceFramework.verifyKYC(msg.sender), "KYC verification required");
        
        VaultInfo memory vault = _vaultInfo[tokenId];
        require(vault.isActive, "Vault storage inactive");
        
        // Mark as redeemed
        isRedeemed[tokenId] = true;
        
        // Transfer to vault for physical delivery
        _transfer(msg.sender, vault.vaultOperator, tokenId);
        
        emit AssetRedeemed(tokenId, msg.sender, vault.vaultOperator);
    }
    
    /**
     * @dev Get current market value of asset in USD
     */
    function getAssetValue(uint256 tokenId) 
        external 
        view 
        override 
        tokenExists(tokenId) 
        returns (uint256 valueUSD) 
    {
        AssetSpecification memory spec = _assetSpecs[tokenId];
        address oracle = priceOracles[spec.assetType];
        
        if (oracle != address(0)) {
            // Get price from oracle (implementation depends on oracle type)
            // This is a placeholder - actual implementation would call oracle
            return spec.insuranceValue; // Fallback to insured value
        }
        
        return spec.insuranceValue;
    }
    
    /**
     * @dev Update asset specification (only compliance officer)
     */
    function updateAssetSpecification(
        uint256 tokenId,
        AssetSpecification calldata newSpec
    ) external onlyRole(COMPLIANCE_OFFICER_ROLE) tokenExists(tokenId) {
        _assetSpecs[tokenId] = newSpec;
        
        emit AssetSpecificationUpdated(
            tokenId,
            newSpec.category,
            newSpec.assetType,
            newSpec.purity
        );
    }
    
    /**
     * @dev Authorize/deauthorize vault operator
     */
    function setVaultAuthorization(address vaultOperator, bool authorized) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        authorizedVaults[vaultOperator] = authorized;
        
        if (authorized) {
            _grantRole(VAULT_OPERATOR_ROLE, vaultOperator);
        } else {
            _revokeRole(VAULT_OPERATOR_ROLE, vaultOperator);
        }
        
        emit VaultStatusUpdated(vaultOperator, authorized);
    }
    
    /**
     * @dev Set price oracle for asset type
     */
    function setPriceOracle(uint256 assetType, address oracle) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        priceOracles[assetType] = oracle;
        emit PriceOracleUpdated(assetType, oracle);
    }
    
    /**
     * @dev Update insurance information
     */
    function updateInsurance(
        uint256 tokenId,
        uint256 policyId,
        address provider,
        uint256 value
    ) external onlyRole(VAULT_OPERATOR_ROLE) tokenExists(tokenId) {
        _vaultInfo[tokenId].insurancePolicyId = policyId;
        _vaultInfo[tokenId].insuranceProvider = provider;
        _assetSpecs[tokenId].insuranceValue = value;
        _assetSpecs[tokenId].isInsured = true;
        
        emit InsuranceUpdated(tokenId, policyId, provider, value);
    }
    
    /**
     * @dev Emergency pause (compliance officer only)
     */
    function pause() external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause (admin only)
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    // View functions for asset data
    function getAssetSpecification(uint256 tokenId) 
        external 
        view 
        override 
        returns (AssetSpecification memory) 
    {
        return _assetSpecs[tokenId];
    }
    
    function getCertificationData(uint256 tokenId) 
        external 
        view 
        override 
        returns (CertificationData memory) 
    {
        return _certificationData[tokenId];
    }
    
    function getVaultInfo(uint256 tokenId) 
        external 
        view 
        returns (VaultInfo memory) 
    {
        return _vaultInfo[tokenId];
    }
    
    function isValidCertification(uint256 tokenId) 
        external 
        view 
        override 
        returns (bool) 
    {
        CertificationData memory cert = _certificationData[tokenId];
        return cert.isValid && cert.expiryDate > block.timestamp;
    }
    
    function totalSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }
    
    // Override functions for access control
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override whenNotPaused {
        // Compliance checks for transfers
        if (from != address(0) && to != address(0)) {
            require(complianceFramework.verifyKYC(to), "Recipient KYC required");
            
            // Check if transaction requires additional compliance
            uint256 assetValue = this.getAssetValue(tokenId);
            require(
                complianceFramework.isTransactionCompliant(
                    from, 
                    to, 
                    1, // quantity
                    assetValue,
                    IComplianceFramework.JurisdictionType.US // Default jurisdiction
                ), 
                "Transaction not compliant"
            );
        }
        
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
    
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
}