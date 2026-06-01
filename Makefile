-include .env

.PHONY: all test deploy

build :; forge build

test :; forge test

install :; forge install Cyfrin/foundry-devops && forge install smartcontractkit/chainlink-evm && forge install foundry-rs/forge-std && forge install vectorized/solady