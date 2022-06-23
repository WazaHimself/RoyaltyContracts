// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "./ERC2981/IERC2981Royalties.sol";

import "hardhat/console.sol";

import "./IRoyaltySplitter.sol";

contract NFTMarket is ReentrancyGuard {
    bytes4 ROYALTY_SPLITTER_INTERFACE_ID = 0xaab2f986;

    using Counters for Counters.Counter;
    Counters.Counter private _itemIds;
    Counters.Counter private _itemsSold;
    Counters.Counter private _itemsCanceled;

    uint256 public totalRoyalties;
    mapping(uint256 => uint256) public royaltiesPerToken;

    enum MarketItemState {
        ON_SALE,
        SOLD,
        SALE_CANCELED
    }

    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    address payable owner;

    function checkRoyalties(address _contract) internal view returns (bool) {
        bool success = IERC165(_contract).supportsInterface(
            _INTERFACE_ID_ERC2981
        );
        return success;
    }

    constructor() {
        owner = payable(msg.sender);
    }

    struct MarketItem {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address creator;
        address payable seller;
        address payable owner;
        uint256 price;
        MarketItemState state;
    }

    mapping(uint256 => MarketItem) private idToMarketItem;

    event MarketItemCreated(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address creator,
        address seller,
        address owner,
        uint256 price,
        MarketItemState state
    );

    event MarketItemSold(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address creator,
        address seller,
        address owner,
        uint256 price,
        MarketItemState state
    );

    /* Places an item for sale on the marketplace */
    function createMarketItem(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) public payable nonReentrant {
        require(price > 0, "Price must be at least 1 wei");

        _itemIds.increment();

        uint256 itemId = _itemIds.current();
        idToMarketItem[itemId] = MarketItem(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            payable(msg.sender),
            payable(address(this)),
            price,
            MarketItemState.ON_SALE
        );

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        emit MarketItemCreated(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            msg.sender,
            address(this),
            price,
            MarketItemState.ON_SALE
        );
    }

        /* Places an item for sale on the marketplace */
    function createAndTransferMarketItem(
        address nftContract,
        uint256 tokenId,
        address to
    ) public payable nonReentrant {
        _itemIds.increment();

        uint256 itemId = _itemIds.current();
        idToMarketItem[itemId] = MarketItem(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            payable(msg.sender),
            payable(to),
            0,
            MarketItemState.SOLD
        );

        IERC721(nftContract).transferFrom(msg.sender, to, tokenId);

        emit MarketItemCreated(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            msg.sender,
            address(to),
            0,
            MarketItemState.SOLD
        );

        _itemsSold.increment();
    }

    /* Cancels the sale of a marketplace item */
    function cancelMarketSale(uint256 itemId) public payable nonReentrant {
        address seller = idToMarketItem[itemId].seller;
        require(
            idToMarketItem[itemId].state == MarketItemState.ON_SALE,
            "This item is not on sale"
        );
        require(msg.sender == seller, "Only seller can cancel sale");

        idToMarketItem[itemId].state = MarketItemState.SALE_CANCELED;
        idToMarketItem[itemId].seller = payable(address(0));
        idToMarketItem[itemId].owner = payable(msg.sender);

        IERC721(idToMarketItem[itemId].nftContract).transferFrom(
            address(this),
            msg.sender,
            idToMarketItem[itemId].tokenId
        );

        _itemsCanceled.increment();
    }

    /* allows someone to resell a token they have purchased */
    function resellToken(uint256 itemId, uint256 price) public payable {
        MarketItemState curState = idToMarketItem[itemId].state;

        require(
            idToMarketItem[itemId].owner == msg.sender,
            "Only item owner can perform this operation"
        );
        require(
            idToMarketItem[itemId].state != MarketItemState.ON_SALE,
            "This item is already on sale"
        );

        idToMarketItem[itemId].state = MarketItemState.ON_SALE;
        idToMarketItem[itemId].price = price;
        idToMarketItem[itemId].seller = payable(msg.sender);
        idToMarketItem[itemId].owner = payable(address(this));

        IERC721(idToMarketItem[itemId].nftContract).transferFrom(
            msg.sender,
            address(this),
            idToMarketItem[itemId].tokenId
        );

        if(curState == MarketItemState.SOLD) _itemsSold.decrement();
        else if (curState == MarketItemState.SALE_CANCELED) _itemsCanceled.decrement();
    }

    /* Creates the sale of a marketplace item */
    /* Transfers ownership of the item, as well as funds between parties */
    function createMarketSale(address nftContract, uint256 itemId)
        public
        payable
        nonReentrant
    {
        uint256 price = idToMarketItem[itemId].price;
        uint256 tokenId = idToMarketItem[itemId].tokenId;
        require(
            idToMarketItem[itemId].state == MarketItemState.ON_SALE,
            "This item is not on sale"
        );
        require(
            msg.value == price,
            "Please submit the asking price in order to complete the purchase"
        );

        uint256 finalTransfer = msg.value;
        // Here I check if the nftContract supports EIP2981 and if we are in a secondary sale
        if (
            checkRoyalties(nftContract) &&
            idToMarketItem[itemId].creator != idToMarketItem[itemId].seller
        ) {
            (address receiver, uint256 royaltyAmount) = IERC2981Royalties(
                nftContract
            ).royaltyInfo(tokenId, msg.value);

            finalTransfer -= royaltyAmount;
            royaltiesPerToken[tokenId] += royaltyAmount;
            totalRoyalties += royaltyAmount;

            payable(receiver).transfer(royaltyAmount);
        }

        // Here i calculate Mktplace royalties and
        uint256 marketplaceRoyalties = (msg.value * 250) / 10000;
        finalTransfer -= marketplaceRoyalties;

        payable(owner).transfer(marketplaceRoyalties);

        idToMarketItem[itemId].seller.transfer(finalTransfer);
        IERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        idToMarketItem[itemId].owner = payable(msg.sender);

        idToMarketItem[itemId].state = MarketItemState.SOLD;
        _itemsSold.increment();

        emit MarketItemSold(
            itemId,
            nftContract,
            tokenId,
            idToMarketItem[itemId].creator,
            idToMarketItem[itemId].seller,
            msg.sender,
            price,
            MarketItemState.SOLD
        );
    }

    /* Returns all unsold market items */
    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint256 itemCount = _itemIds.current();
        uint256 unsoldItemCount = _itemIds.current() - _itemsSold.current() - _itemsCanceled.current();
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        for (uint256 i = 0; i < itemCount; i++) {
            if (idToMarketItem[i + 1].owner == address(this)) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns onlyl items that a user has purchased */
    function fetchMyNFTs() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _itemIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].owner == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].owner == msg.sender) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns only items a user has created */
    function fetchItemsCreated() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _itemIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].seller == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].seller == msg.sender) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns only items a user has created */
    function fetchAllItems() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _itemIds.current();
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](totalItemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            uint256 currentId = i + 1;
            MarketItem storage currentItem = idToMarketItem[currentId];
            items[currentIndex] = currentItem;
            currentIndex += 1;
        }
        return items;
    }

        /* Returns only items a user has created */
    function fetchMyItemsWithRoyalties() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _itemIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            uint256 tokenId = idToMarketItem[i + 1].tokenId;
            address nftContract = idToMarketItem[i + 1].nftContract;
            
            (address _receiver,) = IERC2981Royalties(nftContract).royaltyInfo(tokenId, 0);

            if(_receiver == msg.sender) itemCount++;
            else if (IERC165(_receiver).supportsInterface(ROYALTY_SPLITTER_INTERFACE_ID)) {
                (address[] memory beneficiaries,) = IRoyaltySplitter(_receiver).getBeneficiariesAndShares();

                bool found = false;
                for (uint256 j = 0; j < beneficiaries.length && !found; j++) {
                    if (beneficiaries[j] == msg.sender) found = true;
                }

                if(found) {
                    itemCount++;
                }
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            uint256 tokenId = idToMarketItem[i + 1].tokenId;
            address nftContract = idToMarketItem[i + 1].nftContract;
            
            (address _receiver,) = IERC2981Royalties(nftContract).royaltyInfo(tokenId, 0);

            if(_receiver == msg.sender) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
            else if (IERC165(_receiver).supportsInterface(ROYALTY_SPLITTER_INTERFACE_ID)) {
                (address[] memory beneficiaries,) = IRoyaltySplitter(_receiver).getBeneficiariesAndShares();

                bool found = false;
                for (uint256 j = 0; j < beneficiaries.length && !found; j++) {
                    if (beneficiaries[j] == msg.sender) found = true;
                }

                if(found) {
                    uint256 currentId = i + 1;
                    MarketItem storage currentItem = idToMarketItem[currentId];
                    items[currentIndex] = currentItem;
                    currentIndex += 1;
                }
            }
        }
                    
        return items;
    }
}
