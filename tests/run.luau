--!strict
-- Discovers every tests/*.luau case file, so adding a module means adding a file, not
-- editing the runner. Run from the repository root: `lune run tests/run.luau`.

local fs = require("@lune/fs")
local process = require("@lune/process")
local Harness = require("./harness")

local SKIP = { ["run.luau"] = true, ["harness.luau"] = true }

local names = {}
for _, entry in fs.readDir("tests") do
	if entry:match("%.luau$") and not SKIP[entry] then
		table.insert(names, entry)
	end
end
table.sort(names)

local passed, failed = 0, 0

for _, entry in names do
	local name = entry:gsub("%.luau$", "")
	local case: Harness.Case = require("./" .. name)
	local suite = Harness.suite(name)
	case(suite)

	passed += suite.passed
	failed += #suite.failures
	for _, failure in suite.failures do
		print(("FAIL %s / %s"):format(name, failure))
	end
end

print(("%d passed, %d failed (%d files)"):format(passed, failed, #names))
if failed > 0 then
	process.exit(1)
end
