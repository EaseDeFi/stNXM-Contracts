pragma solidity 0.8.26;

interface IMorpho {
    function deposit(uint256 assets, address receiver) external;
    function redeem(uint256 shares, address caller, address receiver) external;
    function balanceOf(address user) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
}