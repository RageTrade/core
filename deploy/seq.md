0. Deploy VBase
1. Deploy Oracle
2. Deploy VPoolFactory (VBase, Oracle)
   VBase - SetOwnerShip(VPoolFactory)
3. Deploy ClearingHouse(VPoolFactory, RealBase)
   ClearingHouse - setFixedFee
4. VPoolFactory - InitBridge(ClearingHouse)
