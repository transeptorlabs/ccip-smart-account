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

/**
 * @title TranseptorAccount
 * @dev Minimal account with that:
  *  this is minimal ERC-4337 account
  *  has execute, eth handling methods
  *  has a single signer that can send requests through the entryPoint.
  *  has a CCIPReceiver to allow cross chain token transfers
*/
contract TranseptorAccount is ERC4337BaseAccount, UUPSUpgradeable, Initializable, CCIPReceiver {
    using ECDSA for bytes32;

    // Used to determine if contract should use LINK or native token for ccip fee when send token cross chain
    enum PayFeesIn {
        Native,
        LINK
    }
    // Address of the CCIP router contract on source chain
    address immutable _router;

    // Address of the LINK token contract on source chain
    address immutable _link;

    // Owner of the account
    address public owner;

    // CCIPReceiver State
    bytes32 _latestMessageId;
    uint64 _latestSourceChainSelector;
    address _latestSender;
    string _latestMessage;

    // Entry point contract
    IEntryPoint private immutable _entryPoint;

    // Event emitted when TranseptorAccount is initialized
    event TranseptorAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner, address indexed ccipRouter);

    // Event emitted when CCIP message is received
    event MessageReceived(
        bytes32 latestMessageId,
        uint64 latestSourceChainSelector,
        address latestSender,
        string latestMessage
    );

    // Event emitted when CCIP message is sent
    event MessageSent(bytes32 messageId, uint256 ccipFee, PayFeesIn payFeesIn);

    /**
     * @dev Constructor to initialize TranseptorAccount with an entry point and cci router
     * @param anEntryPoint Address of the entry point contract on source chain
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

    function _onlyOwner() internal view {
        //directly from EOA owner, or through the account itself (which gets redirected through execute())
        require(msg.sender == owner || msg.sender == address(this), "only owner");
    }

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
     * @dev Get the latest CCIP message details
     * @return Message details
     */
    function getLatestMessageDetails()
        public
        view
        returns (bytes32, uint64, address, string memory)
    {
        return (
            _latestMessageId,
            _latestSourceChainSelector,
            _latestSender,
            _latestMessage
        );
    }

    /**
     * @dev Send a CCIP message
     * @param destinationChainSelector Destination chain selector
     * @param receiver Receiver address
     * @param messageText Message text
     * @param payFeesIn Pay fees in LINK or native token on source chain
     */
    function ccipSend(
        uint64 destinationChainSelector,
        address receiver,
        string memory messageText,
        PayFeesIn payFeesIn
    ) external {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(messageText),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: payFeesIn == PayFeesIn.LINK ? _link : address(0)
        });

        uint256 fee = IRouterClient(_router).getFee(
            destinationChainSelector,
            message
        );

        bytes32 messageId;

        if (payFeesIn == PayFeesIn.LINK) {
            // We sent a max approval to the router contract in the constructor, so no need to approve LINK here just send ccip message to router
            messageId = IRouterClient(_router).ccipSend(
                destinationChainSelector,
                message
            );
        } else {
            //  Send native token to router contract, no need to approve
            messageId = IRouterClient(_router).ccipSend{value: fee}(
                destinationChainSelector,
                message
            );
        }

        emit MessageSent(messageId, fee, payFeesIn);
    }

    /* ******************************************************
     * Internal functions
     * ******************************************************
    */

    /**
     * @dev CCIPReceiver callback
     * @param message CCIP message
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory message
    ) internal override {
        _latestMessageId = message.messageId;
        _latestSourceChainSelector = message.sourceChainSelector;
        _latestSender = abi.decode(message.sender, (address));
        _latestMessage = abi.decode(message.data, (string));

        emit MessageReceived(
            _latestMessageId,
            _latestSourceChainSelector,
            _latestSender,
            _latestMessage
        );
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
