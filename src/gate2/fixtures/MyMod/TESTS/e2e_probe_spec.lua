-- mod TESTS probe (gate1 mod_loader_spec fixture pattern): when the gate2
-- runner is launched with --mod and NO explicit spec args, the mod's TESTS
-- dirs become the spec set — ALL PASS here proves the auto-exec order
-- matched the pinned engine sp sequence.
describe("mod loader e2e probe (mod TESTS default specs)", function()
    it("auto-exec order is the engine sp sequence", function()
        expect(__FIX_ORDER).toEqual({ "common-shared", "42-shared", "42-client", "42-server" })
    end)
end)
