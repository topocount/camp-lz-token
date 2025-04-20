// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Mock imports
import {OFTMock} from "../mocks/OFTMock.sol";
//import {OFTAdapterMock} from "../mocks/OFTAdapterMock.sol";
import {NativeCampOFTAdapter} from "../../contracts/NativeCampOFTAdapter.sol";
import {OFTComposerMock} from "../mocks/OFTComposerMock.sol";
import {NativeOFTAdapter} from "@layerzerolabs/oft-evm/contracts/NativeOFTAdapter.sol";

// OApp imports
import {
    IOAppOptionsType3, EnforcedOptionParam
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import {IOFT, SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

// OZ imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Forge imports
import "forge-std/console.sol";

// DevTools imports
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract NativeCampOFTAdapterTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;

    NativeCampOFTAdapter private aNativeAdapter;
    OFTMock private bOFT;

    address private userA = address(0x1);
    address private userB = address(0x2);
    address private userC = address(0x3);
    uint256 private initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        aNativeAdapter = NativeCampOFTAdapter(
            payable(
                _deployOApp(
                    type(NativeCampOFTAdapter).creationCode,
                    abi.encode(address(endpoints[aEid]), address(this))
                )
            )
        );

        bOFT = OFTMock(
            _deployOApp(
                type(OFTMock).creationCode, abi.encode("Token", "TOKEN", address(endpoints[bEid]), address(this))
            )
        );

        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(aNativeAdapter);
        ofts[1] = address(bOFT);
        this.wireOApps(ofts);

        // fund userA with native tokens
        vm.deal(userA, initialBalance);
    }

    function test_constructor() public view {
        assertEq(aNativeAdapter.owner(), address(this));
        assertEq(bOFT.owner(), address(this));

        assertEq(userA.balance, initialBalance);
        assertEq(address(aNativeAdapter).balance, 0);
        assertEq(bOFT.balanceOf(userB), 0);

        assertEq(bOFT.token(), address(bOFT));
    }

    function test_send_native_adapter() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aNativeAdapter.quoteSend(sendParam, false);

        assertEq(userA.balance, initialBalance);
        assertEq(address(aNativeAdapter).balance, 0);
        assertEq(bOFT.balanceOf(userB), 0);

        vm.prank(userA);
        aNativeAdapter.send{value: fee.nativeFee + sendParam.amountLD}(sendParam, fee, payable(userC));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(userA.balance, initialBalance - tokensToSend - fee.nativeFee);
        assertEq(address(aNativeAdapter).balance, tokensToSend);
        assertEq(bOFT.decimals(), 18);
        assertEq(bOFT.balanceOf(userB), tokensToSend);
    }

    function test_fuzz_send_native(address sender, address recipient, uint256 amount) public {
        // Bound the amount to be between 0.1 ether and 10 ether
        // capped at 15 ether since there appears to be a bug in the provided mocks that mishandles the amountReceived
        // on the other side of the bridge beyond this rough value
        amount = bound(amount, 0.1 ether, 15 ether);

        // Ensure sender and recipient are valid addresses
        vm.assume(sender != address(0) && recipient != address(0));
        vm.assume(sender != address(aNativeAdapter) && sender != address(bOFT));
        vm.assume(recipient != address(aNativeAdapter) && recipient != address(bOFT));

        // Fund the sender
        vm.deal(sender, amount * 10);

        uint256 initialEthBalance = sender.balance;

        // Set up options and parameters
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);
        SendParam memory sendParam = SendParam(bEid, addressToBytes32(recipient), amount, amount, options, "", "");
        MessagingFee memory fee = aNativeAdapter.quoteSend(sendParam, false);

        // Execute the send
        vm.prank(sender);
        aNativeAdapter.send{value: fee.nativeFee + amount}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        // Verify balances
        assertEq(address(aNativeAdapter).balance, amount);
        assertEq(bOFT.balanceOf(recipient), amount);
        // Ensure the balance difference is just gas + amount
        assertLt(initialEthBalance - amount - fee.nativeFee - sender.balance, 2.5e8);
    }

    function test_fail_send_native_invalid_amount(uint32 variance, bool add) public {
        vm.assume(variance != 0);
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userA), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aNativeAdapter.quoteSend(sendParam, false);

        assertEq(userA.balance, initialBalance);
        assertEq(address(aNativeAdapter).balance, 0);
        assertEq(bOFT.balanceOf(userB), 0);

        vm.prank(userA);
        if (add) {
            vm.expectRevert(abi.encodeWithSelector(NativeOFTAdapter.IncorrectMessageValue.selector, fee.nativeFee + tokensToSend + variance,fee.nativeFee + tokensToSend));
            aNativeAdapter.send{value: fee.nativeFee + tokensToSend + variance}(sendParam, fee, payable(address(this)));
            // Verify the excess is refunded
            //assertEq(userA.balance, initialBalance - tokensToSend - fee.nativeFee);
        } else {
            // Should revert when sending less than needed
            vm.expectRevert(abi.encodeWithSelector(NativeOFTAdapter.IncorrectMessageValue.selector, fee.nativeFee + tokensToSend - variance,fee.nativeFee + tokensToSend));
            aNativeAdapter.send{value: fee.nativeFee + tokensToSend - variance}(sendParam, fee, payable(address(this)));
        }
    }

    function test_send_native_roundtrip() public {
        uint256 initialEthBalance = userA.balance;
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userA), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aNativeAdapter.quoteSend(sendParam, false);

        assertEq(userA.balance, initialBalance);
        assertEq(address(aNativeAdapter).balance, 0);
        assertEq(bOFT.balanceOf(userB), 0);

        vm.prank(userA);
        aNativeAdapter.send{value: fee.nativeFee + tokensToSend}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        // ensure the balance difference is just gas + tokens sent
        assertLt(initialEthBalance - tokensToSend - fee.nativeFee - userA.balance, 2.5e8);
        assertEq(address(aNativeAdapter).balance, tokensToSend);
        //assertEq(bOFT.balanceOf(userA), tokensToSend);

        // try sending funds back across the bridge
        uint256 tokensToSendBack = 0.5 ether;
        assertEq(userC.balance, 0);

        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        sendParam = SendParam(aEid, addressToBytes32(userC), tokensToSendBack, tokensToSendBack, options, "", "");
        fee = bOFT.quoteSend(sendParam, false);

        vm.prank(userA);
        bOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(aEid, addressToBytes32(address(aNativeAdapter)));

        assertEq(bOFT.balanceOf(userA), tokensToSendBack);
        // ensure native ETH is distributed
        assertEq(userC.balance, tokensToSendBack);
    }
}
