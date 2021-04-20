//Example creating of a Market. Paste it to `hardhat console` to execute
{formatEther, parseEther} = ethers.utils
MarketFactory = await ethers.getContractFactory("MarketFactory");
TToken = await ethers.getContractFactory("TToken");
Market = await ethers.getContractFactory("Market");
ConditionalToken = await ethers.getContractFactory("ConditionalToken");
a = await ethers.getSigner();
dai = await TToken.deploy("Dai", "Dai", 18);
await dai.deployed();
ct = await ConditionalToken.deploy();
await ct.deployed();
link = await TToken.attach("0xa36085F69e2889c224210F603D836748e7dC0088");
await link.deployed();
m = await Market.deploy();
await m.deployed();
mf = await MarketFactory.deploy(m.address, ct.address);
await mf.deployed();
await mf.setBaseCurrency("ETH", true);
await mf.setCollateralCurrency("DAI", dai.address);
await mf.setProtocolFee(parseEther("0.003"))
await dai.mint(a.address, ethers.utils.parseEther("20000"));
await dai.approve(mf.address, ethers.utils.parseEther("10000"));
await link.approve(mf.address, ethers.utils.parseEther("0.2"));
await mf.create("ETH", "DAI", 600, ethers.utils.parseEther("10000"));
v = Market.attach(mf.marketList(0));
await dai.approve(v.address, ethers.utils.parseEther("10000"));
bull = ConditionalToken.attach(await v.bullToken());
bear = ConditionalToken.attach(await v.bearToken());

await v.buy(ethers.utils.parseEther("1000"));
await bull.approve(v.address, ethers.utils.parseEther("100"));
await bear.approve(v.address, ethers.utils.parseEther("100"));

await v.close();
await v.redeem(parseEther("100"))
