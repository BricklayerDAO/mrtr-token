# BrickLayerDAO MRTR Token

Implementation of a staking contract and token with autorestaking. Rewards are distributed over several quarters and are automatically pulled by the staking contract.

## Detailed breakdown

### Rewards

- Rewards are distributed quarterly over a period of 80 quarters.
- Rewards are accrued in a time-weighted manner according to ERC4626 shares of every user.
- Rewards are autorestaked.
- User can claim they assets at any time so they xMRTR balance is updated
- Any action involving a user triggers a claim of the rewards, so every action is executed with the latest data.
- Contract automatically deploys a treasury for rewards management.
  - Staking contract will pull rewards from this treasury after every quarter
  - Admin should take care of adding liquidity to this treasury regularly
    - If there is not enough liquidity once a new quarter begings transactions will start to fail
  - Admin have full control over the assets in the treasury, so they can take back any assets at any time.

### ERC4626

- There are just a few functions overridden to ensure Staking data is updated before executing the logic. That is the case of `deposit`, `mint`, `withdraw`, `redeem`, `transfer`, `transferFrom`.
- `totalAssets` is overridden to return the total balance of the staking contract while deducting assets associated to the Quarry rewards which are not part of the staked balance.

### Governance

- The staking contract implements the `VotesUpgradeable` interface to allow the token to be used as a voting token.
- `clock` is configured to use timestamp instead of block number for compatibility with operations done based on quarters timestamps.
- Users must claim their rewards for the governance to record their balance after each distribution.

## Deployment

// TODO: Add deployment script and update this section

## Testing

To run the test suite use foundry test command.

```bash
forge test
```
