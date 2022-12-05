// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

// IntercessorV1 for a tradable pair like USDC/DAI
contract IntercessorERC20V1 is Ownable, ReentrancyGuard {
    address private _base_token_address;
    address private _term_token_address;
    
    mapping(address => bool) private _allowed_parties;

    // Counterparty cp1 transfers amount_1 of token_1 to cp2;
    // First leg is sent at creation_time and
    // Second leg must be executed before deadline
    struct SltDatum {
        bool exists;
        string trade_id;

        address base_cp;
        uint256 base_amt;
        address base_token;

        address term_cp;
        uint256 term_amt;
        address term_token;
        
        uint256 creation_time;
        uint256 deadline;

        address trigger_address;
        bool settled;
    }

    mapping(string => SltDatum) private _settlements;

    modifier onlyParticipant {
         require(_allowed_parties[msg.sender], "Participant is not allowed");
        _;
    }

    event ParticipantAddedEvent(address adr);
    event ParticipantRemovedEvent(address adr);
    event TradeEntryCreatedEvent(SltDatum datum);
    event TradeSwapEvent(SltDatum datum);
    
    constructor(address base_token_address, address term_token_address) {
        _base_token_address = base_token_address;
        _term_token_address = term_token_address;
    }

    function add_participant(address participant) public onlyOwner nonReentrant {
        _allowed_parties[participant] = true;
        emit ParticipantAddedEvent(participant);
    }

    function remove_participant(address participant) public onlyOwner nonReentrant {
        _allowed_parties[participant] = false;
    }

    // todo - eth? https://ethereum.stackexchange.com/questions/56466/wrapping-eth-calling-the-weth-contract
    // https://solidity-by-example.org/payable/
    function trade(
        string memory trade_id, 
        uint256 base_amount, 
        address base_counter_party,
        address base_token_address,
        uint256 term_amount,
        address term_counter_party,
        address term_token_address) public onlyParticipant nonReentrant {
        
        require(msg.sender == base_counter_party || msg.sender == term_counter_party, "Sender and counter parties must match");
        require(_base_token_address == base_token_address, "Base Token Addresses Do Not Match");
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
                base_token_address, 
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
            require(sltDatum.trigger_address != msg.sender, "Wrong sender for the second leg");
            require(sltDatum.settled == false, "Already settled");

            console.log("IntercessorERC20V1::trade There is an entry.. we need to see if there is a match i.e. all args must match");
            require(sltDatum.base_cp == base_counter_party, "Base Counter Party Mismatch");
            require(sltDatum.base_amt == base_amount, "Base Amount Party Mismatch");
            require(sltDatum.base_token == base_token_address, "Base Token Party Mismatch");

            require(sltDatum.term_cp == term_counter_party, "Term Counter Party Mismatch");
            require(sltDatum.term_amt == term_amount, "Term Amount Party Mismatch");
            require(sltDatum.term_token == term_token_address, "Term Token Party Mismatch");

            uint256 current_time  = block.timestamp;
            require(current_time <= sltDatum.deadline, "Trade Leg Expired");

            console.log("IntercessorERC20V1::trade All basic checks are good");

            // At this stage - all Trade Data match
            // We will start the checks for the Swaps by starting with Approves, Amount and finally the Swap

            IERC20 base_token = IERC20(base_token_address);
            require(base_token.allowance(base_counter_party, address(this)) >= base_amount, 
                "base_counter_party has not approved enough");
            require(base_token.balanceOf(base_counter_party) >= base_amount, "base_counter_party has inssuficient amount");

            IERC20 term_token = IERC20(term_token_address);
            require(term_token.allowance(term_counter_party, address(this)) >= term_amount, 
                "term_counter_party has not approved enough");
            require(term_token.balanceOf(term_counter_party) >= term_amount, "term_counter_party has insuficient amount");

            console.log("IntercessorERC20V1::trade Allowances are good");

            // Let's swap
            bool sent = base_token.transferFrom(base_counter_party, term_counter_party, base_amount);
            require(sent, "Issue with sending the base token");

            sent = term_token.transferFrom(term_counter_party, base_counter_party, term_amount);
            require(sent, "Issue with sending the term token");

            sltDatum.settled = true;
            emit TradeSwapEvent(sltDatum);
        }
    }
}