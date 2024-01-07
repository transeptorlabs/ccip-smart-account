import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment, TaskArguments } from "hardhat/types";
import { getPrivateKey, getProviderRpcUrl, getRouterConfig, getTranseptorAccontFactoyAddess } from "./utils";
import { Wallet, providers } from "ethers";
import { DestinationAccountFactoryReceiver, DestinationAccountFactoryReceiver__factory } from "../typechain-types";
import { Spinner } from "../utils/spinner";

task(`deploy-destination-account-factory-receiver`, `Deploys the DestinationAccountFactoryReceiver smart contract`)
    .addOptionalParam(`router`, `The address of the Router contract`)
    .addOptionalParam(`smartAccoutFactory`, `The address of the TranseptorAccountFactory contract`)
    .setAction(async (taskArguments: TaskArguments, hre: HardhatRuntimeEnvironment) => {
        if (hre.network.name === 'ethereumSepolia') {
            throw new Error("This task cannot be executed on the ethereumSepolia network");
        }

        const routerAddress = taskArguments.router ? taskArguments.router : getRouterConfig(hre.network.name).address;
        const accountFactoryAddress = taskArguments.smartAccoutFactory ? taskArguments.smartAccoutFactory : getTranseptorAccontFactoyAddess(hre.network.name);

        const privateKey = getPrivateKey();
        const rpcProviderUrl = getProviderRpcUrl(hre.network.name);

        const provider = new providers.JsonRpcProvider(rpcProviderUrl);
        const wallet = new Wallet(privateKey);
        const deployer = wallet.connect(provider);

        const spinner: Spinner = new Spinner();

        console.log(`ℹ️  Attempting to deploy DestinationAccountFactoryReceiver on the ${hre.network.name} blockchain using ${deployer.address} address, with the Router address ${routerAddress} and the TranseptorAccountFactory address ${accountFactoryAddress}.`);
        spinner.start();

        const transeptorAccountFactoryFactory: DestinationAccountFactoryReceiver__factory = await hre.ethers.getContractFactory('DestinationAccountFactoryReceiver') as DestinationAccountFactoryReceiver__factory;
        const transeptorAccountFactory: DestinationAccountFactoryReceiver = await transeptorAccountFactoryFactory.deploy(routerAddress,accountFactoryAddress);
        await transeptorAccountFactory.deployed();

        spinner.stop();
        console.log(`✅ Transeptor Account Factory deployed at address ${transeptorAccountFactory.address} on ${hre.network.name} blockchain`)
    });