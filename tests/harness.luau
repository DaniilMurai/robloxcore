--!strict
-- Own assert harness: TestEZ's Wally stub is Rojo-style and cannot load in Lune (S-01).

export type Suite = {
	name: string,
	passed: number,
	failures: { string },
	check: (self: Suite, label: string, condition: boolean, detail: string?) -> (),
	eq: (self: Suite, label: string, actual: any, expected: any) -> (),
	errs: (self: Suite, label: string, result: any, code: string) -> (),
}

export type Case = (suite: Suite) -> ()

local Harness = {}

function Harness.suite(name: string): Suite
	local suite = {
		name = name,
		passed = 0,
		failures = {},
	} :: any

	function suite:check(label, condition, detail)
		if condition then
			self.passed += 1
		else
			table.insert(self.failures, label .. (detail and (": " .. detail) or ""))
		end
	end

	function suite:eq(label, actual, expected)
		self:check(
			label,
			actual == expected,
			("expected %s, got %s"):format(tostring(expected), tostring(actual))
		)
	end

	-- Result-typed failures are checked by code, never by message text.
	function suite:errs(label, result, code)
		if type(result) ~= "table" then
			self:check(label, false, ("expected an Err table, got %s"):format(typeof(result)))
		elseif result.ok ~= false then
			self:check(label, false, "expected an Err, got ok")
		else
			self:eq(label, result.code, code)
		end
	end

	return suite
end

return Harness
