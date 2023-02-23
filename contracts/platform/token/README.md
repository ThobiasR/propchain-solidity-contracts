# PlatformToken

The platform native token is distributed using vesting, uses a staking system to obtain various rights to interact with the platform, and in this tokens there are cashback payments after the purchase of ST tokens.

ERC20 token with some extra functionality:
    All tokens are changed during initialization and further dominance is not possible. It is possible to burn tokens, but only admins can do this (only tokens on the balance of admins, not user ones);

    By default, all transfers are not allowed for all contracts, platform admins can add exclusion contracts. At any time, platform admins can turn off these restrictions, and they will never be turned back on. I draw your attention - the restrictions apply only to smart contracts (it was done so that third-party users would not create swap pools);

    There is a special method similar to transfer from, however the recipient of this transfer is always the one who called the method. Frome differs from transfer in that it does not require approval. Only three contracts can call the method: platform vesting and platform cashback (to make it easier for admins to increase pool liquidity), platform staking (to make it easier for users to stake);

