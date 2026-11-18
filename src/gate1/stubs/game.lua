--     getCapacityWeight() returns the CURRENT contents weight while

local pzmock = _G.mock

local function umbrellaWrap(obj, class_name)
    local U = rawget(_G, "Umbrella")
    if U then return U.w(obj, class_name) end
    return obj
end

_G.getTimeInMillis = function()
    return os.time() * 1000
end

if rawget(_G, "debug") == nil then
    _G.debug = {
        getinfo = function()
            return { source = "@pz_lua_testkit" }
        end,
    }
end

local modDataStore = {}
_G.ModData = {
    getOrCreate = function(key)
        if modDataStore[key] == nil then
            modDataStore[key] = {}
        end
        return modDataStore[key]
    end,
    get = function(key)
        return modDataStore[key]
    end,
    add = function(key, val)
        modDataStore[key] = val
    end,
    exists = function(key)
        return modDataStore[key] ~= nil
    end,
    transmit = function(key) end,
    request = function(key) end,
    addCopy = pzmock(function(key, val) end),
    purge = pzmock(function(key) end),
}

_G.ZomboidGlobals = {}

_G.SandboxVars = {}

_G.getCore = function()
    return {
        getGameVersion = function()
            return "v42"
        end,
    }
end

_G.sendClientCommand = function(...) end
_G.sendServerCommand = function(...) end

_G.triggerEvent = function(...) end

_G.IsoUtils = {
    DistanceTo = function(x1, y1, z1, x2, y2, z2)
        return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2 + (z1 - z2) ^ 2)
    end,
    DistanceTo2D = function(x1, y1, x2, y2)
        return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
    end,
}

_G.AdjacentFreeTileFinder = {
    isTileOrAdjacent = function(sq1, sq2)
        return true
    end,
    Find = function(sq, player)
        return sq
    end,
}

_G.luautils = {
    countItemsRecursive = function(containerList, initialCount)
        local count = initialCount or 0
        for _, container in ipairs(containerList) do
            count = count + container:getItems():size()
        end
        return count
    end,
    walkAdj = function(player, square, isWalk) end,
    walkToContainer = function(container, playerNum)
        return true
    end,
    okModal = function(text, centerX, centerY, target, onOk) end,
}

local function defineClass(name, super, build)
    local cls = setmetatable({}, { __index = super })
    cls.__name = name
    cls.__super = super

    function cls:derive(childName)
        return defineClass(childName, cls, build)
    end

    cls.new = function(a, ...)
        if a == cls then
            return build(cls, ...)
        end
        return build(cls, a, ...)
    end
    return cls
end

local function buildInstance(class)
    local o = setmetatable({}, { __index = class })
    o.__class = class
    return o
end

local IsoSprite
local ItemContainer
local InventoryItem

IsoSprite = defineClass("IsoSprite", nil, function(class, name)
    local o = buildInstance(class)
    o.name = name or "test_sprite"
    return o
end)
_G.IsoSprite = IsoSprite
function IsoSprite:getName()
    return self.name
end
function IsoSprite:getProperties()
    return {
        has = function(_, key)
            return false
        end,
        get = function(_, key)
            return nil
        end,
    }
end

ItemContainer = defineClass("ItemContainer", nil, function(class, type_, parent)
    local o = buildInstance(class)
    o.type = type_ or "container"
    o.parent = parent
    o.items = {}
    o.capacityWeight = 50.0
    return o
end)
_G.ItemContainer = ItemContainer

function ItemContainer:getParent()
    return rawget(self, "parent")
end
function ItemContainer:setParent(parent)
    self.parent = parent
end
function ItemContainer:getType()
    return self.type
end
function ItemContainer:getInventory()
    return self
end
function ItemContainer:isExplored()
    return true
end
function ItemContainer:setExplored(b) end
function ItemContainer:getItemsFromCategory(category)
    return {
        size = function()
            return 0
        end,
        get = function(_, i)
            return nil
        end,
    }
end
-- D8: B42 semantics — CURRENT contents weight (NOT the max limit)
function ItemContainer:getCapacityWeight()
    return self:getContentsWeight()
end

function ItemContainer:getCapacity()
    return self.capacityWeight
end
function ItemContainer:getEffectiveCapacity(chr)
    return self:getCapacity()
end
function ItemContainer:getContentsWeight()
    local weight = 0.0
    for _, list in pairs(self.items) do
        for _, item in ipairs(list) do
            if item.getActualWeight then
                weight = weight + item:getActualWeight()
            elseif item.weight then
                weight = weight + item.weight
            else
                weight = weight + 0.1
            end
        end
    end
    return weight
end
function ItemContainer:getItems()
    local flat = {}
    for _, list in pairs(self.items) do
        for _, item in ipairs(list) do
            table.insert(flat, item)
        end
    end
    return {
        size = function()
            return #flat
        end,
        get = function(_, i)
            return flat[i + 1]
        end,
    }
end
function ItemContainer:getItemCount(itemType)
    if not self.items[itemType] then
        return 0
    end
    return #self.items[itemType]
end
function ItemContainer:getCountRecurse(predicate)
    return self:getItems():size()
end
function ItemContainer:contains(item)
    local itemType = type(item) == "table" and item:getFullType() or item
    if not self.items[itemType] then
        return false
    end
    if type(item) == "table" then
        for _, it in ipairs(self.items[itemType]) do
            if it == item then
                return true
            end
        end
        return false
    end
    return #self.items[itemType] > 0
end
function ItemContainer:addItem(itemOrType)
    local item
    local itemType
    if type(itemOrType) == "table" then
        item = itemOrType
        itemType = item:getFullType()
    else
        itemType = itemOrType
        item = InventoryItem.new(itemType)
    end
    self.items[itemType] = self.items[itemType] or {}
    table.insert(self.items[itemType], item)
end
function ItemContainer:AddItem(itemOrType)
    return self:addItem(itemOrType)
end
function ItemContainer:removeItem(itemOrType)
    local itemType = type(itemOrType) == "table" and itemOrType:getFullType() or itemOrType
    if self.items[itemType] and #self.items[itemType] > 0 then
        if type(itemOrType) == "table" then
            for i, it in ipairs(self.items[itemType]) do
                if it == itemOrType then
                    table.remove(self.items[itemType], i)
                    return
                end
            end
        else
            table.remove(self.items[itemType], 1)
        end
    end
end
function ItemContainer:Remove(itemOrType)
    return self:removeItem(itemOrType)
end
function ItemContainer:getContainer()
    return self
end

InventoryItem = defineClass("InventoryItem", nil, function(class, itemType, count)
    local o = buildInstance(class)
    o.type = itemType or "Base.Item"
    o.count = count or 1
    o.weight = 0.1
    return o
end)
_G.InventoryItem = InventoryItem
function InventoryItem:getFullType()
    return self.type
end
function InventoryItem:getActualWeight()
    return self.weight
end
function InventoryItem:setWeight(weight)
    self.weight = weight
end
function InventoryItem:getCount()
    return self.count
end
function InventoryItem:getCategory()
    return "Item"
end
function InventoryItem:getInventory()
    return nil
end
function InventoryItem:isContainer()
    return false
end

local IsoObject = defineClass("IsoObject", nil, function(class, name)
    local o = buildInstance(class)
    o.objectName = name or "Object"
    o.modData = {}
    o.square = nil
    o.sprite = IsoSprite.new(name or "constructedobjects_01_44")
    return o
end)
_G.IsoObject = IsoObject
function IsoObject:getModData()
    return self.modData
end
function IsoObject:getObjectName()
    return self.objectName
end

function IsoObject:getSquare()
    return rawget(self, "square")
end
function IsoObject:setSquare(square)
    self.square = square
end
function IsoObject:getSprite()
    return self.sprite
end
function IsoObject:getContainer()
    return nil
end

local IsoPlayer = defineClass("IsoPlayer", IsoObject, function(class, username, isAdmin)
    local o = buildInstance(class)
    o.username = username or "TestPlayer"
    o.admin = isAdmin or false
    o.inventory = ItemContainer.new()
    o.playerNum = 0
    o.square = nil
    o.x = 0
    o.y = 0
    o.z = 0
    return o
end)
_G.IsoPlayer = IsoPlayer
function IsoPlayer:getUsername()
    return self.username
end
function IsoPlayer:isAdmin()
    return self.admin
end
function IsoPlayer:getAccessLevel()
    return self.admin and "Admin" or "None"
end
function IsoPlayer:getInventory()
    return self.inventory
end
function IsoPlayer:getPlayerNum()
    return self.playerNum
end
function IsoPlayer:DistTo(x, y)
    if type(x) == "table" then
        return IsoUtils.DistanceTo(self.x or 0, self.y or 0, self.z or 0, x:getX(), x:getY(), x:getZ())
    end
    return IsoUtils.DistanceTo2D(self.x or 0, self.y or 0, x, y)
end
function IsoPlayer:DistTo2D(x, y)
    return IsoUtils.DistanceTo2D(self.x or 0, self.y or 0, x, y)
end

_G.IsoDeadBody = defineClass("IsoDeadBody", IsoObject, function(class)
    local o = buildInstance(class)
    o.modData = {}
    return o
end)

local IsoGridSquare = defineClass("IsoGridSquare", nil, function(class, x, y, z)
    local o = buildInstance(class)
    o.x = x or 0
    o.y = y or 0
    o.z = z or 0
    o.objects = {}
    return o
end)
_G.IsoGridSquare = IsoGridSquare
function IsoGridSquare:getX()
    return self.x
end
function IsoGridSquare:getY()
    return self.y
end
function IsoGridSquare:getZ()
    return self.z
end
function IsoGridSquare:getObjects()
    return self.objects
end
function IsoGridSquare:addObject(obj)
    table.insert(self.objects, obj)
end

_G.getSquare = function(x, y, z)
    return umbrellaWrap(IsoGridSquare.new(x, y, z), "IsoGridSquare")
end

local function newCorePlayer(id)
    local p = {
        username = "TestPlayer_" .. tostring(id),
        admin = false,
        playerNum = id,
        x = 0,
        y = 0,
        z = 0,
        square = nil,
        inventory = {
            getItems = function()
                return {}
            end,
        },
    }
    p.getUsername = pzmock(function(self)
        return self.username
    end)
    p.getX = pzmock(function(self)
        return self.x
    end)
    p.getY = pzmock(function(self)
        return self.y
    end)
    p.getZ = pzmock(function(self)
        return self.z
    end)
    p.getInventory = pzmock(function(self)
        return self.inventory
    end)
    function p:isAdmin()
        return self.admin
    end
    function p:getAccessLevel()
        return self.admin and "Admin" or "None"
    end
    function p:getPlayerNum()
        return self.playerNum
    end

    function p:getSquare()
        return rawget(self, "square")
    end
    function p:DistTo(x, y)
        if type(x) == "table" then
            return IsoUtils.DistanceTo(self.x or 0, self.y or 0, self.z or 0, x:getX(), x:getY(), x:getZ())
        end
        return IsoUtils.DistanceTo2D(self.x or 0, self.y or 0, x, y)
    end
    function p:DistTo2D(x, y)
        return IsoUtils.DistanceTo2D(self.x or 0, self.y or 0, x, y)
    end
    return p
end

_G.getSpecificPlayer = pzmock(function(id)
    return umbrellaWrap(newCorePlayer(id), "IsoPlayer")
end)
_G.getPlayer = pzmock(function(id)
    return umbrellaWrap(newCorePlayer(id), "IsoPlayer")
end)

_G.ScriptManager = {
    getScript = pzmock(function(name)
        return {}
    end),
    getItem = pzmock(function(fullType)
        return {}
    end),
    FetchAll = pzmock(function(...)
        return {}
    end),
    instance = {
        getItem = function(_, fullType)
            return {
                getActualWeight = function()
                    return 0.1
                end,
            }
        end,
    },
}

_G.HaloTextHelper = {
    addText = pzmock(function(player, text) end),
    addBadText = pzmock(function(player, text) end),
}

_G.ISTransferAction = {
    transferItem = function() end,
}

local ISPanel = defineClass("ISPanel", nil, function(class, x, y, width, height)
    local o = buildInstance(class)
    o.x = x
    o.y = y
    o.width = width
    o.height = height
    return o
end)
_G.ISPanel = ISPanel
function ISPanel:initialise() end
function ISPanel:instantiate() end
function ISPanel:createChildren() end
function ISPanel:setVisible(visible) end
function ISPanel:addToUIManager() end

_G.ISButton = ISPanel:derive("ISButton")
_G.ISScrollingListBox = ISPanel:derive("ISScrollingListBox")
_G.ISImage = ISPanel:derive("ISImage")
_G.ISLabel = ISPanel:derive("ISLabel")
_G.ISComboBox = ISPanel:derive("ISComboBox")
_G.ISTextEntryBox = ISPanel:derive("ISTextEntryBox")
_G.ISTiledIconListBox = ISPanel:derive("ISTiledIconListBox")

_G.ISInventoryPage = ISPanel:derive("ISInventoryPage")
function ISInventoryPage:setNewContainer(inventory) end

_G.ISEntityWindow = ISPanel:derive("ISEntityWindow")

_G.ISTableLayout = ISPanel:derive("ISTableLayout")
function ISTableLayout:calculateLayout() end
function ISTableLayout:addColumn()
    return {}
end
function ISTableLayout:addColumnFill()
    return {}
end
function ISTableLayout:addRow()
    return {
        index = function()
            return 0
        end,
    }
end
function ISTableLayout:addRowFill()
    return {}
end
function ISTableLayout:setElement() end

_G.ISWorldObjectContextMenu = {
    addToolTip = function()
        return {
            setName = function(_, name) end,
        }
    end,
}

_G.ISContextMenu = {
    getNew = function(self, playerOrParent)

        local o = {
            player = (type(playerOrParent) == "table"
                    and rawget(playerOrParent, "player"))
                or playerOrParent
                or 0,
            addOption = function(_, name, target, onSelect, ...) end,
            addSubMenu = function(_, option, menu) end,
        }
        o.getNew = self.getNew
        return o
    end,
}

local function defineTimedActionClass(name, super)
    local cls = defineClass(name, super, function(class, character)
        local o = buildInstance(class)
        o.character = character
        o.onCompleteFunc = nil
        o.onCompleteArgs = nil
        return o
    end)
    function cls:setOnComplete(func, ...)
        self.onCompleteFunc = func
        self.onCompleteArgs = { n = select("#", ...), ... }
    end
    function cls:stop() end
    return cls
end

_G.ISWalkToTimedAction = defineTimedActionClass("ISWalkToTimedAction", _G.ISBaseTimedAction)

_G.ISDestroyStuffAction = defineTimedActionClass("ISDestroyStuffAction", _G.ISBaseTimedAction)
_G.ISDismantleAction = defineTimedActionClass("ISDismantleAction", _G.ISBaseTimedAction)
_G.ISMoveablesAction = defineTimedActionClass("ISMoveablesAction", _G.ISBaseTimedAction)

_G.ISMoveableSpriteProps = {}
_G.ISDestroyCursor = {}
_G.ISMoveableCursor = {}
_G.ISMoveableInfoWindow = {}
_G.ISMoveablesIconToolTip = {}

if rawget(_G, "middleclass") == nil then
    _G.middleclass = function(name)
        local class = {
            __name = name,
        }
        class.__index = class

        function class.new(...)
            local instance = setmetatable({}, class)
            if instance.initialize then
                instance:initialize(...)
            end
            return instance
        end

        setmetatable(class, {
            __call = function(cls, ...)
                return cls.new(...)
            end,
        })

        return class
    end
end

_G.JASM_AcceptTradeAction = {
    new = function(_, player, entity, payload)
        return {}
    end,
}
_G.JASM_PublishTradeAction = {
    new = function(_, player, entity, payload)
        return {}
    end,
}

_G.ContainerAuthorityFramework = {}

package.preload["pz_utils_shared"] = function()
    local sandboxStore = {}
    return {
        konijima = {
            Utilities = {
                IsPlayerAdmin = function(player)
                    return false
                end,
                SendClientCommand = function(...) end,
                SendServerCommandTo = function(...) end,
                SquareToString = function(square)
                    return "0,0,0"
                end,
            },
        },
        escape = {
            SandboxVarsModule = function()
                return {
                    Init = function(namespace, defaults)
                        sandboxStore[namespace] = sandboxStore[namespace] or {}
                        for k, v in pairs(defaults or {}) do
                            if sandboxStore[namespace][k] == nil then
                                sandboxStore[namespace][k] = v
                            end
                        end
                    end,
                    Create = function(name, defaults)
                        sandboxStore[name] = sandboxStore[name] or {}
                        for k, v in pairs(defaults or {}) do
                            if sandboxStore[name][k] == nil then
                                sandboxStore[name][k] = v
                            end
                        end
                        local ns = name
                        return {
                            Get = function(key, default)
                                if sandboxStore[ns][key] ~= nil then
                                    return sandboxStore[ns][key]
                                end
                                return default
                            end,
                        }
                    end,
                    Get = function(namespace, key, default)
                        if sandboxStore[namespace] and sandboxStore[namespace][key] ~= nil then
                            return sandboxStore[namespace][key]
                        end
                        return default
                    end,
                    GetAll = function(namespace)
                        return sandboxStore[namespace] or {}
                    end,
                }
            end,
            Utilities = {
                GetIRLTimestamp = function()
                    return os.time()
                end,
            },
        },
    }
end

package.preload["pz_lua_commons_shared"] = function()
    return {
        kikito = {
            middleclass = _G.middleclass,
        },
    }
end

package.preload["zul"] = function()
    local ZUL = {}
    ZUL.new = function(name)
        return {
            info = function(...) end,
            error = function(...) end,
            debug = function(...) end,
            trace = function(...) end,
            warn = function(...) end,
            setLevel = function(...) end,
        }
    end
    return ZUL
end

package.preload["ISUI/ISPanel"] = function()
    return _G.ISPanel
end
package.preload["ISUI/ISButton"] = function()
    return _G.ISButton
end
package.preload["ISUI/ISScrollingListBox"] = function()
    return _G.ISScrollingListBox
end
package.preload["ISUI/ISImage"] = function()
    return _G.ISImage
end
package.preload["ISUI/ISLabel"] = function()
    return _G.ISLabel
end
package.preload["ISUI/ISComboBox"] = function()
    return _G.ISComboBox
end
package.preload["ISUI/ISTextEntryBox"] = function()
    return _G.ISTextEntryBox
end
package.preload["ISUI/ISInventoryPage"] = function()
    return _G.ISInventoryPage
end
package.preload["TimedActions/ISBaseTimedAction"] = function()
    return _G.ISBaseTimedAction
end
package.preload["TimedActions/ISWalkToTimedAction"] = function()
    return _G.ISWalkToTimedAction
end
package.preload["TimedActions/ISTimedActionQueue"] = function()
    return _G.ISTimedActionQueue
end
package.preload["Entity/ISUI/Windows/ISEntityWindow"] = function()
    return _G.ISEntityWindow
end
package.preload["Entity/ISUI/Controls/ISTableLayout"] = function()
    return _G.ISTableLayout
end
package.preload["Entity/ISUI/CraftRecipe/ISTiledIconListBox"] = function()
    return _G.ISTiledIconListBox
end

package.preload["just_another_shop_mod/entity_ui/customer_view_window"] = function()
    return { open = function() end }
end
package.preload["just_another_shop_mod/entity_ui/owner_view_window"] = function()
    return { open = function() end }
end

local jasmPlainModules = {
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
for _, key in ipairs(jasmPlainModules) do
    package.preload[key] = function()
        return {}
    end
end

print("[pzspec] game stub pack loaded (SURFACE ## game, D9 per-event, ISTableLayout final-state)")
