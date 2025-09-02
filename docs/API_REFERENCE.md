# FTH Gold Exchange - API Reference

## Smart Contract Interfaces

### PreciousAssetVault

The main NFT contract for tokenizing precious assets.

#### Functions

##### `mintAssetToken(address to, AssetSpecification spec, CertificationData cert, VaultInfo vault, string tokenURI) → uint256`
Mint a new asset token representing a physical precious asset.

**Parameters:**
- `to`: Address to receive the NFT
- `spec`: Asset specification (category, type, purity, weight, etc.)
- `cert`: Certification data (certificate number, authority, hashes)
- `vault`: Vault storage information
- `tokenURI`: Metadata URI for the NFT

**Returns:** Token ID of the minted NFT

**Requirements:**
- Caller must have `VAULT_OPERATOR_ROLE`
- `to` address must have valid KYC
- Vault must be authorized
- Certification must be valid and not expired

##### `redeemAsset(uint256 tokenId)`
Redeem the physical asset and burn the NFT.

**Parameters:**
- `tokenId`: ID of the token to redeem

**Requirements:**
- Caller must own the token
- Caller must have valid KYC
- Asset must not already be redeemed

##### `getAssetValue(uint256 tokenId) → uint256`
Get the current USD value of an asset.

**Parameters:**
- `tokenId`: ID of the token

**Returns:** Current value in USD (6 decimals)

---

### AtomicEscrow

Atomic delivery-vs-payment system for risk-free trading.

#### Functions

##### `createTrade(address seller, address paymentToken, uint256 paymentAmount, address assetContract, uint256 assetTokenId, uint256 deadline) → uint256`
Create a new atomic trade escrow.

**Parameters:**
- `seller`: Address of the asset seller
- `paymentToken`: ERC20 token for payment (address(0) for ETH)
- `paymentAmount`: Amount to pay
- `assetContract`: Contract address of the asset
- `assetTokenId`: Token ID of the asset
- `deadline`: Trade expiration timestamp

**Returns:** Trade ID

**Requirements:**
- Both buyer and seller must have valid KYC
- Seller must own the asset
- Deadline must be reasonable (1 hour to 30 days)

##### `depositPayment(uint256 tradeId)`
Buyer deposits payment into escrow.

**Parameters:**
- `tradeId`: ID of the trade

**Requirements:**
- Caller must be the buyer
- Payment not already deposited
- Trade not expired

##### `depositAsset(uint256 tradeId)`
Seller deposits asset into escrow.

**Parameters:**
- `tradeId`: ID of the trade

**Requirements:**
- Caller must be the seller
- Asset not already deposited
- Trade not expired

##### `executeTrade(uint256 tradeId)`
Execute the atomic trade (automatic when conditions are met).

**Parameters:**
- `tradeId`: ID of the trade

**Requirements:**
- Both payment and asset deposited
- Compliance checks passed
- Oracle verification successful (for precious assets)

---

### ComplianceRegistry

Global compliance framework for KYC/AML and regulatory requirements.

#### Functions

##### `verifyKYC(address user) → bool`
Check if a user has valid KYC status.

**Parameters:**
- `user`: Address to check

**Returns:** True if KYC is valid and not expired

##### `updateKYCStatus(address user, ComplianceStatus status, RiskLevel riskLevel, bytes32 evidenceHash)`
Update KYC status for a user.

**Parameters:**
- `user`: User address
- `status`: Compliance status (PENDING, APPROVED, REJECTED, etc.)
- `riskLevel`: Risk level (LOW, MEDIUM, HIGH, PROHIBITED)
- `evidenceHash`: Hash of KYC evidence documents

**Requirements:**
- Caller must be authorized KYC provider

##### `performAMLCheck(address user, uint256 amount, bytes32 sourceHash) → bool`
Perform anti-money laundering check.

**Parameters:**
- `user`: User to check
- `amount`: Transaction amount
- `sourceHash`: Hash of source of funds documentation

**Returns:** True if AML check passes

---

### OracleManager

Price feeds and verification oracles for precious assets.

#### Functions

##### `getLatestPrice(uint256 assetType) → AssetPrice`
Get the latest price for an asset type.

**Parameters:**
- `assetType`: Type of asset (0=Gold, 1=Silver, etc.)

**Returns:** AssetPrice struct with price, timestamp, confidence, and staleness

##### `updateCustomPrice(uint256 assetType, uint256 price, uint256 confidence)`
Update custom price feed (for assets not on Chainlink).

**Parameters:**
- `assetType`: Asset type to update
- `price`: Price in USD (8 decimals)
- `confidence`: Confidence level (0-10000 basis points)

**Requirements:**
- Caller must have `PRICE_UPDATER_ROLE`

##### `calculateAssetValue(uint256 assetType, uint256 weight, uint256 purity) → uint256`
Calculate total asset value based on current prices.

**Parameters:**
- `assetType`: Type of asset
- `weight`: Weight in grams (metals) or carats (stones)
- `purity`: Purity level (parts per thousand)

**Returns:** Total value in USD

---

## Asset Types and Classifications

### Precious Metals
- `0`: Gold (24K, 22K, 18K, 14K, 10K)
- `1`: Silver (999, 925 Sterling, 900 Coin, 958 Britannia)
- `2`: Platinum (950, 900)
- `3`: Palladium
- `4`: Rhodium
- `5`: Iridium
- `6`: Ruthenium
- `7`: Osmium

### Precious Stones
- `10`: Diamond (Natural, Lab-grown)
- `11`: Emerald (Colombian, Zambian, Brazilian)
- `12`: Ruby (Burmese, Thai, African)
- `13`: Sapphire (Kashmir, Ceylon, Australian)
- `14`: Alexandrite
- `15`: Paraiba Tourmaline
- `16`: Jadeite
- `17`: Tanzanite
- `18`: Painite
- `19`: Red Beryl (Bixbite)

### Compliance Jurisdictions
- `0`: US (United States)
- `1`: EU (European Union)
- `2`: UK (United Kingdom)
- `3`: SINGAPORE
- `4`: SWITZERLAND
- `5`: DUBAI (UAE/DMCC)
- `6`: HONGKONG
- `7`: CANADA
- `8`: AUSTRALIA
- `9`: JAPAN

## Error Codes

### Common Errors
- `"KYC verification required"`: User needs valid KYC
- `"Not authorized vault operator"`: Caller lacks vault permissions
- `"Invalid certification"`: Asset certification is invalid or expired
- `"Trade expired"`: Trade deadline has passed
- `"Insufficient balance"`: Not enough tokens/ETH for transaction
- `"Price feed is stale"`: Oracle price is too old
- `"Transaction not compliant"`: Fails compliance checks

### Asset Validation Errors
- `"Asset already redeemed"`: Cannot trade redeemed assets
- `"Vault not authorized"`: Vault operator not approved
- `"Invalid asset type"`: Asset type not supported
- `"Certificate expired"`: Asset certification has expired

### Trading Errors
- `"Trade not ready for execution"`: Missing deposits or approvals
- `"Payment already deposited"`: Cannot deposit payment twice
- `"Asset already deposited"`: Cannot deposit asset twice
- `"No active dispute"`: Trying to resolve non-existent dispute

## Events

### Key Events to Monitor

#### AssetTokenized
```solidity
event AssetTokenized(uint256 indexed tokenId, address indexed owner, AssetCategory category, uint256 assetType, uint256 weight, address vaultOperator)
```

#### TradeCreated
```solidity
event TradeCreated(uint256 indexed tradeId, address indexed buyer, address indexed seller, uint256 paymentAmount, uint256 assetTokenId, uint256 deadline)
```

#### TradeExecuted
```solidity
event TradeExecuted(uint256 indexed tradeId, address indexed buyer, address indexed seller, uint256 paymentAmount, uint256 assetTokenId)
```

#### KYCStatusUpdated
```solidity
event KYCStatusUpdated(address indexed user, ComplianceStatus oldStatus, ComplianceStatus newStatus, RiskLevel riskLevel)
```

#### PriceFeedUpdated
```solidity
event PriceFeedUpdated(uint256 indexed assetType, uint256 price, uint256 timestamp, string source)
```