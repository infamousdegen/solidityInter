// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//@note using openzepplin's version of erc4626 because it is puts more checks
//@todo change time constant to immutable to save gas

import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/console.sol";

//@


contract Staking is ERC4626,Ownable2Step{
    using Math for uint256;
    using SafeERC20 for IERC20;


    IERC20 private immutable baseToken;


    struct SUBPOOL {
        uint256 pool1;
        uint256 pool2;
        uint256 pool3;
    }

    SUBPOOL subPool;
    

    //@todo I can reduce this to a small time unit
    uint64 immutable public timeConstant;
    //@note time when the contract was deployed
    uint64 immutable public deploymentTime;

    uint64 immutable public timeConstant0; //deploymentTime + T;
    uint64 immutable public timeConstant1; //deployment time + 2T
    uint64 immutable public timeConstant2; //deployment time + 3T
    uint64 immutable public timeConstant3; //deployment time + 4T

    uint32 constant public decayingFactor1 = 2e3; //20% in basis points
    uint32 constant public decayingFactor2 = 3e3; //30% in basis points
    uint32 constant public decayingFactor3 = 5e3; //50% in basis points

    uint256 constant denominator =  1e4; // 1,0000 to be used as denominator
    

    uint256 public totalRewardAvailable;

    uint256 public totalDeposit;




    //Errors

    error timePassed();
    error withdrawLocked();
    

    //@note Enter the time constant in second eg: 1 day = 86400 seconds
    constructor(IERC20 _baseToken,uint64 _timeConstant) ERC4626( _baseToken) ERC20("Staking","STK"){
        baseToken = _baseToken;

        timeConstant = _timeConstant;
        deploymentTime = uint64(block.timestamp);

        timeConstant0 = deploymentTime + timeConstant;
        timeConstant1 = deploymentTime + (2*timeConstant);
        timeConstant2 = deploymentTime + (3*timeConstant);
        timeConstant3 = deploymentTime + (4*timeConstant);

    }


        /* -------------------------------------------------------------------
       |                      Public functions                               |
       | ________________________________________________________________ | */

    
    //@Gas: Gas efficient to use inline revert statement than modifiers;
    function deposit(uint256 assets, address receiver) public override returns(uint256){
        if (uint64(block.timestamp) > uint64(deploymentTime + timeConstant)) revert timePassed();       
        return(super.deposit(assets,receiver));
    }


    //@Gas: Gas efficient to use inline revert statement than modifiers;
    function mint(uint256 shares, address receiver) public override returns (uint256){

        if (uint64(block.timestamp) > uint64(deploymentTime + timeConstant)) revert timePassed(); 

        return(super.mint(shares,receiver));
    }


    //@Gas: Gas efficient to use inline revert statement than modifiers;

    function withdraw(uint256 assets,address receiver,address _owner) public override returns(uint256){
        if(uint64(block.timestamp) > uint64(deploymentTime + timeConstant) 
        && uint64(block.timestamp) < uint64(deploymentTime + (2 * timeConstant))) 
        revert withdrawLocked();


        syncRewards();
            
        return(super.withdraw(assets,receiver,_owner));
    }


    //@Gas: Gas efficient to use inline revert statement than modifiers;
    function redeem(uint256 shares,address receiver,address _owner) public override returns (uint256){
        if(uint64(block.timestamp) > uint64(deploymentTime + timeConstant) 
        && uint64(block.timestamp) < uint64(deploymentTime + (2 * timeConstant))) 
        revert withdrawLocked();

        syncRewards();

        return(super.redeem(shares,receiver,_owner));
    }

       //@note: syncrewards has to called manually after the initial transfer tokens
    function syncRewards() public { 
        uint256 rewardAmountCache = (baseToken.balanceOf(address(this)) - totalDeposit);

        if(rewardAmountCache > totalRewardAvailable){
        SUBPOOL memory poolCache = subPool;

        poolCache.pool1 = poolCache.pool1 + rewardAmountCache.mulDiv(decayingFactor1,denominator);

        poolCache.pool2 = poolCache.pool2 + rewardAmountCache.mulDiv(decayingFactor2,denominator);

        poolCache.pool3 = poolCache.pool3 + rewardAmountCache.mulDiv(decayingFactor3,denominator);
        
        subPool = poolCache;

        }

        totalRewardAvailable = rewardAmountCache;
        
    }



    function calculateRewards(address _depositor,Math.Rounding rounding) internal returns(uint256 rewards){
        uint256 totalReward;

        //@note dont have to calculate any of these if block.timestamp is not greater than 2T

        if(uint64(block.timestamp) > uint64(timeConstant1)){

        uint256 supply = totalSupply();
        uint256 depositorShares = balanceOf(_depositor);

        SUBPOOL memory subpoolCache = subPool;

        if (uint64(block.timestamp) < uint64(timeConstant2)){
            totalReward = _calculateRewards(depositorShares,subpoolCache.pool1,supply,rounding);
            subpoolCache.pool1 = subpoolCache.pool1 - totalReward;


        }

        else if(uint64(block.timestamp) < uint64(timeConstant3)){
            uint256 reward1 = _calculateRewards(depositorShares,subpoolCache.pool1,supply,rounding);
            uint256 reward2 = _calculateRewards(depositorShares,subpoolCache.pool2,supply,rounding);
            subpoolCache.pool1 = subpoolCache.pool1 - reward1;
            subpoolCache.pool2 = subpoolCache.pool2 - reward2;
            totalReward = reward1 + reward2;

        }

        else {
            uint256 reward1 = _calculateRewards(depositorShares,subpoolCache.pool1,supply,rounding);
            uint256 reward2 = _calculateRewards(depositorShares,subpoolCache.pool2,supply,rounding);
            uint256 reward3 = _calculateRewards(depositorShares,subpoolCache.pool3,supply,rounding);
            subpoolCache.pool1 = subpoolCache.pool1 - reward1;
            subpoolCache.pool2 = subpoolCache.pool2 - reward2;
            subpoolCache.pool3 = subpoolCache.pool3 - reward3;
            totalReward = reward1 + reward2 + reward3;


        }

        subPool = subpoolCache;

        }
        

        return(totalReward);


    }




    function _calculateRewards(uint256 _depositorShares,uint256 actualAmount,uint256 _supply,Math.Rounding rounding) internal pure returns(uint256){
            //@Note: multiplying by the decimals to decimal adjust the reward
        return
            (_supply == 0 || _depositorShares == 0)
            ? 0
            : (_depositorShares.mulDiv(actualAmount,_supply,rounding));
    }



        //@Note Overriding to change totalAsset to totalDeposit as reward amount should not be calculated as stake

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        return
            (assets == 0 || supply == 0)
                ? _initialConvertToShares(assets, rounding)
                : assets.mulDiv(supply, totalDeposit, rounding);
    }

    //@Note Overriding to change totalAsset to totalDeposit as reward amount should not be calculated as stake
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        return
            (supply == 0) ? _initialConvertToAssets(shares, rounding) : shares.mulDiv(totalDeposit, supply, rounding);
    }




        /* -------------------------------------------------------------------
       |                      Core functions                               |
       | ________________________________________________________________ | */



    function _withdraw(address caller,address receiver,address _owner,uint256 assets,uint256 shares) internal override{
        totalDeposit = totalDeposit - assets;


        assets = assets + calculateRewards(_owner,Math.Rounding.Down);

        super._withdraw(caller,receiver,_owner,assets,shares);
    }

    //@Note: Updating Total Deposit inside here because both deposit and mint will call this function in the end
    function _deposit(address caller,address receiver,uint256 assets,uint256 shares) internal override{
            totalDeposit = totalDeposit + assets;
            super._deposit(caller,receiver,assets,shares);
    }

        /* -------------------------------------------------------------------
       |                      Owner functions                               |
       | ________________________________________________________________ | */


    function ownerWithdraw(address _addy) external onlyOwner{
        require((block.timestamp > timeConstant3) && totalDeposit == 0,"Not allowed yet");
        baseToken.safeTransfer(_addy,baseToken.balanceOf(address(this)));
    }

}




