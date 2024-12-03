include .env
export $(shell sed 's/=.*//' .env)

deploy_test:
	@echo "Deploying contracts to Mainnet"
	@forge script script/Deploy.s.sol:DeployVault --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY)  
	@echo "Deployment completed!"

deploy_mainnet:
	@echo "Deploying contracts to Mainnet"
	@forge script script/Deploy.s.sol:DeployVault --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify -vvvv
	@echo "Deployment completed!"