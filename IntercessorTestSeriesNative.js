const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("IntercessorV1", function () {
  let _term_token;
  let _intercessor;
  let _cp1, _cp2;
  let _deployer;

  before(async () => {
    const [p1, p2, deployer] = await ethers.getSigners();
    _cp1 = p1;
    _cp2 = p2;
    _deployer = deployer;
    console.log("_cp1: {}", _cp1.address);
    console.log("_cp2: {}", _cp2.address);

    const DAI = await ethers.getContractFactory("Gen20Token");
    _term_token = await DAI.connect(_deployer).deploy(100, "DAI", "DAI");
    await _term_token.deployed();

    const IntercessorNativeV1 = await ethers.getContractFactory("IntercessorNativeV1");
    _intercessor = await IntercessorNativeV1.deploy(_term_token.address);
    await _intercessor.deployed();
    console.log("_intercessor:", _intercessor.address);

    await (expect(_intercessor.add_participant(_cp1.address))).
      to.emit(_intercessor, 'ParticipantAddedEvent').
      withArgs(_cp1.address);

    await (expect(_intercessor.add_participant(_cp2.address))).
      to.emit(_intercessor, 'ParticipantAddedEvent').
      withArgs(_cp2.address);
  });

  it ("Swap Test 1", async function () {
    const trade_id = "tid-1";

    const base_counter_party = _cp1.address;

    const term_amount = 30;
    const term_counter_party = _cp2.address;
    const term_token_address = _term_token.address;

    await _term_token.connect(_deployer).transfer(_cp2.address, 50);
    await _term_token.connect(_cp2).approve(_intercessor.address, 30);

    const base_eth_balance_0 = await ethers.provider.getBalance(_cp1.address);
    const term_eth_balance_0 = await ethers.provider.getBalance(_cp2.address);
    console.log("(B) Base ETH", base_eth_balance_0);
    console.log("(B) Term ETH", term_eth_balance_0);

    const cp1_term_token_amount_0 = await _term_token.balanceOf(_cp1.address);
    const cp2_term_token_amount_0 = await _term_token.balanceOf(_cp2.address);
    console.log("(B) _cp1 has term tokens", cp1_term_token_amount_0);
    console.log("(B) _cp2 has term tokens", cp2_term_token_amount_0);

    await (expect(_intercessor.connect(_cp1).deposit(
      trade_id,
      base_counter_party,
      term_amount,
      term_counter_party,
      term_token_address,
    { value: ethers.utils.parseEther("1") })
    )).to.emit(_intercessor, 'TradeEntryCreatedEvent');

    await (expect(_intercessor.connect(_cp2).trade(
      trade_id,
      BigInt(1000000000000000000),
      base_counter_party,
      term_amount,
      term_counter_party,
      term_token_address
    ))).to.emit(_intercessor, 'TradeSwapEvent');

    const base_eth_balance_1 = await ethers.provider.getBalance(_cp1.address);
    const term_eth_balance_1 = await ethers.provider.getBalance(_cp2.address);
    console.log("(A) Base ETH", base_eth_balance_1);
    console.log("(A) Term ETH", term_eth_balance_1);

    const cp1_term_token_amount_1 = await _term_token.balanceOf(_cp1.address);
    const cp2_term_token_amount_1 = await _term_token.balanceOf(_cp2.address);
    console.log("(A) _cp1 has term tokens", cp1_term_token_amount_1);
    console.log("(A) _cp2 has term tokens", cp2_term_token_amount_1);

    const diff_base_eth = base_eth_balance_1 - base_eth_balance_0;
    const diff_term_eth = term_eth_balance_1 - term_eth_balance_0;
    console.log("Diff ETH Base", diff_base_eth);
    console.log("Diff ETH Term", diff_term_eth); 
    
    // Base: -1000409707428446200
    // Term:   999843930423951400
    // Tft :  1000000000000000000
  });
});