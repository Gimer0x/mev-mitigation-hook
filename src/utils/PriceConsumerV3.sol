// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DataFeedsScript} from "lib/foundry-chainlink-toolkit/script/feeds/DataFeed.s.sol";

contract PriceConsumerV3 {
    DataFeedsScript public volatilityFeed;

    // 0x03121C1a9e6b88f56b27aF5cc065ee1FaF3CB4A9
    constructor(address _priceFeed) {
        volatilityFeed = DataFeedsScript(
            _priceFeed
        );
    }

    function getLatestRoundData() external view returns (int256 volatility) {
        (
            /* uint80 roundID */,
            int256 answer,
            /* uint256 startedAt */,
            /* uint256 updatedAt */,
            /* uint80 answeredInRound */
        ) = volatilityFeed.getLatestRoundData();

        volatility = (answer * 100) / int256(10 ** uint256(getDecimals()));
    }

    function getDecimals()
        public
        view
        returns (uint8)
    {
        return volatilityFeed.getDecimals();
    }
}