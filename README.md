# Antfarm Smart Contracts Documentation

Antfarm’s smart contracts are split among three main folders and categories:
Antfarm: core smart contracts of the DEX,
Governance: smart contracts related to the DAO and its management,
External: other smart contracts related to key features of the ecosystem.

## Antfarm Contracts

* AntfarmAtfPair.sol
* AntfarmPair.sol
* AntfarmOracle.sol
* AntfarmFactory.sol
* AntfarmPosition.sol
* AntfarmRouter.sol

Antfarm is a DEX that uses different pieces of logic from UniswapV2 and UniswapV3. The main characteristics of Antfarm’s protocol compared to other DEXs are described below:
LPs can provide liquidity into 8 different pools for every pair, the only difference between those being the swapping fee (1%, 5%, 10%, 15%, 25%, 50%, 75% or 100%).
All swapping fees are paid using ATF, the utility token of the ecosystem. The fee amount is easily determined when one of the two assets is ATF (fee % of the absolute variation of the reserve). When it’s not the case the pool has to find a 1% fee pool with ATF and one of the two assets to determine the correct amount to pay.

### AntfarmAtfPair.sol
This contract is based on UniswapV2 pairs and has a very similar interface (mint, swap, burn). All swapping fees collected are split and claimable at any moment by Liquidity Providers (LPs) using a dividend system that keeps splitting the fees pro-rata based on LPs liquidity.
Unlike UniswapV2, liquidity isn’t ERC20 compatible and any address can hold several positions by providing a positionId for any liquidity related operation (mint, burn, claim).
Any AntfarmAtfPair instance that has 1% set as fee deploys an AntfarmOracle instance to be used to calculate swapping fees on other pairs that have the second token in the pool.

### AntfarmPair.sol
This contract serves the same purpose as AntfarmAtfPair, the only difference being that it only manages liquidity between tokens that aren’t ATF. It means that those pools can only work if there is an existing 1% fee pool with ATF and one of the two tokens to be able to determine the swap fee to pay. 

### AntfarmOracle.sol
This contract is based on TWAP oracles of UniswapV2. A new instance is created by AntfarmAtfPair when the swapping fee is set to 1%. Later it is used by AntfarmPair instances.

### AntfarmFactory.sol
The contract used to create new pairs, it either creates a new AntfarmAtfPair or an AntfarmPair based on the tokens of the pool to be created. It also manages all the different fees possible for every pair.

### AntfarmRouter.sol
Adapts all the principles of UniswapV2 router to protect users by making sure the swapping conditions are met when making a swap.

### AntfarmPosition.sol
The contract to be used by users to manage their liquidity through ERC721 Positions and claim their profits. Those positions hold the user Position details and add some extra features like locking its liquidity for a certain period while being able to claim its profits.


## Governance Contracts

Governance contracts represent the DAO and its close ecosystem.

* GovernanceToken.sol
* GovernorContract.sol
* TimeLock.sol
* VoteEscrowToken.sol
* PositionManager.sol

### GovernanceToken.sol
Antfarm Governance Token (AGT), a simple OpenZeppelin ERC20. Needs to be staked in order to vote and claim rewards (see VoteEscrowedToken).

### GovernorContract.sol & TimeLock.sol
OpenZeppelin Governor.

### VoteEscrowedToken.sol
A contract where users can receive veAGT by staking AGT. veAGT is the token used to vote in the DAO. By staking AGT, users can claim ATF rewards from a portion of the fees collected by the DAO on its positions (see PositionManager).

### PositionManager.sol
This contract is owned by the DAO (TimeLock) and owns the Positions of the DAO. Anyone can the call this contract to claim the fees from its owned positions before being split among a list of payees. The goal is to automate (through a small incentive) the process of claiming and dispatching the collected fees of the DAO between itself (TimeLock) and AGT stakers (VoteEscrowedToken).


## External Contracts

All the other contracts used to launch the ecosystem in a fair manner.

* AntfarmSale.sol
* AntfarmLinearSale.sol
* AntfarmStaking.sol
* AntfarmLiquidityMining.sol

### AntfarmSale.sol
The Initial Liquidity Offering (ILO) contract. Its goal is to sell 30% of the ATF supply to let the DAO create liquidity on Antfarm pools. The sale is split in two, a first portion for a private sale (giving 25% bonus tokens for a 18 months vesting period) and a public offering. It has a softcap and a hardcap.
Vesting assets can be sent to AntfarmStaking to be vested there for the same period and still receive the AGT rewards.

### AntfarmLinearSale.sol
Let users buy ATF with a stablecoin, the price increases linearly with the remaining amount of ATF, this is to ensure the DAO gets more capital to add as liquidity when the price increases a lot (and compensate for the square root value increase of the pool's liquidity).

### AntfarmStaking.sol
Users can claim their ATF to receive a AGT time-based reward proportional to their stake. Vested ATF can be vested here in order for the private investors to still be able to get their share of AGT. It’s a 12 month staking program with a logarithmic curve of distribution.

### AntfarmLiquidityMining.sol
Manages the Liquidity Mining program that lets any Position holders getting an ATF and AGT bonus once every 28 days if their positions have unclaimed ATF. The bonus amount depends on the contract balances and the elapsed time. It’s a 3 year program and only applies to whitelisted pairs in order to avoid potential flaws.
