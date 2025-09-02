// Helper script to get deployer address for contract verification
async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(deployer.address);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});