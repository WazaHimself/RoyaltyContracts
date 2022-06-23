// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.4;


interface IRoyaltySplitter {
    function changeBeneficiariesShares(
        address payable[] memory _beneficiaries,
        uint256[] memory _shares
    ) external;

    function getBeneficiariesAndShares() external view returns(address[] memory, uint256[] memory);

    function distribute() external;
}
