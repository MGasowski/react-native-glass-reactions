// Expo resolves this file and expects the plugin *function*, not the module
// namespace. Re-exporting `require('./plugin/build')` hands it an object, which
// is why this unwraps `.default` explicitly.
module.exports = require('./plugin/build').default;
