// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV3PriceManipulationTest is Test {
    // Constants for Optimism Mainnet addresses
    address constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // Uniswap V3 Factory (same on Optimism)
    address constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;  // Uniswap V3 SwapRouter (same on Optimism)
    address constant LINK = 0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6;   // Chainlink Token on Optimism
    address constant WETH = 0x4200000000000000000000000000000000000006;  // WETH on Optimism

    // Pool parameters
    uint24 constant FEE = 3000;           // 0.3% fee tier
    uint256 constant SWAP_AMOUNT = 12000 ether; // 12,500 LINK (assuming 18 decimals)

    // Contract instances
    IUniswapV3Factory public immutable factory = IUniswapV3Factory(FACTORY);
    ISwapRouter public immutable router = ISwapRouter(ROUTER);
    IUniswapV3Pool public pool;

    // RPC URL for Optimism Mainnet fork
    string constant ALCHEMY_API_KEY = "FbbPbdaturO9DZOX5Ww57ySEyEq3uCgs";
    string optimismRpcUrl = string(abi.encodePacked("https://opt-mainnet.g.alchemy.com/v2/", ALCHEMY_API_KEY));

    uint256 prevSpotPrice;
    uint256 prevTwapPrice;

    function setUp() public {
        vm.createSelectFork(optimismRpcUrl);
        console.log("Forked block number:", block.number);

        address poolAddress = factory.getPool(LINK, WETH, FEE);
        require(poolAddress != address(0), "Pool does not exist");
        pool = IUniswapV3Pool(poolAddress);
        console.log("Pool Address:", address(pool));

        deal(LINK, address(this), SWAP_AMOUNT * 2); // 
        TransferHelper.safeApprove(LINK, address(router), type(uint256).max);
    }

    function testPriceManipulation() public {
    uint256 linkBalanceInitial = IERC20(LINK).balanceOf(address(this));

    _skip(1); // Block 133719783, T + 12
    _logPrices(); // Initial prices

    (uint160 sqrtPriceX96Before, , , , , , ) = pool.slot0();
    uint256 spotPriceBefore = _getPriceFromSqrtPrice(sqrtPriceX96Before);
    uint256 twapPriceBefore = getTwapPrice(300); // 5-min TWAP

    // First swap: LINK -> WETH
    uint256 amountOutWeth = executeSwap(LINK, WETH, SWAP_AMOUNT);
    TransferHelper.safeApprove(WETH, address(router), type(uint256).max);

    _skip(1); // Advance 300 seconds (25 blocks * 12 sec/block)
    _logPrices(); // Prices after swap, with TWAP reflecting new price

    (uint160 sqrtPriceX96After, , , , , , ) = pool.slot0();
    uint256 spotPriceAfter = _getPriceFromSqrtPrice(sqrtPriceX96After);
    uint256 twapPriceAfter = getTwapPrice(300); // 5-min TWAP

    // Second swap: WETH -> LINK
    uint256 amountOutLink = executeSwap(WETH, LINK, amountOutWeth);

    uint256 linkBalanceFinal = IERC20(LINK).balanceOf(address(this));
    uint256 linkDifference = linkBalanceInitial > linkBalanceFinal
        ? linkBalanceInitial - linkBalanceFinal
        : linkBalanceFinal - linkBalanceInitial;

    uint256 spotPriceChange = _calculatePercentageChange(spotPriceBefore, spotPriceAfter);
    uint256 twapPriceChange = _calculatePercentageChange(twapPriceBefore, twapPriceAfter);

    // Log results
    console.log("Initial LINK Balance:", linkBalanceInitial / 1e18);
    console.log("Swap Amount (LINK):", SWAP_AMOUNT / 1e18);
    console.log("WETH Received:", amountOutWeth / 1e18);
    console.log("LINK Received from Reverse Swap:", amountOutLink / 1e18);
    console.log("Final LINK Balance:", linkBalanceFinal / 1e18);
    console.log("LINK Difference (abs):", linkDifference / 1e18);
    console.log("Spot Price Before (LINK/WETH x 1e18):", spotPriceBefore);
    console.log("Spot Price After (LINK/WETH x 1e18):", spotPriceAfter);
    console.log("Spot Price Change (% * 1e6):", spotPriceChange);
    console.log("5-min TWAP Before (x 1e18):", twapPriceBefore);
    console.log("5-min TWAP After (x 1e18):", twapPriceAfter);
    console.log("TWAP Price Change (% * 1e6):", twapPriceChange);
}

    function executeSwap(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: FEE,
            recipient: address(this),
            deadline: block.timestamp + 15,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        return router.exactInputSingle(params);
    }

    function _skip(uint256 blocks) private {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * 12); // Assume 12 sec/block
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
        console.log("Spot Price (LINK/WETH x 1e18): %s", spotPrice, spotPriceChange);
        console.log("TWAP Price (LINK/WETH x 1e18): %s", twapPrice, twapPriceChange);
        console.log("");
    }

    function _getPriceFromSqrtPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        // For LINK/WETH pool: token0 = LINK, token1 = WETH
        // sqrtPriceX96 = sqrt(WETH/LINK) * 2^96
        // Price = (sqrtPriceX96^2 / 2^192) = WETH/LINK, invert for LINK/WETH
        uint256 priceX192 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 price = (1 << 192) / priceX192; // LINK/WETH
        return price * 1e18; // Scale to 1e18
    }

    function getTwapPrice(uint32 secondsAgo) internal view returns (uint256) {
        (int24 arithmeticMeanTick, ) = OracleLibrary.consult(address(pool), secondsAgo);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        return _getPriceFromSqrtPrice(sqrtPriceX96);
    }

    function _calculatePercentageChange(uint256 before, uint256 post) internal pure returns (uint256) {
        if (before == 0) return 0;
        uint256 absoluteChange = post > before ? post - before : before - post;
        return (absoluteChange * 1e6) / before; // Percentage * 1e6
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

// forge test --match-test testPriceManipulation -vvv
