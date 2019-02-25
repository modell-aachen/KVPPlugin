module.exports = {
    "moduleFileExtensions": [
        "js",
        "json",
        "vue",
    ],
    "transform": {
        ".*\\.(vue)$": "vue-jest",
        "^.+\\.js$": "<rootDir>/node_modules/babel-jest",
    },
    "moduleNameMapper": {
        "\\.(css|less)$": "identity-obj-proxy",
        "^vue$": "vue/dist/vue.js"
    },
    "testRegex": "Spec\\.js$",
    "transformIgnorePatterns": [
        "node_modules/(?!(vue-timers)/)"
    ],
    "collectCoverageFrom": [
        "dev/**/*.{js,vue}",
        "!**/node_modules/**"
    ],
    "coverageReporters": ["lcov", "text-summary"],
    "globals": {
        "ts-jest": {
            "diagnostics": {
                "ignoreCodes": [151001]
            }
        },
    },
    "setupFiles": []
};
