module.exports = {
    "extends": [
        "eslint:recommended",
        "plugin:vue/recommended"
    ],
    "parserOptions": {
        "parser": "babel-eslint",
        "ecmaVersion": 8,
        "sourceType": "module",
    },
    "plugins": [
        "json"
    ],
    "env": {
        "browser": true,
        "node": true,
        "commonjs": true,
        "es6": true,
        "jasmine": true
    },
    "globals": {
        "Vue": false,
        "$": false
    },
    "rules": {
        "callback-return":              [2, ["callback", "cb", "next", "done", "proceed"]],
        "comma-style":                  [2, "last"],
        "curly":                        [2],
        "eqeqeq":                       [2, "always"],
        "eol-last":                     [1],
        "handle-callback-err":          [2],
        "indent":                       [1, 4, {"SwitchCase": 1}],
        "linebreak-style":              [2, "unix"],
        "no-mixed-spaces-and-tabs":     [2, "smart-tabs"],
        "no-return-assign":             [2, "always"],
        "no-sequences":                 [2],
        "no-trailing-spaces":           [1],
        "no-undef":                     [0],
        "no-unexpected-multiline":      [1],
        "no-unused-vars":               [1],
        "one-var":                      [2, "never"],
        "semi":                         [2, "always"],
        "vue/html-indent":              ["error", 4],
        "no-var":                       [1],
        "brace-style":                  [1],
        "vue/html-closing-bracket-newline": ["error", { "singleline": "never", "multiline": "never" }]
    }
};