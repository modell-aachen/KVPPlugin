const CompressionPlugin = require('compression-webpack-plugin');

const isProduction = () => process.env.NODE_ENV === 'production';

const plugins = [];
if (isProduction()) {
    plugins.push(new CompressionPlugin({
        include: [/\.(?:js|css)$/],
    }));
}

module.exports = {
    configureWebpack: {
        plugins: plugins,
        optimization: {
            splitChunks: false,
        },
        output: {
            filename: '[name].js',
        },
    },
    css: {
        extract: false,
    },
    chainWebpack: config => {
        page = 'vue-transitions';
        config.plugins.delete(`html-${page}`);
        config.plugins.delete(`preload-${page}`);
        config.plugins.delete(`prefetch-${page}`);
    },
    productionSourceMap: true,
    outputDir: 'pub/System/KVPPlugin',
    pages: {
        'vue-transitions': {
            entry: 'dev/js/vue-transitions.js',
        },
    },
};
