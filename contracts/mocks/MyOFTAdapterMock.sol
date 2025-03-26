// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {CampOFTAdapter} from "../CampOFTAdapter.sol";

// @dev WARNING: This is for testing purposes only
contract CampOFTAdapterMock is CampOFTAdapter {
    constructor(address _token, address _lzEndpoint, address _delegate) CampOFTAdapter(_token, _lzEndpoint, _delegate) {}
}
