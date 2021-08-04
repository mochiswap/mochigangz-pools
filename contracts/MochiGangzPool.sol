// File: @openzeppelin/contracts/token/ERC20/IERC20.sol
import 'interfaces/IERC20.sol';
import 'libraries/SafeMath.sol';
import 'libraries/Address.sol';
import 'libraries/SafeERC20.sol';

pragma solidity 0.6.12;

contract MochiGangzPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    address constant burnAddress = 0x0000000000000000000000000000000000000000;

    struct UserInfo 
    {
        uint256 amount;                     // How many hMOCHI tokens the user has provided.
        uint256 rewardDebt;                 // Reward debt. See explanation below.
    }

    struct PoolInfo 
    {
        uint256 lastRewardBlock;            // Last block number that reward distribution occured.
        uint256 accRewardPerShare;          // Accumulated reward per share, times 1e12. See below.
    }

    IERC20 public immutable hMOCHI;              
    IERC20 public immutable REWARD;                   // Reward token
    uint256 public immutable rewardPerBlock;          // Reward tokens created per block.
    uint256 public immutable startBlock;              // The block number at which reward distribution starts.
    uint256 public immutable endBlock;                // The block number at which reward distribution ends.
    uint256 public immutable lockBlock;               // The block number at which deposit period ends.
    PoolInfo public poolInfo;

    mapping (address => UserInfo) public userInfo;     // Info of each user that stakes hMOCHI tokens.

    event Withdraw(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event Burn(uint256 amount);

    constructor(IERC20 _hMOCHI, IERC20 _REWARD, uint256 _rewardPerBlock, uint256 _startBlock, uint256 _endBlock, uint256 _lockBlock) public {
        require(address(_hMOCHI) != address(0), "_hMOCHI address not set!");
        require(address(_REWARD) != address(0), "_REWARD address not set!");
        require(_rewardPerBlock != 0, "_rewardPerBlock not set!");
        require(_startBlock < _lockBlock, "_startBlock too high!");
        require(_lockBlock < _endBlock, "_lockBlock too high!");

        hMOCHI = _hMOCHI;
        REWARD = _REWARD;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
        lockBlock = _lockBlock;

        poolInfo = PoolInfo({
            lastRewardBlock: _startBlock,
            accRewardPerShare: 0
        });
    }

    /**
     * @dev Return reward multiplier over the given _from to _to blocks based on block count.
     * @param _from First block.
     * @param _to Last block.
     * @return Number of blocks.
     */
    function getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to < endBlock) {
            return _to.sub(_from);
        } else if (_from >= endBlock) {
            return 0;
        } else {
            return endBlock.sub(_from);
        }     
    }

    /**
     * @dev View function to see pending rewards on frontend.
     * @param _user Address of a specific user.
     * @return Pending rewards.
     */
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = poolInfo.accRewardPerShare;
        uint256 hmochiSupply = hMOCHI.balanceOf(address(this));
        if (block.number > poolInfo.lastRewardBlock && hmochiSupply != 0) {
            uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(rewardPerBlock);
            accRewardPerShare = accRewardPerShare.add(tokenReward.mul(1e12).div(hmochiSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
    }

    /**
     * @dev Update reward variables of the given pool to be up-to-date.
     */
    function updatePool() public {
        if (block.number <= poolInfo.lastRewardBlock) {
            return;
        }
        uint256 hmochiSupply = hMOCHI.balanceOf(address(this));
        if (hmochiSupply == 0) {
            poolInfo.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(rewardPerBlock);
        poolInfo.accRewardPerShare = poolInfo.accRewardPerShare.add(tokenReward.mul(1e12).div(hmochiSupply));
        poolInfo.lastRewardBlock = block.number;
    }

    /**
     * @dev Deposit hMOCHI tokens to the Pool for rewards allocation and/or withdraw outstanding rewards.
     * @param _amount Amount of hMOCHI tokens to deposit.
     */
    function transact(uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 tempRewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);
            uint256 pending = tempRewardDebt.sub(user.rewardDebt);
            user.rewardDebt = tempRewardDebt; // Avoid reentrancy
            safeRewardTransfer(msg.sender, pending);
            emit Withdraw(msg.sender, pending);
        }
        if (block.number < lockBlock && _amount != 0) {
            hMOCHI.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
            user.rewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);
            emit Deposit(msg.sender, _amount);
        }
        if (block.number >= endBlock) {
            hMOCHI.safeTransfer(burnAddress, user.amount);
            user.amount = 0;
            user.rewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);
            emit Burn(user.amount);
        }
        user.rewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);
    }

    /**
     * @dev Safe transfer function, just in case if rounding error causes the Pool to not have enough rewards.
     * @param _to Target address.
     * @param _amount Amount of rewards to transfer.
     */
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBalance = REWARD.balanceOf(address(this));
        if (_amount > rewardBalance) {
            REWARD.safeTransfer(_to, rewardBalance);
        } else {
            REWARD.safeTransfer(_to, _amount);
        }
    }
}
