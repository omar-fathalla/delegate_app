// Minimal, lenient ESLint config for Cloud Functions (ESLint 8, eslintrc format).
// Only real problems are errors; no stylistic/formatting rules.
module.exports = {
  root: true,
  env: {es2022: true, node: true},
  parserOptions: {ecmaVersion: 2022, sourceType: "script"},
  ignorePatterns: ["lib/", "node_modules/"],
  extends: ["eslint:recommended"],
  overrides: [
    {
      files: ["**/*.ts"],
      parser: "@typescript-eslint/parser",
      parserOptions: {sourceType: "module"},
      plugins: ["@typescript-eslint"],
      extends: ["plugin:@typescript-eslint/recommended"],
      rules: {},
    },
  ],
  rules: {
    // Existing code: find_nan.js has an unused local (one-off script) -> warn, not error.
    "no-unused-vars": "warn",
    // Intentional: delegate_login_logic.ts rejects deviceIds containing control characters (\u0000-\u001f).
    "no-control-regex": "warn",
  },
};
