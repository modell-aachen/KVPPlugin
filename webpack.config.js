const path = require('path');
const zip = require('compression-webpack-plugin');
const ExtractTextPlugin = require("extract-text-webpack-plugin");

const devDir = path.join(__dirname, 'dev');
const testDir = path.join(__dirname, 'tests');

module.exports = {
    devtool: 'source-map',
    entry: {
        "vue-transitions": path.join(devDir, 'js', 'vue-transitions.js'),
    },
    output: {
        path: path.join(__dirname, 'pub/System/KVPPlugin'),
        filename: '[name].js',
    },
    resolve: {
        extensions: ['.vue', '.js']
    },
    watchOptions: {
        aggregateTimeout: 250,
        ignored: '/node_modules/',
        poll: 1000
    },
    plugins: [
        new zip({
            minRation: 1,
            include: [/\.(?:js|css)$/]
        }),
        new ExtractTextPlugin('[name].css'),
    ],
    module: {
        rules: [
            {
                test: /\.vue$/,
                loader: 'eslint-loader',
                include: [devDir],
                enforce: "pre"
            },
            {
                test: /\.vue$/,
                loader: 'vue-loader',
                include: [devDir],
                options: {
                    loaders: {
                        js:'babel-loader',
                    },
                }
            },
            {
                test: /\.js$/,
                loader: 'babel-loader',
                include: [devDir, testDir],
            },
            {
                test: /\.s[ac]ss$/,
                include: [devDir],
                loader: ExtractTextPlugin.extract({
                    fallback: 'style-loader',
                    use: [ 'css-loader', 'sass-loader' ],
                }),
            },
            {
                test: /\.json$/,
                include: [devDir],
                loader: 'json-loader'
            }
        ]
    }
};