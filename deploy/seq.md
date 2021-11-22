0. Deploy VBase
1. Deploy Oracle
2. Deploy VPoolWrapperDeployer
3. Deploy VPoolFactory (VBase, VPoolWrapperDeployer)
   VBase - SetOwnerShip(VPoolFactory)
4. Deploy ClearingHouse(VPoolFactory, RealBase)
   ClearingHouse - setFixedFee

5. VPoolFactory - InitBridge(ClearingHouse)
