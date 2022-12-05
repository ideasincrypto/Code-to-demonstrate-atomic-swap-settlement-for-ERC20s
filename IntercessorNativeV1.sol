// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

// IntercessorV1 for a tradable pair like ETH/USDC
contract IntercessorNativeV1 is Ownable, ReentrancyGuard {
    address private _term_token_address;
    
    mapping(address => bool) private _allowed_parties;

    // Counterparty cp1 transfers ETH to this smart contract to receive the term token
    // Cp2 receives ETH and sends the term token
    // First leg is sent at creation_time and
    // Second leg must be executed before deadline
    struct SltDatum {
        bool exists;
        string trade_id;

        address base_cp;
        uint256 base_amt;

        address term_cp;
        uint256 term_amt;
        address term_token;
        
        uint256 creation_time;
        uint256 deadline;

        address trigger_address;
        bool settled;
    }

    mapping(string => SltDatum) private _settlements;
    mapping(address => uint256) private _native_legs;

    modifier onlyParticipant {
         require(_allowed_parties[msg.sender], "Participant is not allowed");
        _;
    }

    event ParticipantAddedEvent(address adr);
    event ParticipantRemovedEvent(address adr);
    event TradeEntryCreatedEvent(SltDatum datum);
    event TradeSwapEvent(SltDatum datum);
    
    constructor(address term_token_address) {
        _term_token_address = term_token_address;
    }

    function add_participant(address participant) public onlyOwner nonReentrant {
        _allowed_parties[participant] = true;
        emit ParticipantAddedEvent(participant);
    }

    function remove_participant(address participant) public onlyOwner nonReentrant {
        _allowed_parties[participant] = false;
    }

    function deposit(
        string memory trade_id, 
        address base_counter_party,
        uint256 term_amount,
        address term_counter_party,
        address term_token_address) public onlyParticipant nonReentrant payable {
        
        require(msg.sender == base_counter_party || msg.sender == term_counter_party, "Sender and counter parties must match");
        require(_term_token_address == term_token_address, "Term Token Addresses Do Not Match");
        require(msg.value > 0, "Value amount must be > 0");
        require(term_amount > 0, "Term amount must be > 0");

        SltDatum memory sltDatum = _settlements[trade_id];

        uint256 current_amount = _native_legs[msg.sender];
        uint256 value_received = msg.value;
        uint256 new_amount = current_amount + value_received;
        _native_legs[msg.sender] = new_amount;
        console.log("IntercessorNativeV1::deposit Sender / Amount", msg.sender, new_amount);

        if (!sltDatum.exists) {
            console.log("IntercessorNativeV1::deposit The first call does not exist - so we simply create the entry");
            uint256 creation_time  = block.timestamp;
            uint256 deadline = creation_time + 1 days; // Move as a property
            sltDatum = SltDatum(
                true, 
                trade_id, 
                base_counter_party, 
                value_received, 
                term_counter_party, 
                term_amount,
                term_token_address,
                creation_time,
                deadline,
                msg.sender,
                false);
            _settlements[trade_id] = sltDatum;
            emit TradeEntryCreatedEvent(sltDatum);
        } else {
            process_trade(
                value_received,
                msg.sender,
                term_amount,
                term_counter_party,
                term_token_address,
                sltDatum);
        }
    }

    // https://solidity-by-example.org/payable/
    function trade(
        string memory trade_id, 
        uint256 base_amount, 
        address base_counter_party,
        uint256 term_amount,
        address term_counter_party,
        address term_token_address) public onlyParticipant nonReentrant {
               
        require(msg.sender == base_counter_party || msg.sender == term_counter_party, "Sender and counter parties must match");
        require(_term_token_address == term_token_address, "Term Token Addresses Do Not Match");
        require(base_amount > 0, "Base amount must be > 0");
        require(term_amount > 0, "Term amount must be > 0");

        SltDatum memory sltDatum = _settlements[trade_id];
        
        if (!sltDatum.exists) {
            console.log("IntercessorV1::trade The first call does not exist - so we simply create the entry");
            uint256 creation_time  = block.timestamp;
            uint256 deadline = creation_time + 1 days; // Move as a property
            sltDatum = SltDatum(
                true, 
                trade_id, 
                base_counter_party, 
                base_amount, 
                term_counter_party, 
                term_amount,
                term_token_address,
                creation_time,
                deadline,
                msg.sender,
                false);
            _settlements[trade_id] = sltDatum;
            emit TradeEntryCreatedEvent(sltDatum);
        } else {
            process_trade(
                base_amount,
                base_counter_party,
                term_amount,
                term_counter_party,
                term_token_address,
                sltDatum);
        }
    }

    function process_trade( 
        uint256 base_amount, 
        address base_counter_party,
        uint256 term_amount,
        address term_counter_party,
        address term_token_address,
        SltDatum memory sltDatum) private {
        require(sltDatum.trigger_address != msg.sender, "Wrong sender for the second leg");
        require(sltDatum.settled == false, "Already settled");

        console.log("IntercessorNativeV1::deposit There is an entry.. we need to see if there is a match i.e. all args must match");
        require(sltDatum.base_cp == base_counter_party, "Base Counter Party Mismatch");
        require(sltDatum.base_amt == base_amount, "Base Amount Party Mismatch");

        require(sltDatum.term_cp == term_counter_party, "Term Counter Party Mismatch");
        require(sltDatum.term_amt == term_amount, "Term Amount Party Mismatch");
        require(sltDatum.term_token == term_token_address, "Term Token Party Mismatch");

        uint256 current_time  = block.timestamp;
        require(current_time <= sltDatum.deadline, "Trade Leg Expired");

        console.log("IntercessorERC20V1::trade All basic checks are good");

        IERC20 term_token = IERC20(term_token_address);
        require(term_token.allowance(term_counter_party, address(this)) >= term_amount, 
                "term_counter_party has not approved enough");
        require(term_token.balanceOf(term_counter_party) >= term_amount, "term_counter_party has insuficient amount");

        console.log("IntercessorERC20V1::trade Allowances are good");

        // Let's swap
        bool sent = term_token.transferFrom(term_counter_party, base_counter_party, term_amount);
        require(sent, "Issue with sending the term token to base_counter_party");

        (bool success, ) = term_counter_party.call{value: base_amount}("");
        require(success, "Failed to send Ether to term_counter_party");

        emit TradeSwapEvent(sltDatum);
    }
}