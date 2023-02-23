import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { PlatformAdminPanel } from "../typechain";

describe("PlatformAdminPanel", async () => {
    let user1: SignerWithAddress;
    let user2: SignerWithAddress;
    let adminPanel: PlatformAdminPanel;

    before(async () => {
        let signerList = await ethers.getSigners();

        user1 = signerList[0];
        user2 = signerList[signerList.length - 1];

        adminPanel = await (await ethers.getContractFactory("PlatformAdminPanel")).deploy(user1.address);
    });

    it("Add admin", async () => {
        await adminPanel.updateAdminList([user2.address], [], { from: user1.address });
        expect(await adminPanel.isAdmin(user2.address)).to.equal(true);
    });

    it("Rem admin", async () => {
        await adminPanel.updateAdminList([], [user2.address], { from: user1.address });
        expect(await adminPanel.isAdmin(user2.address)).to.equal(false);
    });

    it("Change root admin", async () => {
        adminPanel.setRootAdmin(user2.address, { from: user1.address });
        expect(await adminPanel.rootAdmin()).to.equal(user2.address);
    });
});