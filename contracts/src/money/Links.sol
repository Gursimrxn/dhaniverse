// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// The few calls our contracts make to each other, as small interfaces, so each contract depends only on what it uses.
// Every link is one-way and listed under "talksTo" in docs/architecture/spec.json.

/// @notice What Treasury, CampaignEscrow, FloatManager and LuckyLedger call on HousePool.
interface IHousePool {
    function fund(uint8 bucket, uint256 amount) external;
    function payDraw(address winner, uint256 amount, bytes32 ref) external;
}

/// @notice What HousePool calls on MealCounter to buy a rescue or voucher meal for a player.
interface IMealCounter {
    function buyMealFor(address player, bytes32 item, uint256 food, uint256 maxUsdc, bytes32 ref)
        external
        returns (uint256 usdcPaid, uint256 fromRation);
}

/// @notice What FloatManager and SpiceMerchant read from CampaignEscrow.
interface ICampaignBook {
    function totalLiabilities() external view returns (uint256);
    function liveDailyCapSum() external view returns (uint256);
    function pendingRefunds() external view returns (uint256);
    function deliverTo(uint256 campaignId) external view returns (address);
    function questToken(uint256 campaignId) external view returns (address);
    function isLive(uint256 campaignId) external view returns (bool);
}

/// @notice What CampaignEscrow calls on FloatManager, which holds the sponsors' USDC.
interface IFloatManager {
    function pay(address to, uint256 amount) external;
    function release(address to, uint256 amount) external;
}
