// SPDX-License-Identifier: MIT

pragma solidity >=0.6.6;

import "../interfaces/IBitcoinxRouter.sol";
import "../libraries/TransferHelper.sol";
import "../interfaces/IBitcoinxFactory.sol";
import "../libraries/BitcoinxLibrary.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IWETH.sol";
import "../libraries/SafeMath.sol";
import '../token/BEP20.sol';

contract BitcoinxRouter is IBitcoinxRouter {
    using SafeMath for uint;

    address public override factory;
    address public override WETH;
    address public override routerFeeReceiver;
    uint256 baseReward = 10000000000000000000000; //wei
    address public owner;

    BEP20 public rewardToken;
    mapping(address => uint256) rewards;

    constructor(address _factory, address _WETH, address _routerFeeReceiver, BEP20 _rewardToken) {
        factory = _factory;
        WETH = _WETH;
        routerFeeReceiver = _routerFeeReceiver;
        rewardToken = _rewardToken;
        owner = msg.sender;
    }
   
    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'BitcoinxRouter: EXPIRED');
        _;
    }
    
    function setRouterFeeReceiver(address _receiver) public onlyOwner {
        routerFeeReceiver = _receiver;
    }
    function setFactory(address _factory) public onlyOwner {
        factory = _factory;
    }
    
    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function routerFee(address _user, address _token, uint _amount) internal returns (uint) {
        if (routerFeeReceiver != address(0)) {
            uint fee = _amount.mul(1).div(1000);
            if (fee > 0) {
                if (_user == address(this)) {
                    TransferHelper.safeTransfer(_token, routerFeeReceiver, fee);
                } else {
                    TransferHelper.safeTransferFrom(
                        _token, msg.sender, routerFeeReceiver, fee
                    );
                }
                _amount = _amount.sub(fee);
            }
        }
        return _amount;
    }
    //liquidity    
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        if (IBitcoinxFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IBitcoinxFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = BitcoinxLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = BitcoinxLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'BitcoinxRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = BitcoinxLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'BitcoinxRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = BitcoinxLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IBitcoinxPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = BitcoinxLibrary.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IBitcoinxPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value.sub(amountETH));
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = BitcoinxLibrary.pairFor(factory, tokenA, tokenB);
        IBitcoinxPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IBitcoinxPair(pair).burn(to);
        (address token0,) = BitcoinxLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'BitcoinxRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'BitcoinxRouter: INSUFFICIENT_B_AMOUNT');
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = BitcoinxLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IBitcoinxPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = BitcoinxLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IBitcoinxPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = BitcoinxLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IBitcoinxPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }
    //swap
    function _swap(
        uint[] memory amounts, 
        address[] memory path, 
        address _to
    ) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = BitcoinxLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];

            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? address(this) : _to;
            IBitcoinxPair(BitcoinxLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
            if (i < path.length - 2) {
                amounts[i + 1] = routerFee(address(this), path[i + 1], amounts[i + 1]);
                TransferHelper.safeTransfer(path[i + 1], BitcoinxLibrary.pairFor(factory, output, path[i + 2]), amounts[i + 1]);
            }
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = BitcoinxLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'BitcoinxRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        amounts[0] = routerFee(msg.sender, path[0], amounts[0]);
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BitcoinxLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
        rewards[msg.sender] += baseReward;
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] memory path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = BitcoinxLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'BitcoinxRouter: EXCESSIVE_INPUT_AMOUNT');
        amounts[0] = routerFee(msg.sender, path[0], amounts[0]);
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BitcoinxLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
        rewards[msg.sender] += baseReward;
    }

    function swapExactETHForTokens(uint amountOutMin, address[] memory path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts
    ) {
        require(path[0] == WETH, 'BitcoinxRouter: INVALID_PATH');
        amounts = BitcoinxLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'BitcoinxRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        amounts[0] = routerFee(address(this), path[0], amounts[0]);
        assert(IWETH(WETH).transfer(BitcoinxLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        rewards[msg.sender] += baseReward;
    }

    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] memory path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts
    ) {
        require(path[path.length - 1] == WETH, 'BitcoinxRouter: INVALID_PATH');
        amounts = BitcoinxLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'BitcoinxRouter: EXCESSIVE_INPUT_AMOUNT');
        amounts[0] = routerFee(msg.sender, path[0], amounts[0]);
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BitcoinxLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        rewards[msg.sender] += baseReward;
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] memory path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts
    ) {
        require(path[path.length - 1] == WETH, 'BitcoinxRouter: INVALID_PATH');
        amounts = BitcoinxLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'BitcoinxRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        amounts[0] = routerFee(msg.sender, path[0], amounts[0]);
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BitcoinxLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        rewards[msg.sender] += baseReward;
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(uint amountOut, address[] memory path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts
    ) {
        require(path[0] == WETH, 'BitcoinxRouter: INVALID_PATH');
        amounts = BitcoinxLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'BitcoinxRouter: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        uint oldAmounts = amounts[0];
        amounts[0] = routerFee(address(this), path[0], amounts[0]);
        assert(IWETH(WETH).transfer(BitcoinxLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        rewards[msg.sender] += baseReward;
        // refund dust eth, if any
        if (msg.value > oldAmounts) TransferHelper.safeTransferETH(msg.sender, msg.value - oldAmounts);
    }

    function _swapSupportingFeeOnTransferTokens(
        address[] memory path, 
        address _to
    ) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = BitcoinxLibrary.sortTokens(input, output);
            IBitcoinxPair pair = IBitcoinxPair(BitcoinxLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = BitcoinxLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            //address to = i < path.length - 2 ? BitcoinxLibrary.pairFor(factory, output, path[i + 2]) : _to;
            //address to = i < path.length - 2 ? address(this) : _to;
            pair.swap(amount0Out, amount1Out, i < path.length - 2 ? address(this) : _to, new bytes(0));
            if (i < path.length - 2) {
                amountOutput = IERC20(output).balanceOf(address(this));
                routerFee(address(this), output, amountOutput);
                TransferHelper.safeTransfer(path[i + 1], BitcoinxLibrary.pairFor(factory, output, path[i + 2]), IERC20(output).balanceOf(address(this)));
            }
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        amountIn = routerFee(msg.sender, path[0], amountIn);
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BitcoinxLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        rewards[msg.sender] += baseReward;
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'BitcoinxRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] memory path,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) {
        require(path[0] == WETH, 'BitcoinxRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        amountIn = routerFee(address(this), path[0], amountIn);
        assert(IWETH(WETH).transfer(BitcoinxLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        rewards[msg.sender] += baseReward;
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'BitcoinxRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WETH, 'BitcoinxRouter: INVALID_PATH');
        amountIn = routerFee(msg.sender, path[0], amountIn);
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, BitcoinxLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        rewards[msg.sender] += baseReward;
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'BitcoinxRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }
    //helper
    function quote(
        uint amountA, 
        uint reserveA, 
        uint reserveB
    ) public pure virtual override returns (uint amountB) {
        return BitcoinxLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint amountIn, 
        uint reserveIn, 
        uint reserveOut
    ) public pure virtual override returns (uint amountOut) {
        return BitcoinxLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint amountOut, 
        uint reserveIn, 
        uint reserveOut
    ) public pure virtual override returns (uint amountIn) {
        return BitcoinxLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(
        uint amountIn, 
        address[] memory path
    ) public view virtual override returns (uint[] memory amounts) {
        return BitcoinxLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(
        uint amountOut, 
        address[] memory path
    ) public view virtual override returns (uint[] memory amounts) {
        return BitcoinxLibrary.getAmountsIn(factory, amountOut, path);
    }

    function setBaseReward(uint256 reward) external onlyOwner{
        baseReward = reward;
    }

    function setRewardToken(BEP20 _rewardToken) external onlyOwner{
        rewardToken = _rewardToken;
    }

    function getRewardByAddress(address _address) public view returns(uint256) {
        return rewards[_address];
    }

    function withdrawTokens() external {
        require(rewards[msg.sender] <= rewardToken.balanceOf(address(this)), 'Insufficient funds');
        BEP20(rewardToken).transfer(msg.sender, rewards[msg.sender]);
        rewards[msg.sender] = 0;
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
