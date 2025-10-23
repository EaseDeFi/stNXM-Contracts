pragma solidity 0.8.26;

interface IMorphoFactory {
    function createMarket(address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) external returns (address);
}