local GATE1 = (rawget(_G, "PZ_GATE") == "gate1")

if GATE1 then

    if rawget(_G, "ModData") == nil then
        pcall(require, "game")
    end

    describe("game pack — pinned core (ModData, player, recording)", function()
        it("ModData.getOrCreate: persistent per-key table, same table twice", function()
            local a = ModData.getOrCreate("game_pack_spec_key")
            local b = ModData.getOrCreate("game_pack_spec_key")
            expect(a).toBe(b)
            a.marker = true
            expect(ModData.get("game_pack_spec_key").marker).toBeTruthy()
        end)

        it("ModData: get nil on miss, exists, add replaces, transmit/request no-ops", function()
            expect(ModData.get("game_pack_spec_missing")).toBeNil()
            expect(ModData.exists("game_pack_spec_missing")).toBeFalsy()
            ModData.add("game_pack_spec_add", { replaced = 1 })
            expect(ModData.get("game_pack_spec_add").replaced).toBe(1)
            expect(ModData.exists("game_pack_spec_add")).toBeTruthy()
            expect(ModData.transmit("game_pack_spec_add")).toBeNil()
            expect(ModData.request("game_pack_spec_missing")).toBeNil()
        end)

        it("ModData addCopy/purge record their calls (plan-pinned recorders)", function()
            local before = #ModData.addCopy.calls
            ModData.addCopy("k", { v = 1 })
            expect(#ModData.addCopy.calls).toBe(before + 1)
            expect(ModData.addCopy.calls[before + 1][1]).toBe("k")
            expect(ModData.addCopy.calls[before + 1].n).toBe(2)
            local beforePurge = #ModData.purge.calls
            ModData.purge("k")
            expect(#ModData.purge.calls).toBe(beforePurge + 1)
            expect(ModData.purge.calls[beforePurge + 1][1]).toBe("k")
        end)

        it("getSpecificPlayer(0): call recorded, player methods record, brief shape", function()
            local before = #getSpecificPlayer.calls
            local p = getSpecificPlayer(0)
            expect(#getSpecificPlayer.calls).toBe(before + 1)
            expect(getSpecificPlayer.calls[before + 1][1]).toBe(0)

            expect(p:getUsername()).toBe("TestPlayer_0")
            p:getX()
            p:getY()
            p:getZ()
            expect(#p.getUsername.calls >= 1).toBeTruthy()
            expect(#p.getX.calls >= 1).toBeTruthy()
            expect(#p.getY.calls >= 1).toBeTruthy()
            expect(#p.getZ.calls >= 1).toBeTruthy()

            local inv = p:getInventory()
            expect(type(inv)).toBe("table")
            expect(#p.getInventory.calls >= 1).toBeTruthy()
            local items = inv:getItems()
            expect(items:size()).toBe(0)
            expect(function() items:get(0) end).toThrow()
            expect(function() items:get(-1) end).toThrow()

            expect(p:getPlayerNum()).toBe(0)
            expect(p:isAdmin()).toBeFalsy()
            expect(p:getAccessLevel()).toBe("None")
            expect(p:getSquare()).toBeNil()
        end)

        it("getPlayer(idx): separate recorder, id flows into the player", function()
            local before = #getPlayer.calls
            local p = getPlayer(2)
            expect(#getPlayer.calls).toBe(before + 1)
            expect(getPlayer.calls[before + 1][1]).toBe(2)
            expect(p:getPlayerNum()).toBe(2)
            expect(p:getUsername()).toBe("TestPlayer_2")
        end)

        it("HaloTextHelper.addText/addBadText record (plan-pinned)", function()
            local p = getSpecificPlayer(0)
            local before = #HaloTextHelper.addText.calls
            HaloTextHelper.addText(p, "hello", "extra")
            expect(#HaloTextHelper.addText.calls).toBe(before + 1)
            local call = HaloTextHelper.addText.calls[before + 1]
            expect(call[1]).toBe(p)
            expect(call[2]).toBe("hello")
            expect(call.n).toBe(3)
            local beforeBad = #HaloTextHelper.addBadText.calls
            HaloTextHelper.addBadText(p, "bad news")
            expect(#HaloTextHelper.addBadText.calls).toBe(beforeBad + 1)
        end)

        it("ScriptManager: getScript/getItem/FetchAll record and return {}; instance.getItem -> script item", function()
            local b1 = #ScriptManager.getScript.calls
            expect(ScriptManager.getScript("Base.Axe")).toEqual({})
            expect(#ScriptManager.getScript.calls).toBe(b1 + 1)
            local b2 = #ScriptManager.getItem.calls
            expect(ScriptManager.getItem("Base.Axe")).toEqual({})
            expect(#ScriptManager.getItem.calls).toBe(b2 + 1)
            local b3 = #ScriptManager.FetchAll.calls
            expect(ScriptManager.FetchAll()).toEqual({})
            expect(#ScriptManager.FetchAll.calls).toBe(b3 + 1)

            local item = ScriptManager.instance:getItem("Base.Whatever")
            expect(item:getActualWeight()).toBe(0.1)
        end)
    end)

    describe("game pack — SURFACE engine globals + utilities", function()
        it("ZomboidGlobals exists; SandboxVars is a namespace-agnostic store (D6)", function()
            expect(type(ZomboidGlobals)).toBe("table")
            expect(type(SandboxVars)).toBe("table")

            SandboxVars.GamePackSpecNS = { Flag = true }
            expect(SandboxVars.GamePackSpecNS.Flag).toBeTruthy()
            SandboxVars.GamePackSpecNS = nil
        end)

        it("getCore/getTimeInMillis/sendClientCommand/sendServerCommand/triggerEvent", function()
            expect(getCore():getGameVersion()).toBe("v42")
            expect(type(getTimeInMillis())).toBe("number")
            expect(type(sendClientCommand)).toBe("function")
            expect(sendClientCommand("mod", "cmd", {})).toBeNil()
            expect(type(sendServerCommand)).toBe("function")
            expect(sendServerCommand("mod", "cmd", {})).toBeNil()

            expect(type(triggerEvent)).toBe("function")
            expect(triggerEvent("OnTick")).toBeNil()
        end)

        it("ISTransferAction.transferItem (CAF usage)", function()
            expect(type(ISTransferAction.transferItem)).toBe("function")
            expect(ISTransferAction.transferItem()).toBeNil()
        end)

        it("luautils: countItemsRecursive sums getItems():size(), walk/modal no-ops", function()
            local c1 = { getItems = function() return { size = function() return 2 end } end }
            local c2 = { getItems = function() return { size = function() return 3 end } end }
            expect(luautils.countItemsRecursive({ c1, c2 }, 0)).toBe(5)
            expect(luautils.countItemsRecursive({ c1, c2 })).toBe(5)
            expect(luautils.countItemsRecursive({}, 7)).toBe(7)
            local p = getSpecificPlayer(0)
            local sq = getSquare(0, 0, 0)
            expect(luautils.walkAdj(p, sq, true)).toBeNil()
            expect(luautils.walkToContainer(c1, 0)).toBe(true)
            expect(luautils.okModal("msg", 0, 0, p, function() end)).toBeNil()
        end)

        it("IsoUtils.DistanceTo/DistanceTo2D: real 3D/2D distances", function()
            expect(IsoUtils.DistanceTo(0, 0, 0, 3, 4, 12)).toBe(13)
            expect(IsoUtils.DistanceTo2D(0, 0, 3, 4)).toBe(5)
        end)

        it("AdjacentFreeTileFinder: isTileOrAdjacent true, Find returns the input square", function()
            local sq = getSquare(1, 1, 0)
            expect(AdjacentFreeTileFinder.isTileOrAdjacent(sq, sq)).toBeTruthy()
            expect(AdjacentFreeTileFinder.Find(sq, getSpecificPlayer(0))).toBe(sq)
        end)

        it("getSquare(x, y, z): square shape with getX/getY/getZ/getObjects/addObject", function()
            local sq = getSquare(7, 8, 9)
            expect(sq:getX()).toBe(7)
            expect(sq:getY()).toBe(8)
            expect(sq:getZ()).toBe(9)
            expect(#sq:getObjects()).toBe(0)
            sq:addObject("thing")
            expect(sq:getObjects()[1]).toBe("thing")
            expect(getSquare():getX()).toBe(0)
        end)
    end)

    describe("game pack — SURFACE classes (union shapes)", function()
        it("IsoPlayer: CAF/MAF class form + JASM factory form (D5: both authority APIs)", function()
            local pl = IsoPlayer.new("Bob")
            expect(pl:getUsername()).toBe("Bob")
            expect(pl:isAdmin()).toBeFalsy()
            expect(pl:getAccessLevel()).toBe("None")
            expect(pl:getPlayerNum()).toBe(0)
            expect(pl:getSquare()).toBeNil()
            expect(pl:getInventory():getItems():size()).toBe(0)
            local admin = IsoPlayer.new("Chief", true)
            expect(admin:isAdmin()).toBeTruthy()
            expect(admin:getAccessLevel()).toBe("Admin")

            expect(pl:DistTo2D(3, 4)).toBe(5)
            expect(pl:DistTo(getSquare(3, 4, 12))).toBe(13)
        end)

        it("IsoObject: union of CAF/MAF/JASM forms (D4)", function()
            local o = IsoObject.new()
            expect(o:getModData()).toBe(o:getModData())
            expect(o:getObjectName()).toBe("Object")
            expect(o:getSquare()).toBeNil()
            expect(o:getContainer()).toBeNil()
            expect(o:getSprite():getName()).toBe("constructedobjects_01_44")
            expect(o:getSprite():getProperties():has("anything")).toBeFalsy()
            expect(o:getSprite():getProperties():get("anything")).toBeNil()
            local sq = getSquare(1, 2, 0)
            o:setSquare(sq)
            expect(o:getSquare()).toBe(sq)
            expect(IsoObject.new("Custom"):getObjectName()).toBe("Custom")
        end)

        it("IsoDeadBody: CAF members (getModData); instanceof pin lives in the D1 suite", function()
            local body = IsoDeadBody.new()
            expect(body:getModData()).toBe(body:getModData())
        end)

        it("IsoGridSquare: MAF class ctor + JASM factory shape (D3)", function()
            local sq = IsoGridSquare.new(1, 2, 3)
            expect(sq:getX()).toBe(1)
            expect(sq:getY()).toBe(2)
            expect(sq:getZ()).toBe(3)
            expect(#sq:getObjects()).toBe(0)
            sq:addObject("obj")
            expect(sq:getObjects()[1]).toBe("obj")
            expect(IsoGridSquare.new():getX()).toBe(0)
        end)

        it("IsoSprite: name + property map (has false / get nil)", function()
            expect(IsoSprite.new("spr"):getName()).toBe("spr")
            expect(IsoSprite.new():getName()).toBe("test_sprite")
            local props = IsoSprite.new("spr"):getProperties()
            expect(props:has("k")).toBeFalsy()
            expect(props:get("k")).toBeNil()
        end)

        it("InventoryItem: CAF new(fullType) + JASM factory members", function()
            local item = InventoryItem.new("Base.Axe")
            expect(item:getFullType()).toBe("Base.Axe")
            expect(item:getActualWeight()).toBe(0.1)
            expect(item:getCount()).toBe(1)
            expect(item:getCategory()).toBe("Item")
            expect(item:isContainer()).toBeFalsy()
            expect(item:getInventory()).toBeNil()
            item:setWeight(2)
            expect(item:getActualWeight()).toBe(2)
            expect(InventoryItem.new():getFullType()).toBe("Base.Item")
            expect(InventoryItem.new("X", 5):getCount()).toBe(5)
        end)

        it("ItemContainer: CAF ctor + JASM factory surface, D8 weight semantics", function()
            local outer = ItemContainer.new("floor")
            expect(outer:getType()).toBe("floor")
            expect(outer:getParent()).toBeNil()
            expect(outer:getInventory()).toBe(outer)
            expect(outer:getContainer()).toBe(outer)
            expect(outer:isExplored()).toBeTruthy()
            outer:setExplored(false)
            expect(outer:getItemsFromCategory("Food").size()).toBe(0)

            expect(outer:getItemCount("Base.Axe")).toBe(0)
            expect(outer:contains("Base.Axe")).toBeFalsy()

            outer:AddItem("Base.Axe")
            expect(outer:getItemCount("Base.Axe")).toBe(1)
            expect(outer:contains("Base.Axe")).toBeTruthy()
            local it1 = outer:getItems():get(0)
            expect(it1:getFullType()).toBe("Base.Axe")
            expect(outer:getItems():size()).toBe(1)
            expect(outer:getCountRecurse(function() return true end)).toBe(1)

            expect(outer:getContentsWeight()).toBeCloseTo(0.1)
            expect(outer:getCapacityWeight()).toBeCloseTo(0.1)
            expect(outer:getCapacity()).toBe(50)
            expect(outer:getEffectiveCapacity(nil)).toBe(50)

            expect(outer:contains(it1)).toBeTruthy()

            outer:Remove("Base.Axe")
            expect(outer:getItemCount("Base.Axe")).toBe(0)

            local inner = ItemContainer.new("crate", outer)
            expect(inner:getType()).toBe("crate")
            expect(inner:getParent()).toBe(outer)
            inner:setParent(nil)
            expect(inner:getParent()).toBeNil()

            expect(ItemContainer.new():getType()).toBe("container")
        end)

        it("middleclass: factory, new invokes initialize, callable class, module form", function()
            local Kind = middleclass("Kind")
            local seen
            function Kind:initialize(v)
                self.v = v
                seen = v
            end
            local inst = Kind.new("a")
            expect(inst.v).toBe("a")
            expect(seen).toBe("a")
            local inst2 = Kind("b")
            expect(inst2.v).toBe("b")
            local Plain = middleclass("Plain")
            expect(type(Plain.new())).toBe("table")

            expect(require("pz_lua_commons_shared").kikito.middleclass).toBe(middleclass)
        end)

        it("JASM trade action classes: new(player, entity, payload) -> instance", function()
            expect(type(JASM_AcceptTradeAction:new("p", "e", {}))).toBe("table")
            expect(type(JASM_PublishTradeAction:new("p", "e", {}))).toBe("table")
        end)
    end)

    describe("game pack — instanceof real signature (SURFACE D1 RESOLVED)", function()
        it("instanceof(obj, className): object first, class-name string second; subclass walk; miss-tolerant", function()
            local body = IsoDeadBody.new()
            local pl = IsoPlayer.new("Bob")
            local obj = IsoObject.new()
            expect(instanceof(body, "IsoDeadBody")).toBeTruthy()
            expect(instanceof(pl, "IsoPlayer")).toBeTruthy()
            expect(instanceof(obj, "IsoObject")).toBeTruthy()

            expect(instanceof(pl, "IsoObject")).toBeTruthy()
            expect(instanceof(body, "IsoObject")).toBeTruthy()

            expect(instanceof("IsoDeadBody", body)).toBeFalsy()

            expect(instanceof(nil, "IsoPlayer")).toBeFalsy()
            expect(instanceof(123, "IsoPlayer")).toBeFalsy()
            expect(instanceof(body, 999)).toBeFalsy()
            expect(instanceof(body, "NotARealClass")).toBeFalsy()
        end)
    end)

    describe("game pack — IS UI tree + timed actions", function()
        it("ISPanel base: ctor fields, members, derive", function()
            local panel = ISPanel:new(1, 2, 3, 4)
            expect(panel.x).toBe(1)
            expect(panel.y).toBe(2)
            expect(panel.width).toBe(3)
            expect(panel.height).toBe(4)
            for _, m in ipairs({ "initialise", "instantiate", "createChildren", "setVisible", "addToUIManager" }) do
                expect(type(panel[m])).toBe("function")
            end
            panel:initialise()
            panel:setVisible(true)
            local Derived = ISPanel:derive("Derived")
            expect(Derived.__name).toBe("Derived")
            expect(type(Derived:new(0, 0, 1, 1))).toBe("table")
        end)

        it("derived panels exist, inherit ISPanel surface, satisfy instanceof", function()
            local names = { "ISButton", "ISScrollingListBox", "ISImage", "ISLabel", "ISComboBox", "ISTextEntryBox", "ISTiledIconListBox" }
            for _, name in ipairs(names) do
                local cls = _G[name]
                expect(type(cls)).toBe("table")
                local inst = cls:new(0, 0, 10, 10)
                expect(type(inst.setVisible)).toBe("function")
                expect(instanceof(inst, name)).toBeTruthy()
                expect(instanceof(inst, "ISPanel")).toBeTruthy()
            end
            local inv = ISInventoryPage:new(0, 0, 10, 10)
            expect(type(ISInventoryPage.setNewContainer)).toBe("function")
            ISInventoryPage.setNewContainer(inv, {})
            expect(instanceof(inv, "ISPanel")).toBeTruthy()
            local ew = ISEntityWindow:new(0, 0, 10, 10)
            expect(instanceof(ew, "ISEntityWindow")).toBeTruthy()
            expect(instanceof(ew, "ISPanel")).toBeTruthy()
        end)

        it("ISTableLayout: final-state derive-style shape (JASM late reassign) + SURFACE members", function()

            expect(ISTableLayout.__name).toBe("ISTableLayout")
            local tl = ISTableLayout:new(0, 0, 10, 10)
            expect(type(tl.calculateLayout)).toBe("function")
            tl:calculateLayout()
            expect(type(tl:addColumn())).toBe("table")
            expect(type(tl:addColumnFill())).toBe("table")
            expect(tl:addRow().index()).toBe(0)
            expect(type(tl:addRowFill())).toBe("table")
            tl:setElement()
            expect(instanceof(tl, "ISPanel")).toBeTruthy()
        end)

        it("ISWorldObjectContextMenu + ISContextMenu: tooltip and menu builders", function()
            local tt = ISWorldObjectContextMenu.addToolTip()
            expect(type(tt.setName)).toBe("function")
            tt:setName("Tip")
            local menu = ISContextMenu:getNew(0)
            expect(type(menu.addOption)).toBe("function")
            expect(type(menu.addSubMenu)).toBe("function")
            menu:addOption("Opt", nil, function() end)
            menu:addSubMenu(nil, menu)
            local nested = menu:getNew(1)
            expect(type(nested.addOption)).toBe("function")
        end)

        it("timed-action classes carry the SURFACE ISBaseTimedAction surface (D7 left to core)", function()
            local ta = ISWalkToTimedAction:new("chr")
            expect(ta.character).toBe("chr")
            local fn = function() end
            ta:setOnComplete(fn, "x", 1)
            expect(ta.onCompleteFunc).toBe(fn)
            expect(ta.onCompleteArgs.n).toBe(2)
            expect(ta.onCompleteArgs[1]).toBe("x")
            ta:stop()
            expect(ISWalkToTimedAction:derive("Sub").__name).toBe("Sub")
            for _, name in ipairs({ "ISDestroyStuffAction", "ISDismantleAction", "ISMoveablesAction" }) do
                local cls = _G[name]
                expect(type(cls)).toBe("table")
                local a = cls:new("c")
                expect(a.character).toBe("c")
                expect(type(a.stop)).toBe("function")
                expect(type(a.setOnComplete)).toBe("function")
            end

            for _, name in ipairs({ "ISMoveableSpriteProps", "ISDestroyCursor", "ISMoveableCursor", "ISMoveableInfoWindow", "ISMoveablesIconToolTip" }) do
                expect(type(_G[name])).toBe("table")
            end

            expect(type(ISBaseTimedAction.new)).toBe("function")
            expect(type(ISBaseTimedAction.new())).toBe("table")
            expect(type(ISTimedActionQueue.add)).toBe("function")
        end)
    end)

    describe("game pack — package.preload module keys", function()
        it("pz_utils_shared: konijima.Utilities + escape.SandboxVarsModule/Utilities", function()
            local shared = require("pz_utils_shared")
            expect(type(shared.konijima.Utilities.IsPlayerAdmin)).toBe("function")
            expect(shared.konijima.Utilities.IsPlayerAdmin({})).toBeFalsy()
            expect(shared.konijima.Utilities.SquareToString(getSquare(0, 0, 0))).toBe("0,0,0")
            expect(type(shared.konijima.Utilities.SendClientCommand)).toBe("function")
            expect(type(shared.konijima.Utilities.SendServerCommandTo)).toBe("function")
            local svm = shared.escape.SandboxVarsModule()
            svm.Init("GamePackNS", { Limit = 3 })
            local ns = svm.Create("GamePackNS2", { Cap = 9 })
            expect(ns.Get("Cap")).toBe(9)
            expect(ns.Get("missing", 7)).toBe(7)
            expect(svm.Get("GamePackNS", "Limit", 0)).toBe(3)
            expect(svm.Get("GamePackNS", "missing", 5)).toBe(5)
            expect(svm.Get("NoNS", "k", 4)).toBe(4)
            expect(svm.GetAll("GamePackNS").Limit).toBe(3)
            expect(svm.GetAll("NoNS")).toEqual({})
            expect(shared.escape.Utilities.GetIRLTimestamp() > 0).toBeTruthy()
        end)

        it("zul: module exposes new(name) -> logger with the six levels (JASM shape: require('zul') IS the ZUL table)", function()
            local ZUL = require("zul")
            local logger = ZUL.new("spec")
            for _, m in ipairs({ "info", "error", "debug", "trace", "warn", "setLevel" }) do
                expect(type(logger[m])).toBe("function")
            end
        end)

        it("engine module preloads return the matching globals", function()
            local engineModules = {
                ["ISUI/ISPanel"] = "ISPanel",
                ["ISUI/ISButton"] = "ISButton",
                ["ISUI/ISScrollingListBox"] = "ISScrollingListBox",
                ["ISUI/ISImage"] = "ISImage",
                ["ISUI/ISLabel"] = "ISLabel",
                ["ISUI/ISComboBox"] = "ISComboBox",
                ["ISUI/ISTextEntryBox"] = "ISTextEntryBox",
                ["ISUI/ISInventoryPage"] = "ISInventoryPage",
                ["TimedActions/ISBaseTimedAction"] = "ISBaseTimedAction",
                ["TimedActions/ISWalkToTimedAction"] = "ISWalkToTimedAction",
                ["TimedActions/ISTimedActionQueue"] = "ISTimedActionQueue",
                ["Entity/ISUI/Windows/ISEntityWindow"] = "ISEntityWindow",
                ["Entity/ISUI/Controls/ISTableLayout"] = "ISTableLayout",
                ["Entity/ISUI/CraftRecipe/ISTiledIconListBox"] = "ISTiledIconListBox",
            }
            for mod, glob in pairs(engineModules) do
                expect(require(mod)).toBe(_G[glob])
            end
        end)

        it("JASM-internal UI module keys exist; shop_item_details_panel omission preserved", function()
            expect(type(require("just_another_shop_mod/entity_ui/customer_view_window").open)).toBe("function")
            expect(type(require("just_another_shop_mod/entity_ui/owner_view_window").open)).toBe("function")
            local plainKeys = {
                "just_another_shop_mod/entity_ui/models/shop_data_manager",
                "just_another_shop_mod/entity_ui/components/shop/shared/shop_search_filter_panel",
                "just_another_shop_mod/entity_ui/components/product/product_list_panel",
                "just_another_shop_mod/entity_ui/components/shop/customer/shop_item_header",
                "just_another_shop_mod/entity_ui/components/shop/customer/shop_item_gives_panel",
                "just_another_shop_mod/entity_ui/components/shop/customer/shop_item_requirements_panel",
                "just_another_shop_mod/entity_ui/components/shop/customer/shop_item_action_footer",
                "just_another_shop_mod/entity_ui/components/shop/owner/shop_trade_offer_panel",
                "just_another_shop_mod/entity_ui/components/shop/owner/shop_requirement_panel",
                "just_another_shop_mod/entity_ui/components/shop/owner/shop_footer_panel",
            }
            for _, key in ipairs(plainKeys) do
                expect(type(require(key))).toBe("table")
            end

            expect(package.preload["just_another_shop_mod/entity_ui/components/shop/customer/shop_item_details_panel"]).toBeNil()
        end)
    end)
end
