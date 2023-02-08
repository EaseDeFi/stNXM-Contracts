// SPDX-License-Identifier: (c) Ease DAO
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWNXM is IERC20 {
    function wrap(uint256 _amount) external;

    function unwrap(uint256 _amount) external;
}
