-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil zktest

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install foundry-rs/forge-std@v1.8.2 --no-commit && forge install openzeppelin/openzeppelin-contracts@v5.0.2 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

zktest :; foundryup-zksync && forge test --zksync && foundryup

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network base-sepolia,$(ARGS)),--network base-sepolia)
	NETWORK_ARGS := --rpc-url $(BASE_SEPOLIA_RPC) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(BASESCAN_API_KEY) -vvvv
endif

deploy: 
	@forge script script/DeployPhenomenon.s.sol:DeployPhenomenon --rpc-url $(BASE_SEPOLIA_RPC) --account deployer --sender 0xa25CB4e9e15680220d2b9c23E6bde63E487c5b1D --broadcast --verify --etherscan-api-key $(BASESCAN_API_KEY) -vvvv

entergame: 
	cast send 0x1ef73a17bC9df0eec4088A08acF6d8f752a6E100 "enterGame(bytes32[])" [] --rpc-url $BASE_SEPOLIA_RPC --account player1