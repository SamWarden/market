//Example creating of a Market. Paste it to `hardhat console` to execute
let {formatEther, parseEther} = ethers.utils;
let MarketFactory = await ethers.getContractFactory("MarketFactory");
let TToken = await ethers.getContractFactory("TToken");
let Market = await ethers.getContractFactory("Market");
let ConditionalToken = await ethers.getContractFactory("ConditionalToken");
let acc = await ethers.getSigner();
let dai = await TToken.deploy("Dai", "Dai", 18);
await dai.deployed();
let ct = await ConditionalToken.deploy();
await ct.deployed();
let link = await TToken.attach("0xa36085F69e2889c224210F603D836748e7dC0088"); //Kovan link-token
await link.deployed();
let bm = await Market.deploy();
await bm.deployed();
let mf = await MarketFactory.deploy(bm.address, ct.address);
await mf.deployed();
await mf.setBaseCurrency("ETH", true);
await mf.setCollateralCurrency("DAI", dai.address);
await mf.setProtocolFee(parseEther("0.003"))
await dai.mint(acc.address, parseEther("20000"));
await dai.approve(mf.address, parseEther("10000"));
await link.approve(mf.address, parseEther("0.2"));
await mf.create("ETH", "DAI", 600, parseEther("10000"));
let m = Market.attach(mf.marketList(0));
await dai.approve(m.address, parseEther("10000"));
let bull = ConditionalToken.attach(await m.bullToken());
let bear = ConditionalToken.attach(await m.bearToken());

await m.buy(parseEther("1000"));
await bull.approve(m.address, parseEther("100"));
await bear.approve(m.address, parseEther("100"));

await m.close();
await m.redeem(parseEther("100"));
