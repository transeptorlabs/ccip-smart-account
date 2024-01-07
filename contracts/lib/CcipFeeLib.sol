// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

/**
 * Utility functions helpful when working with CCIP
 */
library CcipFeeLib {

    // Used to determine if contract should use LINK or native token for CCIP fee when send token cross chain
    enum PayFeesIn {
        Native,
        LINK
    }

    /**
     * @dev Get the CCIP fee for sending tokens
     * @param destinationChainSelector Destination chain selector
     * @param receiver Receiver address. The receiver can be a smart contract or an EAO.
     * @param token token address.
     * @param amount token amount.
     * @param isEao true if receiver is an EAO
     * @param router Router address
     * @param link LINK token address
     * @param payFeesIn Pay fees in LINK or native token on source chain
     * @return fee The ccip fee for sending tokens
     */
    function getCcipTokenTransferFee(
        uint64 destinationChainSelector,
        address receiver,
        address token,
        uint256 amount,
        bool isEao,
        address router,
        address link,
        PayFeesIn payFeesIn
    ) external view returns (uint256 fee) {

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        uint256 ccipGaslimt = 200_000;
        if (isEao) {
            // for transfers to EOA gas limit is 0
            ccipGaslimt = 0;
        }

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: token,
            amount: amount
        });
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: "", // no data
            tokenAmounts: tokenAmounts, // Tokens amounts
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: ccipGaslimt, strict: false}) // Additional arguments, setting gas limit and non-strict sequency mode
            ),
            feeToken: payFeesIn == PayFeesIn.LINK ? link : address(0)
        });

        fee = IRouterClient(router).getFee(
            destinationChainSelector,
            evm2AnyMessage
        );
    }

    /**
     * @dev Get the CCIP fee for sending batch tokens
     * @param destinationChainSelector Destination chain selector
     * @param receiver Receiver address. The receiver can be a smart contract or an EAO.
     * @param tokensToSendDetails Array of token details to send
     * @param isEao true if receiver is an EAO
     * @param router Router address
     * @param link LINK token address
     * @param payFeesIn Pay fees in LINK or native token on source chain
     * @return fee The ccip fee for sending tokens
     */
    function getCcipTokenTransferBatchFee(
        uint64 destinationChainSelector,
        address receiver,
        Client.EVMTokenAmount[] memory tokensToSendDetails,
        bool isEao,
        address router,
        address link,
        PayFeesIn payFeesIn
    ) external view returns (uint256 fee) {

       // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        uint256 ccipGaslimt = 200_000;
        if (isEao) {
            // for transfers to EOA gas limit is 0
            ccipGaslimt = 0;
        }

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: "", // no data
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: ccipGaslimt, strict: false}) // Additional arguments, setting gas limit and non-strict sequency mode
            ),
            feeToken: payFeesIn == PayFeesIn.LINK ? link : address(0)
        });

        fee = IRouterClient(router).getFee(
            destinationChainSelector,
            evm2AnyMessage
        );
    }
}