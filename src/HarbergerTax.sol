// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC721 } from "@solmate/tokens/ERC721.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

// HOW IT WORKS:
// - Owners set the price for their asset.
// - Owners pay a 2% tax based on the asset price.
// - If owner fails to pay the tax, the asset can be bought by someone else at
//   any price they choose which will be the new asset price.
// - Anyone can force a sale of the asset from the owner if they paid equal or
//   more than the asset price. The amount paid will be the new asset price.

contract HarbergerTax is ERC721("Asset", "ASSET") {
    using FixedPointMathLib for uint256;

    uint256 public constant TAX_PER_YEAR = 0.02e18; // 2%

    mapping(uint256 => uint256) public prices;
    mapping(uint256 => uint256) public taxesPaid;
    mapping(uint256 => uint256) public lastPurchased;

    function tokenURI(uint256) public pure override returns (string memory) {
        return "PLACEHOLDER";
    }

    function buyAsset(uint256 id) external payable {
        uint256 paid = msg.value;
        uint256 price = prices[id];
        uint256 paidTaxes = taxesPaid[id];
        uint256 dueTaxes = taxesDue(id);
        uint256 payment = price > paid ? paid : price;

        if (paidTaxes >= dueTaxes) {
            require(paid >= price, "Not enough paid.");

            // Refund taxes.
            uint256 refund = paidTaxes - dueTaxes;
            if (refund > 0) payment += refund;
        }

        prices[id] = paid;
        lastPurchased[id] = block.timestamp;

        address owner = _ownerOf[id];
        safeTransferFrom(owner, msg.sender, id);

        if (owner != address(0))
            SafeTransferLib.safeTransferETH(owner, payment);
    }

    function payTax(uint256 id) external payable {
        address owner = _ownerOf[id];
        require(
            msg.sender == owner || isApprovedForAll[owner][msg.sender],
            "Not authorized."
        );

        taxesPaid[id] += msg.value;
    }

    function taxesDue(uint256 id) public view returns (uint256) {
        uint256 elapsedTime = block.timestamp - lastPurchased[id];

        // Allow 1 month grace period from purchase date before taxation.
        if (elapsedTime <= 28 days) return 0;

        return (prices[id] * TAX_PER_YEAR * elapsedTime) / 1e18 / 365 days;
    }

    receive() external payable {}
}
