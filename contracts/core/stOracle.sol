pragma solidity ^0.8.26;

import '../interfaces/INonfungiblePositionManager.sol';
import '../libraries/v3-core/PositionValue.sol';


contract stOracle {

    // This is equivalent to 50% per year.
    // Way more than APY will ever be, but less
    // than needed for a useful price manipulation.
    uint256 constant saneApy = 5 * 1e17;
    uint256 public immutable startTime;
    IUniswapV3Pool public dex;

    constructor(address _dex) {
        startTime = block.timestamp;
        dex = IUniswapV3Pool(_dex);
    }

    // Find the price of stNXM in wNXM
    // Protections:
    // stNxm price on the dex will be very difficult to be too high because
    // minting is always available.
    function price() external view returns (uint256 dexPrice) {
        (dexPrice,,,) = dex.observations(19);
        // Check if it's over a 
        require(sanePrice(dexPrice));

        // Scale to meet Morpho standards
        dexPrice = dexPrice * 1e36;
    }

    // Checks if the price isn't too high.
    // Since the only reason price should increase is because of profits from staking,
    // over 20% APY or so per year is an unreasonable gain and something is likely wrong.
    function sanePrice(uint256 _price) public view returns (bool) {
        // Amount of 1 year it's been
        uint256 elapsedTime = block.timestamp - startTime;
        // If price is lower than equal it's not too high.
        if (_price < 1e18) return true;
        uint256 apy = (_price - 1e18) * 31_536_000 / elapsedTime;
        return apy <= saneApy;
    }

}