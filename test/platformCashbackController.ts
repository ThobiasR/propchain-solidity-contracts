import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { PlatformTokenPriceProvider, PlatformToken, PlatformVesting, PlatformStaking, PlatformCashbackController } from "../typechain";

describe("PlatformCashbackController", async () => {
    let admin: SignerWithAddress;
    let user0: SignerWithAddress;
    let user1: SignerWithAddress;

    let provider: PlatformTokenPriceProvider;
    let token: PlatformToken;
    let staking: PlatformStaking;
    let cashback: PlatformCashbackController;

    before(async () => {
        const signerList = await ethers.getSigners();
        admin = signerList[0];
        user0 = signerList[1];
        user1 = signerList[2];

        const panel = await (await ethers.getContractFactory("PlatformAdminPanel")).deploy(admin.address);
        provider = await (await ethers.getContractFactory("PlatformTokenPriceProvider")).deploy(panel.address);
        token = await (await ethers.getContractFactory("PlatformToken")).deploy(panel.address);
        staking = await (await ethers.getContractFactory("PlatformStaking")).deploy(
            panel.address,
            "1000000000000000000000",
            "10000000000000000000000",
            "100000000000000000000000",
            "1000000000000000000000000",
            "0",
            "3600"
        );
        cashback = await (await ethers.getContractFactory("PlatformCashbackController")).deploy(panel.address);

        await provider.setHardcodeProvider(1, 2);
        await token.initiate(
            admin.address,  //
            staking.address,
            cashback.address,
            admin.address,
            "1000000000000000000000000000000000000"
        );
        await staking.initiate(
            token.address,
            admin.address, //
            provider.address
        );
        await cashback.initiate(
            provider.address,
            token.address,
            staking.address,
            admin.address, //
            {
                freeShare: "0",
                starShare: "2000",
                moviShare: "10000",
                moguShare: "12000",
                tycoShare: "14000",
            },
            {
                freeUsdLimit: "0",
                starUsdLimit: "10000000000000",
                moviUsdLimit: "100000000000000",
                moguUsdLimit: "1000000000000000",
                tycoUsdLimit: "10000000000000000",
            },
            {
                distributeDuration: 10,
                claimDuration: 0,
            }
        );

        await token.transfer(user1.address, "100000000000000000000000");
        await staking.connect(user1).stake(2, []);
    });

    it("Increase liqudity", async () => {
        const before = await token.balanceOf(admin.address);

        await cashback.increaseLiqudity("100000000000000000000000000000000");
        const liqudity = await cashback.liqudity();

        const after = await token.balanceOf(admin.address);

        expect(after.add(liqudity)).to.equal(before);
    });

    it("Distribute for FREE (nothing happens)", async () => {
        await cashback.distribute(user0.address, "1000000000000000000000000");

        const time = 60 + Math.ceil(Date.now() / 1000);
        const amount = await cashback.amountForClaim(user0.address, time);

        expect(amount).to.equal(0);
    });

    it("Distribute for MOVI, check limit", async () => {
        const time = 60 + Math.ceil(Date.now() / 1000);

        await cashback.distribute(user1.address, "1000000000000000");

        const before = await cashback.amountForClaim(user1.address, time);

        await cashback.distribute(user1.address, "1000000000000000");

        const after = await cashback.amountForClaim(user1.address, time);
        expect(after).to.equal(before);
    });

    it("Claim", async () => {
        await (new Promise<void>((res, rej) => setTimeout(() => res(), 10_000)));

        const time = 60 + Math.ceil(Date.now() / 1000);

        const before = await token.balanceOf(user1.address);
        const amount = await cashback.amountForClaim(user1.address, time);

        await cashback.claim(user1.address);

        const after = await token.balanceOf(user1.address);

        expect(before.add(amount)).to.equal(after);
    });
});