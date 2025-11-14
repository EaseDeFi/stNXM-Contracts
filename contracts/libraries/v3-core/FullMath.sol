// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library FullMath {
    /// @notice Calculates floor(a×b÷denominator) with full precision.
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = a * b
            uint256 prod0; // lower 256 bits
            uint256 prod1; // upper 256 bits
            assembly {
                let mm := mulmod(a, b, not(0))
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Fast path if no overflow in 256-bit product.
            if (prod1 == 0) {
                require(denominator != 0, "div0");
                assembly { result := div(prod0, denominator) }
                return result;
            }

            // Make sure result < 2^256 and denominator != 0
            require(denominator > prod1, "overflow");

            // Subtract remainder from [prod1 prod0] to make division exact.
            uint256 remainder;
            assembly { remainder := mulmod(a, b, denominator) }
            assembly {
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                // flip twos to 2^256 / twos
                twos := add(div(sub(0, twos), twos), 1)
            }
            // Shift in bits from prod1 into prod0.
            assembly { prod0 := or(prod0, mul(prod1, twos)) }

            // Compute modular inverse of denominator mod 2^256.
            uint256 inv = (3 * denominator) ^ 2;
            inv *= 2 - denominator * inv; // 8 bits
            inv *= 2 - denominator * inv; // 16
            inv *= 2 - denominator * inv; // 32
            inv *= 2 - denominator * inv; // 64
            inv *= 2 - denominator * inv; // 128
            inv *= 2 - denominator * inv; // 256

            // Final multiply (exact division).
            assembly { result := mul(prod0, inv) }
        }
    }

    /// @notice Calculates ceil(a×b÷denominator) with full precision.
    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        unchecked {
            if (mulmod(a, b, denominator) > 0) {
                require(result < type(uint256).max, "ru overflow");
                result++;
            }
        }
    }
}
