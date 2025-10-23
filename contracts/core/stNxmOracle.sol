pragma solidity ^0.8.26;
import "../libraries/v3-core/IUniswapV3Pool.sol";
import "../libraries/v3-core//OracleLibrary.sol";

contract StOracle {

    IUniswapV3Pool public dex;
    address immutable wNxm;
    address immutable stNxm;

    // This is equivalent to 50% per year.
    // Way more than APY will ever be, but less
    // than needed for a useful price manipulation.
    uint256 constant saneApy = 5 * 1e17;
    // 30 minute twap
    uint256 constant twapPeriod = 1800;
    uint256 public immutable startTime;

    constructor(address _dex, address _wNxm, address _stNxm) {
        dex = IUniswapV3Pool(_dex);
        wNxm = _wNxm;
        stNxm = _stNxm;
        startTime = block.timestamp;
    }

    // Find the price of stNXM in wNXM
    // Protections:
    // stNxm price on the dex will be very difficult to be too high because
    // minting is always available.
    function price() external view returns (uint256 twap) {
        (int24 meanTick, ) = OracleLibrary.consult(address(dex), twapPeriod);
        twap = OracleLibrary.getQuoteAtTick(meanTick, 1 ether, stNxm, wNxm);

        // Make sure price isn't too high
        require(sanePrice(twap));

        // Scale to meet Morpho standards
        twap = twap * 1e36;
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