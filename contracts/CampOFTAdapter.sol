// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFTAdapter} from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";
import { IERC20Metadata, IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {WETH9} from "./WETH9.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOFT, SendParam, OFTLimit, OFTReceipt, OFTFeeDetail, MessagingReceipt, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/**
 * @title OFTAdapter Contract
 * @dev OFTAdapter is a contract that adapts an ERC-20 token to the OFT functionality.
 *
 * @dev For existing ERC20 tokens, this can be used to convert the token to crosschain compatibility.
 * @dev WARNING: ONLY 1 of these should exist for a given global mesh,
 * unless you make a NON-default implementation of OFT and needs to be done very carefully.
 */
contract CampOFTAdapter is OFTAdapter {
    using SafeERC20 for IERC20;

    // Storage slot for authorized senders
    uint256 private constant AUTHORIZED_SENDER_SLOT = 42069;
    

    constructor(address _token, address _lzEndpoint, address _delegate)
        OFTAdapter(_token, _lzEndpoint, _delegate)
        Ownable(_delegate)
    {}

    /**
     * @dev Credits unwrapped CAMP to the specified address.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @dev This sends gas tokens directly to the recipient and unwraps the adapted token
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override returns (uint256 amountReceivedLD) {

        // Enable this contract to receive ETH from the WETH contract during withdraw
        assembly {
            tstore(AUTHORIZED_SENDER_SLOT, 1)
        }
        
        // @dev Unwrap the tokens and transfer to the recipient.
        WETH9(payable(address(innerToken))).withdraw(_amountLD);

        // Disable the authorization after the operation is complete
        assembly {
            tstore(AUTHORIZED_SENDER_SLOT, 0)
        }
        
        payable(_to).transfer(_amountLD);
        
        return _amountLD;
    }

    function sharedDecimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev Allows the contract to receive ETH, but only from this contract
     * Uses transient storage (tstore) to prevent unauthorized sends
     */
    receive() external payable {
        bool canReceive;
        assembly {
            canReceive := tload(AUTHORIZED_SENDER_SLOT)
        }
        if (!canReceive) {
            // Revert if sender is not authorized
            revert("Unauthorized sender");
        }
    }
}
