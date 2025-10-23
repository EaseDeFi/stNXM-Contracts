pragma solidity 0.8.26;

interface IUniswapFactory {
  function createPool(
    address tokenA,
    address tokenB,
    uint24 fee
  ) external returns (address pool);
}