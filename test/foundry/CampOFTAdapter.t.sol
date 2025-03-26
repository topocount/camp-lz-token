// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Mock imports
import {OFTMock} from "../mocks/OFTMock.sol";
//import {OFTAdapterMock} from "../mocks/OFTAdapterMock.sol";
import {CampOFTAdapter} from "../../contracts/CampOFTAdapter.sol";
import {WETH9} from "../../contracts/WETH9.sol";
import {CampBridge} from "../../contracts/CampBridge.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {OFTComposerMock} from "../mocks/OFTComposerMock.sol";

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

contract CampOFTAdapterTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;

    WETH9 private aToken;
    CampOFTAdapter private aOFTAdapter;
    OFTMock private bOFT;
    CampBridge private bridge;

    address private userA = address(0x1);
    address private userB = address(0x2);
    address private userC = address(0x3);
    uint256 private initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        //aToken = ERC20Mock(_deployOApp(type(ERC20Mock).creationCode, abi.encode("Token", "TOKEN")));
        aToken = new WETH9();

        aOFTAdapter = CampOFTAdapter(
            payable(_deployOApp(
                type(CampOFTAdapter).creationCode, abi.encode(address(aToken), address(endpoints[aEid]), address(this))
            ))
        );

        bOFT = OFTMock(
            _deployOApp(
                type(OFTMock).creationCode, abi.encode("Token", "TOKEN", address(endpoints[bEid]), address(this))
            )
        );

        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(aOFTAdapter);
        ofts[1] = address(bOFT);
        this.wireOApps(ofts);

        // mint tokens
        //aToken.mint(userA, initialBalance);
        hoax(userA);
        aToken.deposit{value: initialBalance}();
    }

    function test_constructor() public view {
        assertEq(aOFTAdapter.owner(), address(this));
        assertEq(bOFT.owner(), address(this));

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(aToken.balanceOf(address(aOFTAdapter)), 0);
        assertEq(bOFT.balanceOf(userB), 0);

        assertEq(aOFTAdapter.token(), address(aToken));
        assertEq(bOFT.token(), address(bOFT));
    }

    function test_send_oft_adapter() public {
        uint256 tokensToSend = 1 ether;
        //bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        // try 100k in gas
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userA), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aOFTAdapter.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(aToken.balanceOf(address(aOFTAdapter)), 0);
        assertEq(bOFT.balanceOf(userB), 0);

        vm.prank(userA);
        aToken.approve(address(aOFTAdapter), tokensToSend);

        vm.prank(userA);
        aOFTAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(aToken.balanceOf(address(aOFTAdapter)), tokensToSend);
        assertEq(bOFT.balanceOf(userA), tokensToSend);
    }

    function test_send_bridge() public {
        uint256 initialEthBalance = userA.balance;
        bridge = new CampBridge(aToken, aOFTAdapter);
        uint256 tokensToSend = 1 ether;
        //bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        // try 100k in gas
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(100_000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userA), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aOFTAdapter.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(aToken.balanceOf(address(aOFTAdapter)), 0);
        assertEq(bOFT.balanceOf(userB), 0);

        //vm.prank(userA);
        //aToken.approve(address(aOFTAdapter), tokensToSend);

        //vm.prank(userA);
        //aOFTAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        vm.prank(userA);
        bridge.send{value: fee.nativeFee + tokensToSend}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        // initial weth balance should be untouched
        assertEq(aToken.balanceOf(userA), initialBalance);
        // ensure the balance difference is just gas
        assertLt(initialEthBalance - tokensToSend - userA.balance, 2.5e8);
        assertEq(aToken.balanceOf(address(aOFTAdapter)), tokensToSend);
        assertEq(bOFT.balanceOf(userA), tokensToSend);

        // try sending funds back across the bridge
        uint256 tokensToSendBack = 0.5 ether;
        assertEq(userC.balance, 0);

        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);
        sendParam =
            SendParam(aEid, addressToBytes32(userC), tokensToSendBack, tokensToSendBack, options, "", "");
        fee = bOFT.quoteSend(sendParam, false);

        vm.prank(userA);
        bOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(aEid, addressToBytes32(address(aOFTAdapter)));

        assertEq(bOFT.balanceOf(userA), tokensToSendBack);
        // ensure eth is distributed instead of weth
        assertEq(userC.balance, tokensToSendBack);
    }

    // disabled, since we aren't attempting to interact with a composer
    function test_send_oft_adapter_compose_msg() private {
        uint256 tokensToSend = 1 ether;

        OFTComposerMock composer = new OFTComposerMock();

        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(0, 500000, 0);
        bytes memory composeMsg = hex"1234";
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(address(composer)), tokensToSend, tokensToSend, options, composeMsg, "");
        MessagingFee memory fee = aOFTAdapter.quoteSend(sendParam, false);

        assertEq(aToken.balanceOf(userA), initialBalance);
        assertEq(aToken.balanceOf(address(aOFTAdapter)), 0);
        assertEq(bOFT.balanceOf(userB), 0);

        vm.prank(userA);
        aToken.approve(address(aOFTAdapter), tokensToSend);

        vm.prank(userA);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            aOFTAdapter.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        // lzCompose params
        uint32 dstEid_ = bEid;
        address from_ = address(bOFT);
        bytes memory options_ = options;
        bytes32 guid_ = msgReceipt.guid;
        address to_ = address(composer);
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce, aEid, oftReceipt.amountReceivedLD, abi.encodePacked(addressToBytes32(userA), composeMsg)
        );
        this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

        assertEq(aToken.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(aToken.balanceOf(address(aOFTAdapter)), tokensToSend);
        assertEq(bOFT.balanceOf(address(composer)), tokensToSend);

        assertEq(composer.from(), from_);
        assertEq(composer.guid(), guid_);
        assertEq(composer.message(), composerMsg_);
        assertEq(composer.executor(), address(this));
        assertEq(composer.extraData(), composerMsg_); // default to setting the extraData to the message as well to test
    }

    // TODO import the rest of oft tests?
}
