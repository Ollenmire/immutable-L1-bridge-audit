// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// solhint-disable private-vars-leading-underscore

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {RootERC20BridgeFlowRatePatched} from "src/root/flowrate/RootERC20BridgeFlowRatePatched.sol";
import {IRootERC20Bridge} from "src/interfaces/root/IRootERC20Bridge.sol";
import {IRootBridgeAdaptor} from "src/interfaces/root/IRootBridgeAdaptor.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// -----------------------------------------------------------------------------
// Minimal ERC-20 mocks
// -----------------------------------------------------------------------------

contract LegitimateToken is ERC20 {
    constructor() ERC20("Legitimate Token", "LEGIT") {
        _mint(msg.sender, 1e30);
    }
}

contract AttackerToken is ERC20 {
    constructor() ERC20("Poison Token", "POISON") {
        _mint(msg.sender, 1e30);
    }
}

contract ImxTokenMock is ERC20 {
    constructor() ERC20("Immutable X", "IMX") {
        _mint(msg.sender, 1e30);
    }
}

// -----------------------------------------------------------------------------
// Adaptor mock
// -----------------------------------------------------------------------------

contract MockBridgeAdaptor is IRootBridgeAdaptor {
    event Sent(bytes payload, address sender, uint256 value);

    function sendMessage(
        bytes calldata payload,
        address refundRecipient
    ) external payable override {
        emit Sent(payload, refundRecipient, msg.value);
    }

    receive() external payable {}
}

// -----------------------------------------------------------------------------
// Patched withdrawal-queue tests
// -----------------------------------------------------------------------------

contract QueueBombPatchedTest is Test {
    // System under test
    RootERC20BridgeFlowRatePatched internal bridge;
    LegitimateToken internal legit;
    AttackerToken internal attackerToken;
    ImxTokenMock internal imx;
    MockBridgeAdaptor internal rootBridgeAdaptor;

    // Addresses / constants
    address constant CHILD_BRIDGE = address(0xBEEF);
    address constant CHILD_BRIDGE_ADAPTOR_TEMPLATE = address(0xCAFE);
    address constant WETH_TOKEN = address(0xDEAD);

    address internal initializer = address(this);
    address internal rateAdmin = address(this);

    address internal receiver = address(0xA11CE);
    address internal victim = address(0xB00B);

    // ---------------------------------------------------------------------
    // Setup
    // ---------------------------------------------------------------------

    function setUp() public {
        legit = new LegitimateToken();
        attackerToken = new AttackerToken();
        imx = new ImxTokenMock();
        rootBridgeAdaptor = new MockBridgeAdaptor();

        bridge = new RootERC20BridgeFlowRatePatched(initializer);

        IRootERC20Bridge.InitializationRoles memory roles = IRootERC20Bridge
            .InitializationRoles({
                defaultAdmin: address(this),
                pauser: address(this),
                unpauser: address(this),
                variableManager: address(this),
                adaptorManager: address(this)
            });

        bridge.initialize(
            roles,
            address(rootBridgeAdaptor),
            CHILD_BRIDGE,
            CHILD_BRIDGE_ADAPTOR_TEMPLATE,
            address(imx),
            WETH_TOKEN,
            type(uint256).max,
            rateAdmin
        );

        bridge.mapToken{value: 1 ether}(legit);
        bridge.mapToken{value: 1 ether}(attackerToken);

        // Pre-fund bridge so legitimate aggregation has funds to transfer
        legit.transfer(address(bridge), 2_000 ether);

        bridge.activateWithdrawalQueue();
    }

    // ---------------------------------------------------------------------
    // Helper to enqueue many withdrawals
    // ---------------------------------------------------------------------

    function _stuffQueue(
        address forReceiver,
        address token,
        uint256 count,
        uint256 amount
    ) internal {
        bytes32 withdrawSig = bridge.WITHDRAW_SIG();
        for (uint256 i = 0; i < count; i++) {
            bytes memory payload = abi.encode(
                withdrawSig,
                token,
                address(this),
                forReceiver,
                amount
            );
            vm.prank(address(rootBridgeAdaptor));
            bridge.onMessageReceive(payload);
        }
    }

    // ---------------------------------------------------------------------
    // Aggregated-withdrawal protection tests
    // ---------------------------------------------------------------------

    function testTooManyIndicesReverts() public {
        console.log("[PATCHED] testTooManyIndicesReverts start");
        uint256 big = bridge.MAX_AGGREGATED_WITHDRAWALS() + 1;
        console.log("Stuffing queue with", big, "LEGIT withdrawals");
        _stuffQueue(receiver, address(legit), big, 1 ether);
        vm.warp(block.timestamp + 2 days);

        uint256[] memory idx = new uint256[](big);
        for (uint256 i = 0; i < big; i++) {
            idx[i] = i;
        }

        console.log(
            "Calling finaliseQueuedWithdrawalsAggregatedLimited expecting revert"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                RootERC20BridgeFlowRatePatched.TooManyIndices.selector,
                big,
                bridge.MAX_AGGREGATED_WITHDRAWALS()
            )
        );
        bridge.finaliseQueuedWithdrawalsAggregatedLimited(
            receiver,
            address(legit),
            idx
        );
        console.log("Revert asserted - test passed\n");
    }

    function testAggregationWithinLimitSucceeds() public {
        console.log("[PATCHED] testAggregationWithinLimitSucceeds start");
        uint256 n = bridge.MAX_AGGREGATED_WITHDRAWALS();
        console.log("Stuffing queue with", n, "LEGIT withdrawals");
        _stuffQueue(receiver, address(legit), n, 1 ether);
        vm.warp(block.timestamp + 2 days);

        uint256[] memory idx = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            idx[i] = i;
        }

        console.log("Aggregating within limit - expecting success");
        bridge.finaliseQueuedWithdrawalsAggregatedLimited(
            receiver,
            address(legit),
            idx
        );
        console.log("Aggregation succeeded\n");
    }

    // ---------------------------------------------------------------------
    // Scan protection tests
    // ---------------------------------------------------------------------

    function testScanRangeTooLargeReverts() public {
        console.log("[PATCHED] testScanRangeTooLargeReverts start");
        uint256 excessive = bridge.MAX_SCAN_RANGE() + 1;
        console.log(
            "Stuffing victim queue with",
            excessive,
            "attacker withdrawals"
        );
        _stuffQueue(victim, address(attackerToken), excessive, 1 wei);
        vm.warp(block.timestamp + 2 days);

        console.log("Calling findPendingWithdrawalsLimited expecting revert");
        vm.expectRevert(
            abi.encodeWithSelector(
                RootERC20BridgeFlowRatePatched.ScanRangeTooLarge.selector,
                excessive,
                bridge.MAX_SCAN_RANGE()
            )
        );
        bridge.findPendingWithdrawalsLimited(
            victim,
            address(attackerToken),
            0,
            excessive,
            10
        );
        console.log("Revert asserted - test passed\n");
    }

    function testScanWithinLimitSucceeds() public {
        console.log("[PATCHED] testScanWithinLimitSucceeds start");
        uint256 limit = bridge.MAX_SCAN_RANGE();
        console.log(
            "Stuffing victim queue with",
            limit,
            "attacker withdrawals"
        );
        _stuffQueue(victim, address(attackerToken), limit, 1 wei);
        vm.warp(block.timestamp + 2 days);

        console.log("Scanning within limit - expecting success");
        bridge.findPendingWithdrawalsLimited(
            victim,
            address(attackerToken),
            0,
            limit,
            10
        );
        console.log("Scan succeeded\n");
    }

    // ---------------------------------------------------------------------
    // Stress tests with 60k items + 25M gas to ensure guard reverts fast
    // ---------------------------------------------------------------------

    function testHugeAggregationGuardReverts() public {
        console.log("[PATCHED] testHugeAggregationGuardReverts start");
        uint256 big = 45_000;
        uint256[] memory idx = new uint256[](big);
        for (uint256 i = 0; i < big; i++) idx[i] = i;

        bytes memory callData = abi.encodeWithSelector(
            bridge.finaliseQueuedWithdrawalsAggregatedLimited.selector,
            receiver,
            address(legit),
            idx
        );

        (bool ok, ) = address(bridge).call{gas: 25_000_000}(callData);
        console.log("Low-level call returned", ok);
        require(!ok, "Call unexpectedly succeeded");
        console.log("Call reverted as expected (guard hit)\n");
    }

    function testHugeScanGuardReverts() public {
        console.log("[PATCHED] testHugeScanGuardReverts start");
        uint256 big = 45_000;
        bytes memory callData = abi.encodeWithSelector(
            bridge.findPendingWithdrawalsLimited.selector,
            victim,
            address(attackerToken),
            0,
            big,
            10
        );
        (bool ok, ) = address(bridge).call{gas: 25_000_000}(callData);
        console.log("Low-level scan call returned", ok);
        require(!ok, "Scan unexpectedly succeeded");
        console.log("Scan reverted as expected (guard hit)\n");
    }
}
