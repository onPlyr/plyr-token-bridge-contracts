// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./WmbApp.sol";
import "./WrappedToken.sol";

contract PlyrBridge is ReentrancyGuardUpgradeable, WmbApp {
    using SafeERC20 for IERC20;

    struct TokenInfo {
        string name;
        string symbol;
        uint8 decimals;
    }

    mapping(address => bool) public isTokenAllowed;
    mapping(address => bool) public isWrappedToken;
    mapping(address => address) public remoteTokenMappings;
    mapping(bytes32 => address) public wrappedTokens; // TokenInfo keccak256 hash => wrapped token address
    mapping(address => TokenInfo) public tokenInfos;

    event CrossTo(address indexed token, uint256 toChainId, address indexed recipent, uint256 amount);
    event CrossBack(address indexed token, uint256 toChainId, address indexed recipent, uint256 amount);
    event ConfigTokenAllowed(address indexed token, string name, string symbol, uint8 decimals, bool allowed);
    event ReceivedMessage(address indexed from, bytes32 indexed messageId, uint256 indexed fromChainId, address token, address recipent, uint256 amount, string name, string symbol, uint8 decimals);

    function initialize(address _owner, address _gateway) public initializer {
        __initialize(_gateway);
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
    }

    function crossTo(
        address token,
        uint256 toChainId, // bip-44 chainId
        address recipent,
        uint256 amount
    ) external payable nonReentrant {
        require(isTokenAllowed[token], "PlyrBridge: token not allowed");
        uint fee = msg.value;
        if (token == address(0)) { // for native coin such as ETH, AVAX, MATIC etc.
            require(msg.value >= amount, "PlyrBridge: insufficient amount");
            fee = msg.value - amount;
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        _dispatchMessage(
            toChainId, // bip-44 chainId
            address(this), // same contract on other chain
            abi.encode("crossTo", token, recipent, amount, tokenInfos[token].name, tokenInfos[token].symbol, tokenInfos[token].decimals),
            fee
        );
        emit CrossTo(token, toChainId, recipent, amount);
    }

    function crossBack(
        address token,
        uint256 toChainId,
        address recipent,
        uint256 amount
    ) external payable nonReentrant {
        require(isWrappedToken[token], "PlyrBridge: token not wrapped");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        WrappedToken(token).burn(address(this), amount);

        _dispatchMessage(
            toChainId, // bip-44 chainId
            address(this), // same contract on other chain
            abi.encode("crossBack", remoteTokenMappings[token], recipent, amount, "", "", 0), // fill blank to make same length as crossTo
            msg.value
        );
        emit CrossBack(token, toChainId, recipent, amount);
    }
    
    function configTokenAllowed(address token, string calldata name, string calldata symbol, uint8 decimals, bool allowed) external onlyOwner {
        isTokenAllowed[token] = allowed;
        tokenInfos[token] = TokenInfo(name, symbol, decimals);
        emit ConfigTokenAllowed(token, name, symbol, decimals, allowed);
    }

    function _wmbReceive(
        bytes calldata data,
        bytes32 messageId,
        uint256 fromChainId,
        address from
    ) virtual internal override {
        (string memory method, address token, address recipent, uint256 amount, string memory name, string memory symbol, uint8 decimals) = abi.decode(data, (string, address, address, uint256, string, string, uint8));
        if (keccak256(abi.encodePacked(method)) == keccak256(abi.encodePacked("crossTo"))) {
            TokenInfo memory tokenInfo = TokenInfo(name, symbol, decimals);
            bytes32 tokenHash = keccak256(abi.encode(tokenInfo));
            address wrappedToken = wrappedTokens[tokenHash];
            if (wrappedToken == address(0)) {
                wrappedToken = address(new WrappedToken(name, symbol, decimals));
                wrappedTokens[tokenHash] = wrappedToken;
                isWrappedToken[wrappedToken] = true;
                remoteTokenMappings[wrappedToken] = token;
            }
            WrappedToken(wrappedToken).mint(recipent, amount);
        } else if (keccak256(abi.encodePacked(method)) == keccak256(abi.encodePacked("crossBack"))) {
            if (token == address(0)) {
                Address.sendValue(payable(recipent), amount);
            } else {
                IERC20(token).safeTransfer(recipent, amount);
            }
        }
        emit ReceivedMessage(from, messageId, fromChainId, token, recipent, amount, name, symbol, decimals);
    }
}