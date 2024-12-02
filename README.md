# BrickLayerDAO MRTR Token

Implementation of a staking contract and token with autorestaking. Rewards are distributed over several quarters and are automatically pulled by the staking contract.

## Detailed breakdown

### Staking Rewards

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

### Quarry Rewards

- QUARRY_ROLE is used for miners to be able to deposit quarry rewards.
- Only one quarry reward can be active at a time.
- 30 days period for claiming.
- Shares of the users at quarry reward deposit time are used to distribute the rewards.
- Rewards can be deposited at any time if no other quarry reward is unclaimed
- Default admin can retrive any unclaimed rewards which is mandatory for more quarry rewards to be deposited

### ERC4626

- There are just a few functions overridden to ensure Staking data is updated before executing the logic. That is the case of `deposit`, `mint`, `withdraw`, `redeem`, `transfer`, `transferFrom`.
- `totalAssets` is overridden to return the total balance of the staking contract while deducting assets associated to the Quarry rewards which are not part of the staked balance.

### Governance

- The staking contract implements the `VotesUpgradeable` interface to allow the token to be used as a voting token.
- `clock` is configured to use timestamp instead of block number for compatibility with operations done based on quarters timestamps.
- Users must claim their rewards for the governance to record their balance after each distribution.

## Deployment

You can start by creating your `.env` file based on `.env.example`.

```bash
cp .env.example .env
```

Add values to each of the variables there except for `MRTR_TOKEN`.

### MRTR Token

```bash
forge script script/DeployMRTR.s.sol:DeployMRTR --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

You will see the contract address in the displayed output. Add it to your `.env` file as `MRTR_TOKEN` before deploying the staking contract.

### Staking

```bash
forge script script/DeployStaking.s.sol:DeployStaking --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

You will see the contract address in the displayed output.

### Verification

Make sure to add the `--verify` flag if you want the contracts to be verified. You will need an Etherscan API key configured in your `foundry.toml` file or pass it as a flag to the command. Check verification docs in Foundry book for more details.

### Upgrades

## Testing

To run the test suite use foundry test command.

```bash
forge test
```
