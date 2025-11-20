# Governance: Full Lifecycle Integration Test (Proposal → Vote → Queue → Execute)

This guide walks you through simulating a complete on-chain governance cycle with the Huffy Governor and Timelock, targeting two DAO-controlled modules:
- ParameterStore: update risk parameters (e.g., `maxTradeBps`, `maxSlippageBps`, `tradeCooldownSec`)
- PairWhitelist: add a trading pair

We will:
1) Construct proposal actions (calldata) for both targets
2) Create a proposal
3) Vote with HTK (ERC20Votes)
4) Queue the passed proposal in the Timelock
5) Execute from the Timelock
6) Verify resulting state changes and events

---

## Prerequisites

- Foundry installed (`forge`, `cast`)
- Hedera Testnet RPC (Hashio or another provider)
- Deployed contracts:
  - `HuffyTimelock`
  - `HuffyGovernor` (wired to the Timelock and HTK)
  - `ParameterStore` (owned by Timelock)
  - `PairWhitelist` (managed directly by DAO admin)
  - `HTK` Votes token address (ERC20Votes-compatible) with voting power delegated

If you need to deploy the stack, see `script/Governor.s.sol` for a reference deployment flow.

---

## Hedera Testnet Quickstart (using your env names)

The commands below are tailored for Hedera Testnet via Hashio and your environment variable names. On Hedera Testnet, you cannot mine blocks or time-travel, so plan to wait for voting periods and timelock delays to elapse on-chain.

1) Prepare .env with your variables (copy/paste and fill the blanks):

```bash
ACCOUNT_ID=0.0.xxxxx
PRIVATE_KEY=0x...
RPC_URL=https://testnet.hashio.io/api

TIMELOCK_ADDRESS=0x...
GOVERNOR_ADDRESS=0x...
PARAM_STORE_ADDRESS=0x...
PAIR_WHITELIST_ADDRESS=0x...
HTK_TOKEN_ADDRESS=0x...

NEW_MAX_TRADE_BPS=750
NEW_MAX_SLIPPAGE_BPS=400
NEW_TRADE_COOLDOWN_SEC=120

USDC_TOKEN_ADDRESS=0x...
HTK_TOKEN_ADDRESS=0x...

TIMELOCK_DELAY=172800
```

2) Load env and derive your EOA address for cast:

```bash
source .env
# Derive the EVM address from the private key for read/vote/tx commands
ACCOUNT_ID=$(cast wallet address --private-key $PRIVATE_KEY)
echo "ACCOUNT_ID=$ACCOUNT_ID"
```

Notes for Hedera Testnet:
- Use moderate pacing to avoid Hashio throttling (429). If throttled, retry after a short delay.
- Ensure your Hedera ACCOUNT_ID has an EVM address. PRIVATE_KEY must correspond to that EVM address.
- Voting snapshots: delegate HTK votes before voting starts.

---


## 1) Environment

Prepare a `.env` with the relevant addresses and parameters, then `source .env`.

```bash
source .env
```

---

## 2) Sanity checks (optional but recommended)

```bash
# Governor basics
cast call $GOVERNOR_ADDRESS "name()" --rpc-url $RPC_URL
cast call $GOVERNOR_ADDRESS "votingDelay()" --rpc-url $RPC_URL
cast call $GOVERNOR_ADDRESS "votingPeriod()" --rpc-url $RPC_URL
cast call $GOVERNOR_ADDRESS "quorumNumerator()" --rpc-url $RPC_URL

# Timelock delay (seconds)
cast call $TIMELOCK_ADDRESS "getMinDelay()" --rpc-url $RPC_URL

# Ownership of modules should be Timelock
cast call $PARAM_STORE_ADDRESS "TIMELOCK()" --rpc-url $RPC_URL
cast call $PAIR_WHITELIST_ADDRESS "TIMELOCK()" --rpc-url $RPC_URL
```

---

## 3) Ensure voting power for the voter (HTK delegation)

Voting power is accounted from the snapshot block once voting starts. Delegate before the snapshot. If your HTK token requires delegation to self:

```bash
# Check current votes
cast call $HTK_TOKEN_ADDRESS "getVotes(address)" $ACCOUNT_ID --rpc-url $RPC_URL

# Delegate to self (if needed)
cast send $HTK_TOKEN_ADDRESS "delegate(address)" $ACCOUNT_ID \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY

# Re-check votes
cast call $HTK_TOKEN_ADDRESS "getVotes(address)" $ACCOUNT_ID --rpc-url $RPC_URL
```


---

## 4) Build proposal actions (calldata arrays)

We will create a multi-action proposal with two calls that the Timelock will execute atomically:
- `ParameterStore.setParameters(uint256,uint256,uint256)`
- `PairWhitelist.addPair(address,address)`

We must encode each action’s calldata and list their target addresses and values.

```bash
# A) Encode calldatas
PARAMS_CALldata=$(cast calldata \
  "setParameters(uint256,uint256,uint256)" \
  $NEW_MAX_TRADE_BPS $NEW_MAX_SLIPPAGE_BPS $NEW_TRADE_COOLDOWN_SEC)

PAIR_ADD_CALldata=$(cast calldata \
  "addPair(address,address)" \
  $USDC_TOKEN_ADDRESS $HTK_TOKEN_ADDRESS)

echo $PARAMS_CALldata
echo $PAIR_ADD_CALldata

# B) Targets (comma-separated for clarity)
TARGETS="$PARAM_STORE_ADDRESS,$PAIR_WHITELIST_ADDRESS"

# C) Values (both zero ether)
VALUES="0,0"

# D) Calldatas (comma-separated hex)
CALLDATAS="$PARAMS_CALldata,$PAIR_ADD_CALldata"

# E) Human-readable description (becomes part of proposalId via description hash)
DESC="Update risk params and whitelist pair"
```

Notes:
- Ordering of arrays must match across `targets`, `values`, and `calldatas`.
- You can also use JSON-style array passing with `cast` if preferred, but comma-separated strings are often simpler. See examples below for both styles.

---

## 5) Propose

OpenZeppelin Governor’s `propose` expects arrays and a string description.

```bash
cast send $GOVERNOR_ADDRESS \
  "propose(address[],uint256[],bytes[],string)" \
  "[$TARGETS]" "[$VALUES]" "[$CALLDATAS]" "$DESC" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY -v
```

Capture the transaction hash from stdout; you can fetch logs later to see the `ProposalCreated` event.

You can compute the `proposalId` deterministically via `hashProposal` using the same arrays and `descriptionHash = keccak256(bytes(DESC))`.

```bash
DESC_HASH=$(cast keccak "$DESC")

PROPOSAL_ID=$(cast call $GOVERNOR_ADDRESS \
  "hashProposal(address[],uint256[],bytes[],bytes32)" \
  "[$TARGETS]" "[$VALUES]" "[$CALLDATAS]" $DESC_HASH \
  --rpc-url $RPC_URL)

echo "PROPOSAL_ID=$PROPOSAL_ID"
```

Check initial proposal state:

```bash
cast call $GOVERNOR_ADDRESS "state(uint256)" $PROPOSAL_ID --rpc-url $RPC_URL
```

If `votingDelay > 0`, wait until voting starts.

---

## 6) Vote with HTK

You can vote For (1), Against (0), Abstain (2) using `castVote` or with a reason using `castVoteWithReason`.

```bash
# Basic vote: support = 1 (For)
cast send $GOVERNOR_ADDRESS "castVote(uint256,uint8)" $PROPOSAL_ID 1 \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY -v
```

If the voting period spans many blocks, wait until voting ends.

```bash
cast call $GOVERNOR_ADDRESS "state(uint256)" $PROPOSAL_ID --rpc-url $RPC_URL
```

---

## 7) Queue in Timelock

After a proposal is `Succeeded`, queue it by providing the arrays and `descriptionHash`.

```bash
cast send $GOVERNOR_ADDRESS \
  "queue(address[],uint256[],bytes[],bytes32)" \
  "[$TARGETS]" "[$VALUES]" "[$CALLDATAS]" $DESC_HASH \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY -v
```

Wait for the Timelock delay to elapse before executing.

```bash
# Get min delay (seconds)
MIN_DELAY=$(cast call $TIMELOCK_ADDRESS "getMinDelay()" --rpc-url $RPC_URL)
echo "MIN_DELAY=$MIN_DELAY"
```

---

## 8) Execute

Execute with the same parameters and the `descriptionHash`.

```bash
EXEC_TX=$(cast send $GOVERNOR_ADDRESS \
  "execute(address[],uint256[],bytes[],bytes32)" \
  "[$TARGETS]" "[$VALUES]" "[$CALLDATAS]" $DESC_HASH \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY -v | awk '/transactionHash/ {print $2}')

echo "EXEC_TX=$EXEC_TX"
```

Check the final state (should be `Executed`):

```bash
cast call $GOVERNOR_ADDRESS "state(uint256)" $PROPOSAL_ID --rpc-url $RPC_URL
```

---

## 9) Verify state changes

- ParameterStore values
```bash
cast call $PARAM_STORE_ADDRESS "getRiskParameters()" --rpc-url $RPC_URL
cast call $PARAM_STORE_ADDRESS "maxTradeBps()" --rpc-url $RPC_URL
cast call $PARAM_STORE_ADDRESS "maxSlippageBps()" --rpc-url $RPC_URL
cast call $PARAM_STORE_ADDRESS "tradeCooldownSec()" --rpc-url $RPC_URL
```

- PairWhitelist status
```bash
cast call $PAIR_WHITELIST_ADDRESS "isPairWhitelisted(address,address)" $USDC_TOKEN_ADDRESS $HTK_TOKEN_ADDRESS --rpc-url $RPC_URL
```

You should see the new risk parameters and a `true` whitelist flag for the specified pair.
