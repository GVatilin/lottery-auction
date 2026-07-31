-include .env

.PHONY: install update build test format anvil deploy-anvil deploy-sepolia

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

install:
	forge install foundry-rs/forge-std@v1.16.2
	forge install smartcontractkit/chainlink-brownie-contracts@1.3.0
	forge install transmissions11/solmate@v6

update:
	forge update

build:
	forge build

test:
	forge test

format:
	forge fmt

anvil:
	anvil --steps-tracing --block-time 1

deploy-anvil:
	@forge script script/Deploy.s.sol:DeployScript \
		--rpc-url http://127.0.0.1:8545 \
		--private-key $(DEFAULT_ANVIL_KEY) \
		--broadcast \
		-vvvv

deploy-sepolia:
	@forge script script/Deploy.s.sol:DeployScript \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--broadcast \
		--account default \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY) \
		-vvvv