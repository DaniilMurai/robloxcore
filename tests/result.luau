--!strict

local Result = require("../src/logic/result")

return function(t)
	local ok = Result.ok(42)
	t:eq("ok returns ok=true", ok.ok, true)
	t:eq("ok carries the value", ok.value, 42)

	local err = Result.err("InsufficientFunds", "not enough gold")
	t:errs("err carries a known code", err, "InsufficientFunds")
	t:eq("err carries the message", err.message, "not enough gold")

	local succeeded = pcall(function()
		Result.err("TotallyMadeUp" :: any, "boom")
	end)
	t:check("err with an unknown code raises error()", not succeeded)
end
