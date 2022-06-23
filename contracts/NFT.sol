// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC2981/ERC2981PerTokenRoyalties.sol";
import "hardhat/console.sol";

contract NFT is ERC721URIStorage, Ownable, ERC2981PerTokenRoyalties {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    address contractAddress;

    /// @inheritdoc	ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC2981Base)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    constructor(address marketplaceAddress) ERC721("Superfist", "SPFT") {
        contractAddress = marketplaceAddress;
    }

    function createToken(
        string memory tokenURI,
        address royaltyRecipient, // Address singolo o address di un royaltySplitter
        uint256 royaltyPercent // percentuale della royalty sulla sale finale
    ) public returns (uint256) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);
        
        setApprovalForAll(contractAddress, true);

        _setTokenRoyalty(newItemId, royaltyRecipient, royaltyPercent);

        return newItemId;
    }

    function getTokensOf(address _address) external view returns (uint256[] memory) {
        uint256 balanceOfAddress = balanceOf(_address);

        uint256 counter = 0;

        uint256[] memory tokenIds = new uint256[](balanceOfAddress);
        for(uint i = 1; i <= _tokenIds.current() && counter < balanceOfAddress; i++) {
            if(ownerOf(i) == _address) {
                tokenIds[counter] = i;
                counter++;
            }
        }

        return tokenIds;
    }
}
