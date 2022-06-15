import { expect } from 'chai';
import hre, { ethers } from 'hardhat';
import { GovernableTest } from '../../typechain-types';

describe('Governable', () => {
  const governableFixture = hre.deployments.createFixture(async hre => {
    const factory = await hre.ethers.getContractFactory('GovernableTest');
    return { governable: await factory.deploy() };
  });

  describe('#deploy', () => {
    it('sets variables', async () => {
      const { governable } = await governableFixture();
      const [signer] = await hre.ethers.getSigners();
      expect(await governable.governance()).to.eq(signer.address);
      expect(await governable.teamMultisig()).to.eq(signer.address);
    });
  });

  describe('#transfer', () => {
    it('initiates governance transfer', async () => {
      const { governable } = await governableFixture();
      const [signer, otherSigner] = await hre.ethers.getSigners();
      await governable.initiateGovernanceTransfer(otherSigner.address);

      // sets pending variables
      expect(await governable.governancePending()).to.eq(otherSigner.address);
      expect(await governable.teamMultisigPending()).to.eq(ethers.constants.AddressZero);

      // does not change ownership variables
      expect(await governable.governance()).to.eq(signer.address);
      expect(await governable.teamMultisig()).to.eq(signer.address);
    });

    it('initiates teamMultisig transfer by governance', async () => {
      const { governable } = await governableFixture();
      const [signer, otherSigner] = await hre.ethers.getSigners();
      await governable.initiateTeamMultisigTransfer(otherSigner.address);

      // sets pending variables
      expect(await governable.governancePending()).to.eq(ethers.constants.AddressZero);
      expect(await governable.teamMultisigPending()).to.eq(otherSigner.address);

      // does not change ownership variables
      expect(await governable.governance()).to.eq(signer.address);
      expect(await governable.teamMultisig()).to.eq(signer.address);
    });

    it('initiates teamMultisig transfer by team multisig address', async () => {
      const { governable } = await governableFixture();
      const [signer, teamMultisig, otherAccount] = await hre.ethers.getSigners();

      // first making team multisig owner
      await governable.initiateTeamMultisigTransfer(teamMultisig.address);
      await governable.connect(teamMultisig).acceptTeamMultisigTransfer();

      // does not change ownership variables
      expect(await governable.governance()).to.eq(signer.address);
      expect(await governable.teamMultisig()).to.eq(teamMultisig.address);

      await governable.connect(teamMultisig).initiateTeamMultisigTransfer(otherAccount.address);

      // sets pending variables
      expect(await governable.governancePending()).to.eq(ethers.constants.AddressZero);
      expect(await governable.teamMultisigPending()).to.eq(otherAccount.address);
    });

    it('accepts governance transfer', async () => {
      const { governable } = await governableFixture();
      const [signer, otherSigner] = await hre.ethers.getSigners();

      await governable.initiateGovernanceTransfer(otherSigner.address);

      await expect(governable.acceptGovernanceTransfer()).to.be.revertedWith('Unauthorised()');

      await governable.connect(otherSigner).acceptGovernanceTransfer();

      // resets pending variable
      expect(await governable.governancePending()).to.eq(ethers.constants.AddressZero);

      // only changes governance address
      expect(await governable.governance()).to.eq(otherSigner.address);
      expect(await governable.teamMultisig()).to.eq(signer.address); // still the original signer
    });

    it('accepts teamMultisig transfer', async () => {
      const { governable } = await governableFixture();
      const [signer, otherSigner] = await hre.ethers.getSigners();

      await governable.initiateTeamMultisigTransfer(otherSigner.address);

      await expect(governable.acceptTeamMultisigTransfer()).to.be.revertedWith('Unauthorised()');

      await governable.connect(otherSigner).acceptTeamMultisigTransfer();

      // resets pending variable
      expect(await governable.teamMultisigPending()).to.eq(ethers.constants.AddressZero);

      // only changes teamMultisig address
      expect(await governable.governance()).to.eq(signer.address); // still the original signer
      expect(await governable.teamMultisig()).to.eq(otherSigner.address);
    });

    it('can change pending address to something again', async () => {
      const { governable } = await governableFixture();
      const [signer, signer2, signer3] = await hre.ethers.getSigners();

      await governable.initiateGovernanceTransfer(signer2.address);
      expect(await governable.governancePending()).to.eq(signer2.address);

      await governable.initiateGovernanceTransfer(signer3.address);
      expect(await governable.governancePending()).to.eq(signer3.address);
    });

    it('can cancel transfer', async () => {
      const { governable } = await governableFixture();
      const [signer, signer2] = await hre.ethers.getSigners();

      await governable.initiateGovernanceTransfer(signer2.address);
      expect(await governable.governancePending()).to.eq(signer2.address);

      await governable.initiateGovernanceTransfer(ethers.constants.AddressZero);
      expect(await governable.governancePending()).to.eq(ethers.constants.AddressZero);
    });
  });
});
