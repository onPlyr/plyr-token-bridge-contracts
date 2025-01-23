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

    struct DecimalInfo {
        uint8 fromDecimals;
        uint8 wrappedDecimals;
    }

    bool public paused;
    mapping(address => bool) public isTokenAllowed;
    mapping(address => bool) public isWrappedToken;
    mapping(address => address) public remoteTokenMappings;
    mapping(bytes32 => address) public wrappedTokens; // TokenInfo keccak256 hash => wrapped token address
    mapping(address => TokenInfo) public tokenInfos;
    mapping(uint256 => mapping(address => uint256)) public remoteQuota;
    mapping(address => DecimalInfo) public decimalInfos;

    event CrossTo(address indexed token, uint256 toChainId, address indexed recipent, uint256 amount);
    event CrossBack(address indexed token, uint256 toChainId, address indexed recipent, uint256 amount);
    event ConfigTokenAllowed(address indexed token, string name, string symbol, uint8 fromDecimals, uint8 wrappedDecimals, bool allowed);
    event ReceivedMessage(address indexed from, bytes32 indexed messageId, uint256 indexed fromChainId, address token, address recipent, uint256 amount, string name, string symbol, uint8 decimals);

    modifier notPaused() {
        require(!paused, "PlyrBridge: paused");
        _;
    }

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
    ) external payable nonReentrant notPaused {
        require(isTokenAllowed[token], "PlyrBridge: token not allowed");
        uint fee = msg.value;
        uint receivedAmount;
        if (token == address(0)) { // for native coin such as ETH, AVAX, MATIC etc.
            require(msg.value >= amount, "PlyrBridge: insufficient amount");
            fee = msg.value - amount;
            receivedAmount = amount;
        } else {
            uint balanceBefore = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            receivedAmount = IERC20(token).balanceOf(address(this)) - balanceBefore;
        }

        uint256 wrappedAmount;
        {
            uint256 fromDecimals = decimalInfos[token].fromDecimals;
            uint256 wrappedDecimals = decimalInfos[token].wrappedDecimals;
            wrappedAmount = receivedAmount * (10 ** wrappedDecimals) / (10 ** fromDecimals);
        }

        _dispatchMessage(
            toChainId, // bip-44 chainId
            address(this), // same contract on other chain
            abi.encode("crossTo", token, recipent, wrappedAmount, tokenInfos[token].name, tokenInfos[token].symbol, tokenInfos[token].decimals),
            fee
        );
        emit CrossTo(token, toChainId, recipent, receivedAmount);
    }

    function crossBack(
        address token,
        uint256 toChainId,
        address recipent,
        uint256 amount
    ) external payable nonReentrant notPaused {
        require(isWrappedToken[token], "PlyrBridge: token not wrapped");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        WrappedToken(token).burn(address(this), amount);
        string memory name = WrappedToken(token).name();
        string memory symbol = WrappedToken(token).symbol();
        uint8 decimals = WrappedToken(token).decimals();

        require(remoteQuota[toChainId][remoteTokenMappings[token]] >= amount, "PlyrBridge: insufficient quota");
        remoteQuota[toChainId][remoteTokenMappings[token]] -= amount;
        
        _dispatchMessage(
            toChainId, // bip-44 chainId
            address(this), // same contract on other chain
            abi.encode("crossBack", remoteTokenMappings[token], recipent, amount, name, symbol, decimals), // fill blank to make same length as crossTo
            msg.value
        );
        emit CrossBack(token, toChainId, recipent, amount);
    }
    
    function configTokenAllowed(address token, string calldata symbol, uint8 fromDecimals, uint8 wrappedDecimals, bool allowed) external onlyOwner {
        isTokenAllowed[token] = allowed;
        string memory name = strConcat("PLYR Wrapped ", symbol);
        tokenInfos[token] = TokenInfo(name, symbol, wrappedDecimals);
        decimalInfos[token] = DecimalInfo(fromDecimals, wrappedDecimals);
        emit ConfigTokenAllowed(token, name, symbol, fromDecimals, wrappedDecimals, allowed);
    }

    function configWmbGateway(address _wmbGateway) external onlyOwner {
        wmbGateway = _wmbGateway;
    }

    function configPause(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function strConcat(string memory _a, string memory _b) public pure returns (string memory) {
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        bytes memory _result = new bytes(_ba.length + _bb.length);
        uint256 k = 0;
        for (uint256 i = 0; i < _ba.length; i++) {
            _result[k] = _ba[i];
            k++;
        }
        for (uint256 i = 0; i < _bb.length; i++) {
            _result[k] = _bb[i];
            k++;
        }
        return string(_result);
    }

    function _wmbReceive(
        bytes calldata data,
        bytes32 messageId,
        uint256 fromChainId,
        address from
    ) virtual internal override notPaused {
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
            remoteQuota[fromChainId][token] += amount;
        } else if (keccak256(abi.encodePacked(method)) == keccak256(abi.encodePacked("crossBack"))) {
            TokenInfo memory tokenInfo = TokenInfo(name, symbol, decimals);
            require(keccak256(abi.encode(tokenInfos[token])) == keccak256(abi.encode(tokenInfo)), "PlyrBridge: token name mismatch");
            require(isTokenAllowed[token], "PlyrBridge: token not allowed");
            uint256 fromDecimals = decimalInfos[token].fromDecimals;
            uint256 wrappedDecimals = decimalInfos[token].wrappedDecimals;
            uint256 fromAmount = amount * (10 ** fromDecimals) / (10 ** wrappedDecimals);

            if (token == address(0)) {
                Address.sendValue(payable(recipent), fromAmount);
            } else {
                IERC20(token).safeTransfer(recipent, fromAmount);
            }
        }
        emit ReceivedMessage(from, messageId, fromChainId, token, recipent, amount, name, symbol, decimals);
    }
}