import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { PlatformToken, PlatformVesting, PlatformStaking } from "../typechain";

describe("PlatformVestingAndStaking", async () => {
    let admin: SignerWithAddress;
    let user: SignerWithAddress;

    let token: PlatformToken;

    let vesting: PlatformVesting;

    const stP = {
        tierRequirements: {
            0: "0",
            1: "1000000000000000000000",
            2: "10000000000000000000000",
            3: "100000000000000000000000",
            4: "1000000000000000000000000",
        },
        fee: 10000,
        lockTime: 1,
    }
    let staking: PlatformStaking;

    before(async () => {
        const signerList = await ethers.getSigners();
        admin = signerList[0];
        user = signerList[signerList.length - 1];

        let panel = await (await ethers.getContractFactory("PlatformAdminPanel")).deploy(admin.address);
        let provider = await (await ethers.getContractFactory("PlatformTokenPriceProvider")).deploy(panel.address);

        token = await (await ethers.getContractFactory("PlatformToken")).deploy(panel.address);
        vesting = await (await ethers.getContractFactory("PlatformVesting")).deploy(panel.address);
        staking = await (await ethers.getContractFactory("PlatformStaking")).deploy(
            panel.address,
            stP.tierRequirements[1],
            stP.tierRequirements[2],
            stP.tierRequirements[3],
            stP.tierRequirements[4],
            stP.fee,
            stP.lockTime
        );

        await token.initiate(
            vesting.address,
            staking.address,
            "0x0000000000000000000000000000000000000000",
            admin.address,
            "1000000000000000000000000000000",
            { from: admin.address }
        );

        await vesting.initiate(token.address, staking.address, { from: admin.address });
        await staking.initiate(
            token.address,
            vesting.address,
            provider.address,
            { from: admin.address }
        );

        await provider.setHardcodeProvider(1, 1, { from: admin.address });

        const now = Math.floor(Date.now() / 1000);
        await vesting.insertVestingList(
            [
                {
                    isStakeSupport: true,
                    amountForUser: "5000000000000000000000",
                    tgeAmountForUser: "1000000000000000000000",
                    startTime: now,
                    tickCount: 1,
                    tickDuration: 45,
                    unallocateAmount: "10000000000000000000000",
                },
                {
                    isStakeSupport: true,
                    amountForUser: "5000000000000000000000",
                    tgeAmountForUser: "1000000000000000000000",
                    startTime: now,
                    tickCount: 1,
                    tickDuration: 45,
                    unallocateAmount: "10000000000000000000000",
                },
            ],
            { from: admin.address }
        );

        await new Promise<void>((res) => setTimeout(() => res(), 3000));
    });

    it("Add user to vesting", async () => {
        await vesting.updateUserListBatch(
            [[user.address], [user.address]],
            [[], []],
            { from: admin.address }
        );

        expect((await vesting.userPropertiesList(user.address))[0].isActive).to.equal(true);
        expect((await vesting.userPropertiesList(user.address))[1].isActive).to.equal(true);
    });

    it("Claim tge", async () => {
        const before = await token.balanceOf(user.address);

        const now = Math.floor(Date.now() / 1000);
        const amounts = await vesting.amountForClaimList(user.address, now);

        await vesting.claimBatch(user.address);

        const after = await token.balanceOf(user.address);

        expect(before.add(amounts[0]).add(amounts[1]).toString()).to.equal(after.toString());
    });

    it("Stake", async () => {
        const now = Math.floor(Date.now() / 1000);
        await staking.connect(user).stake(
            "2",
            ["4000000000000000000000", "4000000000000000000000"]
        );

        const res = await staking.userTier(user.address, now);
        expect(res.tier).to.equal(2);
        expect(res.isTierTurnOn).to.equal(true);
    });

    it("Rem user from vesting", async () => {
        await vesting.updateUserListBatch(
            [[], []],
            [[user.address], [user.address]],
            { from: admin.address }
        );

        expect((await vesting.userPropertiesList(user.address))[0].isActive).to.equal(false);
        expect((await vesting.userPropertiesList(user.address))[1].isActive).to.equal(false);
    });

    it("Decrease liqudity", async () => {
        await vesting.updateLiqudityBatch(
            ["0", "0"],
            ["9000000000000000000000", "9000000000000000000000"]
        );

        const before = await token.balanceOf(admin.address);

        const add = (await vesting.vestingPropertiesList())
            .map(x => x.unallocateAmount)
            .reduce((x, y) => x.add(y));

        const after = await token.balanceOf(admin.address);

        expect(before.add(add)).to.equal(after);
    });

    it("Unstake", async () => {
        await staking.connect(user).unstake();
        expect((await token.balanceOf(user.address)).toString()).to.equal("1800000000000000000000");
    });

    it("Withdraw stake fee", async () => {
        const before = await token.balanceOf(admin.address);

        const add = await staking.amountForWithdraw();
        await staking.withdraw();

        const after = await token.balanceOf(admin.address);

        expect(before.add(add).toString()).to.equal(after.toString());
    });
});
