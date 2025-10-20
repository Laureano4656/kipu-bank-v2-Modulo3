# 🏦 KipuBank v2

KipuBank v2 is a production-oriented smart contract designed to simulate a decentralized multi-asset bank.  
It improves upon the original `KipuBank` by introducing access control, multi-token support, USD-based accounting via Chainlink oracles, and safer, gas-optimized logic patterns.

---

## 📘 Overview

This contract allows users to **deposit and withdraw Ether or ERC-20 tokens** while the bank maintains a global capacity (`bankCap`) denominated in USD (6 decimals, USDC-style).  
It leverages **Chainlink price feeds** to dynamically calculate USD value for deposits and ensures that the total value stored never exceeds the defined cap.

---

## 🚀 Features

### ✅ Core Functionality
- **Deposit and withdraw** Ether and ERC-20 tokens.
- **Global USD cap** enforced using Chainlink ETH/USD price feed.
- **Per-token withdrawal limits.**
- **Internal accounting** supports multiple tokens via:
  ```solidity
  mapping(address => mapping(address => uint256)) s_balances;
  // s_balances[tokenAddress][user] = balance
  // Use address(0) for native Ether

### 🛡️ Security & Reliability

- **Uses OpenZeppelin’s SafeERC20 for safe token transfers.**

- **Employs ReentrancyGuard to prevent reentrancy attacks.**

- **Implements Checks-Effects-Interactions pattern for external calls.**

- **Uses custom errors for gas-efficient and clear revert reasons.**

### ⚙️ Administration & Roles

- **DEFAULT_ADMIN_ROLE: can configure limits and feeds.**

- **Optional roles can be extended for minters, pausers, etc.**

### 💱 Price Feed Integration

- **Uses Chainlink AggregatorV3Interface to fetch live ETH/USD prices.**

- **Converts deposit values to USD (6 decimals) internally for accounting.**

- **Example conversion (for 1 ETH at $2000):**

```yaml
1 ETH → 2000 * 10^6 = 2,000,000,000 (USD6 units)
```
### 🧩 Technologies Used

- **Solidity 0.8.30**

- **OpenZeppelin Contracts**

    - **AccessControl**

    - **ReentrancyGuard**

    - **SafeERC20**

    - **IERC20Metadata**

- **Chainlink Data Feeds**

- **Compatible with Hardhat, Foundry, and Remix IDE**

### 🧠 Contract Architecture
Category	Description
Bank Cap	Maximum USD value the contract can hold (USDC decimals)
Balances	Stored per user per token
Deposits	Users can deposit ETH or ERC-20 tokens
Withdrawals	Users can withdraw up to their balance and below per-token limit
Access Control	Admin can update caps and per-token limits
Oracle Feed	Converts ETH → USD using Chainlink ETH/USD price feed
⚙️ Deployment (Remix IDE)

Open Remix IDE

Load the KipuBankV2.sol contract

Compile using Solidity 0.8.30

Deploy using the Remix VM (London) or a testnet provider (e.g., Sepolia)

Set constructor parameters:

_bankCapUsd6: e.g. 100000000000 ( = 100,000 USDC)

_priceFeed: Chainlink ETH/USD feed address

Sepolia: 0x694AA1769357215DE4FAC081bf1f309aDC325306

Once deployed, you can interact with:

depositETH() for native ETH

depositToken(address token, uint256 amount) for ERC-20 tokens

withdrawETH(uint256 amount)

withdrawToken(address token, uint256 amount)

getBalance(token, user)

setTokenMaxWithdraw(token, newLimit)

## 🧪 Interacting With the Contract
### 🪙 Depositing ERC-20 Tokens

**1. Approve KipuBank to spend your tokens:**

```solidity
IERC20(token).approve(kipuBankAddress, amount);
```

**2. Deposit:**
```solidity
kipuBank.depositToken(tokenAddress, amount);
```

### 💰 Depositing Ether

Simply call:

```solidity
kipuBank.depositETH({ value: 1 ether });
```

or send Ether directly (will trigger receive()):
```solidity
(address of kipuBank).sendTransaction({ value: 1 ether });
```

### 💸 Withdrawals
```solidity
kipuBank.withdrawToken(tokenAddress, amount);
```

or
```solidity
kipuBank.withdrawETH(amount);
```


### 📜 License

This project is licensed under the **MIT License.**

### 👨‍💻 Author

Laureano García Di Martino
Full Stack & Smart Contract Developer
Universidad Nacional de Mar del Plata