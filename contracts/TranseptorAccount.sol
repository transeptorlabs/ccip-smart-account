// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable reason-string */

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import "./core/ERC4337BaseAccount.sol";

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";

/**
 * @title TranseptorAccount
 * @dev Minimal smart contract account:
  *  is minimal ERC-4337 account to send user operations
  *  has a single signer that can send requests through the entryPoint.
  *  has a CCIPReceiver to allow cross chain token transfers
*/
contract TranseptorAccount is ERC4337BaseAccount, UUPSUpgradeable, Initializable, CCIPReceiver {
    using ECDSA for bytes32;

    address immutable _router; // Address of the CCIP router contract on source chain
    address immutable _link;  // Address of the LINK token contract on source chain
    address public owner; // Owner of the account
    IEntryPoint private immutable _entryPoint; // Entry point contract

   // Used to determine if contract should use LINK or native token for CCIP fee when send token cross chain
    enum PayFeesIn {
        Native,
        LINK
    }

    // Struct to hold details of a CCIP message.
    struct Message {
        uint64 sourceChainSelector;
        address sender;
        string message; 
        address token;
        uint256 amount;
    }

    bytes32[] public receivedMessages; // Array to keep track of the IDs of received messages.
    mapping(bytes32 => Message) public messageDetail; // Mapping from message ID to Message struct, storing details of each received message.

    // Event emitted when TranseptorAccount is initialized
    event TranseptorAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner, address indexed ccipRouter);

    // Event emitted when CCIP message is sent
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        string message, // The message being sent.
        Client.EVMTokenAmount tokenAmount, // The token amount that was sent.
        uint256 ccipFee, // The fees paid for sending the message.
        PayFeesIn payFeesIn // The token used to pay the fees.
    );

    // Event emitted when CCIP message is received
    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        string message, // The message that was received.
        Client.EVMTokenAmount tokenAmount // The token amount that was received.
    );

    error NoMessageReceived(); // Used when trying to access a message but no messages have been received.
    error IndexOutOfBound(uint256 providedIndex, uint256 maxIndex); // Used when the provided index is out of bounds.
    error MessageIdNotExist(bytes32 messageId); // Used when the provided message ID does not exist.

    /**
     * @dev Constructor to initialize TranseptorAccount with an entry point and cci router
     * @param anEntryPoint Address of the erc-4337 entry point contract on source chain
     * @param router Address of the CCIP router contract on source chain
     * @param link Address of the LINK token contract on source chain
    */
    constructor(IEntryPoint anEntryPoint, address router, address link) CCIPReceiver(router) {
        _entryPoint = anEntryPoint;
        _router = router;
        _link = link;
        LinkTokenInterface(_link).approve(router, type(uint256).max);
        _disableInitializers();
    }

    // Modifier to restrict access to the owner
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    /// @inheritdoc ERC4337BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /**
     * @dev Execute a transaction (called directly from owner or by entryPoint)
     * @param dest Destination address
     * @param value ETH value to send
     * @param func Calldata for the transaction
    */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPointOrOwner();
        _call(dest, value, func);
    }

    /**
     * @dev Execute a sequence of transactions
     * @param dest Array of destination addresses
     * @param value Array of ETH values to send
     * @param func Array of calldata for the transactions
     */
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        require(dest.length == func.length && (value.length == 0 || value.length == func.length), "wrong array lengths");
        if (value.length == 0) {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], 0, func[i]);
            }
        } else {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], value[i], func[i]);
            }
        }
    }
    
    /**
     * @dev Get the current account deposit in the entryPoint
     * @return Deposit amount
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * @dev Deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value : msg.value}(address(this));
    }

    /**
     * @dev Withdraw value from the account's deposit
     * @param withdrawAddress Target address to send to
     * @param amount Amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public onlyOwner {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of TranseptorAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     * @param anOwner Owner address
     */
    function initialize(address anOwner) public virtual initializer {
        _initialize(anOwner);
    }

    /**
     * @dev Send a CCIP message: Sends data and token to receiver on the destination chain.
     * @param destinationChainSelector Destination chain selector
     * @param receiver Receiver address
     * @param message The string message to be sent.
     * @param token token address.
     * @param amount token amount.
     * @param payFeesIn Pay fees in LINK or native token on source chain
     * @return messageId The ID of the message that was sent.
     */
    function ccipSendMessage(
        uint64 destinationChainSelector,
        address receiver,
        string calldata message,
        address token,
        uint256 amount,
        PayFeesIn payFeesIn
    ) external  returns (bytes32 messageId) {

        // transfer token to this contract and approve them th ccip router, if not approved already it will fail
        IERC20(token).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        
        // we do not need to approve link to router contract as we already sent a max approval in the constructor
        if (token != _link) {
            IERC20(token).approve(
                _router,
                amount
            );
        }
    
       // set the tokent amounts
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: token,
            amount: amount
        });
        tokenAmounts[0] = tokenAmount;

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: abi.encode(message), // ABI-encoded string message
            tokenAmounts: tokenAmounts, // Tokens amounts
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false}) // Additional arguments, setting gas limit and non-strict sequency mode
            ),
            feeToken: payFeesIn == PayFeesIn.LINK ? _link : address(0)
        });

        uint256 fee = IRouterClient(_router).getFee(
            destinationChainSelector,
            evm2AnyMessage
        );

        if (payFeesIn == PayFeesIn.LINK) {
            // We sent a max approval to the router contract in the constructor, so no need to approve LINK here just send ccip message to router
            messageId = IRouterClient(_router).ccipSend(
                destinationChainSelector,
                evm2AnyMessage
            );
        } else {
            //  Send native token to router contract, no need to approve
            messageId = IRouterClient(_router).ccipSend{value: fee}(
                destinationChainSelector,
                evm2AnyMessage
            );
        }

        emit MessageSent(
            messageId,
            destinationChainSelector,
            receiver,
            message,
            tokenAmount,
            fee,
            payFeesIn
        );
           
        // Return the message ID
        return messageId;
    }

    /**
     * @dev Get the supported token addresses from CCIP router contract
     * @param chainSelector Chain selector for the destination chain
     * @return tokens supported tokens address array
     */
    function getSupportedTokens(
        uint64 chainSelector
    ) external view returns (address[] memory tokens) {
        tokens = IRouterClient(_router).getSupportedTokens(chainSelector);
    }

    /**
     * @dev Get the total number of received messages.
     * @return number The total number of received messages.
    */
    function getNumberOfReceivedMessages() external view returns (uint256 number) {
        return receivedMessages.length;
    }

    /**
      * @notice Fetches details of a received message by message ID.
      * @dev Reverts if the message ID does not exist.
      * @param messageId The ID of the message whose details are to be fetched.
      * @return sourceChainSelector The source chain identifier (aka selector).
      * @return sender The address of the sender.
      * @return message The received message.
      * @return token The received token.
      * @return amount The received token amount.
    */
    function getReceivedMessageDetails(
        bytes32 messageId
    )
        external
        view
        returns (
            uint64 sourceChainSelector,
            address sender,
            string memory message,
            address token,
            uint256 amount
        )
    {
        Message memory detail = messageDetail[messageId];
        if (detail.sender == address(0)) revert MessageIdNotExist(messageId);
        return (
            detail.sourceChainSelector,
            detail.sender,
            detail.message,
            detail.token,
            detail.amount
        );
    }

     /**
      * @notice Fetches details of a received message by its position in the received messages list.
      * @dev Reverts if the index is out of bounds.
      * @param index The position in the list of received messages.
      * @return messageId The ID of the message.
      * @return sourceChainSelector The source chain identifier (aka selector).
      * @return sender The address of the sender.
      * @return message The received message.
      * @return token The received token.
      * @return amount The received token amount.
    */
    function getReceivedMessageAt(
        uint256 index
    )
        external
        view
        returns (
            bytes32 messageId,
            uint64 sourceChainSelector,
            address sender,
            string memory message,
            address token,
            uint256 amount
        )
    {
        if (index >= receivedMessages.length)
            revert IndexOutOfBound(index, receivedMessages.length - 1);
        messageId = receivedMessages[index];
        Message memory detail = messageDetail[messageId];
        return (
            messageId,
            detail.sourceChainSelector,
            detail.sender,
            detail.message,
            detail.token,
            detail.amount
        );
    }

    /**
      * @notice Fetches the details of the last received message.
      * @dev Reverts if no messages have been received yet.
      * @return messageId The ID of the last received message.
      * @return sourceChainSelector The source chain identifier (aka selector) of the last received message.
      * @return sender The address of the sender of the last received message.
      * @return message The last received message.
      * @return token The last transferred token.
      * @return amount The last transferred token amount.
    */
    function getLastReceivedMessageDetails()
        external
        view
        returns (
            bytes32 messageId,
            uint64 sourceChainSelector,
            address sender,
            string memory message,
            address token,
            uint256 amount
        )
    {
        // Revert if no messages have been received
        if (receivedMessages.length == 0) revert NoMessageReceived();

        // Fetch the last received message ID
        messageId = receivedMessages[receivedMessages.length - 1];

        // Fetch the details of the last received message
        Message memory detail = messageDetail[messageId];

        return (
            messageId,
            detail.sourceChainSelector,
            detail.sender,
            detail.message,
            detail.token,
            detail.amount
        );
    }

    /* ******************************************************
     * Internal functions
     * ******************************************************
    */

    /**
     * @dev CCIPReceiver callback
     * @param any2EvmMessage CCIP message
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        bytes32 messageId = any2EvmMessage.messageId; // fetch the messageId
        uint64 sourceChainSelector = any2EvmMessage.sourceChainSelector;
        address sender = abi.decode(any2EvmMessage.sender, (address));
        string memory message = abi.decode(any2EvmMessage.data, (string));

        //  Get the token and amount from the message
        Client.EVMTokenAmount[] memory tokenAmounts = any2EvmMessage.destTokenAmounts;
        address token = tokenAmounts[0].token; // we expect one token to be transfered at once but of course, you can transfer several tokens.
        uint256 amount = tokenAmounts[0].amount; // we expect one token to be transfered at once but of course, you can transfer several tokens.

        Message memory detail = Message(
            sourceChainSelector,
            sender,
            message,
            token,
            amount
        );

        // Update state variables
        messageDetail[messageId] = detail;
        receivedMessages.push(messageId);

        emit MessageReceived(
            messageId,
            sourceChainSelector,
            sender,
            message,
            tokenAmounts[0]
        );
    }


    /**
     * @dev Modifier to restrict access to the owner
     */
    function _onlyOwner() internal view {
        //directly from EOA owner, or through the account itself (which gets redirected through execute())
        require(msg.sender == owner || msg.sender == address(this), "only owner");
    }

    /**
     * @dev Initialize the TranseptorAccount
     * @param anOwner Owner address
     */
    function _initialize(address anOwner) internal virtual {
        owner = anOwner;
        emit TranseptorAccountInitialized(_entryPoint, owner, _router);
    }

    /**
     * @dev Require that the function call went through EntryPoint or owner
     */    
    function _requireFromEntryPointOrOwner() internal view {
        require(msg.sender == address(entryPoint()) || msg.sender == owner, "account: not Owner or EntryPoint");
    }

    /**
     * @inheritdoc ERC4337BaseAccount
     * @dev Implement template method of ERC4337BaseAccount
     */
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
    internal override virtual returns (uint256 validationData) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner != hash.recover(userOp.signature))
            return SIG_VALIDATION_FAILED;
        return 0;
    }

    /**
     * @dev Internal function to call another contract
     * @param target Target contract address
     * @param value ETH value to send
     * @param data Calldata for the transaction
    */
    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * @dev Authorize the upgrade of the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _onlyOwner();
    }
}
