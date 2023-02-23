import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { PlatformAdminPanel, PlatformTokenPriceProvider } from "../typechain";

describe("PlatformTokenPriceProvider", async () => {
    let admin: SignerWithAddress;
    let priceProvider: PlatformTokenPriceProvider;

    before(async () => {
        const signerList = await ethers.getSigners();
        admin = signerList[0];

        let adminPanel = await (await ethers.getContractFactory("PlatformAdminPanel")).deploy(admin.address);
        priceProvider = await (await ethers.getContractFactory("PlatformTokenPriceProvider")).deploy(adminPanel.address);
    });

    it("Usd amount", async () => {
        await priceProvider.setHardcodeProvider(3, 5, { from: admin.address });
        expect(await priceProvider.usdAmount(1000)).to.equal(Math.floor(1000 * 3 / 5));
    });

    it("Token amount", async () => {
        await priceProvider.setHardcodeProvider(7, 11, { from: admin.address });
        expect(await priceProvider.tokenAmount(1000)).to.equal(Math.floor(1000 * 11 / 7));
    });
});