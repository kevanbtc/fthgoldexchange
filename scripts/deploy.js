const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Deploying FTH Gold Exchange - Ultimate Web3 Precious Assets System");
  console.log("=" .repeat(80));

  const [deployer] = await ethers.getSigners();
  console.log(`📝 Deploying contracts with account: ${deployer.address}`);
  console.log(`💰 Account balance: ${ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH`);

  const network = await ethers.provider.getNetwork();
  console.log(`🌐 Network: ${network.name} (${network.chainId})`);
  console.log();

  // Deploy contracts in dependency order
  const contracts = {};

  try {
    // 1. Deploy ComplianceRegistry first (no dependencies)
    console.log("1️⃣  Deploying ComplianceRegistry...");
    const ComplianceRegistry = await ethers.getContractFactory("ComplianceRegistry");
    contracts.complianceRegistry = await ComplianceRegistry.deploy();
    await contracts.complianceRegistry.waitForDeployment();
    console.log(`   ✅ ComplianceRegistry deployed to: ${await contracts.complianceRegistry.getAddress()}`);

    // 2. Deploy OracleManager (no dependencies)
    console.log("2️⃣  Deploying OracleManager...");
    const OracleManager = await ethers.getContractFactory("OracleManager");
    contracts.oracleManager = await OracleManager.deploy();
    await contracts.oracleManager.waitForDeployment();
    console.log(`   ✅ OracleManager deployed to: ${await contracts.oracleManager.getAddress()}`);

    // 3. Deploy PreciousAssetVault (depends on ComplianceRegistry)
    console.log("3️⃣  Deploying PreciousAssetVault...");
    const PreciousAssetVault = await ethers.getContractFactory("PreciousAssetVault");
    contracts.assetVault = await PreciousAssetVault.deploy(
      await contracts.complianceRegistry.getAddress()
    );
    await contracts.assetVault.waitForDeployment();
    console.log(`   ✅ PreciousAssetVault deployed to: ${await contracts.assetVault.getAddress()}`);

    // 4. Deploy AtomicEscrow (depends on all previous contracts)
    console.log("4️⃣  Deploying AtomicEscrow...");
    const AtomicEscrow = await ethers.getContractFactory("AtomicEscrow");
    contracts.atomicEscrow = await AtomicEscrow.deploy(
      await contracts.assetVault.getAddress(),
      await contracts.complianceRegistry.getAddress(),
      await contracts.oracleManager.getAddress(),
      deployer.address // Fee recipient (can be changed later)
    );
    await contracts.atomicEscrow.waitForDeployment();
    console.log(`   ✅ AtomicEscrow deployed to: ${await contracts.atomicEscrow.getAddress()}`);

    console.log();
    console.log("🔧 Setting up initial configurations...");

    // Set up initial roles and permissions
    console.log("   🔑 Setting up roles and permissions...");
    
    // Grant roles to AtomicEscrow contract
    await contracts.assetVault.grantRole(
      await contracts.assetVault.VAULT_OPERATOR_ROLE(),
      await contracts.atomicEscrow.getAddress()
    );

    // Authorize the deployer as a KYC provider for testing
    await contracts.complianceRegistry.authorizeKYCProvider(deployer.address, true);

    // Set up some basic oracle configurations (placeholder prices)
    console.log("   📊 Setting up basic oracle prices...");
    
    // Gold (asset type 0) - $2000/oz = $64,310 per kg
    await contracts.oracleManager.updateCustomPrice(0, 6431000000000, 9000); // $64,310 with 8 decimals, 90% confidence
    
    // Silver (asset type 1) - $25/oz = $803 per kg  
    await contracts.oracleManager.updateCustomPrice(1, 80300000000, 9000); // $803 with 8 decimals, 90% confidence
    
    // Platinum (asset type 2) - $1000/oz = $32,150 per kg
    await contracts.oracleManager.updateCustomPrice(2, 3215000000000, 9000); // $32,150 with 8 decimals, 90% confidence

    // Diamond (asset type 10) - $5000/carat
    await contracts.oracleManager.updateCustomPrice(10, 500000000000, 8500); // $5000 with 8 decimals, 85% confidence

    console.log();
    console.log("📋 DEPLOYMENT SUMMARY");
    console.log("=" .repeat(80));
    console.log(`🏦 ComplianceRegistry:    ${await contracts.complianceRegistry.getAddress()}`);
    console.log(`📊 OracleManager:         ${await contracts.oracleManager.getAddress()}`);
    console.log(`🏛️  PreciousAssetVault:    ${await contracts.assetVault.getAddress()}`);
    console.log(`⚖️  AtomicEscrow:          ${await contracts.atomicEscrow.getAddress()}`);
    console.log();
    console.log(`👤 Admin/Deployer:        ${deployer.address}`);
    console.log(`💰 Fee Recipient:         ${deployer.address}`);
    console.log();

    // Save deployment info to JSON file
    const deploymentInfo = {
      network: {
        name: network.name,
        chainId: Number(network.chainId),
        deployed: new Date().toISOString()
      },
      contracts: {
        ComplianceRegistry: await contracts.complianceRegistry.getAddress(),
        OracleManager: await contracts.oracleManager.getAddress(),
        PreciousAssetVault: await contracts.assetVault.getAddress(),
        AtomicEscrow: await contracts.atomicEscrow.getAddress()
      },
      deployer: deployer.address,
      feeRecipient: deployer.address,
      initialPrices: {
        gold: "64310.00000000", // $64,310 per kg
        silver: "803.00000000",  // $803 per kg  
        platinum: "32150.00000000", // $32,150 per kg
        diamond: "5000.00000000" // $5000 per carat
      }
    };

    const fs = require('fs');
    const path = require('path');
    
    // Ensure deployments directory exists
    const deploymentsDir = path.join(process.cwd(), 'deployments');
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir);
    }

    // Save deployment info
    const filename = `deployment-${network.name}-${Date.now()}.json`;
    fs.writeFileSync(
      path.join(deploymentsDir, filename),
      JSON.stringify(deploymentInfo, null, 2)
    );

    console.log(`💾 Deployment info saved to: deployments/${filename}`);
    console.log();

    // Display next steps
    console.log("🎯 NEXT STEPS");
    console.log("=" .repeat(80));
    console.log("1. Verify contracts on block explorer (if on mainnet/testnet):");
    console.log(`   npx hardhat verify --network ${network.name} ${await contracts.complianceRegistry.getAddress()}`);
    console.log(`   npx hardhat verify --network ${network.name} ${await contracts.oracleManager.getAddress()}`);
    console.log(`   npx hardhat verify --network ${network.name} ${await contracts.assetVault.getAddress()} ${await contracts.complianceRegistry.getAddress()}`);
    console.log(`   npx hardhat verify --network ${network.name} ${await contracts.atomicEscrow.getAddress()} ${await contracts.assetVault.getAddress()} ${await contracts.complianceRegistry.getAddress()} ${await contracts.oracleManager.getAddress()} ${deployer.address}`);
    console.log();
    console.log("2. Set up additional KYC providers and vault operators");
    console.log("3. Configure Chainlink price feeds for production");
    console.log("4. Set up proper fee recipient address");
    console.log("5. Configure jurisdiction-specific compliance rules");
    console.log();
    console.log("🎉 FTH Gold Exchange deployment completed successfully!");

  } catch (error) {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });