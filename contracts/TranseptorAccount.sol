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

    // Owner of the account
    address public owner;

    // CCIPReceiver State
    bytes32 latestMessageId;
    uint64 latestSourceChainSelector;
    address latestSender;
    string latestMessage;

    // Entry point contract
    IEntryPoint private immutable _entryPoint;

    // Event emitted when TranseptorAccount is initialized
    event TranseptorAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);

    // Event emitted when CCIP message is received
    event MessageReceived(
        bytes32 latestMessageId,
        uint64 latestSourceChainSelector,
        address latestSender,
        string latestMessage
    );

    /**
     * @dev Constructor to initialize TranseptorAccount with an entry point
     * @param anEntryPoint Address of the entry point contract
     */
    constructor(IEntryPoint anEntryPoint, address router) CCIPReceiver(router) {
        _entryPoint = anEntryPoint;
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
     * @dev Get the latest CCIP message details
     * @return Message details
     */
    function getLatestMessageDetails()
        public
        view
        returns (bytes32, uint64, address, string memory)
    {
        return (
            latestMessageId,
            latestSourceChainSelector,
            latestSender,
            latestMessage
        );
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
        latestMessageId = message.messageId;
        latestSourceChainSelector = message.sourceChainSelector;
        latestSender = abi.decode(message.sender, (address));
        latestMessage = abi.decode(message.data, (string));

        emit MessageReceived(
            latestMessageId,
            latestSourceChainSelector,
            latestSender,
            latestMessage
        );
    }

    /**
     * @dev Initialize the TranseptorAccount
     * @param anOwner Owner address
     */
    function _initialize(address anOwner) internal virtual {
        owner = anOwner;
        emit TranseptorAccountInitialized(_entryPoint, owner);
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
