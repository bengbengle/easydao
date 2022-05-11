/**
 * 此处定义的角色与 GovernanceHelper.sol 中可用的角色匹配，
 * 否则角色将不起作用。
 */
export const governanceRoles: Record<string, string> = {
  ONLY_GOVERNOR: "governance.role.$contractAddress",
};
