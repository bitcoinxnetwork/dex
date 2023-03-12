// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../interfaces/IBitcoinxRouter.sol';
import '../interfaces/IBitcoinxPair.sol';

contract LiquidityMigrator {
  
  IBitcoinxRouter public router;
  IBitcoinxPair public pair;
  IBitcoinxRouter public routerFork;
  IBitcoinxPair public pairFork;

  address public owner;
  bool public migrationDone;

  constructor(
    address _router, 
    address _pair, 
    address _routerFork,
    address _pairFork
  ) {
    router = IBitcoinxRouter(_router);
    pair = IBitcoinxPair(_pair); 
    routerFork = IBitcoinxRouter(_routerFork);
    pairFork = IBitcoinxPair(_pairFork);
    owner = msg.sender;
  }

  function deposit(uint amount) external {
    require(migrationDone == false, 'migration already done');
    pair.transferFrom(msg.sender, address(this), amount);
  }

  function migrate() external {
    require(msg.sender == owner, 'only owner');
    require(migrationDone == false, 'migration already done');
    IERC20 token0 = IERC20(pair.token0());
    IERC20 token1 = IERC20(pair.token1());
    uint totalBalance = pair.balanceOf(address(this));
    router.removeLiquidity(
      address(token0),
      address(token1),
      totalBalance,
      0,
      0,
      address(this),
      block.timestamp
    );

    uint token0Balance = token0.balanceOf(address(this));
    uint token1Balance = token1.balanceOf(address(this));
    token0.approve(address(routerFork), token0Balance); 
    token1.approve(address(routerFork), token1Balance); 

    routerFork.addLiquidity(
      address(token0),
      address(token1),
      token0Balance,
      token1Balance,
      token0Balance,
      token1Balance,
      address(this),
      block.timestamp
    );
    migrationDone = true;
  }

  function resetMigration() external onlyOwner{
    migrationDone = false;
  }

  function setRouter(address _router) external onlyOwner {
    router = IBitcoinxRouter(_router);
  }

  function setPairAddress(address _pair) external onlyOwner {
    pair = IBitcoinxPair(_pair);
  }

  function setRouterFork(address _router) external onlyOwner {
    routerFork = IBitcoinxRouter(_router);
  }

  function setPairAddressFork(address _pair) external onlyOwner {
    pairFork = IBitcoinxPair(_pair);
  }

  function transferOwnership(address _address) public onlyOwner {
    require(_address != address(0), "Invalid Address");
    owner = _address;
  }

  modifier onlyOwner() {
      require(owner == msg.sender, "Only owner can call this function");
      _;
  }

}
