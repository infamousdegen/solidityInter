// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

//@note using openzepplin's version of erc4626 because it is puts more checks
//@todo update converToShare and subtract the totalAsset() by the reward amount deposited
//@todo in convertToAsset change totalAsset to reward amount

import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "forge-std/console.sol";


contract Staking is ERC4626,Ownable2Step{
    using Math for uint256;

    IERC20 private immutable baseToken;

    //@todo I can reduce this to a small time unit
    uint64 immutable public timeConstant;
    //@note time when the contract was deployed
    uint64 immutable public deploymentTime;
    uint32 constant public decayingFactor1 = 2e3; //20% in basis points
    uint32 constant public decayingFactor2 = 5e3; //50% in basis points(20%+30%)
    uint32 constant public decayingFactor3 = 1e4; //100% in basis points(20%+30%+50%)

    uint256 constant denominator =  1e4; // 1,0000 to be used as denominator
    

    uint256 public rewardAmount;

    //tracking totalDeposit seperately to prevent inflation attack 
    uint256 public totalDeposit;


    //Errors

    error timePassed();
    error withdrawLocked();


//@Note: Gas efficient to call this inline but including it as a modifier for reaadeability
    modifier checkWithdraw() {
        //@audit test this 
        // if(uint64(block.timestamp + timeConstant) > uint64(block.timestamp) && uint64(block.timestamp) < uint64(block.timestamp + (2 * timeConstant))) revert withdrawLocked();
        _;
    }

//@Note : Its gas efficient to call this inline but including it as a modifier for readeability
    modifier poke() {
        syncRewards();
        _;
    }

    

    //@note Enter the time constant in second eg: 1 day = 86400 seconds
    constructor(IERC20 _baseToken,uint64 _timeConstant) ERC4626( _baseToken) ERC20("Staking","STK"){
        baseToken = _baseToken;

        timeConstant = _timeConstant;
        deploymentTime = uint64(block.timestamp);

    }


        /* -------------------------------------------------------------------
       |                      Public functions                               |
       | ________________________________________________________________ | */
    function deposit(uint256 assets, address receiver) public override returns(uint256){
        if(uint64(deploymentTime + timeConstant) < uint64(block.timestamp)) revert timePassed();       
        return(super.deposit(assets,receiver));
    }



    function mint(uint256 shares, address receiver) public override returns (uint256){

        if(uint64(deploymentTime + timeConstant) < uint64(block.timestamp)) revert timePassed();

        return(super.mint(shares,receiver));
    }

    //@Note: wont' break the interface because the reward amount is not minted as share (previewWithdraw)

    function withdraw(uint256 assets,address receiver,address owner) public override checkWithdraw poke returns(uint256){

            return(super.withdraw(assets,receiver,owner));
    }

    //@Note: wont' break the interface because the reward amount is not minted as share (previewRedeem)
    function redeem(uint256 shares,address receiver,address owner) public override checkWithdraw poke returns (uint256){
        return(super.redeem(shares,receiver,owner));
    }

       //@note: syncrewards has to called manually after transferring the tokens
    function syncRewards() public {
        rewardAmount = baseToken.balanceOf(address(this)) - totalDeposit;

    }


        /* -------------------------------------------------------------------
       |                      View functions                               |
       | ________________________________________________________________ | */
    function calculateRewards(address _depositor,Math.Rounding rounding) public view returns(uint256 rewards){
        uint256 supply = totalSupply();
        uint256 depositorShares = balanceOf(_depositor);
        uint256 factor;

        //No need to check if it is less than 2T because without 2T you cant deposit

        if (uint64(block.timestamp) < uint64(deploymentTime + (3*timeConstant))){
            factor = decayingFactor1;
        }

        else if(uint64(block.timestamp) < uint64(deploymentTime + (4*timeConstant))){
            factor = decayingFactor2;
        }

        else {
            factor = decayingFactor3;

        }
        console.log(factor);
        console.log(depositorShares);

        uint256 _denominator = (10**decimals()) * denominator;

        uint256 rewardPool = (rewardAmount.mulDiv(factor,_denominator,rounding));
        console.log(rewardPool);
        console.log(supply);
        console.log(rewardAmount);
    //@Note: multiplying by the decimals to decimal adjust the reward
        return
            (supply == 0 || depositorShares == 0)
            ? 0
            : (depositorShares.mulDiv(rewardPool,supply,rounding) * 10 **decimals());
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



    function _withdraw(address caller,address receiver,address owner,uint256 assets,uint256 shares) internal override{
        totalDeposit = totalDeposit - assets;
        assets = assets + calculateRewards(owner,Math.Rounding.Down);

        super._withdraw(caller,receiver,owner,assets,shares);
    }

    //@Note: Updating Total Deposit inside here because both deposit and mint will call this function in the end
    function _deposit(address caller,address receiver,uint256 assets,uint256 shares) internal override{
            totalDeposit = totalDeposit + assets;
            super._deposit(caller,receiver,assets,shares);
    }







}




