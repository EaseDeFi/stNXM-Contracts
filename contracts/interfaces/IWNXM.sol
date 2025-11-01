// SPDX-License-Identifier: (c) Ease DAO
pragma solidity ^0.8.17;

interface IWNXM {
    function wrap(uint256 _amount) external;
    function unwrap(uint256 _amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
}
