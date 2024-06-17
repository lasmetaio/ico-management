# Lasm ICO/IDO Manager Smart Contract

## Overview

The `Manager` contract is designed to manage ICO/IDO rounds using the efficient 1167 minimal proxy pattern. It enables the creation, management, and finalization of token sale rounds including crowdsales and whitelist sales.

## Tech Stack

- **Solidity**
- **OpenZeppelin Contracts**
  - `SafeERC20`
  - `Pausable`
  - `ReentrancyGuard`
- **1167 Minimal Proxy Pattern**

## Features

- **Create and Manage Sales Rounds**: Easily create and manage multiple sales rounds with minimal gas costs.
- **Token Handling**: Securely transfer and manage tokens for each round.
- **Administrative Control**: Pause, unpause, and finalize rounds to manage the ICO/IDO lifecycle.
- **Event Notifications**: Emit events for important actions like round creation, finalization, and token transfers.

## Events

- `BaseTokenAddressUpdated`
- `PaymentTokenUpdated`
- `SalesRoundCreated`
- `RoundTriggered`
- `RoundFinalized`
- `RoundPaused`
- `RoundUnPaused`
- `RoundMinClaimChanged`
- `Withdrawal`

## Security

- **Pausable Functionality**: Allows pausing of contract operations in case of emergency.
- **Reentrancy Protection**: Prevents reentrancy attacks for secure contract interactions.

## Resources

- Learn more about the [EIP-1167 Minimal Proxy Pattern](https://eips.ethereum.org/EIPS/eip-1167).
