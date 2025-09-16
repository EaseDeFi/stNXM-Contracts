contract stOracle {

    // This is equivalent to 50% per year.
    // Way more than APY will ever be, but less
    // than needed for a useful price manipulation.
    uint256 constant saneApy = 5 * 1e17;
    uint256 public constant startTime;

    constructor() {
        startTime = block.timestamp;
    }

    // Find the price of stNXM in wNXM
    // Protections:
    // stNxm price on the dex will be very difficult to be too high because
    // minting is always available.
    function price() external view returns (uint256 price) {
        uint256 price = v3.getPrice(1e18);
        // Check if it's over a 
        require(sanePrice(price));

        // Scale to meet Morpho standards
        price = price * 1e36;
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