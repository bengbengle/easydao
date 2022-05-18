pragma solidity ^0.8.0;



import "../../core/DaoRegistry.sol";

interface IDistribute {
    function submitProposal(
        DaoRegistry dao,
        bytes32 proposalId,
        address unitHolderAdrr,
        address token,
        uint256 amount,
        bytes calldata data
    ) external;

    function processProposal(DaoRegistry dao, bytes32 proposalId) external;

    function distribute(DaoRegistry dao, uint256 toIndex) external;
}
