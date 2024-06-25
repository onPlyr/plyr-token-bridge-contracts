// scripts/deploy.js

const PROXY_ADMIN = '0x89b62163bF568F97E800cc6C25A07747c7297aa5';
const PROXY_ADDRESS = '0x43B1EF2D8B0Ea6E9929e969B3eBfE3207B657b94';


async function main() {
  const [deployer] = await ethers.getSigners();

  const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin");
  const proxyAdmin = await ProxyAdmin.attach(PROXY_ADMIN);

  console.log("ProxyAdmin address:", proxyAdmin.target);

  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy logic contract
  const PlyrBridge = await ethers.getContractFactory("PlyrBridge");

  const plyrBridge = await PlyrBridge.deploy();
  await plyrBridge.waitForDeployment();
  console.log("PlyrBridge deployed to:", plyrBridge.target);


  await proxyAdmin.upgradeAndCall(PROXY_ADDRESS, plyrBridge.target, '0x');

  console.log("Contract upgrade successfully!");
}

// 处理可能的错误
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
