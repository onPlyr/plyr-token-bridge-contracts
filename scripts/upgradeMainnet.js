// scripts/deploy.js


async function main() {
  const [deployer] = await ethers.getSigners();


  // Deploy logic contract
  const PlyrBridge = await ethers.getContractFactory("PlyrBridge");

  const plyrBridge = await PlyrBridge.deploy();
  await plyrBridge.waitForDeployment();
  console.log("PlyrBridge deployed to:", plyrBridge.target);

  console.log("Mannualy upgrade the contract!");
}

// 处理可能的错误
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
