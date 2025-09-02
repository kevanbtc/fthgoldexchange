const { ethers } = require("hardhat");

async function main() {
  console.log("🏆 FTH Gold Exchange - Demo Asset Minting");
  console.log("==========================================");

  const [deployer, user1] = await ethers.getSigners();
  console.log(`🔑 Using deployer: ${deployer.address}`);
  console.log(`👤 Demo user: ${user1.address}`);

  // Get deployed contract addresses from latest deployment
  const fs = require('fs');
  const path = require('path');
  
  let contractAddresses;
  try {
    // Read from deployment summary if it exists
    const deploymentFiles = fs.readdirSync('deployments').filter(f => f.endsWith('.json'));
    if (deploymentFiles.length > 0) {
      const latestDeployment = deploymentFiles.sort().reverse()[0];
      const deploymentData = JSON.parse(fs.readFileSync(path.join('deployments', latestDeployment)));
      contractAddresses = deploymentData.contracts;
    }
  } catch (error) {
    console.error("❌ Could not find deployment addresses. Please run deploy.js first.");
    process.exit(1);
  }

  // Get contract instances
  const ComplianceRegistry = await ethers.getContractFactory("ComplianceRegistry");
  const PreciousAssetVault = await ethers.getContractFactory("PreciousAssetVault");
  
  const compliance = ComplianceRegistry.attach(contractAddresses.ComplianceRegistry);
  const vault = PreciousAssetVault.attach(contractAddresses.PreciousAssetVault);

  console.log("\n📋 Setting up KYC for demo user...");
  
  // Set up KYC for user1
  await compliance.updateKYCStatus(
    user1.address,
    1, // APPROVED
    1, // LOW risk
    ethers.keccak256(ethers.toUtf8Bytes("demo_user_kyc_docs"))
  );
  
  console.log("✅ KYC approved for demo user");

  // Authorize deployer as vault operator
  console.log("\n🏦 Setting up vault operator...");
  await vault.setVaultAuthorization(deployer.address, true);
  console.log("✅ Vault operator authorized");

  // Create demo asset specifications
  const demoAssets = [
    {
      name: "1oz LBMA Gold Bar",
      spec: {
        category: 0, // PRECIOUS_METAL
        assetType: 0, // GOLD
        purity: 999, // 24K gold (999/1000)
        weight: 31.1 * 10, // 1 troy ounce in grams * 10 for precision
        dimensions: 0,
        certificateHash: ethers.keccak256(ethers.toUtf8Bytes("LBMA_GOLD_CERT_001")),
        certifyingBody: deployer.address,
        isInsured: true,
        insuranceValue: ethers.parseUnits("2000", 6) // $2000 USD
      },
      cert: {
        certificateNumber: "LBMA-GOLD-001",
        certifyingAuthority: "LBMA Certified Assayer",
        certificationDate: Math.floor(Date.now() / 1000),
        expiryDate: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60), // 1 year
        documentHash: ethers.keccak256(ethers.toUtf8Bytes("lbma_certificate_001")),
        isValid: true
      },
      vault: {
        vaultOperator: deployer.address,
        vaultLocation: "FTH Secure Vault - London",
        storageReceipt: ethers.keccak256(ethers.toUtf8Bytes("vault_receipt_001")),
        storageDate: Math.floor(Date.now() / 1000),
        isActive: true,
        insurancePolicyId: 1001,
        insuranceProvider: deployer.address
      },
      tokenURI: "https://metadata.fth.gold/assets/gold-bar-001.json"
    },
    {
      name: "1ct GIA Diamond",
      spec: {
        category: 1, // PRECIOUS_STONE
        assetType: 10, // DIAMOND
        purity: 0, // Not applicable for diamonds
        weight: 100, // 1 carat = 100 points
        dimensions: 0,
        certificateHash: ethers.keccak256(ethers.toUtf8Bytes("GIA_DIAMOND_CERT_002")),
        certifyingBody: deployer.address,
        isInsured: true,
        insuranceValue: ethers.parseUnits("5000", 6) // $5000 USD
      },
      cert: {
        certificateNumber: "GIA-2345678901",
        certifyingAuthority: "Gemological Institute of America",
        certificationDate: Math.floor(Date.now() / 1000),
        expiryDate: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60),
        documentHash: ethers.keccak256(ethers.toUtf8Bytes("gia_certificate_002")),
        isValid: true
      },
      vault: {
        vaultOperator: deployer.address,
        vaultLocation: "FTH Secure Vault - New York",
        storageReceipt: ethers.keccak256(ethers.toUtf8Bytes("vault_receipt_002")),
        storageDate: Math.floor(Date.now() / 1000),
        isActive: true,
        insurancePolicyId: 1002,
        insuranceProvider: deployer.address
      },
      tokenURI: "https://metadata.fth.gold/assets/diamond-001.json"
    },
    {
      name: "100g Silver Bar",
      spec: {
        category: 0, // PRECIOUS_METAL
        assetType: 1, // SILVER
        purity: 999, // Fine silver (999/1000)
        weight: 1000, // 100 grams * 10 for precision
        dimensions: 0,
        certificateHash: ethers.keccak256(ethers.toUtf8Bytes("SILVER_CERT_003")),
        certifyingBody: deployer.address,
        isInsured: true,
        insuranceValue: ethers.parseUnits("80", 6) // $80 USD
      },
      cert: {
        certificateNumber: "AG-999-003",
        certifyingAuthority: "Precious Metals Assayer",
        certificationDate: Math.floor(Date.now() / 1000),
        expiryDate: Math.floor(Date.now() / 1000) + (365 * 24 * 60 * 60),
        documentHash: ethers.keccak256(ethers.toUtf8Bytes("silver_certificate_003")),
        isValid: true
      },
      vault: {
        vaultOperator: deployer.address,
        vaultLocation: "FTH Secure Vault - Singapore",
        storageReceipt: ethers.keccak256(ethers.toUtf8Bytes("vault_receipt_003")),
        storageDate: Math.floor(Date.now() / 1000),
        isActive: true,
        insurancePolicyId: 1003,
        insuranceProvider: deployer.address
      },
      tokenURI: "https://metadata.fth.gold/assets/silver-bar-001.json"
    }
  ];

  console.log("\n💎 Minting demo precious assets...");

  const mintedAssets = [];

  for (let i = 0; i < demoAssets.length; i++) {
    const asset = demoAssets[i];
    console.log(`\n${i + 1}. Minting: ${asset.name}`);

    try {
      const tx = await vault.mintAssetToken(
        user1.address,
        asset.spec,
        asset.cert,
        asset.vault,
        asset.tokenURI
      );

      const receipt = await tx.wait();
      const tokenId = i + 1; // Assuming sequential token IDs

      console.log(`   ✅ Minted NFT #${tokenId}`);
      console.log(`   📊 Value: $${ethers.formatUnits(asset.spec.insuranceValue, 6)}`);
      console.log(`   📜 Certificate: ${asset.cert.certificateNumber}`);
      console.log(`   🏦 Vault: ${asset.vault.vaultLocation}`);
      console.log(`   🔗 Transaction: ${tx.hash}`);

      mintedAssets.push({
        tokenId,
        name: asset.name,
        value: asset.spec.insuranceValue,
        txHash: tx.hash
      });

    } catch (error) {
      console.error(`   ❌ Failed to mint ${asset.name}:`, error.message);
    }
  }

  console.log("\n🎉 DEMO ASSET MINTING COMPLETED!");
  console.log("====================================");
  console.log(`📊 Total Assets Minted: ${mintedAssets.length}`);
  
  let totalValue = 0n;
  mintedAssets.forEach(asset => {
    totalValue += asset.value;
    console.log(`   • ${asset.name} (NFT #${asset.tokenId}) - $${ethers.formatUnits(asset.value, 6)}`);
  });

  console.log(`💰 Total Portfolio Value: $${ethers.formatUnits(totalValue, 6)}`);
  console.log(`👤 Owner: ${user1.address}`);

  console.log("\n🔧 System Status:");
  console.log(`   • ComplianceRegistry: ${contractAddresses.ComplianceRegistry}`);
  console.log(`   • PreciousAssetVault: ${contractAddresses.PreciousAssetVault}`);
  console.log(`   • Total NFT Supply: ${mintedAssets.length}`);

  console.log("\n🎯 Next Steps:");
  console.log("   1. Run: npx hardhat run scripts/demo-escrow-trade.js");
  console.log("   2. Check assets on block explorer");
  console.log("   3. Create atomic escrow trades");
  console.log("   4. Test fraud prevention mechanisms");

  // Save demo results
  const demoResults = {
    timestamp: new Date().toISOString(),
    network: await ethers.provider.getNetwork().then(n => n.name),
    demoUser: user1.address,
    mintedAssets,
    totalValue: ethers.formatUnits(totalValue, 6),
    contractAddresses
  };

  fs.writeFileSync('demo-results.json', JSON.stringify(demoResults, null, 2));
  console.log("\n💾 Demo results saved to: demo-results.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Demo failed:", error);
    process.exit(1);
  });