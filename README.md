# Dynamic Fees for MEV Mitigation

**Atrium Academy Capston Project🦄**

### Introduction

This hook implements a set of strategies to make MEV attacks unprofitable by adjusting fees based on the user’s behavior. In general, this work intends to protect low-liquidity pools from various forms of Miner Extractable Value (MEV) attacks, such as front-running, back-running, and sandwich attacks. These attacks exploit the transparency and ordering of transactions on public blockchains, allowing malicious actors (often bots or miners) to profit at the expense of regular users by manipulating transaction order and pool state.

These attacks lead to:
- Worse execution prices for regular users.
- Increased transaction costs.
- Reduced trust in DEX fairness and security.

## Our Solution
The project implements a MEV Mitigation Hook for Uniswap v4 pools. This hook dynamically adjusts trading fees based on detected transaction patterns and volatility, making MEV attacks less profitable or economically unviable. By increasing fees in response to suspicious activity (e.g., rapid swaps, abnormal gas prices, or price movements), the system discourages and penalizes MEV strategies, thereby protecting liquidity providers and traders.

Our project is inspired by the ideas presented in this article to mitigate MEV attacks by increasing the fees: 
[Sandwich Resistant AMM](https://www.umbraresearch.xyz/writings/sandwich-resistant-amm)


This work is also inspired by some ideas presented by Vitalik Buterin in 2018 in this [post](https://ethresear.ch/t/improving-front-running-resistance-of-x-y-k-market-makers/1281).

The goal is to make a transaction unprofitable when some malicious actions are detected. For instance, Vitalik proposes to prevent any user from buying a pair of tokens at a lower price during a certain amount of time (e.g., in the same block). In our work, we increase the amount of fees when this behaviour is detected helping to mitigate the effect of a backrunning attack. This is possible and easier thanks to Uniswap V4 hooks. 

To prevent frontrunning attacks, we detect when the priority fee exceeds a threshold. If this is detected, the fees are increased. Finally, to mitigate sandwich attacks, if a user intends to buy a token in the opposite direction in the same block, then fees are increased according to the volatility range of the pair obtained from a Chainlink Oracle. 

The project aims to make DEX trading fairer and more secure by automatically detecting and mitigating MEV attacks through dynamic fee adjustments, inspired by the need to address real-world vulnerabilities in DeFi protocols.


### What makes this project unique? What impact will this make?

This project is motivated by our research to create a safer and fairer ARST/USDC pool on Uniswap V4. This work will impact the adoption of our token in Latin America. 

Dynamic, On-Chain MEV Mitigation:
Unlike static fee models or off-chain monitoring, this project introduces a smart contract “hook” that dynamically adjusts trading fees in real time based on observed pool activity and volatility. The hook is directly integrated with Uniswap v4’s extensible architecture, allowing for seamless, protocol-level MEV protection.

Automated Detection and Response:
The system automatically detects suspicious trading patterns (such as those typical of front-running, back-running, and sandwich attacks) and responds by increasing fees or changing pool parameters, making these attacks less profitable or even unprofitable.

Composable and Permissionless:
 Built as a Uniswap v4 hook, the solution is fully composable and can be deployed permissionless to any pool, allowing broad adoption without requiring changes to the core protocol or reliance on centralized actors.

Oracle Integration:
The project leverages on-chain oracles to inform its volatility and fee adjustment logic, providing a robust, data-driven approach to MEV mitigation.

What impact will this make:
Fairer Markets:
By reducing the profitability of MEV attacks, the project helps ensure that regular users and liquidity providers get fairer prices and are less likely to be exploited by sophisticated bots or miners.

Potential Adoption Of the ARST Token:
If successful, this approach might help our token to be adopted in Latin Americaacross and inspire similar mechanisms in other protocols, raising the security baseline for the entire DeFi ecosystem.
