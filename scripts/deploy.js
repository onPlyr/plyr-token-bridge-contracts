// scripts/deploy.js

const OWNER_ADDRESS = '0xb0425C2D2C31A0cf492D92aFB64577671D50E3b5';

// sepolia
// const GATEWAY_ADDRESS = '0x6c6bab7105d72c7b30bda46cb390e67a0acd8c05';

// fuji
// const GATEWAY_ADDRESS = '0x8Ee72C8194ec8A527B1D4981742727437091C913';

// bsc testnet
// const GATEWAY_ADDRESS = '0x7198eb89cc364cdd8c81ef6c39c597712c070ac6';

// plyr testnet
const GATEWAY_ADDRESS = '0xc12cf8cc8eff1f39c9e60da81d11745c25c59501';



async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const LogicContractName = 'PlyrBridge';
  const initializeParams = [
    OWNER_ADDRESS,
    GATEWAY_ADDRESS,
  ]

  // Deploy logic contract
  const Logic = await ethers.getContractFactory(LogicContractName);

  const logic = await Logic.deploy();
  await logic.waitForDeployment();
  console.log(LogicContractName, "Logic address:", logic.target);

  // Deploy proxy contract
  const Proxy = await ethers.getContractFactory("TransparentUpgradeableProxy");
  const proxy = await Proxy.deploy(
    logic.target,
    OWNER_ADDRESS,
    logic.interface.encodeFunctionData("initialize", initializeParams)
  );
  await proxy.waitForDeployment();

  // Get proxyAdmin address from the deployment transaction
  const receipt = await proxy.deploymentTransaction().wait();
  const logs = receipt.logs;
  const proxyAdminLog = logs.find((log) => proxy.interface.parseLog(log)?.name === 'AdminChanged');
  const proxyAdminAddress = proxyAdminLog.args[1];
  console.log("ProxyAdmin address:", proxyAdminAddress);

  const executor = Logic.attach(proxy.target);
  console.log(LogicContractName, "address:", executor.target);

  console.log("Contract deployed successfully!");
}

// 处理可能的错误
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
