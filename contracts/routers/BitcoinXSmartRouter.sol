// SPDX-License-Identifier: Unlicense
pragma solidity >=0.7.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IBitcoinxRouter.sol";
import "../interfaces/IBitcoinxPair.sol";
import "../interfaces/IBitcoinxFactory.sol";
import "../interfaces/IWETH.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract BitcoinXSmartRouter is ReentrancyGuard{

    address public owner;
    address payable public wallet;
    uint256 public reward = 100000000000000000000000;
    address public WETH;
    uint256 public fees = 5;
    address public routerV2;
    address public factoryV2;
    address public rewardToken;
    address public erc20Token;
    address public BUSD;
    address public USDT;

    event SwapETHForTokens(
        uint256 amountIn,
        address[] path
    );

    event SwapTokensForETH(
        uint256 amountIn,
        address[] path
    );
    event SwapTokensForToken(
        uint256 amountIn,
        address[] path
    );

    constructor(address payable _wallet, address _routerV2, address _factoryV2, address _WETH, address _rewardToken, address _BUSD, address _USDT){
        require(_wallet != address(0));
        wallet = _wallet;
        rewardToken = _rewardToken;       
        owner = msg.sender;
        routerV2 = _routerV2;
        factoryV2 = _factoryV2;
        WETH = _WETH;
        BUSD = _BUSD;
        USDT = _USDT;
        erc20Token = _rewardToken;
    }

    function swapForToken(uint256 amountIn, address tokenIn, address tokenOut) public payable nonReentrant{   
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn); 
        uint256 allowance = IERC20(tokenIn).allowance(msg.sender, address(routerV2));
        if(allowance < amountIn){
            IERC20(tokenIn).approve(address(routerV2), type(uint256).max);
        }
        address pair = IBitcoinxFactory(factoryV2).getPair(tokenIn, tokenOut);
        console.log('pair Address', pair);
        uint256 deadline = block.timestamp + 10;
        address[] memory path;
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;       

        uint256 feeAmount = amountIn * fees/1000;
        IERC20(tokenIn).transfer(wallet, feeAmount);

        uint256 amount = amountIn - feeAmount;
        uint[] memory swapAmount = IBitcoinxRouter(routerV2).swapExactTokensForTokens(
            amount,
            0,
            path,
            msg.sender,
            deadline
        );
        console.log('Swap Amount Token01', swapAmount[1]);
        emit SwapTokensForToken(amount, path);

        if(tokenIn == BUSD || tokenIn == USDT){
            IERC20(rewardToken).transfer(msg.sender, calculateTradeUSDTWithReward(amountIn));
            console.log('Swap BUSD to Any Token with reward', calculateTradeUSDTWithReward(amountIn));
        }
        if(tokenOut == BUSD || tokenOut == USDT){
            IERC20(rewardToken).transfer(msg.sender, calculateTradeUSDTWithReward(getEstimatedAmountOut(amountIn, tokenIn, tokenOut)));
            console.log('Swap Any token to BUSD with reward', calculateTradeUSDTWithReward(getEstimatedAmountOut(amountIn, tokenIn, tokenOut)));
        }
               
    }

    function swapETHForToken(uint256 amountIn, address tokenIn, address tokenOut) public payable nonReentrant{
        require(msg.value > 0 , "You have no balance to do the trade");
        uint256 feeAmount = amountIn * fees/1000;
        payable(wallet).transfer(feeAmount);
        console.log('feeAmount', feeAmount);

        address pair = getPairAddress(tokenIn, tokenOut);
        console.log('pair Address ETH', pair);

        uint256 amount = amountIn - feeAmount;
        uint256 deadline = block.timestamp + 10;
        address[] memory path;
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;       
        uint[] memory swapAmount = IBitcoinxRouter(routerV2).swapExactETHForTokens{ value: amount }(
            0,
            path,
            msg.sender,
            deadline
        );
        console.log('Swap Amount Token01', swapAmount[1]);
        emit SwapETHForTokens(amount, path);
        IERC20(rewardToken).transfer(msg.sender, calculateTradeReward(amountIn));
        console.log('BTCX Reward Sent', calculateTradeReward(amountIn));

    }

    function swapExactTokensForETH(uint256 amountIn, address tokenIn, address tokenOut) public payable nonReentrant{
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);        
        uint256 deadline = block.timestamp + 10;
        address[] memory path;
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;      

        uint256 feeAmount = amountIn * fees/1000;
        console.log('feeAmount of token to ETH', feeAmount);
        IERC20(tokenIn).transfer(wallet, feeAmount);
        uint256 amount = amountIn - feeAmount;
        
        uint[] memory swapAmount = IBitcoinxRouter(routerV2).swapExactTokensForETH(
            amount,
            0,
            path,
            msg.sender,
            deadline
        );
        console.log('Swap Amount Token01', swapAmount[1]);
        
        emit SwapTokensForETH(amount, path);
        IERC20(rewardToken).transfer(msg.sender, calculateTradeReward(getEstimatedAmountOut(amountIn, tokenIn, tokenOut)));
        console.log('BTCX Reward Sent', calculateTradeReward(getEstimatedAmountOut(amountIn, tokenIn, tokenOut)));
    }

    function swapETHForTokenSupportingFeeOnTransferTokens(uint256 amountIn, address tokenIn, address tokenOut) public payable nonReentrant{
        require(msg.value > 0 , "You have no balance to do the trade");
        uint256 feeAmount = amountIn * fees/1000;
        payable(wallet).transfer(feeAmount);
        console.log('feeAmount', feeAmount);
        uint256 amount = amountIn - feeAmount;
        uint256 deadline = block.timestamp + 10;
        address[] memory path;
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;       
        IBitcoinxRouter(routerV2).swapExactETHForTokensSupportingFeeOnTransferTokens{ value: amount }(
            0,
            path,
            msg.sender,
            deadline
        );
        emit SwapETHForTokens(amount, path);
        IERC20(rewardToken).transfer(msg.sender, calculateTradeReward(amountIn));
        console.log('BTCX Reward Sent', calculateTradeReward(amountIn));
    }
    

    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 amountIn, address tokenIn, address tokenOut) public payable nonReentrant{
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        uint256 deadline = block.timestamp + 10;
        address[] memory path;
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;      

        uint256 feeAmount = amountIn * fees/1000;
        console.log('feeAmount of token to ETH', feeAmount);
        IERC20(tokenIn).transfer(wallet, feeAmount);
        uint256 amount = amountIn - feeAmount;
        
        IBitcoinxRouter(routerV2).swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            msg.sender,
            deadline
        );
        
        emit SwapTokensForETH(amount, path);
        IERC20(rewardToken).transfer(msg.sender, calculateTradeReward(getEstimatedAmountOut(amountIn, tokenIn, tokenOut)));
        console.log('BTCX Reward Sent', calculateTradeReward(getEstimatedAmountOut(amountIn, tokenIn, tokenOut)));
    }

    function getEstimatedAmountOut(uint256 amountIn, address tokenIn, address tokenOut) public view returns (uint256) {
         uint256[] memory amounts = IBitcoinxRouter(routerV2).getAmountsOut(amountIn, getPath(tokenIn, tokenOut));
         uint256 amountMinOut = amounts[1];
         return amountMinOut;        
    }

    function getPath(address tokenIn, address tokenOut) public pure returns (address[] memory){
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;        
        return path;
    }

    function getPairAddress(address tokenIn, address tokenOut) public view returns(address){
        address pair = IBitcoinxFactory(factoryV2).getPair(tokenIn, tokenOut);
        return pair;
    }

    function getTokenReserves(address tokenIn, address tokenOut) public view returns(uint256 _reserve0, uint256 _reserve1){
        address pair = IBitcoinxFactory(factoryV2).getPair(tokenIn, tokenOut);
        (uint256 reserve0, uint256 reserve1, ) = IBitcoinxPair(pair).getReserves();

        uint256 price = reserve1/reserve0;

        console.log('reserve0', reserve0);
        console.log('reserve1', reserve1);
        return (reserve0, reserve1);
    }

    function calculateTradeUSDTWithReward(uint256 amountIn) public view returns(uint256){
        uint256 rewardAmount = reward;
        if(amountIn >= 2000000000000000000000){
            return rewardAmount * 20;
        }
        else if(amountIn >= 1900000000000000000000){
            return rewardAmount * 19;
        }
        else if(amountIn >= 1800000000000000000000){
            return rewardAmount * 18;
        }
         else if(amountIn >= 1700000000000000000000){
            return rewardAmount * 17;
        }
         else if(amountIn >= 1600000000000000000000){
            return rewardAmount * 16;
        }
         else if(amountIn >= 1500000000000000000000){
            return rewardAmount * 15;
        }
         else if(amountIn >= 1400000000000000000000){
            return rewardAmount * 14;
        }
         else if(amountIn >= 1300000000000000000000){
            return rewardAmount * 13;
        }
         else if(amountIn >= 1200000000000000000000){
            return rewardAmount * 12;
        }
         else if(amountIn >= 1100000000000000000000){
            return rewardAmount * 11;
        }
        else if(amountIn >= 1000000000000000000000){
            return rewardAmount * 10;
        }
        else if(amountIn >= 900000000000000000000){
            return rewardAmount * 9;
        }
        else if(amountIn >= 800000000000000000000){
            return rewardAmount * 8;
        }
        else if(amountIn >= 700000000000000000000){
            return rewardAmount * 7;
        }
        else if(amountIn >= 600000000000000000000){
            return rewardAmount * 6;
        }
        else if(amountIn >= 500000000000000000000){
            return rewardAmount * 5;
        }
        else if(amountIn >= 400000000000000000000){
            return rewardAmount * 4;
        }
        else if(amountIn >= 300000000000000000000){
            return rewardAmount * 3;
        }
        else if(amountIn >= 200000000000000000000){
            return rewardAmount * 2;
        }
        else if(amountIn >= 100000000000000000000){
            return rewardAmount * 1;
        }
        else if(amountIn >= 50000000000000000000){
            return rewardAmount / 2;
        }
        else if(amountIn >= 200000000000000000){
            return rewardAmount / 4;
        }
        else{
            return rewardAmount / 10;
        }
    }

    function calculateTradeReward(uint256 amountIn) public view returns(uint256){
        uint256 rewardAmount = reward;
        if(amountIn >= 2000000000000000000){
            return rewardAmount * 20;
        }
        else if(amountIn >= 1900000000000000000){
            return rewardAmount * 19;
        }
        else if(amountIn >= 1800000000000000000){
            return rewardAmount * 18;
        }
         else if(amountIn >= 1700000000000000000){
            return rewardAmount * 17;
        }
         else if(amountIn >= 1600000000000000000){
            return rewardAmount * 16;
        }
         else if(amountIn >= 1500000000000000000){
            return rewardAmount * 15;
        }
         else if(amountIn >= 1400000000000000000){
            return rewardAmount * 14;
        }
         else if(amountIn >= 1300000000000000000){
            return rewardAmount * 13;
        }
         else if(amountIn >= 1200000000000000000){
            return rewardAmount * 12;
        }
         else if(amountIn >= 1100000000000000000){
            return rewardAmount * 11;
        }
        else if(amountIn >= 1000000000000000000){
            return rewardAmount * 10;
        }
        else if(amountIn >= 900000000000000000){
            return rewardAmount * 9;
        }
        else if(amountIn >= 800000000000000000){
            return rewardAmount * 8;
        }
        else if(amountIn >= 700000000000000000){
            return rewardAmount * 7;
        }
        else if(amountIn >= 600000000000000000){
            return rewardAmount * 6;
        }
        else if(amountIn >= 500000000000000000){
            return rewardAmount * 5;
        }
        else if(amountIn >= 400000000000000000){
            return rewardAmount * 4;
        }
        else if(amountIn >= 300000000000000000){
            return rewardAmount * 3;
        }
        else if(amountIn >= 200000000000000000){
            return rewardAmount * 2;
        }
        else if(amountIn >= 100000000000000000){
            return rewardAmount * 1;
        }
        else if(amountIn >= 50000000000000000){
            return rewardAmount / 2;
        }
        else if(amountIn >= 20000000000000000){
            return rewardAmount / 4;
        }
        else{
            return rewardAmount / 10;
        }
    }

    function withdrawFund(uint amount) external onlyOwner{
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed.");
    }
    
    function transferRewardToken(address to, uint256 amount) public onlyOwner {
        uint256 tokenOutalance = IERC20(rewardToken).balanceOf(address(this));
        require(amount <= tokenOutalance, "Balance is low");
        IERC20(rewardToken).transfer(to, amount);
    }

    function transferERC20Token(address to, uint256 amount) public onlyOwner {
        uint256 tokenOutalance = IERC20(erc20Token).balanceOf(address(this));
        require(amount <= tokenOutalance, "Balance is low");
        IERC20(erc20Token).transfer(to, amount);
    }

    function setERC20Token(address _erc20Token) public onlyOwner{
        erc20Token = _erc20Token;
    }

    function setRewardToken(address _rewardToken) public onlyOwner{
        rewardToken = _rewardToken;
    }

    function setReward(uint256 _reward) public onlyOwner {
        reward = _reward;
    }

    function setFees(uint256 _fees) public onlyOwner {
        fees = _fees;
    }

    function setFactoryV2(address _factoryV2) public onlyOwner {
        factoryV2 = _factoryV2;
    }

    function setRouterV2(address _routerV2) public onlyOwner {
        routerV2 = _routerV2;
    }

    function setUSDTAddress(address _USDT) public onlyOwner {
        USDT = _USDT;
    }

    function setBUSDAddress(address _BUSD) public onlyOwner {
        BUSD = _BUSD;
    }

    function setWallet(address payable _wallet) public onlyOwner {
        wallet = _wallet;
    }

    receive() payable external {}

    modifier onlyOwner() {
        require(owner == msg.sender, "Only owner can call this function");
        _;
    }

    function transferOwnership(address _address) public onlyOwner {
        require(_address != address(0), "Invalid Address");
        owner = _address;
    }

}