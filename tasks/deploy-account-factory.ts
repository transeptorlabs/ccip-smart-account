import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment, TaskArguments } from "hardhat/types";
import { getPrivateKey, getProviderRpcUrl, getRouterConfig, getEntryPointAddess } from "./utils";
import { Wallet, providers } from "ethers";
import { TranseptorAccountFactory__factory, TranseptorAccountFactory } from "../typechain-types";
import { Spinner } from "../utils/spinner";

task(`deploy-account-factory`, `Deploys the TranseptorAccountFactory smart contract`)
    .addOptionalParam(`router`, `The address of the Router contract`)
    .addOptionalParam(`entrypoint`, `The address of the erc4337 entrypoint contract`)
    .setAction(async (taskArguments: TaskArguments, hre: HardhatRuntimeEnvironment) => {
        const routerAddress = taskArguments.router ? taskArguments.router : getRouterConfig(hre.network.name).address;
        const entrypointAddress = taskArguments.entrypoint ? taskArguments.entrypoint : getEntryPointAddess(hre.network.name);

        const privateKey = getPrivateKey();
        const rpcProviderUrl = getProviderRpcUrl(hre.network.name);

        const provider = new providers.JsonRpcProvider(rpcProviderUrl);
        const wallet = new Wallet(privateKey);
        const deployer = wallet.connect(provider);

        const spinner: Spinner = new Spinner();

        console.log(`ℹ️  Attempting to deploy TranseptorAccountFactory on the ${hre.network.name} blockchain using ${deployer.address} address, with the Router address ${routerAddress} provided as constructor argument`);
        spinner.start();

        const transeptorAccountFactoryFactory: TranseptorAccountFactory__factory = await hre.ethers.getContractFactory('TranseptorAccountFactory') as TranseptorAccountFactory__factory;
        const transeptorAccountFactory: TranseptorAccountFactory = await transeptorAccountFactoryFactory.deploy(entrypointAddress, routerAddress);
        await transeptorAccountFactory.deployed();

        spinner.stop();
        console.log(`✅ Transeptor Account Factory deployed at address ${transeptorAccountFactory.address} on ${hre.network.name} blockchain`)
    });