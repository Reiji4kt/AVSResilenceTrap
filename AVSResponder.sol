// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract AVSResponder {
    /// @notice Emitted when the trap detects AVS failure.
    /// reasonCode: 1=dirUnset, 2=notRegistered, 3=neverPublished, 4=stale, 5=inconsistent
    event AVSAlert(address indexed avs, uint8 reasonCode);

    /// @notice Called by Drosera relay when AVSResilienceTrap triggers.
    /// @param avs The AVS contract address
    /// @param reason The reason code provided by the trap
    function respondWithAVSFailure(address avs, uint8 reason) external {
        emit AVSAlert(avs, reason);
    }
}
