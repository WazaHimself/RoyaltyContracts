// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./IRoyaltySplitter.sol";

contract RoyaltySplitter is Ownable, ERC165, IRoyaltySplitter {
    /// @inheritdoc	ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceId == type(IRoyaltySplitter).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    address payable[] beneficiaries;
    uint256[] shares;

    event RoyaltiesReceived(
        address from,
        uint256 amount
    );

    event RoyaltiesPaid(
        uint256 royaltyAmount,
        address payable[] beneficiares,
        uint256[] shares
    );

    event BeneficiarySharesChanged(
        address payable[] oldBeneficiaries,
        uint256[] oldShares,
        address payable[] newBeneficiaries,
        uint256[] newShares
    );

    constructor(
        address payable[] memory _beneficiaries,
        uint256[] memory _shares
    ) {
        changeBeneficiariesShares(_beneficiaries, _shares);
    }

    function changeBeneficiariesShares(
        address payable[] memory _beneficiaries,
        uint256[] memory _shares
    ) public onlyOwner override {
        uint256 sharesSum = 0;
        for (uint256 i = 0; i < _shares.length; i++) {
            sharesSum += _shares[i];
        }

        require(sharesSum == 10000, "nope");
        require(_beneficiaries.length == _shares.length, "need same length");
        emit BeneficiarySharesChanged(
            beneficiaries,
            shares,
            _beneficiaries,
            _shares
        );
        beneficiaries = _beneficiaries;
        shares = _shares;
    }

    function getBeneficiariesAndShares() external view override returns(address[] memory, uint256[] memory) {
        address[] memory _beneficiaries = new address[](beneficiaries.length);
        uint256[] memory _shares = new uint256[](shares.length);

        for (uint256 i = 0; i < beneficiaries.length; i++) {
           _beneficiaries[i] = beneficiaries[i];
           _shares[i] = shares[i];
        }

        return (_beneficiaries, _shares);
    }

    receive() external payable {
        emit RoyaltiesReceived(msg.sender, msg.value);
    }

    function distribute() external override {
        uint amount = address(this).balance;

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            beneficiaries[i].transfer((amount * shares[i]) / 10000);
        }

        emit RoyaltiesPaid(amount, beneficiaries, shares);
    }
}
