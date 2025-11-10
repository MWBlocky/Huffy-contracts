Validators: How to Use, Error Codes, and Extensibility

Overview
- Validators are plug-in contracts that enforce trading policy checks for Relay._validateTrade(tokenIn, tokenOut, amountIn, minAmountOut).
- Governance (DAO_ROLE) can add/remove validators in Relay. All validators are executed for every proposed trade.
- Each validator returns (ok, reasonCode). Relay aggregates failures and emits human-readable reason codes (bytes32) in events and return values.

Expected Interface
- File: src/interfaces/ITradeValidator.sol
- Signature:
  validate(
    address trader,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    TradeContext calldata ctx
  ) external view returns (bool ok, bytes32 reasonCode);

TradeContext fields
- maxTradeBps: Max trade size (basis points) from ParameterStore
- maxSlippageBps: Max slippage (basis points) from ParameterStore
- tradeCooldownSec: Minimum seconds between trades
- lastTradeTimestamp: Timestamp of the last trade executed by Relay
- cooldownRemaining: Remaining cooldown time (if any)
- treasuryBalance: Current Treasury balance of tokenIn
- maxAllowedAmount: Derived = treasuryBalance * maxTradeBps / 10000
- impliedSlippage: Derived by comparing on-chain quote with minAmountOut
- pairWhitelisted: Whether (tokenIn, tokenOut) is whitelisted in PairWhitelist

Error Codes
- Relay is validator-agnostic and does not define any error code mapping.
- Each validator should define and return its own bytes32 reason codes using keccak256("YOUR_REASON").
- Example codes used by the sample validators in this repo:
  - PAIR_NOT_WHITELISTED
  - EXCEEDS_MAX_TRADE_SIZE
  - EXCEEDS_MAX_SLIPPAGE
  - INSUFFICIENT_TREASURY_BALANCE
  - INVALID_PARAMETERS

Current Example Validators (in src/validators)
- PairWhitelistValidator (uses ctx.pairWhitelisted) -> returns keccak256("PAIR_NOT_WHITELISTED") on failure
- MaxTradeSizeValidator (uses ctx.maxAllowedAmount) -> returns keccak256("EXCEEDS_MAX_TRADE_SIZE") on failure
- SlippageValidator (uses ctx.impliedSlippage vs ctx.maxSlippageBps) -> returns keccak256("EXCEEDS_MAX_SLIPPAGE") on failure
- TreasuryBalanceValidator (uses ctx.treasuryBalance vs amountIn) -> returns keccak256("INSUFFICIENT_TREASURY_BALANCE") on failure
- BasicParamsValidator (checks non-zero addresses and amounts) -> returns keccak256("INVALID_PARAMETERS") on failure

How Relay Aggregates
- Relay computes TradeContext and calls every validator.
- If any validator returns ok=false, Relay appends the validator-provided bytes32 reason code to the list.
- Relay._validateTrade returns ValidationResult with:
  - isValid = (no failures)
  - reasonCodes = array of bytes32 error ids
  - also returns contextual parameters for UI/monitoring

Adding a New Validator
1) Create contract under src/validators/, import ITradeValidator, and implement validate(...) per interface above.
2) Define your own bytes32 reason code(s) as keccak256("...") and document them in your validator.
3) Use only the provided TradeContext + function parameters. Do not perform external state-changing calls.
4) Deploy your validator (or include it in your deployment scripts) and add it via Relay.addValidator(address) using an account with DAO_ROLE.
5) To remove a validator, use Relay.removeValidator(address) — removal is by address to avoid index mistakes.
