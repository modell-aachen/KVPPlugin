let baseConfig = require('./webpack.config.js');
let webpack = require('webpack');
let merge = require('webpack-merge');

module.exports = merge(baseConfig, {
  devtool: "inline-source-map",
  plugins: [
    new webpack.ProvidePlugin({
      moment: "moment"
    })
  ]
});

