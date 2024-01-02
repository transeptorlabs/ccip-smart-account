import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment, TaskArguments } from "hardhat/types";
import { getProviderRpcUrl } from "./utils";
import { providers } from "ethers";
import { TranseptorAccount__factory, TranseptorAccount } from "../typechain-types";
import { Spinner } from "../utils/spinner";

task(`get-message`, `Gets TranseptorAccount latest received message details`)
    .addParam(`receiverAddress`, `The TranseptorAccount address`)
    .addParam(`blockchain`, `The name of the blockchain (for example ethereumSepolia)`)
    .setAction(async (taskArguments: TaskArguments, hre: HardhatRuntimeEnvironment) => {
        if (hre.network.name !== 'ethereumSepolia') {
            throw new Error("This task can only be executed on the ethereumSepolia network");
        }
        
        const { receiverAddress, blockchain } = taskArguments;

        const rpcProviderUrl = getProviderRpcUrl(blockchain);
        const provider = new providers.JsonRpcProvider(rpcProviderUrl);

        const transeptorAccountReceiver: TranseptorAccount = TranseptorAccount__factory.connect(receiverAddress, provider);

        const spinner: Spinner = new Spinner();

        console.log(`ℹ️  Attempting to get the latest received message details from the BasicMessageReceiver smart contract (${receiverAddress}) on the ${blockchain} blockchain`);
        spinner.start();

        const latestMessageDetails = await transeptorAccountReceiver.getLastReceivedMessageDetails();

        spinner.stop();
        console.log(`ℹ️ Latest Message Details:`);
        console.log(`- Message Id: ${latestMessageDetails[0]}`);
        console.log(`- Source Chain Selector: ${latestMessageDetails[1]}`);
        console.log(`- Sender: ${latestMessageDetails[2]}`);
        console.log(`- Encoded Data: ${latestMessageDetails[3]}`);
        console.log(`- Token: ${latestMessageDetails[4]}`);
        console.log(`- Amount: ${latestMessageDetails[5]}`);
    });