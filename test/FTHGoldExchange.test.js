const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("FTH Gold Exchange System", function () {
  let deployer, user1, user2, vault1, feeRecipient;
  let complianceRegistry, oracleManager, assetVault, atomicEscrow;
  let mockUSDC;

  const GOLD_TYPE = 0;
  const SILVER_TYPE = 1;
  const DIAMOND_TYPE = 10;

  beforeEach(async function () {
    [deployer, user1, user2, vault1, feeRecipient] = await ethers.getSigners();

    // Deploy mock USDC for testing
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockUSDC = await MockERC20.deploy("Mock USDC", "USDC", 6); // 6 decimals like real USDC
    await mockUSDC.waitForDeployment();

    // Deploy ComplianceRegistry
    const ComplianceRegistry = await ethers.getContractFactory("ComplianceRegistry");
    complianceRegistry = await ComplianceRegistry.deploy();
    await complianceRegistry.waitForDeployment();

    // Deploy OracleManager
    const OracleManager = await ethers.getContractFactory("OracleManager");
    oracleManager = await OracleManager.deploy();
    await oracleManager.waitForDeployment();

    // Deploy PreciousAssetVault
    const PreciousAssetVault = await ethers.getContractFactory("PreciousAssetVault");
    assetVault = await PreciousAssetVault.deploy(await complianceRegistry.getAddress());
    await assetVault.waitForDeployment();

    // Deploy AtomicEscrow
    const AtomicEscrow = await ethers.getContractFactory("AtomicEscrow");
    atomicEscrow = await AtomicEscrow.deploy(
      await assetVault.getAddress(),
      await complianceRegistry.getAddress(),
      await oracleManager.getAddress(),
      feeRecipient.address
    );
    await atomicEscrow.waitForDeployment();

    // Setup initial configurations
    await setupInitialConfig();
  });

  async function setupInitialConfig() {
    // Authorize vault1 as a vault operator
    await assetVault.setVaultAuthorization(vault1.address, true);
    
    // Authorize deployer as KYC provider
    await complianceRegistry.authorizeKYCProvider(deployer.address, true);
    
    // Set up KYC for test users
    await complianceRegistry.updateKYCStatus(
      user1.address,
      1, // APPROVED
      1, // LOW risk
      ethers.keccak256(ethers.toUtf8Bytes("user1_kyc_docs"))
    );

    await complianceRegistry.updateKYCStatus(
      user2.address,
      1, // APPROVED  
      1, // LOW risk
      ethers.keccak256(ethers.toUtf8Bytes("user2_kyc_docs"))
    );

    // Set up oracle prices
    await oracleManager.updateCustomPrice(GOLD_TYPE, ethers.parseUnits("64310", 8), 9000); // $64,310/kg
    await oracleManager.updateCustomPrice(SILVER_TYPE, ethers.parseUnits("803", 8), 9000);   // $803/kg
    await oracleManager.updateCustomPrice(DIAMOND_TYPE, ethers.parseUnits("5000", 8), 8500); // $5000/carat

    // Mint mock USDC to users
    await mockUSDC.mint(user1.address, ethers.parseUnits("100000", 6)); // 100k USDC
    await mockUSDC.mint(user2.address, ethers.parseUnits("100000", 6)); // 100k USDC
  }

  describe("Compliance Registry", function () {
    it("Should verify KYC for approved users", async function () {
      expect(await complianceRegistry.verifyKYC(user1.address)).to.be.true;
      expect(await complianceRegistry.verifyKYC(user2.address)).to.be.true;
    });

    it("Should return correct risk levels", async function () {
      expect(await complianceRegistry.getRiskLevel(user1.address)).to.equal(1); // LOW
      expect(await complianceRegistry.getRiskLevel(user2.address)).to.equal(1); // LOW
    });

    it("Should perform AML checks", async function () {
      const amount = ethers.parseUnits("10000", 6); // $10k
      const sourceHash = ethers.keccak256(ethers.toUtf8Bytes("legitimate_source"));
      
      const result = await complianceRegistry.performAMLCheck(user1.address, amount, sourceHash);
      expect(result).to.be.true; // Should pass for low risk user and amount
    });
  });

  describe("Oracle Manager", function () {
    it("Should return correct asset prices", async function () {
      const goldPrice = await oracleManager.getLatestPrice(GOLD_TYPE);
      expect(goldPrice.price).to.equal(ethers.parseUnits("64310", 8));
      expect(goldPrice.source).to.equal("custom");
      expect(goldPrice.isStale).to.be.false;
    });

    it("Should calculate asset values correctly", async function () {
      // 1kg gold at $64,310/kg with 750/1000 purity (18K)
      const value = await oracleManager.calculateAssetValue(GOLD_TYPE, 1000, 750); // 1000g, 750 purity
      const expectedValue = (1000n * 6431000000000n / 100000000n * 750n) / 1000n; // Apply purity
      expect(value).to.equal(expectedValue);
    });
  });

  describe("Precious Asset Vault", function () {
    it("Should mint asset tokens with proper specifications", async function () {
      const assetSpec = {
        category: 0, // PRECIOUS_METAL
        assetType: GOLD_TYPE,
        purity: 750, // 18K gold (750/1000)
        weight: 1000, // 1000 grams
        dimensions: 0,
        certificateHash: ethers.keccak256(ethers.toUtf8Bytes("gold_certificate")),
        certifyingBody: deployer.address,
        isInsured: true,
        insuranceValue: ethers.parseUnits("48232", 6) // $48,232 (75% of $64,310)
      };

      const certData = {
        certificateNumber: "CERT-001",
        certifyingAuthority: "FTH Assay Office",
        certificationDate: Math.floor(Date.now() / 1000),
        expiryDate: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60), // 1 year
        documentHash: ethers.keccak256(ethers.toUtf8Bytes("cert_document")),
        isValid: true
      };

      const vaultInfo = {
        vaultOperator: vault1.address,
        vaultLocation: "Secure Vault #1",
        storageReceipt: ethers.keccak256(ethers.toUtf8Bytes("storage_receipt")),
        storageDate: Math.floor(Date.now() / 1000),
        isActive: true,
        insurancePolicyId: 12345,
        insuranceProvider: deployer.address
      };

      await expect(
        assetVault.connect(vault1).mintAssetToken(
          user1.address,
          assetSpec,
          certData,
          vaultInfo,
          "https://metadata.fth.com/gold/1"
        )
      ).to.emit(assetVault, "AssetTokenized");

      const tokenId = 1;
      expect(await assetVault.ownerOf(tokenId)).to.equal(user1.address);
      
      const storedSpec = await assetVault.getAssetSpecification(tokenId);
      expect(storedSpec.assetType).to.equal(GOLD_TYPE);
      expect(storedSpec.weight).to.equal(1000);
    });

    it("Should reject minting without valid KYC", async function () {
      const [, , , nonKYCUser] = await ethers.getSigners();
      
      const assetSpec = {
        category: 0,
        assetType: GOLD_TYPE,
        purity: 999,
        weight: 1000,
        dimensions: 0,
        certificateHash: ethers.keccak256(ethers.toUtf8Bytes("gold_certificate")),
        certifyingBody: deployer.address,
        isInsured: true,
        insuranceValue: ethers.parseUnits("64310", 6)
      };

      const certData = {
        certificateNumber: "CERT-002",
        certifyingAuthority: "FTH Assay Office",
        certificationDate: Math.floor(Date.now() / 1000),
        expiryDate: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60),
        documentHash: ethers.keccak256(ethers.toUtf8Bytes("cert_document")),
        isValid: true
      };

      const vaultInfo = {
        vaultOperator: vault1.address,
        vaultLocation: "Secure Vault #1",
        storageReceipt: ethers.keccak256(ethers.toUtf8Bytes("storage_receipt")),
        storageDate: Math.floor(Date.now() / 1000),
        isActive: true,
        insurancePolicyId: 12345,
        insuranceProvider: deployer.address
      };

      await expect(
        assetVault.connect(vault1).mintAssetToken(
          nonKYCUser.address,
          assetSpec,
          certData,
          vaultInfo,
          "https://metadata.fth.com/gold/2"
        )
      ).to.be.revertedWith("KYC verification required");
    });
  });

  describe("Atomic Escrow", function () {
    let goldTokenId;

    beforeEach(async function () {
      // Mint a gold asset for testing
      const assetSpec = {
        category: 0,
        assetType: GOLD_TYPE,
        purity: 999,
        weight: 100, // 100 grams
        dimensions: 0,
        certificateHash: ethers.keccak256(ethers.toUtf8Bytes("gold_certificate")),
        certifyingBody: deployer.address,
        isInsured: true,
        insuranceValue: ethers.parseUnits("6431", 6) // $6,431 for 100g
      };

      const certData = {
        certificateNumber: "CERT-ESCROW",
        certifyingAuthority: "FTH Assay Office", 
        certificationDate: Math.floor(Date.now() / 1000),
        expiryDate: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60),
        documentHash: ethers.keccak256(ethers.toUtf8Bytes("cert_document")),
        isValid: true
      };

      const vaultInfo = {
        vaultOperator: vault1.address,
        vaultLocation: "Secure Vault #1", 
        storageReceipt: ethers.keccak256(ethers.toUtf8Bytes("storage_receipt")),
        storageDate: Math.floor(Date.now() / 1000),
        isActive: true,
        insurancePolicyId: 12345,
        insuranceProvider: deployer.address
      };

      await assetVault.connect(vault1).mintAssetToken(
        user2.address, // user2 will be the seller
        assetSpec,
        certData,
        vaultInfo,
        "https://metadata.fth.com/gold/escrow"
      );

      goldTokenId = 1;
    });

    it("Should create atomic trades successfully", async function () {
      const paymentAmount = ethers.parseUnits("6500", 6); // $6,500 USDC
      const deadline = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60); // 7 days

      await expect(
        atomicEscrow.connect(user1).createTrade(
          user2.address, // seller
          await mockUSDC.getAddress(), // payment token
          paymentAmount,
          await assetVault.getAddress(), // asset contract
          goldTokenId,
          deadline
        )
      ).to.emit(atomicEscrow, "TradeCreated");

      const trade = await atomicEscrow.getTrade(1);
      expect(trade.buyer).to.equal(user1.address);
      expect(trade.seller).to.equal(user2.address);
      expect(trade.paymentAmount).to.equal(paymentAmount);
      expect(trade.assetTokenId).to.equal(goldTokenId);
    });

    it("Should execute complete atomic trade flow", async function () {
      const paymentAmount = ethers.parseUnits("6500", 6); // $6,500 USDC
      const deadline = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60);

      // 1. Create trade
      await atomicEscrow.connect(user1).createTrade(
        user2.address,
        await mockUSDC.getAddress(),
        paymentAmount,
        await assetVault.getAddress(),
        goldTokenId,
        deadline
      );

      const tradeId = 1;

      // 2. Approve and deposit payment (buyer)
      await mockUSDC.connect(user1).approve(await atomicEscrow.getAddress(), paymentAmount);
      await atomicEscrow.connect(user1).depositPayment(tradeId);

      // 3. Approve and deposit asset (seller)
      await assetVault.connect(user2).approve(await atomicEscrow.getAddress(), goldTokenId);
      await atomicEscrow.connect(user2).depositAsset(tradeId);

      // Check trade executed automatically
      const trade = await atomicEscrow.getTrade(tradeId);
      expect(trade.status).to.equal(4); // EXECUTED

      // Verify ownership transfer
      expect(await assetVault.ownerOf(goldTokenId)).to.equal(user1.address);

      // Verify payment transfer (minus fees)
      const expectedPayment = paymentAmount - (paymentAmount * 25n) / 10000n; // Minus 0.25% seller fee
      const user2Balance = await mockUSDC.balanceOf(user2.address);
      expect(user2Balance).to.be.at.least(ethers.parseUnits("99000", 6) + expectedPayment);
    });

    it("Should handle cancellations properly", async function () {
      const paymentAmount = ethers.parseUnits("6500", 6);
      const deadline = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60);

      // Create trade
      await atomicEscrow.connect(user1).createTrade(
        user2.address,
        await mockUSDC.getAddress(),
        paymentAmount,
        await assetVault.getAddress(), 
        goldTokenId,
        deadline
      );

      const tradeId = 1;

      // Deposit payment only
      await mockUSDC.connect(user1).approve(await atomicEscrow.getAddress(), paymentAmount);
      await atomicEscrow.connect(user1).depositPayment(tradeId);

      const initialBalance = await mockUSDC.balanceOf(user1.address);

      // Cancel trade
      await expect(
        atomicEscrow.connect(user1).cancelTrade(tradeId, "Changed mind")
      ).to.emit(atomicEscrow, "TradeCancelled");

      // Verify refund
      const finalBalance = await mockUSDC.balanceOf(user1.address);
      expect(finalBalance).to.equal(initialBalance + paymentAmount);

      // Verify trade status
      const trade = await atomicEscrow.getTrade(tradeId);
      expect(trade.status).to.equal(5); // CANCELLED
    });

    it("Should prevent trades without KYC", async function () {
      const [, , , nonKYCUser] = await ethers.getSigners();
      const paymentAmount = ethers.parseUnits("6500", 6);
      const deadline = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60);

      await expect(
        atomicEscrow.connect(nonKYCUser).createTrade(
          user2.address,
          await mockUSDC.getAddress(),
          paymentAmount,
          await assetVault.getAddress(),
          goldTokenId,
          deadline
        )
      ).to.be.revertedWith("Buyer KYC required");
    });
  });

  describe("Integration Tests", function () {
    it("Should handle end-to-end precious metal trading", async function () {
      // This test simulates a complete flow from asset tokenization to atomic trade
      
      // 1. Vault operator tokenizes 1oz gold bar
      const assetSpec = {
        category: 0, // PRECIOUS_METAL
        assetType: GOLD_TYPE,
        purity: 999, // 24K gold
        weight: 31.1, // 1 troy ounce in grams
        dimensions: 0,
        certificateHash: ethers.keccak256(ethers.toUtf8Bytes("LBMA_certificate")),
        certifyingBody: deployer.address,
        isInsured: true,
        insuranceValue: ethers.parseUnits("2000", 6) // $2000 for 1oz
      };

      const certData = {
        certificateNumber: "LBMA-001",
        certifyingAuthority: "LBMA Certified",
        certificationDate: Math.floor(Date.now() / 1000),
        expiryDate: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60),
        documentHash: ethers.keccak256(ethers.toUtf8Bytes("lbma_cert")),
        isValid: true
      };

      const vaultInfo = {
        vaultOperator: vault1.address,
        vaultLocation: "London Vault",
        storageReceipt: ethers.keccak256(ethers.toUtf8Bytes("london_receipt")),
        storageDate: Math.floor(Date.now() / 1000),
        isActive: true,
        insurancePolicyId: 54321,
        insuranceProvider: deployer.address
      };

      // Mint gold NFT
      await assetVault.connect(vault1).mintAssetToken(
        user2.address,
        assetSpec,
        certData,
        vaultInfo,
        "https://metadata.fth.com/gold/lbma-001"
      );

      const goldTokenId = 1;

      // 2. Create atomic trade
      const paymentAmount = ethers.parseUnits("2100", 6); // $2100 USDC
      const deadline = Math.floor(Date.now() / 1000) + (24 * 60 * 60); // 24 hours

      await atomicEscrow.connect(user1).createTrade(
        user2.address,
        await mockUSDC.getAddress(),
        paymentAmount,
        await assetVault.getAddress(),
        goldTokenId,
        deadline
      );

      // 3. Both parties deposit
      await mockUSDC.connect(user1).approve(await atomicEscrow.getAddress(), paymentAmount);
      await atomicEscrow.connect(user1).depositPayment(1);

      await assetVault.connect(user2).approve(await atomicEscrow.getAddress(), goldTokenId);
      await atomicEscrow.connect(user2).depositAsset(1);

      // 4. Verify successful execution
      const trade = await atomicEscrow.getTrade(1);
      expect(trade.status).to.equal(4); // EXECUTED

      // 5. Verify asset ownership changed
      expect(await assetVault.ownerOf(goldTokenId)).to.equal(user1.address);

      // 6. Verify asset details are preserved
      const retrievedSpec = await assetVault.getAssetSpecification(goldTokenId);
      expect(retrievedSpec.weight).to.equal(31.1 * 10); // Convert to tenths for integer storage
      expect(retrievedSpec.purity).to.equal(999);
      expect(retrievedSpec.assetType).to.equal(GOLD_TYPE);
    });
  });
});

// Mock ERC20 contract for testing
const MockERC20_CONTRACT = `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
`;