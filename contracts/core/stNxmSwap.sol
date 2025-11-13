// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenSwap {
    address private constant DEAD = address(0xdEaD);
    uint256 private constant BUFFER = 1e18;
    IERC20 public immutable arNXM;
    IERC20 public immutable stNXM;
    string public name = "arNXM/stNXM Token Swap";
    uint256 public immutable exchangeRate = 956860757679165373;

    constructor(
        address _stNXM,
        address _arNXM
    ) {
        stNXM = IERC20(_stNXM);
        arNXM = IERC20(_arNXM);
    }

    function swap(uint256 arAmount) external {
        _swap(msg.sender, arAmount);
    }

    function swapFor(address user, uint256 arAmount) external {
        _swap(user, arAmount);
    }

    // arNXM is only worth about 0.96 stNXM so a conversion is required.
    function _swap(address user, uint256 arAmount) internal {
        uint256 stAmount = arAmount * exchangeRate / BUFFER;
        arNXM.transferFrom(user, DEAD, arAmount);
        stNXM.transfer(user, stAmount);
    }
}