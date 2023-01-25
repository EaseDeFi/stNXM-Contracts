
// SPDX-License-Identifier: (c) Ease DAO
pragma solidity ^0.8.17;

// Library imports
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Mintable is IERC20 {
    function mint(address user, uint256 amount) external;
    function burn(address user, uint256 amount) external;
}