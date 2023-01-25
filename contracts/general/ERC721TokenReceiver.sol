// SPDX-License-Identifier: (c) Ease DAO
pragma solidity ^0.8.0;

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @dev Based on Solmate https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol
abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
