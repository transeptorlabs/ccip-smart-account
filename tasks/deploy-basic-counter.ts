import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment, TaskArguments } from "hardhat/types";
import { getPrivateKey, getProviderRpcUrl, getRouterConfig } from "./utils";
import { Wallet, providers } from "ethers";
import { BasicCounter__factory, BasicCounter } from "../typechain-types";
import { Spinner } from "../utils/spinner";
import { LINK_ADDRESSES } from "./constants";

task(`deploy-basic-counter`, `Deploys the BasicCounter smart contract`)
    .addParam(`owner`, `The owner of the BasicCounter contract`)
    .setAction(async (taskArguments: TaskArguments, hre: HardhatRuntimeEnvironment) => {
        const routerAddress = taskArguments.router ? taskArguments.router : getRouterConfig(hre.network.name).address;
        const linkAddress = taskArguments.link ? taskArguments.link : LINK_ADDRESSES[hre.network.name]

        const privateKey = getPrivateKey();
        const rpcProviderUrl = getProviderRpcUrl(hre.network.name);

        const provider = new providers.JsonRpcProvider(rpcProviderUrl);
        const wallet = new Wallet(privateKey);
        const deployer = wallet.connect(provider);

        const spinner: Spinner = new Spinner();

        console.log(`ℹ️  Attempting to deploy BasicCounter on the ${hre.network.name} blockchain using ${deployer.address} address, with the Router address ${routerAddress} and LINK address ${linkAddress} provided as constructor arguments`);
        spinner.start();

        const basicCounterFactory: BasicCounter__factory = await hre.ethers.getContractFactory('BasicCounter');
        const basicCounter: BasicCounter = await basicCounterFactory.deploy();
        await basicCounter.deployed();

        spinner.stop();
        console.log(`✅ Basic Counter deployed at address ${basicCounter.address} on the ${hre.network.name} blockchain`)

        console.log(`ℹ️  Attempting to grant the increment role to the ${taskArguments.owner} address`);
        spinner.start();

        const tx = await basicCounter.transferOwnership(taskArguments.owner);
        await tx.wait();

        spinner.stop();
        console.log(`✅ (owner)${taskArguments.owner} can now increment BasicCounter. Transaction hash: ${tx.hash}`);
    });