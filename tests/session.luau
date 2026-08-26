--!strict

local Session = require("../src/logic/session")

local TTL = 1800
local NOW = 1_756_000_000

return function(t)
	t:eq("no lock grants the claim", Session.resolveClaim(nil, "job-a", NOW, TTL), "grant")

	local mine = { ownerJobId = "job-a", lockedAt = NOW - 10 }
	t:eq("own lock grants the claim", Session.resolveClaim(mine, "job-a", NOW, TTL), "grant")

	local fresh = { ownerJobId = "job-b", lockedAt = NOW - 10 }
	t:eq("someone else's fresh lock denies", Session.resolveClaim(fresh, "job-a", NOW, TTL), "deny")

	local exactly = { ownerJobId = "job-b", lockedAt = NOW - TTL }
	t:eq("a lock exactly at the TTL still denies", Session.resolveClaim(exactly, "job-a", NOW, TTL), "deny")

	local stale = { ownerJobId = "job-b", lockedAt = NOW - TTL - 1 }
	t:eq("a lock past the TTL is stolen", Session.resolveClaim(stale, "job-a", NOW, TTL), "steal")

	local future = { ownerJobId = "job-b", lockedAt = NOW + 60 }
	t:eq("a clock-skewed future lock denies", Session.resolveClaim(future, "job-a", NOW, TTL), "deny")
end
