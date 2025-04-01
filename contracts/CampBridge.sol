// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {CampOFTAdapter} from "./CampOFTAdapter.sol";
import {WETH9} from "./WETH9.sol";
import {
    IOFT,
    SendParam,
    OFTReceipt,
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

contract CampBridge {
    error Bridge_InvalidAmount();

    WETH9 weth;
    CampOFTAdapter oftAdapter;

    constructor(WETH9 weth_, CampOFTAdapter oftAdapter_) {
        weth = weth_;
        oftAdapter = oftAdapter_;
    }

    /**
     * @dev Executes the send operation.
     * @param _sendParam The parameters for the send operation.
     * @param _fee The calculated fee for the send() operation.
     *      - nativeFee: The native fee.
     *      - lzTokenFee: The lzToken fee.
     * @param _refundAddress The address to receive any excess funds.
     * @return msgReceipt The receipt for the send operation.
     * @return oftReceipt The OFT receipt information.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     */
    function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
        external
        payable
        virtual
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
    {
        uint256 amount = _sendParam.amountLD;
        uint256 fee = _fee.nativeFee;
        if (amount + fee != msg.value) revert Bridge_InvalidAmount();
        weth.deposit{value: amount}();
        weth.approve(address(oftAdapter), amount);
        return oftAdapter.send{value: _fee.nativeFee}(_sendParam, _fee, _refundAddress);
    }
}
