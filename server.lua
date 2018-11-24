package.path = 'scripts/lsapi/?.lua;' .. package.path

require("lapis").serve("app")
