import { task } from "hardhat/config";
import { HardhatRuntimeEnvironment, TaskArguments } from "hardhat/types";
import { getPrivateKey, getProviderRpcUrl, getRouterConfig, getEntryPointAddess, getLinkTokenAddress, getTranseptorAccontFactoyAddess, getTranseptorAccontFactoyReceiverAddess, getPayFeesIn } from "./utils";
import { Wallet, providers, utils, constants  } from "ethers";
import { IRouterClient, IRouterClient__factory, IERC20, IERC20__factory, TranseptorAccountFactory__factory, TranseptorAccountFactory,  } from "../typechain-types";
import { Spinner } from "../utils/spinner";
import { getCcipMessageId } from "./helpers";
import { PayFeesIn } from "./constants";

task(`ccip-smart-account-deploy`, `Sends a ccip message to execute a transeptor account factory on destination chain to create a smart account`)
    .addParam(`destinationBlockchain`, `The name of the destination blockchain (for example polygonMumbai)`)
    .addParam(`owner`, `EOA owner of the smart account on the destination chain`)
    .addParam(`salt`, `unit256 salt for the smart account on the destination chain`)
    .addParam(`payFeesIn`, `Choose between 'Native' and 'LINK'`)
    .setAction(async (taskArguments: TaskArguments, hre: HardhatRuntimeEnvironment) => {
      const {destinationBlockchain, payFeesIn, owner, salt } = taskArguments;
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
      const routerAddress = getRouterConfig(sourceBlockchain).address;
      const targetChainSelector = getRouterConfig(destinationBlockchain).chainSelector;
      const router: IRouterClient = IRouterClient__factory.connect(routerAddress, signer);

      // get accout factory address
      const destAccountFactoryAddress = getTranseptorAccontFactoyAddess(destinationBlockchain);
      const destAccountFactoryAddressReceiverAddress = getTranseptorAccontFactoyReceiverAddess(destinationBlockchain);

      // create CCIP message
      const feeIn: PayFeesIn = getPayFeesIn(payFeesIn);

      const gasLimitValue = taskArguments.gasLimit ? taskArguments.gasLimit : 200_000;

      const functionSelector = utils.id("CCIP EVMExtraArgsV1").slice(0, 10);
      const extraArgs = utils.defaultAbiCoder.encode(["uint256", "bool"], [gasLimitValue, false]);
      const encodedExtraArgs = `${functionSelector}${extraArgs.slice(2)}`;

      const transeptorAccountFactory: TranseptorAccountFactory = TranseptorAccountFactory__factory.connect(destAccountFactoryAddress, signer);
      const message = {
          receiver: utils.defaultAbiCoder.encode(["address"], [destAccountFactoryAddressReceiverAddress]),
          data: transeptorAccountFactory.interface.encodeFunctionData('createAccount', [
            owner,
            salt,
          ]),
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

        console.log(`ℹ️  Attempting to send the ${message} message from the EOA onwer(${signer.address}) on the ${sourceBlockchain} blockchain to the DestinationAccountFactoryReceiver smart contract (${destAccountFactoryAddressReceiverAddress} on the ${destinationBlockchain} blockchain)`);
        spinner.start();

        const sendTx = await router.ccipSend(targetChainSelector, message);
        const receipt = await sendTx.wait();

        spinner.stop()
        console.log(`✅ Sent successfully! Transaction hash: ${sendTx.hash}`);

        await getCcipMessageId(sendTx, receipt, provider);

      } else {
        spinner.stop();
        console.log(`ℹ️  Estimated fees (wei): ${fees}`);

        console.log(`ℹ️  Attempting to send the ${message} message from the EOA onwer(${signer.address}) on the ${sourceBlockchain} blockchain to the DestinationAccountFactoryReceiver smart contract (${destAccountFactoryAddressReceiverAddress} on the ${destinationBlockchain} blockchain)`);
        spinner.start();

        const sendTx = await router.ccipSend(targetChainSelector, message, { value: fees });
        const receipt = await sendTx.wait();

        spinner.stop()
        console.log(`✅ Sent successfully! Transaction hash: ${sendTx.hash}`);

        await getCcipMessageId(sendTx, receipt, provider);
      }

      console.log(`✅ Task ccip-token-transfer finished with the execution`);
    });