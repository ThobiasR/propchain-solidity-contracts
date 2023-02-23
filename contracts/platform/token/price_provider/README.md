# PlatformTokenPriceProvider

Implementations of pricing should inherit.
Needed to determine the prices of PROP in USD and vice versa for our tier system.

After deployment, you must call setPoolProvider or setHardcodeProvider.

We are supposed to use HardcodeProvider in the beginning and set the prices hardcoded, resetting them as needed. In the future, it is planned to develop PoolProvider which will find out the price from a certain swap pool (for example Quickswap) and replace the hadcode. Note that this contract will need to implement IPlatformTokenPriceProvider.