// SPDX-License-Identifier: UNLICENSED
//@title: Bank contract which will distribute the rewards based on timestamp and share of the pool
pragma solidity ^0.8.13;

//@dev: Using Openzepplin's implementation of ERC4626 and overriding most of the function to adapt to the requirment


import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";




contract Staking is ERC4626,Ownable2Step{
    using Math for uint256;
    using SafeERC20 for IERC20;


    IERC20 private immutable baseToken;

    // @dev: Diviging into three seperate pool
    struct SUBPOOL {
        uint256 pool1;
        uint256 pool2;
        uint256 pool3;
    }

    // @dev: State variable subPool of type SUBPOOL
    SUBPOOL subPool;
    

    //@dev: uint64 is (2**64)-1 which is more than enough to hold the current time stamp
    uint64 immutable public timeConstant;

    //  @dev: deploymentTime won't change
    uint64 immutable public deploymentTime;

    // @dev: deploymentTime + (nT) where n in [1,2,3,4] respectively
    // @custom:gas Instead of calculating in contract storing it as immutable saves gas
    uint64 immutable public timeConstant0;
    uint64 immutable public timeConstant1; 
    uint64 immutable public timeConstant2; 
    uint64 immutable public timeConstant3; 


    //@dev: corresponind percentage in basis points 
    uint32 constant public decayingFactor1 = 2e3; //20% in basis points
    uint32 constant public decayingFactor2 = 3e3; //30% in basis points
    uint32 constant public decayingFactor3 = 5e3; //50% in basis points
    uint256 constant denominator =  1e4; // 1,0000 to be used as denominator for basis point calculation
    

    //@dev: Useful if the owner wants to transfer more rewards rather than the initial 1000 tokens
    //@custom:gas Cost extra sload and other opcodes but worth it if owner wants to transfer more reward pool
    uint256 public totalRewardAvailable;

    //@dev: Necessary to calculate the total deposit because the underlying reward token that was transferred should not considered as underlying balance
    uint256 public totalDeposit;




    error timePassed();
    error withdrawLocked();
    

    //@dev: Constructor which takes in the basetoken and the time constant
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

    
    //@dev: User deposit function where they can deposit the tokens in terms of undelying assets
    //@custom: gas Better the use inline revert statement than modifier because in modifier the entire code block is copied into "_;" and not worth the readility 
    //@param assets the number of assets to deposit
    //@param receiver the receiver of the shares

    function deposit(uint256 assets, address receiver) public override returns(uint256){
        if (uint64(block.timestamp) > uint64(deploymentTime + timeConstant)) revert timePassed();       
        return(super.deposit(assets,receiver));
    }


    //@dev: User mint function which will calculate the shares to be transferred form the user to this contract based on shares the user wants
    //@param shares the number of sahres that the user wants
    //@param receiver the receiver of the shares
    function mint(uint256 shares, address receiver) public override returns (uint256){

        if (uint64(block.timestamp) > uint64(deploymentTime + timeConstant)) revert timePassed(); 

        return(super.mint(shares,receiver));
    }


    
    //@dev: User withdraw function where they can withdraw the tokens in terms of undelying assets will automatically calculate the underlying shares ot be burned
    //@param assets the number of assets the user wants to withdraw 
    //@param receiver the receiver of the assets
    //@param _owner the owner of the shares

    function withdraw(uint256 assets,address receiver,address _owner) public override returns(uint256){
        if(uint64(block.timestamp) > uint64(timeConstant0) 
        && uint64(block.timestamp) < uint64(timeConstant1)) 
        revert withdrawLocked();


        syncRewards();
            
        return(super.withdraw(assets,receiver,_owner));
    }


    //@dev: User redeem function where they can withdraw in terms of undelying shares the holders
    //@param shares the number of shares to be burned 
    //@param receiver the receiver of the assets
    //@param _owner the owner of the shares

    function redeem(uint256 shares,address receiver,address _owner) public override returns (uint256){
        if(uint64(block.timestamp) > uint64(timeConstant0) 
        && uint64(block.timestamp) < uint64(timeConstant1)) 
        revert withdrawLocked();

        syncRewards();

        return(super.redeem(shares,receiver,_owner));
    }

    
    //@dev: will sync the totalRewardAvailable based on the undelying balance - deposit of the users and divide the total reward into subpools based on the basis point percentage
    //@dev: Will be called before deposit or redeem to make sure the rewards are properly synced
    //@dev: Can be easily modifier to be called only once 
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




    //@dev: Core function which will calculate the reward to distributed
    //@param: _depositor user who holds the shares 
    //@param: Math.Rounding rounding to round down the division value towards negative infinity
    function calculateRewards(address _depositor,Math.Rounding rounding) internal returns(uint256 rewards){
        uint256 totalReward;

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



    //@dev to be called by the calculatedRewards which will calculate reward based on corresponding subpool proportional to share of the depositor 
    //@praram _depositorShares shares of the depositor
    //@param acutalAmount  remaining amount of the corresponding subpool
    //@param _supply total supply of the share token
    function _calculateRewards(uint256 _depositorShares,uint256 actualAmount,uint256 _supply,Math.Rounding rounding) internal pure returns(uint256){
        return
            (_supply == 0 || _depositorShares == 0)
            ? 0
            : (_depositorShares.mulDiv(actualAmount,_supply,rounding));
    }



    //@dev Core function which will convert shares to the assets
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view override returns (uint256 shares) {
        uint256 supply = totalSupply();
        return
            (assets == 0 || supply == 0)
                ? _initialConvertToShares(assets, rounding)
                : assets.mulDiv(supply, totalDeposit, rounding);
    }

     //@dev Core function which will convert assets to the shares
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view override returns (uint256 assets) {
        uint256 supply = totalSupply();
        return
            (supply == 0) ? _initialConvertToAssets(shares, rounding) : shares.mulDiv(totalDeposit, supply, rounding);
    }






    //@dev Core functionw which will calculate the reward to be distributed along with the share of the subpool performs the transfer
    function _withdraw(address caller,address receiver,address _owner,uint256 assets,uint256 shares) internal override{
        totalDeposit = totalDeposit - assets;


        assets = assets + calculateRewards(_owner,Math.Rounding.Down);

        super._withdraw(caller,receiver,_owner,assets,shares);
    }

    //@dev Core functionw which will update total deposit and calls transferFrom
    function _deposit(address caller,address receiver,uint256 assets,uint256 shares) internal override{
            totalDeposit = totalDeposit + assets;
            super._deposit(caller,receiver,assets,shares);
    }


    //@dev Owner function to withdraw the remaining tokems if  timestamp is great than 4T and totalDeposit ==0

    function ownerWithdraw(address _addy) external onlyOwner{
        require((block.timestamp > timeConstant3) && totalDeposit == 0,"Not allowed yet");
        baseToken.safeTransfer(_addy,baseToken.balanceOf(address(this)));
    }

}




