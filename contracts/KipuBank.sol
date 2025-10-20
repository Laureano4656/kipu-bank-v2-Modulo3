// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title KipuBank (refactor) - Multi-token vault with USD bank cap and roles
/// @notice ETH represented as address(0). Uses Chainlink ETH/USD feed for USD valuation.
/// @dev This contract is a refactor of the original exercise to approach a production-like design.

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract KipuBank is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20Metadata;

    /// Roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// Errors
    error ZeroAmount();
    error DepositExceedsBankCap(uint256 capUsd6, uint256 attemptedUsd6);
    error InsufficientBalance(
        address token,
        address user,
        uint256 available,
        uint256 required
    );
    error WithdrawExceedsPerTx(address token, uint256 limit, uint256 attempted);
    error NativeTransferFailed(address to, uint256 amount);
    error TokenReturnFailed(address token, address to, uint256 amount);
    error InvalidPriceFeed();

    /// Events
    event Deposit(
        address indexed token,
        address indexed user,
        uint256 amount,
        uint256 usdValue6
    );
    event Withdrawal(
        address indexed token,
        address indexed user,
        uint256 amount,
        uint256 usdValue6
    );
    event BankCapUpdated(uint256 oldUsd6, uint256 newUsd6);
    event MaxWithdrawForTokenUpdated(address token, uint256 maxPerTx);

    /// Constants / immutables
    /// We use USDC-like decimals (6) as internal USD accounting base
    uint8 public constant USDC_DECIMALS = 6;
    address public constant NATIVE_TOKEN = address(0);

    /// Chainlink ETH/USD feed (immutable)
    AggregatorV3Interface public immutable i_ethUsdPriceFeed;
    uint8 public immutable i_priceFeedDecimals;

    /// State: bank cap in USD with 6 decimals (e.g. 100 USDC -> 100 * 10^6)
    uint256 immutable public s_bankCapUsd6;

    /// Total USD stored (6 decimals) - updated on deposits/withdrawals
    uint256 public s_totalUsdStored6;


    /// Balances[token][user] = raw token units (wei for ETH)
    mapping(address => mapping(address => uint256)) private s_balances;

    /// Counters
    uint256 public s_totalDeposits;
    uint256 public s_totalWithdrawals;

    /// Constructor
    /// @param admin admin address (granted DEFAULT_ADMIN_ROLE)
    /// @param ethUsdPriceFeed address of Chainlink ETH/USD price feed
    /// @param bankCapUsd6 initial bank cap expressed in USDC decimals (6)
    constructor(address admin, address ethUsdPriceFeed, uint256 bankCapUsd6) {
        require(admin != address(0), "admin-zero");
        _grantRole(ADMIN_ROLE, admin);
        i_ethUsdPriceFeed = AggregatorV3Interface(ethUsdPriceFeed);
        i_priceFeedDecimals = i_ethUsdPriceFeed.decimals();
        s_bankCapUsd6 = bankCapUsd6;
    }

    // -----------------------------
    // Admin functions
    // -----------------------------
}

    // -----------------------------
    // Deposits
    // -----------------------------

    /// @notice Deposit native ETH into the sender's vault
    function depositETH() external payable nonReentrant {
        if (msg.value == 0) revert ZeroAmount();

        // compute USD value (6 decimals) for the amount
        uint256 usd6 = _toUsd6(NATIVE_TOKEN, msg.value);

        uint256 newTotalUsd6 = s_totalUsdStored6 + usd6;
        if (newTotalUsd6 > s_bankCapUsd6)
            revert DepositExceedsBankCap(s_bankCapUsd6, newTotalUsd6);

        // effects
        s_balances[NATIVE_TOKEN][msg.sender] += msg.value;
        s_totalUsdStored6 = newTotalUsd6;
        unchecked {
            s_totalDeposits++;
        }

        emit Deposit(NATIVE_TOKEN, msg.sender, msg.value, usd6);
    }

    /// @notice Deposit an ERC20 token (token must implement decimals())
    function depositToken(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (token == NATIVE_TOKEN) revert();

        // pull tokens
        IERC20Metadata(token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        uint256 usd6 = _toUsd6(token, amount);
        uint256 newTotalUsd6 = s_totalUsdStored6 + usd6;
        if (newTotalUsd6 > s_bankCapUsd6) {
            // Attempt to return tokens to sender, then revert.
            // safeTransfer will revert on failure.
            IERC20Metadata(token).safeTransfer(msg.sender, amount);
            revert DepositExceedsBankCap(s_bankCapUsd6, newTotalUsd6);
        }

        s_balances[token][msg.sender] += amount;
        s_totalUsdStored6 = newTotalUsd6;
        unchecked {
            s_totalDeposits++;
        }

        emit Deposit(token, msg.sender, amount, usd6);
    }

    // -----------------------------
    // Withdrawals
    // -----------------------------

    function withdrawETH(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 userBal = s_balances[NATIVE_TOKEN][msg.sender];
        if (userBal < amount)
            revert InsufficientBalance(
                NATIVE_TOKEN,
                msg.sender,
                userBal,
                amount
            );

        uint256 maxPerTx = s_maxWithdrawPerToken[NATIVE_TOKEN];
        if (maxPerTx > 0 && amount > maxPerTx)
            revert WithdrawExceedsPerTx(NATIVE_TOKEN, maxPerTx, amount);

        uint256 usd6 = _toUsd6(NATIVE_TOKEN, amount);

        // effects
        s_balances[NATIVE_TOKEN][msg.sender] = userBal - amount;
        s_totalUsdStored6 = s_totalUsdStored6 - usd6;
        unchecked {
            s_totalWithdrawals++;
        }

        // interaction
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert NativeTransferFailed(msg.sender, amount);

        emit Withdrawal(NATIVE_TOKEN, msg.sender, amount, usd6);
    }

    function withdrawToken(
        address token,
        uint256 amount
    ) external nonReentrant {
        if (token == NATIVE_TOKEN) revert();
        if (amount == 0) revert ZeroAmount();

        uint256 userBal = s_balances[token][msg.sender];
        if (userBal < amount)
            revert InsufficientBalance(token, msg.sender, userBal, amount);

        uint256 maxPerTx = s_maxWithdrawPerToken[token];
        if (maxPerTx > 0 && amount > maxPerTx)
            revert WithdrawExceedsPerTx(token, maxPerTx, amount);

        uint256 usd6 = _toUsd6(token, amount);

        // effects
        s_balances[token][msg.sender] = userBal - amount;
        s_totalUsdStored6 = s_totalUsdStored6 - usd6;
        unchecked {
            s_totalWithdrawals++;
        }

        // interaction
        IERC20Metadata(token).safeTransfer(msg.sender, amount);

        emit Withdrawal(token, msg.sender, amount, usd6);
    }

    // -----------------------------
    // Views
    // -----------------------------
    function getTokenBalance(
        address token,
        address user
    ) external view returns (uint256) {
        return s_balances[token][user];
    }

    function getContractTokenBalance(
        address token
    ) external view returns (uint256) {
        if (token == NATIVE_TOKEN) return address(this).balance;
        return IERC20Metadata(token).balanceOf(address(this));
    }

    function getBankCapUsd6() external view returns (uint256) {
        return s_bankCapUsd6;
    }

    // -----------------------------
    // Internal valuation helper
    // -----------------------------
    /// @dev Convert a token amount to USD with 6 decimals (USDC style).
    /// For ETH (address(0)) uses Chainlink ETH/USD feed. For tokens we assume token is priced in ETH.
    function _toUsd6(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        // get price (ETH / USD)
        (, int256 price, , , ) = i_ethUsdPriceFeed.latestRoundData();
        if (price <= 0) revert InvalidPriceFeed();
        uint256 priceUint = uint256(price); // price units = 10 ^ i_priceFeedDecimals

        // token decimals
        uint8 tokenDecimals = token == NATIVE_TOKEN
            ? 18
            : IERC20Metadata(token).decimals();

        // Calculation:
        // usd6 = amount * priceUint * 10^USDC_DECIMALS / (10^tokenDecimals * 10^priceDecimals)
        // Do multiplication in safe order to avoid truncation as much as possible.
        // scaled = amount * priceUint
        uint256 scaled = amount * priceUint; // ok in 256 bits for reasonable amounts
        uint256 denom = (10 ** tokenDecimals) * (10 ** i_priceFeedDecimals);
        uint256 usd6 = (scaled * (10 ** USDC_DECIMALS)) / denom;
        return usd6;
    }

    // -----------------------------
    // Fallback/receive: force explicit deposit function use or route to depositETH
    // -----------------------------
    receive() external payable {
        // route to depositETH so accounting is consistent
        this.depositETH();
    }

    fallback() external payable {
        // route to depositETH for plain ETH transfers (or revert if you prefer)
        this.depositETH();
    }
}
