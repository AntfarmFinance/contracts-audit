// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../antfarm/AntfarmOracle.sol";
import "./pair/IAntfarmPairState.sol";
import "./pair/IAntfarmPairEvents.sol";
import "./pair/IAntfarmPairActions.sol";
import "./pair/IAntfarmPairDerivedState.sol";

interface IAntfarmBase is
    IAntfarmPairState, 
    IAntfarmPairEvents, 
    IAntfarmPairActions, 
    IAntfarmPairDerivedState 
{
    
}
