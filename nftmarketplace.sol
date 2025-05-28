// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTMarketplace is ERC721URIStorage, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _itemsSold;

    uint256 public listingPrice = 0.025 ether;
    
    struct MarketItem {
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        bool sold;
        string category;
        uint256 timestamp;
    }

    mapping(uint256 => MarketItem) private idToMarketItem;
    mapping(address => uint256[]) private ownerToTokens;

    event MarketItemCreated(
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold,
        string category
    );

    event MarketItemSold(
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
    );

    event NFTMinted(
        uint256 indexed tokenId,
        address creator,
        string tokenURI,
        string category
    );

    constructor() ERC721("NFT Marketplace", "NFTM") Ownable(msg.sender) {}

    /**
     * @dev Core Function 1: Mint and List NFT
     * Creates a new NFT and immediately lists it for sale
     */
    function mintAndListNFT(
        string memory tokenURI,
        uint256 price,
        string memory category
    ) public payable nonReentrant returns (uint256) {
        require(price > 0, "Price must be greater than 0");
        require(msg.value == listingPrice, "Must pay listing fee");
        require(bytes(tokenURI).length > 0, "Token URI cannot be empty");
        require(bytes(category).length > 0, "Category cannot be empty");

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        
        createMarketItem(newTokenId, price, category);
        
        emit NFTMinted(newTokenId, msg.sender, tokenURI, category);
        
        return newTokenId;
    }

    /**
     * @dev Core Function 2: Buy NFT
     * Allows users to purchase listed NFTs
     */
    function buyNFT(uint256 tokenId) public payable nonReentrant {
        uint256 price = idToMarketItem[tokenId].price;
        address seller = idToMarketItem[tokenId].seller;
        
        require(msg.value == price, "Please submit the asking price");
        require(idToMarketItem[tokenId].sold == false, "Item already sold");
        require(seller != msg.sender, "Cannot buy your own NFT");

        idToMarketItem[tokenId].owner = payable(msg.sender);
        idToMarketItem[tokenId].sold = true;
        _itemsSold.increment();

        _transfer(seller, msg.sender, tokenId);
        
        // Transfer payment to seller
        payable(seller).transfer(msg.value);
        
        // Update owner's token list
        updateOwnerTokens(seller, msg.sender, tokenId);
        
        emit MarketItemSold(tokenId, seller, msg.sender, price);
    }

    /**
     * @dev Core Function 3: Get Market Items
     * Returns all unsold market items with filtering options
     */
    function getMarketItems(
        bool onlyUnsold,
        string memory categoryFilter
    ) public view returns (MarketItem[] memory) {
        uint256 itemCount = _tokenIds.current();
        uint256 unsoldItemCount = _tokenIds.current() - _itemsSold.current();
        uint256 currentIndex = 0;
        
        // Determine array size based on filter
        uint256 arraySize = onlyUnsold ? unsoldItemCount : itemCount;
        MarketItem[] memory items = new MarketItem[](arraySize);
        
        for (uint256 i = 0; i < itemCount; i++) {
            uint256 currentId = i + 1;
            MarketItem storage currentItem = idToMarketItem[currentId];
            
            // Apply filters
            bool includeItem = true;
            
            // Filter by sold status
            if (onlyUnsold && currentItem.sold) {
                includeItem = false;
            }
            
            // Filter by category
            if (bytes(categoryFilter).length > 0) {
                if (keccak256(bytes(currentItem.category)) != keccak256(bytes(categoryFilter))) {
                    includeItem = false;
                }
            }
            
            if (includeItem && currentIndex < arraySize) {
                items[currentIndex] = currentItem;
                currentIndex++;
            }
        }
        
        // Resize array to actual size
        MarketItem[] memory result = new MarketItem[](currentIndex);
        for (uint256 i = 0; i < currentIndex; i++) {
            result[i] = items[i];
        }
        
        return result;
    }

    // Helper Functions
    function createMarketItem(
        uint256 tokenId,
        uint256 price,
        string memory category
    ) private {
        idToMarketItem[tokenId] = MarketItem(
            tokenId,
            payable(msg.sender),
            payable(address(this)),
            price,
            false,
            category,
            block.timestamp
        );

        _transfer(msg.sender, address(this), tokenId);
        
        emit MarketItemCreated(
            tokenId,
            msg.sender,
            address(this),
            price,
            false,
            category
        );
    }

    function updateOwnerTokens(
        address from,
        address to,
        uint256 tokenId
    ) private {
        // Remove token from previous owner's list
        uint256[] storage fromTokens = ownerToTokens[from];
        for (uint256 i = 0; i < fromTokens.length; i++) {
            if (fromTokens[i] == tokenId) {
                fromTokens[i] = fromTokens[fromTokens.length - 1];
                fromTokens.pop();
                break;
            }
        }
        
        // Add token to new owner's list
        ownerToTokens[to].push(tokenId);
    }

    // View Functions
    function getMyNFTs() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
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

    function getMyListedNFTs() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
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

    // Admin Functions
    function updateListingPrice(uint256 _listingPrice) public onlyOwner {
        require(_listingPrice > 0, "Listing price must be greater than 0");
        listingPrice = _listingPrice;
    }

    function withdrawFees() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner()).transfer(balance);
    }

    // Utility Functions
    function getTotalNFTs() public view returns (uint256) {
        return _tokenIds.current();
    }

    function getTotalSold() public view returns (uint256) {
        return _itemsSold.current();
    }

    function getListingPrice() public view returns (uint256) {
        return listingPrice;
    }
}
