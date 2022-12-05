const { expect } = require("chai");
const { ethers } = require("hardhat");
const { anyUint } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

describe("IntercessorV1", function () {
  let _base_token;
  let _term_token;
  let _intercessor;
  let _cp1, _cp2;
  let _deployer;
  let _zeth;

  before(async () => {
    const [p1, p2, deployer] = await ethers.getSigners();
    _cp1 = p1;
    _cp2 = p2;
    _deployer = deployer;
    console.log("_cp1: {}", _cp1.address);
    console.log("_cp2: {}", _cp2.address);

    const ZETH = await ethers.getContractFactory("ZETH");
    _zeth = await ZETH.connect(_deployer).deploy();
    await _zeth.deployed();

    const USDC = await ethers.getContractFactory("Gen20Token");
    _base_token = await USDC.connect(_deployer).deploy(100, "USDC", "USDC");
    await _base_token.deployed();

    const DAI = await ethers.getContractFactory("Gen20Token");
    _term_token = await DAI.connect(_deployer).deploy(100, "DAI", "DAI");
    await _term_token.deployed();

    const IntercessorERC20V1 = await ethers.getContractFactory("IntercessorERC20V1");
    _intercessor = await IntercessorERC20V1.deploy(_base_token.address, _term_token.address);
    await _intercessor.deployed();
    console.log("_intercessor:", _intercessor.address);

    await (expect(_intercessor.add_participant(_cp1.address))).
      to.emit(_intercessor, 'ParticipantAddedEvent').
      withArgs(_cp1.address);

    await (expect(_intercessor.add_participant(_cp2.address))).
      to.emit(_intercessor, 'ParticipantAddedEvent').
      withArgs(_cp2.address);
  });

  it ("Swap Test ERC20s", async function () {
    // Transfers some tokens first to the counter parties
    await _base_token.connect(_deployer).transfer(_cp1.address, 50);
    await _term_token.connect(_deployer).transfer(_cp2.address, 50);

    const cp1_base_token_amount_0 = await _base_token.balanceOf(_cp1.address);
    const cp1_term_token_amount_0 = await _term_token.balanceOf(_cp1.address);

    console.log("_cp1 has {} base tokens", cp1_base_token_amount_0);
    console.log("_cp1 has {} term tokens", cp1_term_token_amount_0);

    const cp2_base_token_amount_0 = await _base_token.balanceOf(_cp2.address);
    const cp2_term_token_amount_0 = await _term_token.balanceOf(_cp2.address);

    console.log("_cp2 has base tokens", cp2_base_token_amount_0);
    console.log("_cp2 has {} term tokens", cp2_term_token_amount_0);

    expect(cp1_base_token_amount_0).to.equal(50);
    expect(cp1_term_token_amount_0).to.equal(0);
    expect(cp2_base_token_amount_0).to.equal(0);
    expect(cp2_term_token_amount_0).to.equal(50);

    // Make sure approvals are in place
    // We allow the _intercessor smart contract to spend on the behalf of cp1 and cp2
    // Must be done prior to calling the 'trade' function on the smart contract
    await _base_token.connect(_cp1).approve(_intercessor.address, 25);
    await _term_token.connect(_cp2).approve(_intercessor.address, 30);

    // Trade
    // _cp1 sends 25 _base_token to _cp2
    // _cp2 sends 30 _term_token to cp_1

    const trade_id = "tid-1";

    const base_amount = 25;
    const base_counter_party = _cp1.address;
    const base_token_address = _base_token.address;

    const term_amount = 30;
    const term_counter_party = _cp2.address;
    const term_token_address = _term_token.address;

    await (expect(_intercessor.connect(_cp1).trade(
      trade_id,
      base_amount,
      base_counter_party,
      base_token_address,
      term_amount,
      term_counter_party,
      term_token_address
    ))).to.emit(_intercessor, 'TradeEntryCreatedEvent');

    await (expect(_intercessor.connect(_cp2).trade(
      trade_id,
      base_amount,
      base_counter_party,
      base_token_address,
      term_amount,
      term_counter_party,
      term_token_address
    ))).to.emit(_intercessor, 'TradeSwapEvent');

    const cp1_base_token_amount_1 = await _base_token.balanceOf(_cp1.address);
    const cp1_term_token_amount_1 = await _term_token.balanceOf(_cp1.address);

    console.log("_cp1 has {} base tokens", cp1_base_token_amount_1);
    console.log("_cp1 has {} term tokens", cp1_term_token_amount_1);

    const cp2_base_token_amount_1 = await _base_token.balanceOf(_cp2.address);
    const cp2_term_token_amount_1 = await _term_token.balanceOf(_cp2.address);

    console.log("_cp2 has base tokens", cp2_base_token_amount_1);
    console.log("_cp2 has {} term tokens", cp2_term_token_amount_1);

    expect(cp1_base_token_amount_1).to.equal(25);
    expect(cp1_term_token_amount_1).to.equal(30);
    expect(cp2_base_token_amount_1).to.equal(25);
    expect(cp2_term_token_amount_1).to.equal(20);
  });

  it ("Swap Test ERC20 / WETH", async function () {
    const zeth_total_supply_0 = await _zeth.totalSupply();
    console.log("ZETH Total Supply (0)", zeth_total_supply_0);
    
    // Counterparty 1 will send ETH to ZETH to wrap them
    await _cp1.sendTransaction({
      to: _zeth.address,
      value: ethers.utils.parseEther("1.0"), // Sends exactly 1.0 ether
    });

    const zeth_total_supply_1 = await _zeth.totalSupply();
    console.log("ZETH Total Supply (1)", zeth_total_supply_1);
  });

});