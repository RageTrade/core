0. Deploy VBase
1. Deploy Oracle
2. Deploy VPoolWrapperDeployer (FutureVPoolFactory)
3. Deploy ClearingHouse(FutureVPoolFactory, RealBase)
4. Deploy VPoolFactory (VBase, VPoolWrapperDeployer, ClearingHouse)
   VBase - SetOwnerShip(VPoolFactory)
   ClearingHouse - setFixedFee
