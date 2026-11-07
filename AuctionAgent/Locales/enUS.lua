local ADDON, AA = ...

-- Missing keys fall back to the key itself, so English strings can be used as keys.
AA.L = setmetatable({}, { __index = function(_, k) return k end })

local L = AA.L
L["LOADED"] = "v%s loaded. Type /aa help."
L["HELP_HEADER"] = "Commands:"
L["NO_DATA"] = "No AH data yet"
L["NO_LISTINGS"] = "No listings"
