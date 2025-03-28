// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract ForkTest is Test {
    string constant ALCHEMY_API_KEY = "_zx76GqlQpcxutEzWiwiqmuzLFh6ZNML";
    string baseRpcUrl = string(abi.encodePacked("https://base-mainnet.g.alchemy.com/v2/", ALCHEMY_API_KEY));

    function setUp() public {
        uint256 forkId = vm.createSelectFork(baseRpcUrl);
        console.log("Fork ID:", forkId);
        console.log("Block number:", block.number);
    }

    function testFork() public {
        assertTrue(true); // Dummy test
    }
}