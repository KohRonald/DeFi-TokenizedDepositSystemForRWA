## DeFi-TokenizedDepositSystemForRWA
- This is a DeFi protocol where users can "deposit" collateral (simulated as ERC-20 tokens representing real-world assets like bonds or commodities) to mint tokenized RWA Share tokens, which act as stable, yield-bearing representations of those assets. 
- Incentives of holding these RWA Share tokens are that they are yield-bearing and liquid as they represent a claim, not the asset itself.
- This project is inspired by real banking tokenization initiatives, namely [Project Guardian](#MAS-Project-Guardian), allowing for the exploration of RWA standards, secure minting/burning mechanics, and compliance-like features purely on-chain.

## MAS Project Guardian
- Monetary Authority of Singapore (MAS), recently rolled out an initiative called ["Project Guardian"](https://www.mas.gov.sg/schemes-and-initiatives/project-guardian)
- Project Guardian is a collaborative initiative between policymakers and the financial industry to enhance liquidity and efficiency of financial markets through asset tokenisation.
- Essentially a cross-border sandbox for real-world deployment, aiming to integrate TradFi with DeFi safely.

## Project Overview
- Users lock ERC-20 collateral (representing RWAs, e.g., a mock "GoldToken" for physical gold) into a vault contract to mint "DepositTokens" (ERC-20 compliant, with optional yield via simple staking rewards).
- The system ensures over-collateralization to mimic banking stability, with liquidation mechanics if collateral value drops (using a mock oracle). 
- This simulates tokenizing real-world deposits/assets for on-chain custody and exchange, focusing on secure, scalable blockchain for payments and RWAs.

## Features
- Contract supports dynamic asset deployment
- Supports yield interest rate adjustments

### Key Components
1. RWA Collateral Token (ERC-20)
    - RWA token representation
    - The collateral token

2. RWA Share Token
    - The minted token representing the tokenized deposit
    - Yield-bearing representations of the RWA Collateral Token
    - Implements burnable/pausable features

3. Vault Contract
    - Users approve and lock RWA collateral to mint DepositTokens at a collateral ratio 
    - Redemption: Burn DepositTokens to unlock collateral
    - Liquidation: If collateral value drops below threshold (mock oracle price feed), allow liquidators to seize and auction collateral

4. Mock Oracle
    - Retrieves real world price feed of the RWA

## Documentation
- Transferring/Trading RWA share token forfeits redemption rights to the recipient

### Notes
- Yield rewards retrieved from reward pools are prefunded with RWA Share Tokens
- Yield is calculated per period between user interactions (deposit/withdraw/claim) using a locked-in interest rate from the start of each period
- Implements staleness checks for Oracle price feeds







