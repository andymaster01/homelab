const dns = require("node:dns");
const originalLookup = dns.lookup;

dns.lookup = function lookupIPv4(hostname, options, callback) {
  if (typeof options === "function") {
    callback = options;
    options = {};
  }
  const lookupOptions = typeof options === "number" ? { family: options } : { ...options };
  lookupOptions.family = 4;
  return originalLookup.call(dns, hostname, lookupOptions, callback);
};

require("node:module").syncBuiltinESMExports();
