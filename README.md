## DeFi-TokenizedDepositSystemForRWA
- This is a DeFi protocol where users can "deposit" collateral (simulated as ERC-20 tokens representing real-world assets like bonds or commodities) to mint tokenized RWA Share tokens, which act as stable, yield-bearing representations of those assets. 
- Incentives of holding these RWA Share tokens are that they are yield-bearing and liquid as they represent a claim, not the asset itself.
- This project is inspired by real banking tokenization initiatives, namely [Project Guardian](#MAS-Project-Guardian), allowing for the exploration of RWA standards, secure minting/burning mechanics, and compliance-like features purely on-chain.

## MAS Project Guardian
- Monetary Authority of Singapore (MAS), recently rolled out an initiative called ["Project Guardian"](https://www.mas.gov.sg/schemes-and-initiatives/project-guardian)
- Project Guardian is a collaborative initiative between policymakers and the financial industry to enhance liquidity and efficiency of financial markets through asset tokenisation.
- Essentially a cross-border sandbox for real-world deployment, aiming to integrate TradFi with DeFi safely.

## Project Overview
- Users deposits ETH to mint RWA Token (representing RWAs, e.g., a mock "GoldToken" for physical gold), with the amount of RWA Token minted based on the current asset price. The amount of tokens minted is based on a 1/10 denomation of the asset's value at mint time. 
  - Eg. If gold is $2,500/oz, 1 RWA Token = $250 worth (0.1 oz).
- Users lock RWA Token (ERC-20 collateral) into a vault contract to mint "ShareTokens" (ERC-20 compliant, with yield rewards).
- The system ensures over-collateralization to mimic banking stability, with liquidation mechanics if collateral value drops (using a mock oracle). 
- This simulates tokenizing real-world deposits/assets for on-chain custody and exchange, focusing on secure, scalable blockchain for payments and RWAs.

## Protocol
- The RWA Token's value is tied to the underlying asset's price via oracles, so price movements directly impact everything downstream (health factor, redemption, liquidation).
    1. On Minting RWA Token:
        - Price up (gold to $3,000/oz) → user gets fewer RWA Tokens for the same ETH
        - Price down (gold to $2,000/oz) → user gets more RWA Tokens for the same ETH
  
    2. On Depositing to Tokenized Deposit Engine (Minting RWA Share Token):
        -  The "value" of the deposit is based on the current oracle price of the underlying asset
    
    3. Health factor is calculated using USD value from oracles:
        - If asset price rises → collateral USD value increases → health factor improves (more buffer against liquidation) 
        - If asset price falls → collateral USD value decreases → health factor drops (position becomes riskier)

    4. On Redemption (Burning RWA Share Token):  
        - User burns RWA Share Token to get back RWA Token + yield.  
        - As USD value of RWA Token fluctuates (underlying RWA):
          - Asset price up → redeemed RWA Token is worth more USD than when deposited.
          - Asset price down → redeemed RWA Token is worth less USD.

    5. Liquidation:
        -  Asset price drop → collateral value drops → health factor falls → liquidation risk increases.  
        -  Liquidator can liquidate other users → pays back some minted shares, claims collateral at a discount
        -  incentivizes liquidators to keep the system healthy

## Protocol Disclamers
- RWA Token and RWA Share Token values fluctuate with the underlying asset price, no price stability is guaranteed.
- Deposits are not insured, liquidation can occur on price drops.
- Asset price movements amplify risk/reward:
  -  Rising asset prices make positions safer and more profitable.
  -  Falling asset prices trigger liquidations.

## Features
- Allows fractional ownership of high-value assets without requiring users to buy a full unit
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

## Notes
- Yield rewards retrieved from reward pools are prefunded with RWA Share Tokens
- Yield is calculated per period between user interactions (deposit/withdraw/claim) using a locked-in interest rate from the start of each period
- Implements staleness checks for Oracle price feeds







