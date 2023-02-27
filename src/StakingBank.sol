// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//@note using openzepplin's version of erc4626 because it is puts more checks
//@todo update converToShare and subtract the totalAsset() by the reward amount deposited
//@todo in convertToAsset change totalAsset to reward amount

import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Staking is ERC4626,Ownable2Step{

    //@todo I can reduce this to a small time unit
    uint64 immutable public timeConstant;
    //@note time when the contract was deployed
    uint64 immutable public deploymentTime;

    uint32 constant public decayingFactor1 = 2e3; //20% in basis points
    uint32 constant public decayingFactor2 = 3e3; //30% in basis points
    uint32 constant public decayingFactor3 = 5e3; //50% in basis points
    uint32 constant denominator =  1e4; // 1,0000 to be used as denominator

    uint256 public rewardAmount;

    //Snapshot Of Deposit Time
    mapping(address => uint64) public snapshot;

    //Errors

    error timePassed();
    error withdrawLocked();

//@note: using inline check saves gas compared to modifier but including this for readability
    modifier checkWithdraw() {
        //@audit test this 
        if(uint64(block.timestamp + timeConstant) > uint64(block.timestamp) && uint64(block.timestamp) < uint64(block.timestamp + (2 * timeConstant))) revert withdrawLocked();
        _;
    }

    

    //@note Enter the time constant in second eg: 1 day = 86400 seconds
    constructor(IERC20 _baseToken,uint64 _timeConstant,uint256 _rewardAmotunt) ERC4626( _baseToken) ERC20("Staking","STK"){
        timeConstant = _timeConstant;
        deploymentTime = uint64(block.timestamp);
        rewardAmount = _rewardAmotunt;

    }



    function deposit(uint256 assets, address receiver) public override returns(uint256){
        if(uint64(deploymentTime + timeConstant) < uint64(block.timestamp)) revert timePassed();

        snapshot[receiver] = uint64(block.timestamp);
        
        return(super.deposit(assets,receiver));
    }

    function mint(uint256 shares, address receiver) public override returns (uint256){

        if(uint64(deploymentTime + timeConstant) < uint64(block.timestamp)) revert timePassed();
        snapshot[receiver] = uint64(block.timestamp);
        return(super.mint(shares,receiver));
    }

//@audit test these
    // function withdraw(uint256 assets,address receiver) public  override checkWithdraw returns(uint256){
    //     super.withdraw(assets,receiver,owner());
    // }

    //@note:Updating the convertoAssets internal function
    //@note: The actual withdraw or redeem will cal convertToAsset


    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256 shares){
        uint256 supply = totalSupply();
        uint256 totalAsset = totalAssets() - rewardAmount;
        return
            (assets == 0 || supply == 0)
                ? _initialConvertToShares(assets, rounding)
                : assets.mulDiv(supply, totalAsset, rounding);
    }
    }


    function _convertToAssets(address _owner,uint256 shares, Math.Rounding rounding) internal view override returns (uint256 assets){
        uint64 depositTime = snapshot[_owner];




    }
    


}




