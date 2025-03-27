// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV3PriceManipulationTest is Test {
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant POOL = 0x60594a405d53811d3BC4766596EFD80fd545A270;
    address constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    ISwapRouter public immutable router = ISwapRouter(ROUTER);
    IUniswapV3Pool public immutable pool = IUniswapV3Pool(POOL);
    IWETH public immutable weth = IWETH(WETH);

    uint24 constant FEE = 3000;
    uint256 constant SWAP_AMOUNT = 5000000 ether;

    string constant ALCHEMY_API_KEY = "FbbPbdaturO9DZOX5Ww57ySEyEq3uCgs";
    string mainnetRpcUrl = string(abi.encodePacked("https://eth-mainnet.g.alchemy.com/v2/", ALCHEMY_API_KEY));

    uint256 prevSpotPrice;
    uint256 prevTwapPrice;

    function setUp() public {
        vm.createSelectFork(mainnetRpcUrl);
        deal(DAI, address(this), SWAP_AMOUNT * 2);
        TransferHelper.safeApprove(DAI, ROUTER, type(uint256).max);
    }

    function testPriceManipulation() public {
        _skip(1);
        _logPrices();

        (uint160 sqrtPriceX96Before, , , , , , ) = pool.slot0();
        uint256 spotPriceBefore = _getPriceFromSqrtPrice(sqrtPriceX96Before);
        uint256 twapPriceBefore = getTwapPrice(300);

        uint256 ethBalanceBefore = address(this).balance;
        uint256 amountOut = executeSwap();
        weth.withdraw(amountOut);

        _skip(1);
        _logPrices();

        (uint160 sqrtPriceX96Post, , , , , , ) = pool.slot0();
        uint256 spotPricePost = _getPriceFromSqrtPrice(sqrtPriceX96Post);
        uint256 twapPricePost = getTwapPrice(300);

        uint256 ethBalancePost = address(this).balance;
        uint256 ethCost = ethBalanceBefore > ethBalancePost
            ? ethBalanceBefore - ethBalancePost
            : 0;

        uint256 spotPriceChange = _calculatePercentageChange(spotPriceBefore, spotPricePost);
        uint256 twapPriceChange = _calculatePercentageChange(twapPriceBefore, twapPricePost);

        console.log("Swap Amount (DAI):", SWAP_AMOUNT / 1e18);
        console.log("ETH Received:", amountOut / 1e18);
        console.log("ETH Cost (wei):", ethCost);
        console.log("Spot Price Before (x 1e18):", spotPriceBefore);
        console.log("Spot Price After (x 1e18):", spotPricePost);
        console.log("Spot Price Change (% * 1e6):", spotPriceChange);
        console.log("5-min TWAP Before (x 1e18):", twapPriceBefore);
        console.log("5-min TWAP After (x 1e18):", twapPricePost);
        console.log("TWAP Price Change (% * 1e6):", twapPriceChange);
    }

    function executeSwap() internal returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: DAI,
            tokenOut: WETH,
            fee: FEE,
            recipient: address(this),
            deadline: block.timestamp + 15,
            amountIn: SWAP_AMOUNT,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        return router.exactInputSingle(params);
    }

    function _skip(uint256 blocks) private {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * 12);
    }

    function _logPrices() private {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 spotPrice = _getPriceFromSqrtPrice(sqrtPriceX96);
        uint256 twapPrice = getTwapPrice(300);

        string memory spotPriceChange = _percentChangeString(prevSpotPrice, spotPrice);
        string memory twapPriceChange = _percentChangeString(prevTwapPrice, twapPrice);

        prevSpotPrice = spotPrice;
        prevTwapPrice = twapPrice;

        console.log("=> Current Prices");
        console.log("Spot Price: %e", spotPrice, spotPriceChange);
        console.log("TWAP Price: %e", twapPrice, twapPriceChange);
        console.log("");
    }

    function _getPriceFromSqrtPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return uint256(TickMath.getSqrtRatioAtTick(TickMath.getTickAtSqrtRatio(sqrtPriceX96)));
    }

    function getTwapPrice(uint32 secondsAgo) internal view returns (uint256) {
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(POOL, secondsAgo);
        return uint256(TickMath.getSqrtRatioAtTick(arithmeticMeanTick));
    }

    function _calculatePercentageChange(uint256 before, uint256 post) internal pure returns (uint256) {
        if (before == 0) return 0;
        uint256 absoluteChange = post > before ? post - before : before - post;
        return (absoluteChange * 1e6) / before;
    }

    function _percentChangeString(uint256 prev, uint256 current) private pure returns (string memory) {
        if (prev == 0) return "";
        int256 change = int256(current) - int256(prev);
        int256 percentChange = (change * 100) / int256(prev);
        if (percentChange == 0) return "";
        return string.concat(
            "(",
            percentChange > 0 ? "+" : "",
            vm.toString(percentChange),
            "%)"
        );
    }

    receive() external payable {}
}

interface IWETH {
    function withdraw(uint256 wad) external;
}