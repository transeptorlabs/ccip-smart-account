import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment, TaskArguments } from "hardhat/types";
import { getPrivateKey, getProviderRpcUrl, getRouterConfig, getLinkTokenAddress, getPayFeesIn } from "./utils";
import { Wallet, providers, utils, constants  } from "ethers";
import { IRouterClient, IRouterClient__factory, IERC20, IERC20__factory, BasicCounter__factory, BasicCounter } from "../typechain-types";
import { Spinner } from "../utils/spinner";
import { getCcipMessageId } from "./helpers";
import { PayFeesIn } from "./constants";

task(`ccip-smart-account-execute`, `Sends a ccip message to execute a function on a Transeptor smart account on the destination chain`)
    .addParam(`destinationBlockchain`, `The name of the destination blockchain (for example polygonMumbai)`)
    .addParam(`receiver`, `The address of the receiver TranseptorAccount.sol on the destination blockchain`)
    .addParam(`dest`, `Destination contact address on destination chain that will be called`)
    .addOptionalParam(`router`, `The address of the Router contract`)
    .addParam(`payFeesIn`, `Choose between 'Native' and 'LINK'`)
    .setAction(async (taskArguments: TaskArguments, hre: HardhatRuntimeEnvironment) => {
        const {destinationBlockchain, receiver, dest, payFeesIn } = taskArguments;
        const sourceBlockchain = 'ethereumSepolia';
        const linkAddress = getLinkTokenAddress(hre.network.name);
        const spinner: Spinner = new Spinner();

        if (hre.network.name !== 'ethereumSepolia') {
            throw new Error("This task can only be executed on the ethereumSepolia network");
        }

        if (destinationBlockchain === 'ethereumSepolia') {
            throw new Error("Destination blockchain cannot be the same as source blockchain");
        }

        // get signer eao(should be owner of the TranseptorAccount on the destination chain)
        const privateKey = getPrivateKey();
        const sourceRpcProviderUrl = getProviderRpcUrl(sourceBlockchain);

        const provider = new providers.JsonRpcProvider(sourceRpcProviderUrl);
        const wallet = new Wallet(privateKey);
        const signer = wallet.connect(provider);

        // get router address
        const routerAddress = taskArguments.router ? taskArguments.router : getRouterConfig(sourceBlockchain).address;
        const targetChainSelector = getRouterConfig(destinationBlockchain).chainSelector;
        const router: IRouterClient = IRouterClient__factory.connect(routerAddress, signer);

        // create CCIP message
        const feeIn: PayFeesIn = getPayFeesIn(payFeesIn);
        const gasLimitValue = taskArguments.gasLimit ? taskArguments.gasLimit : 200_000;

        const functionSelector = utils.id("CCIP EVMExtraArgsV1").slice(0, 10);
        const extraArgs = utils.defaultAbiCoder.encode(["uint256", "bool"], [gasLimitValue, false]); // for transfers to EOA gas limit is 0
        const encodedExtraArgs = `${functionSelector}${extraArgs.slice(2)}`;

        const basicCounter: BasicCounter = BasicCounter__factory.connect(dest, signer);
        const counterOwner = await basicCounter.owner();
        if (counterOwner.toLowerCase() !== receiver.toLowerCase()) {
            console.error(`❌ Counter owner ${counterOwner} is not the same as receiver ${receiver}`);
            return 1;
        }

        const message = {
            receiver: utils.defaultAbiCoder.encode(["address"], [receiver]),
            data: utils.defaultAbiCoder.encode(["address", "uint256", "bytes"], [dest, 0, basicCounter.interface.encodeFunctionData("increment")]), // ABI-encoded string message that will be decoded on the destination chain and used to make a call from TranseptorAccount
            tokenAmounts: [],
            extraArgs: encodedExtraArgs,
            feeToken: feeIn === PayFeesIn.LINK ? linkAddress : constants.AddressZero,
        };

        // send CCIP message
        console.log(`ℹ️  Calculating CCIP fees...`);
        spinner.start();

        const fees = await router.getFee(targetChainSelector, message);

        if (feeIn === PayFeesIn.LINK) {
            spinner.stop();
            console.log(`ℹ️  Estimated fees (juels): ${fees}`);

            const supportedFeeTokens = getRouterConfig(sourceBlockchain).feeTokens;

            if (!supportedFeeTokens.includes(linkAddress)) {
                console.error(`❌ Token address ${linkAddress} not in the list of supportedTokens ${supportedFeeTokens}`);
                return 1;
            }

            const feeToken: IERC20 = IERC20__factory.connect(linkAddress, signer);

            console.log(`ℹ️  Attempting to approve Router smart contract (${routerAddress}) to spend ${fees} of ${linkAddress} tokens for Chainlink CCIP fees on behalf of ${signer.address}`);
            spinner.start();

            const approvalTx = await feeToken.approve(routerAddress, fees);
            await approvalTx.wait();

            spinner.stop();
            console.log(`✅ Approved successfully, transaction hash: ${approvalTx.hash}`);

            console.log(`ℹ️  Attempting to send the ${message} message from the EOA onwer(${signer.address}) on the ${sourceBlockchain} blockchain to the Transeptor smart contract (${receiver} on the ${destinationBlockchain} blockchain)`);
            spinner.start();

            const sendTx = await router.ccipSend(targetChainSelector, message);
            const receipt = await sendTx.wait();

            spinner.stop()
            console.log(`✅ Sent successfully! Transaction hash: ${sendTx.hash}`);

            await getCcipMessageId(sendTx, receipt, provider);

        } else {
            spinner.stop();
            console.log(`ℹ️  Estimated fees (wei): ${fees}`);

            console.log(`ℹ️  Attempting to send the ${message} message from the EOA onwer(${signer.address}) on the ${sourceBlockchain} blockchain to the Transeptor smart contract (${receiver} on the ${destinationBlockchain} blockchain)`);
            spinner.start();

            const sendTx = await router.ccipSend(targetChainSelector, message, { value: fees });
            const receipt = await sendTx.wait();

            spinner.stop()
            console.log(`✅ Sent successfully! Transaction hash: ${sendTx.hash}`);

            await getCcipMessageId(sendTx, receipt, provider);
        }

        console.log(`✅ Task ccip-token-transfer finished with the execution`);
    });