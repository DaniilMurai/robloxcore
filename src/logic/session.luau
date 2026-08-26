--!strict
-- Whether this server may claim a player's profile. Pure decision only: the actual
-- lock lives in ProfileStore (S-03), which owns the racy network half.

export type Lock = { ownerJobId: string, lockedAt: number }
export type Claim = "grant" | "deny" | "steal"

local Session = {}

-- A crashed server never runs BindToClose (S-03), so its lock is never released and the
-- player would be locked out forever. Stealing past the TTL is the only way back in; the
-- boundary is exclusive so a lock refreshed exactly on the TTL still counts as alive.
function Session.resolveClaim(lock: Lock?, myJobId: string, now: number, staleAfterSeconds: number): Claim
	if lock == nil then
		return "grant"
	end
	if lock.ownerJobId == myJobId then
		return "grant"
	end
	if now - lock.lockedAt > staleAfterSeconds then
		return "steal"
	end
	return "deny"
end

return Session
