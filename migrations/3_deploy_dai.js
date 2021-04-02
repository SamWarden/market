const TToken = artifacts.require("TToken");
const MarketFactory = artifacts.require("MarketFactory");

module.exports = function (deployer) {
  deployer.deploy(TToken, 'Name', 'DAI', 18).then(function() {
    deployer.deploy(MarketFactory, TToken.address);
  });
};
