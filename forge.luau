--[[                
    FORGE WIP: camera targeting and CCTV
    Uses bundled x64ui from telemetronomics/x64ui; builds camera targeting, ESP,
    NPC/bot tracking, radar, target HUD, and the CCTV monitor.

    Not tested in a Roblox client.
    Prior versions may leave an inactive namecall hook installed after unload.
    Dex++ is third-party code and is not unloaded by FORGE.

    CCTV WORLD RENDERING (ViewportFrame cannot show the live world, so it is rebuilt locally)
      Terrain       Rebuilt from Terrain:ReadVoxels as 4-stud blocks with real material colors,
                    water included. Wedge slopes approximate terrain; no grass decoration.
      Parts         Queried within a bounded radius and cloned in batches, nearer first.
                    Optional tracking includes nearby parts with CanQuery = false.
      Characters    Tracked characters are pose-synced live clones, never static ghosts.
      Sky/lighting  Sky is cloned for cubemap reflections; sun direction,
                    ambient and tint are mirrored. Atmosphere, fog, post-processing, particles,
                    beams, trails, billboards, SurfaceGuis and sounds are not rendered.
      Streaming     With StreamingEnabled only the streamed area exists to be cloned.
      Archivable    CCTVForceArchivable briefly sets Archivable = true on non-archivable
                    instances to clone them, then restores false.
]]

local CONFIG = {
    WindowTitle = "FORGE",
    ConfigFile = "forge_config.json",
    AutoLoadConfig = false,
    MenuKey = "RightShift",

    -- Hotkey names are Enum.KeyCode names, or "None".
    PanicKey = "End",
    ESPKey = "None",
    CCTVKey = "None",

    DexURL = "https://github.com/AZYsGithub/DexPlusPlus/releases/latest/download/out.lua",


    PlayersEnabled = true,
    NPCEnabled = false,
    NPCSource = "Auto", -- "Auto" = any Model with a Humanoid; "Container" = only inside NPCPath
    NPCPath = "",
    NPCInclude = "",    -- comma-separated name substrings, blank = any
    NPCExclude = "",
    NPCRequireHumanoid = true, -- false: accept Models with HumanoidRootPart or Head
    NPCHealthAttribute = "",   -- for bots without a Humanoid
    NPCMaxHealthAttribute = "",

    TargetPart = "Head",
    CameraAimEnabled = true,
    AimActivation = "MouseButton2",
    AimStrength = 0,
    AimLeadSeconds = 0,
    AimWallCheck = true,
    IgnoreFriends = false,
    IgnoreList = "",           -- comma-separated player names or display names
    TeamCheck = false,
    ForceFieldCheck = false,
    FovRadius = 150,
    MaxDistance = 500,
    ScopeEnabled = false, -- WIP: hold the scope key and scroll to magnify
    ScopeKey = "V",
    ScopeMinFov = 5,
    ScopeStep = 4,
    ScopeResponse = 16,
    SelectionRate = 20,

    ShowFov = true,
    ShowArrow = true,
    ArrowBounce = true,
    ArrowDeathMode = "Fade",
    ArrowHeight = 3,
    ArrowFadeSeconds = 0.8,
    ArrowHoldSeconds = 0.35,
    ArrowGlideResponse = 5,
    HudEnabled = true,

    RadarEnabled = false,
    RadarSize = 170,
    RadarRange = 150,
    RadarRotate = true,

    ESPEnabled = false,
    ESPPlayers = true,
    ESPNPCs = true,
    ESPBox = true,
    ESPName = true,
    ESPDistance = true,
    ESPHealth = true,
    ESPTracer = false,
    ESPSkeleton = false,
    ESPVisibleCheck = false,
    ESPTeamColor = true,
    ESPHideTeammates = false,
    ESPMaxDistance = 1500,
    ESPTextSize = 13,
    ESPBoxAspect = 0.55,
    ESPOpacity = 1, -- Drawing convention: 1 = opaque, 0 = invisible
    ESPPlayerColor = Color3.fromRGB(255, 60, 60),
    ESPNPCColor = Color3.fromRGB(255, 170, 0),
    ESPVisibleColor = Color3.fromRGB(80, 255, 120),

    -- CCTV monitor
    CCTVEnabled = false,
    CCTVSource = "Target", -- "Target" or "Self"
    CCTVShowLocation = true,
    CCTVSmoothTerrain = true,
    CCTVSceneTracking = true,
    CCTVMode = "Behind",         -- "Behind", "Front", "Overhead", "Orbit"
    CCTVPin = false,
    CCTVOpenSeconds = 0.45,
    CCTVShowSelf = true,
    CCTVResizeGrip = 24,
    CCTVDistance = 9,
    CCTVHeight = 3.5,
    CCTVFov = 70,
    CCTVSmoothing = 8,
    CCTVLostSeconds = 5,
    CCTVBackground = Color3.fromRGB(95, 125, 165),

    CCTVRadius = 250,
    CCTVMaxParts = 2500,
    CCTVSceneQueryMultiplier = 6,
    CCTVSceneSyncPerStep = 100,
    CCTVSceneRefresh = 3,
    CCTVForceArchivable = true,

    CCTVTerrain = true,
    CCTVTerrainRadius = 160,
    CCTVTerrainHeight = 48,
    CCTVTerrainMaxParts = 4500,
    CCTVTerrainRefresh = 20,

    CCTVSky = true,
    CCTVMatchLighting = true,
    CCTVOthers = true,
    CCTVMaxOthers = 10,
}

local THEME = {
    Panel = Color3.fromRGB(17, 19, 25),
    PanelAlt = Color3.fromRGB(26, 29, 38),
    Stroke = Color3.fromRGB(54, 60, 74),
    Text = Color3.fromRGB(232, 235, 242),
    Muted = Color3.fromRGB(139, 147, 164),
    Accent = Color3.fromRGB(96, 165, 250),
    Good = Color3.fromRGB(74, 222, 128),
    Warn = Color3.fromRGB(250, 204, 21),
    Bad = Color3.fromRGB(248, 113, 113),
    Font = Enum.Font.GothamMedium,
    FontBold = Enum.Font.GothamBold,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

assert(RunService:IsClient(), "FORGE: client execution required")
assert(type(getgenv) == "function", "FORGE: getgenv is required")

local env = getgenv()
assert(type(env) == "table", "FORGE: getgenv did not return a table")

local localPlayer = Players.LocalPlayer
assert(localPlayer, "FORGE: LocalPlayer unavailable")

local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    or localPlayer:WaitForChild("PlayerGui", 10)
assert(playerGui, "FORGE: PlayerGui unavailable")

local previous = env.FORGE_SESSION
if type(previous) == "table" and type(previous.Shutdown) == "function" then
    local ok, err = pcall(previous.Shutdown)
    assert(ok, "FORGE: previous session failed to shut down: " .. tostring(err))
end

local state = {
    alive = true,
    windowGone = false,
    aimHeld = false,
    target = nil,
    targetPart = nil,
    targetCamera = nil,
    targetPosition = nil,
    selectElapsed = math.huge,
    npcRoot = nil,
    arrow = { pos = nil, alpha = 0, rec = nil, idle = 0, gliding = false },
    connections = {},
}

local X64UI, window, espToggle, cctvToggle
local shutdown
local renderName = "ForgeClient_" .. HttpService:GenerateGUID(false)

local function say(text)
    text = tostring(text)
    if window and not state.windowGone and window.Destroyed ~= true then
        if type(window.Log) == "function" then window:Log(text) end
        if type(window.SetStatus) == "function" then window:SetStatus(text) end
    else
        warn("[FORGE] " .. text)
    end
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    state.connections[#state.connections + 1] = connection
    return connection
end

local function disconnectList(list)
    for _, connection in ipairs(list) do
        connection:Disconnect()
    end
    table.clear(list)
end

-- Silent UI sync; SetValue's second argument is the library's no-callback flag.
local function syncControl(control, value)
    if type(control) == "table" and type(control.SetValue) == "function" then
        pcall(control.SetValue, control, value, true)
    end
end

local function hex(color)
    return string.format(
        "#%02x%02x%02x",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function esc(text)
    return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Remote loading --------------------------------------------------------

local function fetch(url)
    if type(url) ~= "string" or string.sub(url, 1, 8) ~= "https://" then
        return nil, "invalid URL"
    end

    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(body) == "string" and #body > 0 then
        return body
    end

    if type(request) == "function" then
        local ok2, response = pcall(request, { Url = url, Method = "GET" })
        if ok2 and type(response) == "table"
            and type(response.Body) == "string" and #response.Body > 0
            and (response.Success == nil or response.Success == true)
        then
            return response.Body
        end
    end

    return nil, "fetch failed: " .. url
end

local function runRemote(url)
    local source, fetchError = fetch(url)
    if not source then
        return false, fetchError
    end
    if type(loadstring) ~= "function" then
        return false, "loadstring unavailable"
    end

    local chunk, compileError = loadstring(source)
    if type(chunk) ~= "function" then
        return false, compileError or "compile failed"
    end

    local ok, result = pcall(chunk)
    if not ok then
        return false, result
    end
    return true, result
end

local function validLibrary(lib)
    return type(lib) == "table"
        and type(lib.CreateWindow) == "function"
        and lib._IntegrityError == nil
end

-- Bundled from telemetronomics/x64ui (main, c631380).
local function createBundledX64UI()
--[[
made by iris
d = desktop
5.1.0d
]]

local X64UI = {
  Version = "5.5.1-desktop",
  MenuKeybind = Enum.KeyCode.RightShift,
  Windows = {},
  ActiveWindow = nil,
  NotifyGui = nil,
  Commands = {},
  CommandOrder = {},
  FocusCounter = 0,
  Theme = {
    Font = Enum.Font.Code,
    TextSize = 13,
    Background = Color3.fromRGB(19, 19, 21),
    TitleBar = Color3.fromRGB(31, 31, 34),
    Toolbar = Color3.fromRGB(33, 33, 33),
  Menu = Color3.fromRGB(26, 26, 29),
    Panel = Color3.fromRGB(29, 29, 32),
    PanelAlt = Color3.fromRGB(38, 38, 42),
    Border = Color3.fromRGB(62, 62, 70),
    Text = Color3.fromRGB(222, 222, 227),
    Dim = Color3.fromRGB(128, 128, 136),
    Accent = Color3.fromRGB(0, 122, 204),
    AccentText = Color3.fromRGB(88, 158, 216),
    Warning = Color3.fromRGB(220, 220, 170),
    Bad = Color3.fromRGB(244, 71, 71),
    Selection = Color3.fromRGB(51, 153, 255),
    Button = Color3.fromRGB(44, 44, 48),
    ButtonHover = Color3.fromRGB(61, 61, 66),
    Scroll = Color3.fromRGB(74, 74, 80),
  },
}

local unpack = unpack or table.unpack

local Services = setmetatable({}, {
  __index = function(self, key)
    local service = game:GetService(key)
    self[key] = service
    return service
  end,
})

local UserInputService = Services.UserInputService
local RunService = Services.RunService
local TweenService = Services.TweenService
local Players = Services.Players
local GuiService = Services.GuiService
local HttpService = Services.HttpService
local Workspace = Services.Workspace

if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
  warn("[X64UI] Mobile is not supported. This build is desktop-only.")
  return
end

if not table.clone then
  function table.clone(t)
    local copy = {}
    for k, v in pairs(t) do
      copy[k] = v
    end
    return copy
  end
end

if not table.pack then
  function table.pack(...)
    return { n = select("#", ...), ... }
  end
end

local Theme = X64UI.Theme

local Layer = {
  Base = 1,
  Panel = 10,
  Popup = 2000,
  ColorPicker = 2500,
  Menu = 3000,
  Modal = 5000,
  Toast = 10000,
  Tooltip = 32767,
}

-- Live theming (Phase 5)
local ThemeBindings = {}

local function themed(instance, property, key)
  if not instance or not key or Theme[key] == nil then return instance end
  ThemeBindings[#ThemeBindings + 1] = { instance, property, key }
  instance[property] = Theme[key]
  return instance
end

function X64UI:SetThemeKey(key, value)
  if Theme[key] == nil and value == nil then return end
  Theme[key] = value
  X64UI.Theme[key] = value
  for i = #ThemeBindings, 1, -1 do
    local b = ThemeBindings[i]
    if not b[1] or not b[1].Parent then
      table.remove(ThemeBindings, i)
    elseif b[3] == key then
      pcall(function() b[1][b[2]] = value end)
    end
  end
end

function X64UI:ApplyTheme(patch)
  if type(patch) ~= "table" then return end
  for k, v in pairs(patch) do
    self:SetThemeKey(k, v)
  end
end




-- Forward declarations (B01): InitTooltip / Dialog call these before the
-- local function bodies appear later in the file.
local getParent, getViewportSize, getMousePos, mouseOverGui, pointInGui, toGuiSpace


local traceback = (debug and debug.traceback) and debug.traceback or function(err)
  return tostring(err)
end

-- ==================== PHASE 1: STRUCTURAL FIXES ====================

-- core/log.lua
local Log = {}
function Log.info(m) print("[X64UI] " .. tostring(m)) end
function Log.warn(m) warn("[X64UI] " .. tostring(m)) end
function Log.error(m) warn("[X64UI ERROR] " .. tostring(m)) end

-- core/platform.lua
local Platform = {
  CanWrite = type(writefile) == "function",
  CanRead = type(readfile) == "function" and type(isfile) == "function",
  CanDelete = type(delfile) == "function",
}

function Platform.readFile(path)
 if not Platform.CanRead then return nil end
 local existsOk, exists = pcall(isfile, path)
 if not existsOk or exists ~= true then return nil end
  local ok, data = pcall(readfile, path)
 return ok and type(data) == "string" and data or nil
end

function Platform.writeFile(path, content)
  if not Platform.CanWrite then return false end
  local ok = pcall(writefile, path, content)
  return ok == true
end

function Platform.fileExists(path)
  if not Platform.CanRead then return false end
  local ok, exists = pcall(isfile, path)
  return ok and exists == true
end

function Platform.deleteFile(path)
  if not Platform.CanDelete then return end
  pcall(delfile, path)
end

-- ui/glyphs.lua (Replaces corrupted Unicode strings)
local Glyphs = {
  Check = "\226\156\147",       -- ✓
  Cross = "\226\156\149",       -- ✕
  ArrowDown = "\226\150\188",   -- ▼
  ArrowRight = "\226\150\182",  -- ▶
  Grip = "\226\151\162",        -- ◢
  Minimize = "\226\128\148",    -- —
  Close = "X",
  Search = "\240\159\148\141"   -- 
}

-- services/registry.lua
local Registry = {}
Registry.__index = Registry
function Registry.new()
  return setmetatable({ Controls = {}, Toggles = {}, Options = {} }, Registry)
end
function Registry:Register(name, control, controlType)
  if not name then return end
  self.Controls[name] = control
  if controlType == "Toggle" then
    self.Toggles[name] = control
  else
    self.Options[name] = control
  end
end
function Registry:Unregister(name)
  self.Controls[name] = nil
  self.Toggles[name] = nil
  self.Options[name] = nil
end
function Registry:Get(name) return self.Controls[name] end
function Registry:Clear()
  -- snapshot first: Destroy mutates Controls via Unregister
  local snapshot = {}
  for _, c in pairs(self.Controls) do
    snapshot[#snapshot + 1] = c
  end
  for _, c in ipairs(snapshot) do
    if c and c.Destroy then pcall(c.Destroy, c) end
  end
  table.clear(self.Controls)
  table.clear(self.Toggles)
  table.clear(self.Options)
end

-- core/create.lua (Strict replacement for create())
local Create = {}
local function setProperty(inst, key, value)
  inst[key] = value
end

function Create.create(className, props, children)
  assert(type(className) == "string", "Create.create: className must be a string")
  assert(props == nil or type(props) == "table", "Create.create: props must be a table or nil")
  assert(children == nil or type(children) == "table", "Create.create: children must be a table or nil")

  local inst = Instance.new(className)
  for k, v in pairs(props or {}) do
    if k ~= "Parent" then
      local ok, err = pcall(setProperty, inst, k, v)
      if not ok and X64UI and X64UI._DebugCreate then
        Log.warn("Create.create failed to set " .. tostring(k) .. ": " .. tostring(err))
      end
    end
  end
  for _, child in ipairs(children or {}) do
    child.Parent = inst
  end
  if props and props.Parent then
    inst.Parent = props.Parent
  end
  return inst
end

-- ==================== SIGNAL ====================

local Signal = {}
Signal.__index = Signal

function Signal.new()
  return setmetatable({
    Bindings = {},
    Destroyed = false,
  }, Signal)
end

function Signal:Connect(callback)
  assert(type(callback) == "function", "Signal callback must be a function")

  if self.Destroyed then
    return {
      Connected = false,
      Disconnect = function() end,
    }
  end

  local binding = {
    Connected = true,
    Callback = callback,
  }

  table.insert(self.Bindings, binding)

  local connection
  connection = {
    Connected = true,
    Disconnect = function()
      if not binding.Connected then return end
      binding.Connected = false
      connection.Connected = false

      for i, current in ipairs(self.Bindings) do
        if current == binding then
          table.remove(self.Bindings, i)
          break
        end
      end
    end,
  }

  binding.Connection = connection
  return connection
end

function Signal:Fire(...)
  if self.Destroyed then
    return
  end

  if self._Firing then
    -- re-entrant: queue unbounded recursion
    return
  end

  self._Firing = true
  local snapshot = table.clone(self.Bindings)
  for _, binding in ipairs(snapshot) do
    if binding and binding.Connected then
      local ok, err = xpcall(binding.Callback, traceback, ...)
      if not ok then
        Log.warn("Signal callback failed:\n" .. tostring(err))
      end
    end
  end
  self._Firing = false
end

function Signal:ConnectDeferred(callback)
  return self:Connect(function(...)
    local args = table.pack(...)
    task.defer(function()
      callback(unpack(args, 1, args.n))
    end)
  end)
end

function Signal:Destroy()
  if self.Destroyed then return end
  self.Destroyed = true
  for _, binding in ipairs(self.Bindings) do
    binding.Connected = false
    if binding.Connection then binding.Connection.Connected = false end
  end
  table.clear(self.Bindings)
end

-- ==================== MAID ====================

local Maid = {}
Maid.__index = Maid

function Maid.new()
  return setmetatable({
    Tasks = {},
    Destroyed = false,
  }, Maid)
end

function Maid:Give(taskObject)
  if self.Destroyed then
    self:CleanupTask(taskObject)
    return taskObject
  end

  table.insert(self.Tasks, taskObject)
  return taskObject
end

function Maid:CleanupTask(taskObject)
  local taskType = typeof(taskObject)

  if taskType == "RBXScriptConnection" then
    pcall(function()
      taskObject:Disconnect()
    end)
  elseif taskType == "Instance" then
    pcall(function()
      taskObject:Destroy()
    end)
  elseif taskType == "thread" then
    pcall(task.cancel, taskObject)
  elseif type(taskObject) == "function" then
    pcall(taskObject)
  elseif type(taskObject) == "table" then
    if type(taskObject.Destroy) == "function" then
      pcall(function()
        taskObject:Destroy()
      end)
    elseif type(taskObject.Disconnect) == "function" then
      pcall(function()
        taskObject:Disconnect()
      end)
    end
  end
end

function Maid:Cleanup()
  for i = #self.Tasks, 1, -1 do
    self:CleanupTask(self.Tasks[i])
    self.Tasks[i] = nil
  end
end

function Maid:Destroy()
  if self.Destroyed then
    return
  end

  self.Destroyed = true
  self:Cleanup()
end

-- ==================== STATE ====================

local State = {}
State.__index = State

function State.new(defaultValue)
  return setmetatable({
    Value = defaultValue,
    Changed = Signal.new(),
  }, State)
end

function State:Get()
  return self.Value
end

function State:Set(value, silent)
  if self.Value == value then
    return false
  end

  local previous = self.Value
  self.Value = value

  if not silent then
    self.Changed:Fire(value, previous)
  end

  return true
end

function State:Destroy()
  self.Changed:Destroy()
end

-- ==================== HISTORY (Phase 4: Transaction-Aware) ====================

local History = {}
History.__index = History

function History.new(limit)
  return setmetatable({
    UndoStack = {},
    RedoStack = {},
    Limit = limit or 100,
    Applying = false,
    Transaction = nil,
  }, History)
end

function History:BeginTransaction(label)
  self._TxDepth = (self._TxDepth or 0) + 1
  if self._TxDepth == 1 then
    self.Transaction = { Label = label or "Transaction", Undos = {}, Redos = {} }
  end
end

function History:EndTransaction()
  self._TxDepth = math.max(0, (self._TxDepth or 0) - 1)
  if self._TxDepth > 0 then return end
  if not self.Transaction then return end
  local t = self.Transaction
  self.Transaction = nil
  if #t.Undos > 0 then
    self:Push(t.Label,
      function() for i = #t.Undos, 1, -1 do t.Undos[i]() end end,
      function() for i = 1, #t.Redos do t.Redos[i]() end end
    )
  end
end

function History:WithTransaction(label, fn)
  self:BeginTransaction(label)
  local ok, err = xpcall(fn, traceback)
  self:EndTransaction()
  if not ok then
    Log.warn("Transaction failed:\n" .. tostring(err))
  end
  return ok
end


function History:Push(label, undo, redo)
  if self.Applying then
    return
  end

  if self.Transaction then
    table.insert(self.Transaction.Undos, undo)
    table.insert(self.Transaction.Redos, redo)
    return
  end

  table.insert(self.UndoStack, {
    Label = label,
    Undo = undo,
    Redo = redo,
  })

  table.clear(self.RedoStack)

  while #self.UndoStack > self.Limit do
    table.remove(self.UndoStack, 1)
  end
end

function History:UndoLast()
  local entry = table.remove(self.UndoStack)

  if not entry then
    return false
  end

  self.Applying = true
  local ok, err = xpcall(entry.Undo, traceback)
  self.Applying = false

  if not ok then
    Log.warn("Undo failed:\n" .. tostring(err))
    table.insert(self.UndoStack, entry)
    return false
  end

  table.insert(self.RedoStack, entry)
  return true
end

function History:RedoLast()
  local entry = table.remove(self.RedoStack)

  if not entry then
    return false
  end

  self.Applying = true
  local ok, err = xpcall(entry.Redo, traceback)
  self.Applying = false

  if not ok then
    Log.warn("Redo failed:\n" .. tostring(err))
    table.insert(self.RedoStack, entry)
    return false
  end

  table.insert(self.UndoStack, entry)
  return true
end

function History:Clear()
  table.clear(self.UndoStack)
  table.clear(self.RedoStack)
end

-- ==================== PHASE 3: LIFECYCLE HARDENING (InputManager) ====================

-- InputRouter: one library-wide input owner (Phase 1)
local InputRouter = {
  Began = {},
  Changed = {},
  Ended = {},
  CaptureStack = {},
  Connected = false,
}

function InputRouter:On(phase, listener)
  table.insert(self[phase], listener)
  return function()
    local index = table.find(self[phase], listener)
    if index then table.remove(self[phase], index) end
  end
end

function InputRouter:PushCapture(handlers)
  table.insert(self.CaptureStack, handlers)
  return function()
    local index = table.find(self.CaptureStack, handlers)
    if index then table.remove(self.CaptureStack, index) end
  end
end

function InputRouter:Dispatch(phase, input, gameProcessed)
  local top = self.CaptureStack[#self.CaptureStack]
  if top then
    local handler = top[phase]
    if handler then
      local ok, err = xpcall(handler, traceback, input, gameProcessed)
      if not ok then Log.warn("InputRouter capture failed:\n" .. tostring(err)) end
    end
    return
  end
  for _, listener in ipairs(self[phase]) do
    local ok, err = xpcall(listener, traceback, input, gameProcessed)
    if not ok then Log.warn("InputRouter listener failed:\n" .. tostring(err)) end
  end
end

function InputRouter:Connect()
  if self.Connected then return end
  self.Connected = true
  self._began = UserInputService.InputBegan:Connect(function(input, gp)
    self:Dispatch("Began", input, gp)
  end)
  self._changed = UserInputService.InputChanged:Connect(function(input, gp)
    self:Dispatch("Changed", input, gp)
  end)
  self._ended = UserInputService.InputEnded:Connect(function(input, gp)
    self:Dispatch("Ended", input, gp)
  end)
end

function InputRouter:Disconnect()
  if self._began then self._began:Disconnect() end
  if self._changed then self._changed:Disconnect() end
  if self._ended then self._ended:Disconnect() end
  self._began, self._changed, self._ended = nil, nil, nil
  self.Connected = false
  table.clear(self.Began)
  table.clear(self.Changed)
  table.clear(self.Ended)
  table.clear(self.CaptureStack)
end

-- Back-compat shim used by existing KeyPicker code
local InputManager = {
  Capturing = false,
  Callback = nil,
  _release = nil,
}
function InputManager:Capture(cb)
  self.Capturing = true
  self.Callback = cb
  if self._release then self._release() end
  self._release = InputRouter:PushCapture({
    Began = function(input, gameProcessed)
      if self.Callback then
        self.Callback(input, gameProcessed)
      end
    end,
  })
end
function InputManager:Cancel()
  self.Capturing = false
  self.Callback = nil
  if self._release then
    self._release()
    self._release = nil
  end
end

-- Bind names: KeyCode.Name (RightShift, LeftControl, ...) or MouseButton1/2/3
local function InputToBindName(input)
  if not input then return nil end
  local uit = input.UserInputType
  if uit == Enum.UserInputType.Keyboard then
    local kc = input.KeyCode
    if not kc or kc == Enum.KeyCode.Unknown then
      return nil
    end
    return kc.Name
  end
  if uit == Enum.UserInputType.MouseButton1 then return "MouseButton1" end
  if uit == Enum.UserInputType.MouseButton2 then return "MouseButton2" end
  if uit == Enum.UserInputType.MouseButton3 then return "MouseButton3" end
  return nil
end

local function InputMatchesBind(input, bindName)
  if not bindName or bindName == "" or bindName == "None" then
    return false
  end
  local name = InputToBindName(input)
  if not name then
    return false
  end
  if name == bindName then
    return true
  end
  -- aliases: Shift / Control / Alt match either side
  if bindName == "Shift" and (name == "LeftShift" or name == "RightShift") then
    return true
  end
  if bindName == "Control" and (name == "LeftControl" or name == "RightControl") then
    return true
  end
  if bindName == "Alt" and (name == "LeftAlt" or name == "RightAlt") then
    return true
  end
  if bindName == "MB1" and name == "MouseButton1" then return true end
  if bindName == "MB2" and name == "MouseButton2" then return true end
  if bindName == "MB3" and name == "MouseButton3" then return true end
  return false
end

InputRouter:Connect()

-- ==================== PHASE 5: UX (Tooltips & Modals) ====================

local TooltipGui, TooltipLabel
local function InitTooltip()
  if TooltipGui then return end
  TooltipGui = Create.create("ScreenGui", {
    Name = "X64Tooltip", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99999, Parent = getParent()
  })
  TooltipLabel = Create.create("TextLabel", {
    Parent = TooltipGui, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
    BackgroundColor3 = Theme.PanelAlt, BorderColor3 = Theme.Border, Text = "",
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text, Visible = false, ZIndex = 99999
  })
end

local function ShowTooltip(text, pos)
  InitTooltip()
  TooltipLabel.Text = text
  TooltipLabel.Position = UDim2.fromOffset(pos.X + 10, pos.Y + 10)
  TooltipLabel.Visible = true
end

local function HideTooltip() if TooltipLabel then TooltipLabel.Visible = false end end

function X64UI:Dialog(opts)
  opts = opts or {}
  local gui = Create.create("ScreenGui", {
    Name = "X64Dialog", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99998, Parent = getParent()
  })
  local bg = Create.create("Frame", {
    Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 0.5, ZIndex = 99990
  })
  local frame = Create.create("Frame", {
    Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(400, 200), BackgroundColor3 = Theme.Panel, BorderColor3 = Theme.Border, ZIndex = 99991
  })
  local closeBtn = Create.create("TextButton", {
    Parent = frame, Size = UDim2.fromOffset(80, 30), Position = UDim2.new(0.5, -40, 1, -40),
    BackgroundColor3 = Theme.Button, Text = "Close", Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text, ZIndex = 99992
  })
  closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)
end

-- ==================== HELPERS ====================

function getParent()
  if gethui then
    local ok, h = pcall(gethui)
    if ok and h then return h end
  end

  local ok, core = pcall(function()
    return game:GetService("CoreGui")
  end)

  if ok and core then
    return core
  end

  local player = Players.LocalPlayer
  if not player then
    repeat task.wait() player = Players.LocalPlayer until player
  end
  return player:WaitForChild("PlayerGui")
end

function getViewportSize(gui)
  -- Prefer measured ScreenGui size (correct with IgnoreGuiInset).
  -- Never add GuiInset on top of Camera.ViewportSize (double-counts topbar).
  if gui and gui.Parent and gui.AbsoluteSize.X > 0 then
    return gui.AbsoluteSize
  end
  local cam = Workspace.CurrentCamera
  if cam and cam.ViewportSize then
    return cam.ViewportSize
  end
  return Vector2.new(1280, 720)
end

local function getSafeViewportRect()
  local viewport = getViewportSize()
  local margin = 8
  -- keep a hard edge inset so corners never sit past the screen
  local left = margin
  local top = margin
  local right = viewport.X - margin
  local bottom = viewport.Y - margin
  return left, top, right, bottom, viewport
end

function getMousePos()
  -- Always use GetMouseLocation (top-left of screen). InputObject.Position from
  -- InputBegan is NOT updated for MouseButton1/2 (Roblox API).
  return UserInputService:GetMouseLocation()
end

function toGuiSpace(point, gui)
  -- ScreenGui with IgnoreGuiInset draws over the topbar; mouse coords do not.
  if gui and gui:IsA("ScreenGui") and gui.IgnoreGuiInset then
    return point + GuiService:GetGuiInset()
  end
  return point
end

function pointInGui(gui, point)
  if not gui or not gui.Parent then return false end

  local pos = gui.AbsolutePosition
  local size = gui.AbsoluteSize

  return point.X >= pos.X
    and point.X <= pos.X + size.X
    and point.Y >= pos.Y
    and point.Y <= pos.Y + size.Y
end

function mouseOverGui(gui)
  local ok, mouse = pcall(getMousePos)
  if not ok or not mouse then return false end

  -- Try both raw mouse and inset-reconciled point so hit tests work for
  -- IgnoreGuiInset and non-IgnoreGuiInset roots.
  if pointInGui(gui, mouse) then return true end
  local inset = GuiService:GetGuiInset()
  return pointInGui(gui, mouse - inset) or pointInGui(gui, mouse + inset)
end

local function bindCanvas(window, scroll, layout)
  local function update()
    if scroll and scroll.Parent then
      scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)
    end
  end

  window:Track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update))
  update()
end

local function isControlValueValid(control, value)
  if not control or not control.Type then
    return false
  end

  local t = control.Type
  if t == "Toggle" then
    return typeof(value) == "boolean"
  end
  if t == "Slider" or t == "NumericInput" then
    return typeof(value) == "number" and value == value and math.abs(value) < math.huge
  end
  if t == "Dropdown" then
    if typeof(value) == "table" then return true end -- multi
    return typeof(value) == "string" or typeof(value) == "number"
  end
  if t == "ColorPicker" then
    return typeof(value) == "Color3" or (type(value) == "table" and value.r ~= nil)
  end
  if t == "KeyPicker" then
    return typeof(value) == "string"
  end
  if t == "ListBox" or t == "Tree" or t == "Table" then
    return typeof(value) == "table" or typeof(value) == "string" or typeof(value) == "number" or value == nil
  end
  if t == "Input" or t == "TextBox" then
    return typeof(value) == "string" or typeof(value) == "number"
  end
  return true -- unknown types: don't block save
end

local function getWindowResizeLimits()
  local left, top, right, bottom, viewport = getSafeViewportRect()
  local margin = 8

  local maxW = math.max(1, right - left)
  local maxH = math.max(1, bottom - top)

  local minW = math.min(760, maxW)
  local minH = math.min(420, maxH)

  return viewport, margin, Vector2.new(minW, minH), Vector2.new(maxW, maxH)
end

-- ==================== CLASSES ====================

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local Groupbox = {}
Groupbox.__index = Groupbox

-- ==================== PHASE 2: CONTROL API STANDARDIZATION (BaseControl) ====================

local BaseControl = {}
BaseControl.__index = BaseControl
function BaseControl.new(type, frame, window, name)
  return setmetatable({ Type = type, Frame = frame, Window = window, Name = name, Visible = true, Disabled = false, ReadOnly = false }, BaseControl)
end
function BaseControl:SetVisible(v)
  self.Visible = v and true or false
  if self.Frame then self.Frame.Visible = self.Visible end
end

function BaseControl:SetDisabled(v)
  self.Disabled = v and true or false
  if self.Frame then
    self.Frame.Active = not self.Disabled
  end
  if self.Label then
    self.Label.TextColor3 = self.Disabled and Theme.Dim or Theme.Text
  end
end

function BaseControl:SetReadOnly(v)
  self.ReadOnly = v and true or false
end

function BaseControl:CanInteract()
  return (not self.Disabled) and (not self.ReadOnly) and self.Visible and (not self.Destroyed)
end

function BaseControl:Destroy()
  if self.Destroyed then return end
  self.Destroyed = true
  if self.Frame then pcall(function() self.Frame:Destroy() end) end
  if self.Window and self.Window.Registry and self.Name then self.Window.Registry:Unregister(self.Name) end
end

-- Chaining helpers (Linoria-style): label:AddKeyPicker, toggle:AddColorPicker
function BaseControl:AddKeyPicker(name, opts)
  if not self.Window or not self.Frame then return nil end
  -- find parent groupbox via Frame parent chain is hard; use Window active tab default
  local group = self._Groupbox
  if not group then return nil end
  opts = opts or {}
  opts.Text = opts.Text or ""
  return group:AddKeyPicker(name, opts)
end

function BaseControl:AddColorPicker(name, opts)
  local group = self._Groupbox
  if not group then return nil end
  return group:AddColorPicker(name, opts)
end


-- ==================== WINDOW CORE ====================

function Window:Track(taskObject)
  if self.Destroyed then
    if self.Maid then
      self.Maid:CleanupTask(taskObject)
    end
    return taskObject
  end

  if self.Maid then
    self.Maid:Give(taskObject)
  end

  return taskObject
end

function Window:DisconnectAll()
  if self.Maid then
    self.Maid:Cleanup()
  end

  if self.Events then
    for _, event in pairs(self.Events) do
      if type(event) == "table" and type(event.Destroy) == "function" then
        pcall(function()
          event:Destroy()
        end)
      end
    end
  end
end

function Window:Focus()
  if self.Destroyed then return end

  X64UI.FocusCounter = (X64UI.FocusCounter + 1) % 1000000

  if self.Gui then
    self.Gui.DisplayOrder = 10000 + X64UI.FocusCounter
  end

  X64UI.ActiveWindow = self

  if self.Events and self.Events.Focused then
    self.Events.Focused:Fire(self)
  end
end

function Window:SetStatus(text)
  if self.StatusLabel then
    self.StatusLabel.Text = tostring(text)
  end
end

function Window:Log(message, severity)
  if not self.LogLabel or not self.LogLabel.Parent then return end

  if not self.Lines then self.Lines = {} end

  local text = tostring(message)
  local sev = severity
  if not sev then
    local lower = string.lower(text)
    if lower:find("error", 1, true) or lower:find("fail", 1, true) then
      sev = "error"
    elseif lower:find("warn", 1, true) then
      sev = "warn"
    elseif lower:find("success", 1, true) or lower:find("loaded", 1, true) then
      sev = "good"
    else
      sev = "info"
    end
  end

  local color = "#DCDCE3"
  if sev == "error" or sev == "bad" then
    color = "#F44747"
  elseif sev == "warn" or sev == "warning" then
    color = "#DCDCAA"
  elseif sev == "good" or sev == "success" then
    color = "#4EC9B0"
  elseif sev == "accent" then
    color = "#589ED8"
  end

  -- escape richtext special chars in message body
  local safe = text:gsub("[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" })
  local line = string.format(
    '<font color="#888888">[%s]</font> <font color="%s">%s</font>',
    os.date("%X"),
    color,
    safe
  )
  self.Lines[#self.Lines + 1] = line

  while #self.Lines > 200 do
    table.remove(self.Lines, 1)
  end

  self._LogDirty = true
  if self._LogFlushScheduled then return end
  self._LogFlushScheduled = true

  task.defer(function()
    self._LogFlushScheduled = false
    if self.Destroyed or not self._LogDirty then return end
    self._LogDirty = false

    if not self.LogLabel or not self.LogLabel.Parent then return end

    local joined = table.concat(self.Lines, "\n")
    if #joined > 12000 then
      joined = joined:sub(#joined - 12000)
    end
    self.LogLabel.Text = joined

    if self.LogScroll and self.LogLabel.Parent then
      local y = self.LogLabel.TextBounds.Y + 10
      self.LogScroll.CanvasSize = UDim2.fromOffset(0, y)
      self.LogScroll.CanvasPosition = Vector2.new(0, math.max(0, y - self.LogScroll.AbsoluteSize.Y))
    end
  end)
end

function Window:ClearLog()
  table.clear(self.Lines)

  if self.LogLabel then
    self.LogLabel.Text = ""
  end

  if self.LogScroll then
    self.LogScroll.CanvasSize = UDim2.new()
  end
end

function Window:CloseDropdowns()
  for _, dropdown in ipairs(self.Dropdowns) do
    if dropdown and dropdown.Close then
      pcall(function() dropdown:Close() end)
    end
  end
end

function Window:UpdateLayout()
  if self.Destroyed or self.Minimized then return end

  local consoleHeight = self.ConsoleVisible and 160 or 0
  local statusHeight = self.StatusVisible and 22 or 0

  self.Console.Visible = self.ConsoleVisible
  self.StatusBar.Visible = self.StatusVisible

  self.Pages.Position = UDim2.fromOffset(4, self.TopOffset)
  self.Pages.Size = UDim2.new(1, -8, 1, -(self.TopOffset + consoleHeight + statusHeight + 8))

  self.Console.Position = UDim2.new(0, 4, 1, -(consoleHeight + statusHeight + 4))
  self.Console.Size = UDim2.new(1, -8, 0, consoleHeight)

  self.StatusBar.Position = UDim2.new(0, 0, 1, -statusHeight)
  self.StatusBar.Size = UDim2.new(1, 0, 0, statusHeight)
end

function Window:ClampToViewport()
  if self.Destroyed or self.Maximized or self.Minimized then return end
  if not self.Main or not self.Main.Parent then return end
  -- never rewrite position mid-drag (that is what caused the snap)
  if self._Dragging then return end

  local left, top, right, bottom, viewport = getSafeViewportRect()
  local _, margin, minSize, maxSize = getWindowResizeLimits()

  local currentSize = Vector2.new(self.Main.AbsoluteSize.X, self.Main.AbsoluteSize.Y)
  local size = Vector2.new(
    math.clamp(currentSize.X, minSize.X, maxSize.X),
    math.clamp(currentSize.Y, minSize.Y, maxSize.Y)
  )

  if size.X ~= currentSize.X or size.Y ~= currentSize.Y then
    self.Main.Size = UDim2.fromOffset(size.X, size.Y)
    self:UpdateLayout()
  end

  -- stay in Position.Offset space (ScreenGui IgnoreGuiInset). AbsolutePosition
  -- can differ by inset and causes a visible jump when written back.
  local posX = self.Main.Position.X.Offset
  local posY = self.Main.Position.Y.Offset

  local maxX = math.max(left, right - size.X)
  local maxY = math.max(top, bottom - size.Y)

  posX = math.clamp(posX, left, maxX)
  posY = math.clamp(posY, top, maxY)

  if posX + size.X > right then
    posX = math.max(left, right - size.X)
  end
  if posY + size.Y > bottom then
    posY = math.max(top, bottom - size.Y)
  end

  self.Main.Position = UDim2.fromOffset(posX, posY)
end

function Window:ToggleConsole()
  self.ConsoleVisible = not self.ConsoleVisible
  self:UpdateLayout()

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("ConsoleVisible", self.ConsoleVisible)
  end
end

function Window:ToggleStatusBar()
  self.StatusVisible = not self.StatusVisible
  self:UpdateLayout()

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("StatusVisible", self.StatusVisible)
  end
end

function Window:SetMinimized(value)
  if value then self:CloseAllPopups() end
  if self.Destroyed then return end

  value = value and true or false
  if value == self.Minimized then return end

  self.Minimized = value
  self.State.Minimized:Set(value)

  if value then
    self.LastSize = self.Main.Size
    self.Main.Size = UDim2.fromOffset(self.Main.AbsoluteSize.X, 24)

    if self.MenuBar then self.MenuBar.Visible = false end
    if self.Toolbar then self.Toolbar.Visible = false end
    if self.MenuDropdown then self.MenuDropdown.Visible = false end
    self.TabBar.Visible = false
    self.Pages.Visible = false
    self.Console.Visible = false
    self.StatusBar.Visible = false
    self.Grip.Visible = false
  else
    self.Main.Size = self.LastSize or UDim2.fromOffset(1000, 640)

    if self.MenuBar then self.MenuBar.Visible = true end
    if self.Toolbar then self.Toolbar.Visible = true end
    self.TabBar.Visible = true
    self.Pages.Visible = true
    self.Console.Visible = self.ConsoleVisible
    self.StatusBar.Visible = self.StatusVisible
    self.Grip.Visible = true

    self:UpdateLayout()
    self:ClampToViewport()
  end

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("Minimized", value)
  end
end

function Window:SetMaximized(value)
  if self.Destroyed or self.Minimized then return end

  value = value and true or false
  if value == self.Maximized then return end

  self.Maximized = value
  self.State.Maximized:Set(value)

  if value then
    self.PreMaxSize = self.Main.Size
    self.PreMaxPosition = self.Main.Position

    local viewport = getViewportSize()
    self.Main.Position = UDim2.fromOffset(0, 0)
    self.Main.Size = UDim2.fromOffset(viewport.X, viewport.Y)
  else
    self.Main.Size = self.PreMaxSize or UDim2.fromOffset(1000, 640)
    self.Main.Position = self.PreMaxPosition or UDim2.fromOffset(100, 100)
    self:ClampToViewport()
  end

  self:UpdateLayout()

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("Maximized", value)
  end
end

function Window:Show()
  if self.Destroyed then return end

  if not self.Main.Visible then
    self.Main.Visible = true
    self.State.Visible:Set(true)

    if self.Events and self.Events.VisibilityChanged then
      self.Events.VisibilityChanged:Fire(true)
    end
  end
end

function Window:Hide()
  self:CloseAllPopups()
  if self.Destroyed then return end

  if self.Main.Visible then
    self:CloseDropdowns()

    if self.CloseMenu then
      self.CloseMenu()
    end

    if self.CommandPalette then
      self.CommandPalette.Visible = false
    end

    if self.MenuDropdown then
      self.MenuDropdown.Visible = false
    end

    self.Main.Visible = false
    self.State.Visible:Set(false)

    if self.Events and self.Events.VisibilityChanged then
      self.Events.VisibilityChanged:Fire(false)
    end
  end
end

function Window:Toggle()
  self:CloseAllPopups()
  if self.Main.Visible then
    self:Hide()
  else
    self:Show()
  end
end


function Window:RegisterPopup(popup)
  if not self.Popups then self.Popups = {} end
  table.insert(self.Popups, popup)
  return popup
end

function Window:CloseAllPopups()
  if not self.Popups then return end
  for _, popup in ipairs(self.Popups) do
    pcall(function()
      if type(popup.Close) == "function" then
        popup:Close()
      elseif type(popup) == "function" then
        popup()
      end
    end)
  end
  table.clear(self.Popups)
end

function Window:Destroy()
  self:CloseAllPopups()
  if self.Destroyed then
    return
  end

  self.Destroyed = true

  if self.Events and self.Events.Destroying then
    self.Events.Destroying:Fire(self)
  end

  if self.CommandPalette then
    self.CommandPalette.Visible = false
  end

  self:CloseDropdowns()

  if self.Maid then
    self.Maid:Destroy()
  else
    self:DisconnectAll()
  end

  if self.Registry then
    self.Registry:Clear()
  end

  if self.Gui then
    self.Gui:Destroy()
    self.Gui = nil
  end

  for i, win in ipairs(X64UI.Windows) do
    if win == self then
      table.remove(X64UI.Windows, i)
      break
    end
  end

  if X64UI.ActiveWindow == self then
    X64UI.ActiveWindow = X64UI.Windows[#X64UI.Windows] or nil
  end
end

function Window:PlayIntro()
  if self.IntroPlayed or self.Destroyed then return end
  self.IntroPlayed = true

  pcall(function()
    local wash = Create.create("CanvasGroup", {
      Parent = self.Gui,
      Size = UDim2.fromScale(1, 1),
      BackgroundColor3 = Color3.fromRGB(7, 7, 9),
      BackgroundTransparency = 0,
      GroupTransparency = 0,
      BorderSizePixel = 0,
      ZIndex = 32767,
    })

    if self.Maid then
      self.Maid:Give(wash)
    end

    local gradient = Create.create("UIGradient", {
      Parent = wash,
      Rotation = 90,
      Offset = Vector2.new(0, -0.2),
      Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.35, 0.22),
        NumberSequenceKeypoint.new(0.65, 0.55),
        NumberSequenceKeypoint.new(1, 1),
      }),
    })

    TweenService:Create(
      gradient,
      TweenInfo.new(0.56, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
      { Offset = Vector2.new(0, 0.28) }
    ):Play()

    local washTween = TweenService:Create(
      wash,
      TweenInfo.new(0.56, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
      { GroupTransparency = 1 }
    )

    washTween:Play()

    washTween.Completed:Connect(function()
      wash:Destroy()
    end)
  end)
end

-- ==================== DRAG / RESIZE ====================

function Window:MakeDraggable(frame, handle)
  local dragging = false
  local startMouse = Vector2.zero
  local startPos = Vector2.zero

  local function canDrag()
    if self.Destroyed or not frame.Parent or not handle.Parent then return false end
    if not self.Main.Visible then return false end
    if self.Maximized then return false end
    if UserInputService:GetFocusedTextBox() then return false end
    if self.MinButton and mouseOverGui(self.MinButton) then return false end
    if self.CloseButton and mouseOverGui(self.CloseButton) then return false end
    return true
  end

  local function beginDrag(input)
    if not canDrag() then return end

    dragging = true
    -- use offset-space only (IgnoreGuiInset ScreenGui). mixing AbsolutePosition
    -- with Position.Offset causes a one-frame snap on every move.
    startMouse = getMousePos()
    startPos = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
    self._Dragging = true
    self:Focus()
  end

  self:Track(handle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      beginDrag(input)
    end
  end))

  self:Track(UserInputService.InputBegan:Connect(function(input)
    if dragging then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      if mouseOverGui(handle) then
        beginDrag(input)
      end
    end
  end))

  self:Track(UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement then
      local current = getMousePos()
      local delta = current - startMouse
      local nextPos = startPos + delta

      -- soft edge limits while dragging (no AbsolutePosition rewrite)
      local left, top, right, bottom = getSafeViewportRect()
      local size = Vector2.new(frame.AbsoluteSize.X, frame.AbsoluteSize.Y)
      nextPos = Vector2.new(
        math.clamp(nextPos.X, left, math.max(left, right - size.X)),
        math.clamp(nextPos.Y, top, math.max(top, bottom - size.Y))
      )

      frame.Position = UDim2.fromOffset(nextPos.X, nextPos.Y)
    end
  end))

  self:Track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
      dragging = false
      self._Dragging = false
      self:ClampToViewport()
    end
  end))
end

function Window:MakeResizable(frame, grip)
  local resizing = false
  local startMouse = Vector2.zero
  local startSize = Vector2.zero

  local function canResize()
    if self.Destroyed or not frame.Parent or not grip.Parent or not grip.Visible then
      return false
    end

    if not self.Main.Visible then return false end
    if self.Minimized or self.Maximized then return false end
    if UserInputService:GetFocusedTextBox() then return false end
    return true
  end

  local function normalizeSize()
    local _, _, minSize, maxSize = getWindowResizeLimits()

    local current = Vector2.new(frame.AbsoluteSize.X, frame.AbsoluteSize.Y)
    local fixed = Vector2.new(
      math.clamp(current.X, minSize.X, maxSize.X),
      math.clamp(current.Y, minSize.Y, maxSize.Y)
    )

    if fixed.X ~= current.X or fixed.Y ~= current.Y then
      frame.Size = UDim2.fromOffset(fixed.X, fixed.Y)
      self:UpdateLayout()
    end

    return fixed
  end

  local function beginResize(input)
    if not canResize() then return end

    resizing = true
    startMouse = getMousePos()
    startSize = normalizeSize()
    self:Focus()
  end

  self:Track(grip.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      beginResize(input)
    end
  end))

  self:Track(UserInputService.InputBegan:Connect(function(input)
    if resizing then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      if mouseOverGui(grip) then
        beginResize(input)
      end
    end
  end))

  self:Track(UserInputService.InputChanged:Connect(function(input)
    if not resizing then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement then
      local _, _, minSize, maxSize = getWindowResizeLimits()
      local current = getMousePos()

      local nextSize = Vector2.new(
        math.clamp(startSize.X + (current.X - startMouse.X), minSize.X, maxSize.X),
        math.clamp(startSize.Y + (current.Y - startMouse.Y), minSize.Y, maxSize.Y)
      )

      frame.Size = UDim2.fromOffset(nextSize.X, nextSize.Y)

      self:UpdateLayout()
      self:ClampToViewport()
    end
  end))

  self:Track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and resizing then
      resizing = false
      self:ClampToViewport()
    end
  end))
end

-- ==================== TABS ====================

function Window:SelectTab(name)
  local tab = self.Tabs[name]
  if not tab then return end

  self:CloseDropdowns()

  if self.CommandPalette then
    self.CommandPalette.Visible = false
  end

  for _, other in pairs(self.Tabs) do
    other.Page.Visible = false
    other.Underline.Visible = false
    other.Button.TextColor3 = Theme.Dim
  end

  tab.Page.Visible = true
  tab.Underline.Visible = true
  tab.Button.TextColor3 = Theme.Text

  self:SetStatus("Tab: " .. tostring(name))
  self.State.ActiveTab:Set(name)

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("ActiveTab", name)
  end
end

function Window:AddTab(name)
  if self.Tabs[name] then
    return self.Tabs[name]
  end

  local tab = setmetatable({
    Window = self,
    Name = name,
    NextLeftOrder = 0,
    NextRightOrder = 0,
  }, Tab)

  local order = #self.TabOrder + 1
  table.insert(self.TabOrder, name)

  tab.Button = Create.create("TextButton", {
    Parent = self.TabBar,
    Size = UDim2.fromOffset(0, 26),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundTransparency = 1,
    Text = "  " .. tostring(name) .. "  ",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Dim,
    LayoutOrder = order,
  })

  tab.Underline = Create.create("Frame", {
    Parent = tab.Button,
    Size = UDim2.new(1, 0, 0, 2),
    Position = UDim2.new(0, 0, 1, -2),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    Visible = false,
  })

  self:Track(tab.Button.MouseEnter:Connect(function()
    if not tab.Underline.Visible then
      tab.Button.TextColor3 = Theme.Text
    end
  end))

  self:Track(tab.Button.MouseLeave:Connect(function()
    if not tab.Underline.Visible then
      tab.Button.TextColor3 = Theme.Dim
    end
  end))

  self:Track(tab.Button.MouseButton1Click:Connect(function()
    self:SelectTab(name)
  end))

  tab.Page = Create.create("Frame", {
    Parent = self.Pages,
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Visible = false,
  })

  tab.LeftPane = Create.create("ScrollingFrame", {
    Parent = tab.Page,
    Size = UDim2.new(0.5, -3, 1, 0),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = Theme.Background,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
    ScrollBarThickness = 8,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })

  tab.RightPane = Create.create("ScrollingFrame", {
    Parent = tab.Page,
    Size = UDim2.new(0.5, -3, 1, 0),
    Position = UDim2.new(0.5, 3, 0, 0),
    BackgroundColor3 = Theme.Background,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
    ScrollBarThickness = 8,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })

  local leftList = Create.create("UIListLayout", {
    Parent = tab.LeftPane,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  local rightList = Create.create("UIListLayout", {
    Parent = tab.RightPane,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  Create.create("UIPadding", {
    Parent = tab.LeftPane,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  Create.create("UIPadding", {
    Parent = tab.RightPane,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  bindCanvas(self, tab.LeftPane, leftList)
  bindCanvas(self, tab.RightPane, rightList)

  self.Tabs[name] = tab

  if #self.TabOrder == 1 then
    self:SelectTab(name)
  end

  return tab
end

-- ==================== CONFIG (Phase 4: State and Config) ====================


function Window:SaveProfile(name)
  name = tostring(name or "default"):gsub("[^%w%-%_]", "")
  if name == "" then name = "default" end
  return self:SaveConfig("x64ui_profile_" .. name .. ".json")
end

function Window:LoadProfile(name, loadOpts)
  name = tostring(name or "default"):gsub("[^%w%-%_]", "")
  if name == "" then name = "default" end
  return self:LoadConfig("x64ui_profile_" .. name .. ".json", loadOpts)
end

function Window:SaveConfig(path)
  path = path or "x64ui_config.json"

  if not Platform.CanWrite then
    self:Log("writefile is not supported by this executor.")
    return false
  end

  local data = {
    Version = 2,
    Toggles = {},
    Options = {},
    Layout = {},
  }

  for name, toggle in pairs(self.Registry.Toggles) do
    if toggle.NoSave then continue end
    if typeof(toggle.Value) == "boolean" then
      data.Toggles[name] = toggle.Value
    end
  end

  for name, option in pairs(self.Registry.Options) do
    if option.NoSave then continue end
    local encoded = X64UI.SerializeValue(option)
    if encoded ~= nil then
      data.Options[name] = encoded
    end
  end

  data.Layout = {
    Size = { self.Main.Size.X.Offset, self.Main.Size.Y.Offset },
    Pos = { self.Main.Position.X.Offset, self.Main.Position.Y.Offset },
    Minimized = self.Minimized == true,
    Maximized = self.Maximized == true,
    Scale = self.Scale or 1,
  }
  data.Version = 3
  data.MenuKeybind = (typeof(X64UI.MenuKeybind) == "EnumItem") and X64UI.MenuKeybind.Name or tostring(X64UI.MenuKeybind)

  local ok, json = pcall(function()
    return HttpService:JSONEncode(data)
  end)

  if ok and Platform.writeFile(path, json) then
    self:Log("Config saved: " .. path)
    return true
  end
  self:Log(ok and "Config write failed." or "Config encode failed.")
  return false
end

function Window:LoadConfig(path, loadOpts)
  path = path or "x64ui_config.json"
  loadOpts = loadOpts or {}

  local silent = loadOpts.Silent
  local fireCallbacks = loadOpts.FireCallbacks ~= false
  local recordHistory = loadOpts.RecordHistory ~= false
  local applyLayout = loadOpts.ApplyLayout ~= false

  if not Platform.fileExists(path) then
    self:Log("Config file not found.")
    return false
  end

  local json = Platform.readFile(path)
  if not json then
    self:Log("Config read failed.")
    return false
  end
  if #json > 1048576 then
    self:Log("Config exceeds the 1 MiB limit.")
    return false
  end

  local okDecode, data = pcall(function()
    return HttpService:JSONDecode(json)
  end)

  if not okDecode or typeof(data) ~= "table" then
    self:Log("Config decode failed.")
    return false
  end

  -- Config migrations (Phase 4)
  if data.Version ~= nil and (type(data.Version) ~= "number"
    or data.Version ~= data.Version or data.Version > 3) then
    self:Log("Unsupported config version.")
    return false
  end
  if not data.Version or data.Version < 2 then
    data.Layout = data.Layout or {}
    data.Version = 2
  end

  if recordHistory then self.History:BeginTransaction("Load Config") end

  if typeof(data.Toggles) == "table" then
    for name, value in pairs(data.Toggles) do
      local toggle = self.Registry:Get(name)
      if toggle and toggle.SetValue and isControlValueValid(toggle, value) then
        toggle:SetValue(value, not fireCallbacks)
      end
    end
  end

  if typeof(data.Options) == "table" then
    for name, value in pairs(data.Options) do
      local option = self.Registry:Get(name)

      if option and option.SetValue then
        value = X64UI.DeserializeValue(option, value)

        if option.Type == "Slider" and typeof(value) == "number" then
          value = math.clamp(value, option.Min or value, option.Max or value)
        end

        if isControlValueValid(option, value) then
          option:SetValue(value, not fireCallbacks)
        else
          Log.warn("Config rejected key '" .. tostring(name) .. "' (invalid value for " .. tostring(option.Type) .. ")")
        end
      end
    end
  end

  if applyLayout and typeof(data.Layout) == "table" then
    local function validPair(pair)
      return type(pair) == "table"
        and type(pair[1]) == "number" and type(pair[2]) == "number"
        and pair[1] == pair[1] and pair[2] == pair[2]
        and math.abs(pair[1]) < 100000 and math.abs(pair[2]) < 100000
    end
    if validPair(data.Layout.Size) then self.Main.Size = UDim2.fromOffset(data.Layout.Size[1], data.Layout.Size[2]) end
    if validPair(data.Layout.Pos) then self.Main.Position = UDim2.fromOffset(data.Layout.Pos[1], data.Layout.Pos[2]) end
    self:ClampToViewport()
    self:UpdateLayout()
  end

  if recordHistory then self.History:EndTransaction() end
  if not silent then self:Log(("Config loaded: %s"):format(path)) end
  return true
end

-- ==================== COMMAND PALETTE ====================

function Window:CreateCommandPalette()
  local palette = Create.create("Frame", {
    Parent = self.Gui,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 90),
    Size = UDim2.fromOffset(520, 320),
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    Visible = false,
    ZIndex = 5000,
  })

  local input = Create.create("TextBox", {
    Parent = palette,
    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.new(1, -16, 0, 30),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    PlaceholderText = "Search commands...  Ctrl+P to toggle",
    ClearTextOnFocus = false,
    Text = "",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    ZIndex = 5001,
  })

  local results = Create.create("ScrollingFrame", {
    Parent = palette,
    Position = UDim2.fromOffset(8, 46),
    Size = UDim2.new(1, -16, 1, -54),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
    ZIndex = 5001,
  })

  local layout = Create.create("UIListLayout", {
    Parent = results,
    Padding = UDim.new(0, 3),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  local itemMaid = Maid.new()
  self.Maid:Give(itemMaid)

  local selectedIndex = 1
  local visibleCommands = {}
  local resultButtons = {}

  local function updateSelection()
    if #resultButtons == 0 then
      return
    end

    selectedIndex = math.clamp(selectedIndex, 1, #resultButtons)

    for i, button in ipairs(resultButtons) do
      button.BackgroundColor3 = (i == selectedIndex) and Theme.Selection or Theme.Button
    end

    local selectedButton = resultButtons[selectedIndex]

    if selectedButton and results.Parent then
      local itemTop = selectedButton.AbsolutePosition.Y - results.AbsolutePosition.Y + results.CanvasPosition.Y
      local itemBottom = itemTop + selectedButton.AbsoluteSize.Y
      local viewTop = results.CanvasPosition.Y
      local viewBottom = viewTop + results.AbsoluteWindowSize.Y

      if itemTop < viewTop then
        results.CanvasPosition = Vector2.new(0, math.max(0, itemTop))
      elseif itemBottom > viewBottom then
        results.CanvasPosition = Vector2.new(0, math.max(0, itemBottom - results.AbsoluteWindowSize.Y))
      end
    end
  end

  local function clearResults()
    itemMaid:Cleanup()
    table.clear(visibleCommands)
    table.clear(resultButtons)
  end

  local function rebuild()
    clearResults()

    local query = string.lower(input.Text or "")
    local order = 1

    for _, commandName in ipairs(X64UI.CommandOrder) do
      local command = X64UI.Commands[commandName]

      if command then
        local searchable = string.lower(
          command.Name .. " " ..
          command.Description .. " " ..
          table.concat(command.Keywords, " ")
        )

        if query == "" or string.find(searchable, query, 1, true) then
          table.insert(visibleCommands, command)

          local text = command.Name
          if command.Description ~= "" then
            text = text .. " — " .. command.Description
          end

          local item = Create.create("TextButton", {
            Parent = results,
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundColor3 = Theme.Button,
            BorderColor3 = Theme.Border,
            Text = "  " .. text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Theme.Font,
            TextSize = Theme.TextSize,
            TextColor3 = Theme.Text,
            AutoButtonColor = false,
            LayoutOrder = order,
            ZIndex = 5002,
          })

          itemMaid:Give(item)

          local index = #visibleCommands

          itemMaid:Give(item.MouseEnter:Connect(function()
            selectedIndex = index
            updateSelection()
          end))

          itemMaid:Give(item.MouseLeave:Connect(function()
            updateSelection()
          end))

          itemMaid:Give(item.MouseButton1Click:Connect(function()
            X64UI:ExecuteCommand(command.Name)
            self:CloseCommandPalette()
          end))

          table.insert(resultButtons, item)
          order += 1
        end
      end
    end

    results.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
    selectedIndex = math.clamp(selectedIndex, 1, math.max(1, #resultButtons))
    updateSelection()
  end

  local function moveSelection(delta)
    if #resultButtons == 0 then return end

    selectedIndex += delta
    selectedIndex = math.clamp(selectedIndex, 1, #resultButtons)
    updateSelection()
  end

  local function executeSelected()
    local command = visibleCommands[selectedIndex]

    if command then
      X64UI:ExecuteCommand(command.Name)
      self:CloseCommandPalette()
    end
  end

  self:Track(input:GetPropertyChangedSignal("Text"):Connect(rebuild))

  self:Track(UserInputService.InputBegan:Connect(function(inputObject)
    if not palette.Visible then return end
    if inputObject.UserInputType ~= Enum.UserInputType.Keyboard then return end

    if inputObject.KeyCode == Enum.KeyCode.Escape then
      self:CloseCommandPalette()
    elseif inputObject.KeyCode == Enum.KeyCode.Up then
      moveSelection(-1)
    elseif inputObject.KeyCode == Enum.KeyCode.Down then
      moveSelection(1)
    elseif inputObject.KeyCode == Enum.KeyCode.Return then
      executeSelected()
    end
  end))

  self.CommandPalette = palette
  self.CommandInput = input
  self.CommandResults = results

  function self:OpenCommandPalette()
    palette.Visible = true
    input.Text = ""
    selectedIndex = 1
    rebuild()
    input:CaptureFocus()
    self:Focus()
  end

  function self:CloseCommandPalette()
    palette.Visible = false
    input:ReleaseFocus()
  end

  function self:ToggleCommandPalette()
    if palette.Visible then
      self:CloseCommandPalette()
    else
      self:OpenCommandPalette()
    end
  end

  return palette
end

-- ==================== CONTROLS ====================

function Tab:AddGroupbox(side, title)
  local isLeft = side == "Left"
  local parent = isLeft and self.LeftPane or self.RightPane

  local order
  if isLeft then
    self.NextLeftOrder += 1
    order = self.NextLeftOrder
  else
    self.NextRightOrder += 1
    order = self.NextRightOrder
  end

  local group = setmetatable({
    Window = self.Window,
    Tab = self,
    NextOrder = 0,
  }, Groupbox)

  group.Frame = Create.create("Frame", {
    Parent = parent,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    LayoutOrder = order,
  })

  Create.create("UIListLayout", {
    Parent = group.Frame,
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  Create.create("TextLabel", {
    Parent = group.Frame,
    LayoutOrder = 0,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
    Text = " " .. tostring(title or "Group"),
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Warning,
  })

  group.Content = Create.create("Frame", {
    Parent = group.Frame,
    LayoutOrder = 1,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
  })

  group.Layout = Create.create("UIListLayout", {
    Parent = group.Content,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  Create.create("UIPadding", {
    Parent = group.Content,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  return group
end

function Tab:AddLeftGroupbox(title)
  return self:AddGroupbox("Left", title)
end

function Tab:AddRightGroupbox(title)
  return self:AddGroupbox("Right", title)
end

function Groupbox:AddDependencyBox()
  local holder = Create.create("Frame", {
    Parent = self.Content,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    LayoutOrder = self.NextOrder,
    Visible = true,
  })
  self.NextOrder += 1

  Create.create("UIListLayout", {
    Parent = holder,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  local proxy = {
    Content = holder,
    NextOrder = 1,
    Window = self.Window,
    Title = self.Title,
  }
  setmetatable(proxy, { __index = Groupbox })

  local box = {
    Type = "DependencyBox",
    Group = self,
    Window = self.Window,
    Visible = true,
    Holder = holder,
  }

  function box:SetupDependencies(deps)
    local function evaluate()
      local show = true
      if type(deps) == "table" then
        for control, required in pairs(deps) do
          if type(control) == "table" and control.GetValue then
            if control:GetValue() ~= required then
              show = false
              break
            end
          end
        end
      end
      holder.Visible = show
      box.Visible = show
    end
    if type(deps) == "table" then
      for control, _ in pairs(deps) do
        if type(control) == "table" and control.Changed and control.Changed.Connect then
          self.Window:Track(control.Changed:Connect(evaluate))
        end
      end
    end
    evaluate()
  end

  for _, method in ipairs({
    "AddToggle", "AddSlider", "AddDropdown", "AddLabel", "AddButton",
    "AddInput", "AddKeyPicker", "AddColorPicker", "AddNumericInput",
    "AddListBox", "AddTree", "AddTable", "AddDivider",
  }) do
    box[method] = function(_, ...)
      return proxy[method](proxy, ...)
    end
  end

  return box
end


function Tab:GetDefaultGroupbox()
  if not self.DefaultGroupbox then
    self.DefaultGroupbox = self:AddLeftGroupbox("General")
  end

  return self.DefaultGroupbox
end


function Groupbox:Clear()
  for _, child in ipairs(self.Content:GetChildren()) do
    if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
      child:Destroy()
    end
  end
  self.NextOrder = 1
end

function Tab:Destroy()
  if self.Destroyed then return end
  self.Destroyed = true
  if self.Page then pcall(function() self.Page:Destroy() end) end
  if self.Frame then pcall(function() self.Frame:Destroy() end) end
  if self.Button then pcall(function() self.Button:Destroy() end) end
end

local function createControlFrame(group, height, automatic, horizontal)
  local row = Create.create("Frame", {
    Parent = group.Content,
    Size = UDim2.new(1, 0, 0, height or 24),
    BackgroundTransparency = 1,
    LayoutOrder = group.NextOrder,
  })

  group.NextOrder += 1

  if automatic then
    row.AutomaticSize = Enum.AutomaticSize.Y
  end

  local layout = Create.create("UIListLayout", {
    Parent = row,
    Padding = UDim.new(0, 3),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  if horizontal then
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
  else
    layout.FillDirection = Enum.FillDirection.Vertical
  end

  return row, layout
end

function Groupbox:AddLabel(text, wrap)
  local row = createControlFrame(self, nil, true, false)

  local label = Create.create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Text = text or "",
    TextWrapped = wrap and true or false,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local obj = BaseControl.new("Label", row, self.Window, nil)
  obj.Label = label
  obj._Groupbox = self
  function obj:SetText(newText) label.Text = tostring(newText) end
  function obj:AddKeyPicker(n, o)
    return self._Groupbox:AddKeyPicker(n, o)
  end
  function obj:AddColorPicker(n, o)
    return self._Groupbox:AddColorPicker(n, o)
  end
  return obj
end

function Groupbox:AddButton(opts)
  opts = opts or {}

  local row = createControlFrame(self, 26, false, false)

  local button = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Theme.Button,
    BorderColor3 = Theme.Border,
    Text = opts.Text or "Button",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local obj = BaseControl.new("Button", row, self.Window, nil)
  obj.Button = button

  function obj:SetText(newText) button.Text = tostring(newText) end

  self.Window:Track(button.MouseEnter:Connect(function()
    button.BackgroundColor3 = Theme.ButtonHover
  end))

  self.Window:Track(button.MouseLeave:Connect(function()
    button.BackgroundColor3 = Theme.Button
  end))

  self.Window:Track(button.MouseButton1Click:Connect(function()
    if not obj.Disabled and opts.Callback then
      local ok, err = xpcall(opts.Callback, traceback)
      if not ok then
        Log.warn("Button callback failed:\n" .. tostring(err))
      end
    end

    self.Window:Log("Button: " .. tostring(opts.Text or "Button"))
  end))

  return obj
end

function Groupbox:AddToggle(name, opts)
  opts = opts or {}

  local row = createControlFrame(self, 22, false, true)
  local state = State.new(opts.Default == true)

  local check = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.fromOffset(18, 18),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = "",
    Font = Theme.Font,
    TextSize = 13,
    TextColor3 = Theme.AccentText,
    AutoButtonColor = false,
  })

  local label = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, -24, 1, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Toggle",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    AutoButtonColor = false,
  })

  local obj = BaseControl.new("Toggle", row, self.Window, name)
  obj.Value = state:Get()
  obj.Button = check
  obj.Changed = Signal.new()

  local internalChange = false

  local function render(value)
    obj.Value = value
    check.Text = value and Glyphs.Check or ""
    check.BackgroundColor3 = value and Theme.Accent or Theme.PanelAlt
  end

  local function set(value, silent, withHistory)
    value = value == true

    local previous = state:Get()
    if previous == value then
      return
    end

    state:Set(value, true)
    render(value)

    if not silent then
      obj.Changed:Fire(value, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "Toggle", value)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(value, previous)
        end, traceback)

        if not ok then
          Log.warn("Toggle callback failed:\n" .. tostring(err))
        end
      end
    end

    if withHistory and not internalChange then
      self.Window.History:Push(
        "Toggle " .. tostring(opts.Text or name),
        function()
          internalChange = true
          set(previous, false, false)
          internalChange = false
        end,
        function()
          internalChange = true
          set(value, false, false)
          internalChange = false
        end
      )
    end
  end

  local function toggle()
    set(not state:Get(), false, true)
  end

  self.Window:Track(check.MouseButton1Click:Connect(toggle))
  self.Window:Track(label.MouseButton1Click:Connect(toggle))

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
  end

  function obj:GetValue()
    return state:Get()
  end

  self.Window.Maid:Give(obj)
  render(state:Get())

  if name then
    self.Window.Registry:Register(name, obj, "Toggle")
  end

  obj._Groupbox = self
  function obj:AddColorPicker(n, o)
    return self._Groupbox:AddColorPicker(n, o)
  end
  function obj:AddKeyPicker(n, o)
    return self._Groupbox:AddKeyPicker(n, o)
  end

  return obj
end

function Groupbox:AddSlider(name, opts)
  opts = opts or {}

  local min = tonumber(opts.Min) or 0
  local max = tonumber(opts.Max) or 100
  local value = tonumber(opts.Default) or min
  local digits = tonumber(opts.Rounding) or 0
  local step = 1 / (10 ^ math.clamp(digits, 0, 6))

  local row = createControlFrame(self, nil, true, false)

  local header = Create.create("Frame", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
  })

  -- Label left, value right (no UIListLayout — scale-1 + list overlaps value into text)
  Create.create("TextLabel", {
    Parent = header,
    Size = UDim2.new(1, -56, 1, 0),
    Position = UDim2.fromOffset(0, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Slider",
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    TextTruncate = Enum.TextTruncate.AtEnd,
  })

  local valueLabel = Create.create("TextBox", {
    Parent = header,
    Size = UDim2.fromOffset(52, 16),
    Position = UDim2.new(1, -52, 0, 0),
    BackgroundTransparency = 1,
    Text = "",
    TextXAlignment = Enum.TextXAlignment.Right,
    TextYAlignment = Enum.TextYAlignment.Center,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.AccentText,
    ClearTextOnFocus = false,
    PlaceholderText = "",
  })

  local bar = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = "",
    AutoButtonColor = false,
  })

  local fill = Create.create("Frame", {
    Parent = bar,
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
  })

  local obj = BaseControl.new("Slider", row, self.Window, name)
  obj.Value = value
  obj.Min = min
  obj.Max = max
  obj.Changed = Signal.new()

  local suffix = opts.Suffix or ""
  local function format(v)
    local s
    if step < 1 then
      s = string.format("%." .. digits .. "f", v)
    else
      s = tostring(math.floor(v + 0.5))
    end
    return s .. suffix
  end

  local function round(v)
    return math.floor((v / step) + 0.5) * step
  end

  local function set(v, silent)
    v = math.clamp(round(v), min, max)

    local previous = obj.Value
    value = v
    obj.Value = v
    valueLabel.Text = format(v)

    local scale = 0
    if max ~= min then
      scale = (v - min) / (max - min)
    end

    fill.Size = UDim2.fromScale(scale, 1)

    if not silent and previous ~= v then
      obj.Changed:Fire(v, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "Slider", v)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(v, previous)
        end, traceback)

        if not ok then
          Log.warn("Slider callback failed:\n" .. tostring(err))
        end
      end
    end
  end

  local dragging = false
  local dragStartValue = value

  local function updateFromX(x)
    if not bar.Parent then return end

    local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
    set(min + ((max - min) * rel), false)
  end

  self.Window:Track(bar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      if not obj:CanInteract() then return end
      dragging = true
      dragStartValue = obj.Value
      updateFromX(getMousePos().X)
    end
  end))

  self.Window:Track(UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
      updateFromX(getMousePos().X)
    end
  end))

  self.Window:Track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
      dragging = false

      local newValue = obj.Value
      if newValue ~= dragStartValue then
        local oldValue = dragStartValue

        self.Window.History:Push(
          "Slider " .. tostring(opts.Text or name),
          function()
            set(oldValue, false)
          end,
          function()
            set(newValue, false)
          end
        )
      end
    end
  end))

  
  self.Window:Track(valueLabel.FocusLost:Connect(function(enter)
    local typed = tonumber(valueLabel.Text:match("[%d%.%-]+"))
    if typed then
      set(typed, false, true)
    else
      valueLabel.Text = format(obj.Value)
    end
  end))

function obj:SetValue(v, silent)
    set(v, silent == true)
  end

  function obj:GetValue()
    return obj.Value
  end

  self.Window.Maid:Give(obj)
  set(value, true)

  if name then
    self.Window.Registry:Register(name, obj, "Option")
  end

  return obj
end

function Groupbox:AddDropdown(name, opts)
  opts = opts or {}

  local values = opts.Values or {}
  local selected = opts.Default or values[1]

  if typeof(selected) == "number" then
    selected = values[selected]
  end

  if not table.find(values, selected) and not opts.Multi then
    selected = values[1]
  end

  local row = createControlFrame(self, nil, true, false)

  Create.create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Dropdown",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local function formatDropdownLabel(val)
    if opts.Multi then
      local n = (type(val) == "table" and #val) or 0
      return Glyphs.ArrowDown .. " " .. tostring(n) .. " selected"
    end
    return Glyphs.ArrowDown .. " " .. tostring(val)
  end

  local button = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = formatDropdownLabel(opts.Multi and (type(selected) == "table" and selected or {}) or selected),
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local list = Create.create("ScrollingFrame", {
    Parent = self.Window.Gui,
    Visible = false,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
    ZIndex = 2000,
  })

  local searchBox = Create.create("TextBox", {
    Parent = list,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    PlaceholderText = "Search",
    Text = "",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    ZIndex = 2001,
  })

  local listLayout = Create.create("UIListLayout", {
    Parent = list,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 1),
  })

  local obj = BaseControl.new("Dropdown", row, self.Window, name)
  if opts.Multi then
    if type(opts.Default) == "table" then
      obj.Value = table.clone(opts.Default)
    else
      obj.Value = {}
    end
  else
    obj.Value = selected
  end
  obj.Values = values
  obj.Button = button
  obj.List = list
  obj.OpenedAt = 0
  obj.Changed = Signal.new()

  local internalChange = false

  local function getListHeight()
    return math.min((#values * 19) + 22, 220)
  end

  function obj:RefreshPosition()
    if not button.Parent then return end

    local pos = button.AbsolutePosition
    local size = button.AbsoluteSize
    local height = getListHeight()
    local viewport = getViewportSize(self.Window and self.Window.Gui)
    local spaceBelow = viewport.Y - (pos.Y + size.Y)
    local openUp = spaceBelow < height + 8 and pos.Y > height + 8

    if openUp then
      list.Position = UDim2.fromOffset(pos.X, pos.Y - height - 2)
    else
      list.Position = UDim2.fromOffset(pos.X, pos.Y + size.Y + 2)
    end
    list.Size = UDim2.fromOffset(size.X, height)
    list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 2)
  end

  function obj:Open()
    obj:RefreshPosition()
    list.Visible = true
    obj.OpenedAt = os.clock()
    self.Window:RegisterPopup({
      Close = function()
        obj:Close()
      end,
    })
  end

  function obj:Close()
    list.Visible = false
  end

  function obj:Toggle()
    if list.Visible then
      obj:Close()
    else
      obj:Open()
    end
  end

  local function set(value, silent, withHistory)
    local previous = obj.Value
    if not opts.Multi and not table.find(values, value) then return end
    
    obj.Value = value
    button.Text = formatDropdownLabel(value)

    if not silent then
      obj.Changed:Fire(value, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "Dropdown", value)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(value, previous)
        end, traceback)

        if not ok then
          Log.warn("Dropdown callback failed:\n" .. tostring(err))
        end
      end
    end

    if withHistory and not internalChange then
      self.Window.History:Push(
        "Dropdown " .. tostring(opts.Text or name),
        function()
          internalChange = true
          set(previous, false, false)
          internalChange = false
        end,
        function()
          internalChange = true
          set(value, false, false)
          internalChange = false
        end
      )
    end
  end

  self.Window:Track(button.MouseButton1Click:Connect(function()
    if not obj:CanInteract() then return end
    obj:Toggle()
  end))

  local itemMaid = Maid.new()
  self.Window.Maid:Give(itemMaid)

  local function buildItems()
    itemMaid:Cleanup()
    for _, child in ipairs(list:GetChildren()) do
      if child:IsA("TextButton") and child ~= searchBox then child:Destroy() end
    end

    local query = string.lower(searchBox.Text or "")
    local order = 1

    -- windowed render for large lists (virtualization)
    local filtered = {}
    for i, value in ipairs(values) do
      if query == "" or string.find(string.lower(tostring(value)), query, 1, true) then
        filtered[#filtered + 1] = value
      end
    end

    local maxVisible = 60
    local startIndex = 1
    local endIndex = #filtered
    if #filtered > maxVisible then
      -- show first maxVisible matches (search already narrows; full scroll virtualization is heavier)
      endIndex = maxVisible
      if not list:FindFirstChild("X64VirtHint") then
        local hint = Create.create("TextLabel", {
          Parent = list,
          Name = "X64VirtHint",
          LayoutOrder = 99999,
          Size = UDim2.new(1, 0, 0, 16),
          BackgroundTransparency = 1,
          Text = string.format("  showing %d of %d — type to filter", maxVisible, #filtered),
          Font = Theme.Font,
          TextSize = Theme.TextSize - 1,
          TextColor3 = Theme.Dim,
          TextXAlignment = Enum.TextXAlignment.Left,
          ZIndex = 2001,
        })
        itemMaid:Give(hint)
      end
    end

    for i = startIndex, endIndex do
      local value = filtered[i]
      if value ~= nil then
        local isSelected = false
        if opts.Multi then
          isSelected = type(obj.Value) == "table" and table.find(obj.Value, value) ~= nil
        else
          isSelected = obj.Value == value
        end

        local item = Create.create("TextButton", {
          Parent = list,
          LayoutOrder = i,
          Size = UDim2.new(1, 0, 0, 18),
          BackgroundColor3 = Theme.Selection,
          BackgroundTransparency = isSelected and 0 or 1,
          Text = (isSelected and "> " or "  ") .. tostring(value),
          TextXAlignment = Enum.TextXAlignment.Left,
          Font = Theme.Font,
          TextSize = Theme.TextSize,
          TextColor3 = Theme.Text,
          ZIndex = 2001,
        })

        itemMaid:Give(item.MouseEnter:Connect(function()
          item.BackgroundColor3 = Theme.Selection
          item.BackgroundTransparency = 0
        end))

        itemMaid:Give(item.MouseLeave:Connect(function()
          local still = false
          if opts.Multi then
            still = type(obj.Value) == "table" and table.find(obj.Value, value) ~= nil
          else
            still = obj.Value == value
          end
          item.BackgroundTransparency = still and 0 or 1
          item.BackgroundColor3 = Theme.Selection
        end))

        itemMaid:Give(item.MouseButton1Click:Connect(function()
          if opts.Multi then
            local current = table.clone(obj.Value)
            local idx = table.find(current, value)
            if idx then table.remove(current, idx) else table.insert(current, value) end
            set(current, false, true)
            buildItems()
          else
            set(value, false, true)
            obj:Close()
          end
        end))
        order += 1
      end
    end
    list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 2)
  end

  self.Window:Track(searchBox:GetPropertyChangedSignal("Text"):Connect(buildItems))
  buildItems()

  function obj:SetValues(newValues)
    values = newValues or {}
    buildItems()
  end

  function obj:Refresh()
    buildItems()
  end

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
  end

  function obj:GetValue()
    return obj.Value
  end

  function obj:Destroy()
    obj.Changed:Destroy()
    if self.List then pcall(function() self.List:Destroy() end) end
    BaseControl.Destroy(self)
  end

  self.Window.Maid:Give(obj)
  if not opts.Multi then set(selected, true) end
  table.insert(self.Window.Dropdowns, obj)

  if name then
    self.Window.Registry:Register(name, obj, "Option")
  end

  return obj
end

function Groupbox:AddInput(name, opts)
  opts = opts or {}

  local row = createControlFrame(self, nil, true, false)

  Create.create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Input",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local box = Create.create("TextBox", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    PlaceholderText = opts.Placeholder or "",
    Text = opts.Default or "",
    ClearTextOnFocus = false,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
  })

  local obj = BaseControl.new("Input", row, self.Window, name)
  obj.Value = tostring(opts.Default or "")
  obj.TextBox = box
  obj.Changed = Signal.new()

  local internalChange = false
  local focusedValue = obj.Value

  local function set(value, silent, withHistory)
    value = tostring(value)

    local previous = obj.Value
    if previous == value then return end

    obj.Value = value
    box.Text = value

    if not box:IsFocused() then
      focusedValue = value
    end

    if not silent then
      obj.Changed:Fire(value, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "Input", value)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(value, previous)
        end, traceback)

        if not ok then
          Log.warn("Input callback failed:\n" .. tostring(err))
        end
      end
    end

    if withHistory and not internalChange then
      self.Window.History:Push(
        "Input " .. tostring(opts.Text or name),
        function()
          internalChange = true
          set(previous, false, false)
          internalChange = false
        end,
        function()
          internalChange = true
          set(value, false, false)
          internalChange = false
        end
      )
    end
  end

  self.Window:Track(box.Focused:Connect(function()
    focusedValue = box.Text
  end))

  self.Window:Track(box.FocusLost:Connect(function(_)
    local newText = box.Text

    if newText ~= focusedValue then
      set(newText, false, true)
      focusedValue = newText
    else
      set(newText, true, false)
    end
  end))

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
    focusedValue = obj.Value
  end

  function obj:GetValue()
    return obj.Value
  end

  self.Window.Maid:Give(obj)

  if name then
    self.Window.Registry:Register(name, obj, "Option")
  end

  return obj
end

function Groupbox:AddKeyPicker(name, opts)
  opts = opts or {}
  local mode = opts.Mode or "Toggle" -- Toggle | Hold | Press | Always
  local noUI = opts.NoUI == true

  local row
  local button
  if not noUI then
    row = createControlFrame(self, 22, false, true)

    Create.create("TextLabel", {
      Parent = row,
      Size = UDim2.new(1, -90, 1, 0),
      BackgroundTransparency = 1,
      Text = opts.Text or name or "Keybind",
      TextXAlignment = Enum.TextXAlignment.Left,
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
    })

    button = Create.create("TextButton", {
      Parent = row,
      Size = UDim2.fromOffset(90, 18),
      BackgroundColor3 = Theme.PanelAlt,
      BorderColor3 = Theme.Border,
      Text = tostring(opts.Default or "None"),
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
    })
  end

  local obj = BaseControl.new("KeyPicker", row, self.Window, name)
  obj.Value = tostring(opts.Default or "None")
  obj.Mode = mode
  obj.Button = button
  obj.Changed = Signal.new()
  obj.Clicked = Signal.new()
  obj._State = false
  obj._Holding = false

  local internalChange = false

  local function set(value, silent, withHistory)
    value = tostring(value)

    local previous = obj.Value
    if previous == value then return end

    obj.Value = value
    if button then button.Text = value end

    if not silent then
      obj.Changed:Fire(value, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "KeyPicker", value)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(value, previous)
        end, traceback)

        if not ok then
          Log.warn("KeyPicker callback failed:\n" .. tostring(err))
        end
      end
    end

    if withHistory and not internalChange then
      self.Window.History:Push(
        "Keybind " .. tostring(opts.Text or name),
        function()
          internalChange = true
          set(previous, false, false)
          internalChange = false
        end,
        function()
          internalChange = true
          set(value, false, false)
          internalChange = false
        end
      )
    end
  end

  local function fireClick()
    obj.Clicked:Fire(obj._State)
    if opts.OnClick then
      local ok, err = xpcall(function()
        opts.OnClick(obj._State)
      end, traceback)
      if not ok then Log.warn("KeyPicker OnClick failed:\n" .. tostring(err)) end
    end
  end

  local function onKeyBegan(input, gameProcessed)
    if obj.Disabled or obj.Destroyed then return end
    if gameProcessed and mode ~= "Always" then return end
    if UserInputService:GetFocusedTextBox() then return end
    if self.Window.PickingKey then return end
    if obj.Value == "None" or obj.Value == "" then return end
    if not InputMatchesBind(input, obj.Value) then return end

    if mode == "Toggle" then
      obj._State = not obj._State
      fireClick()
    elseif mode == "Hold" then
      obj._Holding = true
      obj._State = true
      fireClick()
    elseif mode == "Press" then
      obj._State = true
      fireClick()
      obj._State = false
    elseif mode == "Always" then
      obj._State = true
    end
  end

  local function onKeyEnded(input)
    if mode ~= "Hold" then return end
    if not obj._Holding then return end
    if not InputMatchesBind(input, obj.Value) then return end
    obj._Holding = false
    obj._State = false
    fireClick()
  end

  if InputRouter then
    InputRouter:On("Began", onKeyBegan)
    InputRouter:On("Ended", onKeyEnded)
  else
    self.Window:Track(UserInputService.InputBegan:Connect(onKeyBegan))
    self.Window:Track(UserInputService.InputEnded:Connect(onKeyEnded))
  end

  if button then
    self.Window:Track(button.MouseButton1Click:Connect(function()
      if not obj:CanInteract() then return end
      button.Text = "..."
      self.Window.PickingKey = true

      -- defer so the MouseButton1 that opened the picker is not captured as the bind
      task.defer(function()
        if obj.Destroyed or not self.Window.PickingKey then return end

        InputManager:Capture(function(input)
          local name = InputToBindName(input)
          if not name then
            return -- ignore movement / unknown
          end

          if name == "Escape" then
            set("None", false, true)
          else
            set(name, false, true)
          end

          InputManager:Cancel()
          self.Window.PickingKey = false
          if button then
            button.Text = obj.Value
          end
        end)
      end)
    end))
  end

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
  end

  function obj:GetValue()
    return obj.Value
  end

  function obj:GetState()
    if mode == "Always" then return true end
    return obj._State == true
  end

  function obj:SetMode(newMode)
    mode = newMode or mode
    obj.Mode = mode
    obj._State = false
    obj._Holding = false
  end

  function obj:OnClick(fn)
    return obj.Clicked:Connect(fn)
  end

  self.Window.Maid:Give(obj)
  set(obj.Value, true)

  if name then
    self.Window.Registry:Register(name, obj, "Option")
  end

  -- chaining: allow :AddColorPicker on same row later via group helpers
  return obj
end

function Groupbox:AddDivider()
  local row = createControlFrame(self, 8, false, false)
  local div = Create.create("Frame", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3 = Theme.Border,
    BorderSizePixel = 0,
  })
  local obj = BaseControl.new("Divider", row, self.Window, nil)
  return obj
end

function Groupbox:AddColorPicker(name, opts)
  opts = opts or {}
  local default = opts.Default or Color3.fromRGB(255, 255, 255)
  local hue, sat, vib = default:ToHSV()

  local row = createControlFrame(self, 22, false, true)
  Create.create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, -50, 1, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Color",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local preview = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.fromOffset(40, 18),
    BackgroundColor3 = default,
    BorderColor3 = Theme.Border,
    Text = "",
    AutoButtonColor = false,
  })

  -- Obsidian-style picker panel
  local picker = Create.create("Frame", {
    Parent = self.Window.Gui,
    Visible = false,
    Size = UDim2.fromOffset(230, 230),
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    ZIndex = 2500,
  })

  local satMap = Create.create("ImageButton", {
    Parent = picker,
    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.fromOffset(180, 180),
    BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
    Image = "rbxassetid://4155801252", -- Obsidian SaturationMap
    BorderSizePixel = 0,
    AutoButtonColor = false,
    ZIndex = 2501,
  })

  local satCursor = Create.create("Frame", {
    Parent = satMap,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(6, 6),
    Position = UDim2.fromScale(sat, 1 - vib),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 2503,
  })
  Create.create("UICorner", { Parent = satCursor, CornerRadius = UDim.new(1, 0) })
  Create.create("UIStroke", { Parent = satCursor, Color = Color3.new(0, 0, 0), Thickness = 1 })

  local hueSeq = {}
  for i = 0, 10 do
    local t = i / 10
    table.insert(hueSeq, ColorSequenceKeypoint.new(t, Color3.fromHSV(t, 1, 1)))
  end

  local hueBar = Create.create("TextButton", {
    Parent = picker,
    Position = UDim2.fromOffset(196, 8),
    Size = UDim2.fromOffset(26, 180),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 2501,
  })
  Create.create("UIGradient", {
    Parent = hueBar,
    Rotation = 90,
    Color = ColorSequence.new(hueSeq),
  })

  local hueCursor = Create.create("Frame", {
    Parent = hueBar,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.new(1, 2, 0, 2),
    Position = UDim2.fromScale(0.5, hue),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 2503,
  })
  Create.create("UIStroke", { Parent = hueCursor, Color = Color3.new(0, 0, 0), Thickness = 1 })

  local hexBox = Create.create("TextBox", {
    Parent = picker,
    Position = UDim2.fromOffset(8, 196),
    Size = UDim2.fromOffset(214, 22),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = "#" .. default:ToHex(),
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    ClearTextOnFocus = false,
    ZIndex = 2501,
  })

  local obj = BaseControl.new("ColorPicker", row, self.Window, name)
  obj.Value = default
  obj.Hue, obj.Sat, obj.Vib = hue, sat, vib
  obj.Changed = Signal.new()

  local function display(silent)
    obj.Value = Color3.fromHSV(obj.Hue, obj.Sat, obj.Vib)
    preview.BackgroundColor3 = obj.Value
    satMap.BackgroundColor3 = Color3.fromHSV(obj.Hue, 1, 1)
    satCursor.Position = UDim2.fromScale(obj.Sat, 1 - obj.Vib)
    hueCursor.Position = UDim2.fromScale(0.5, obj.Hue)
    hexBox.Text = "#" .. obj.Value:ToHex()
    if not silent then
      local prev = obj.Value
      obj.Changed:Fire(obj.Value, prev)
      if opts.Callback then
        pcall(opts.Callback, obj.Value, prev)
      end
    end
  end

  local function openPicker()
    if obj.Disabled or obj.ReadOnly then return end
    local pos = preview.AbsolutePosition
    picker.Position = UDim2.fromOffset(pos.X, pos.Y + 22)
    picker.Visible = true
  end

  local function closePicker()
    picker.Visible = false
  end

  self.Window:Track(preview.MouseButton1Click:Connect(function()
    if picker.Visible then closePicker() else openPicker() end
  end))

  local function bindDrag(gui, updateFn)
    self.Window:Track(gui.InputBegan:Connect(function(input)
      if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
      updateFn(getMousePos())
      local conn, endConn
      conn = UserInputService.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement then
          updateFn(inp.Position)
        end
      end)
      endConn = UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
          conn:Disconnect()
          endConn:Disconnect()
        end
      end)
    end))
  end

  bindDrag(satMap, function(pos)
    local rel = satMap.AbsolutePosition
    local size = satMap.AbsoluteSize
    obj.Sat = math.clamp((pos.X - rel.X) / math.max(size.X, 1), 0, 1)
    obj.Vib = 1 - math.clamp((pos.Y - rel.Y) / math.max(size.Y, 1), 0, 1)
    display(false)
  end)

  bindDrag(hueBar, function(pos)
    local rel = hueBar.AbsolutePosition
    local size = hueBar.AbsoluteSize
    obj.Hue = math.clamp((pos.Y - rel.Y) / math.max(size.Y, 1), 0, 1)
    display(false)
  end)

  self.Window:Track(hexBox.FocusLost:Connect(function()
    local text = hexBox.Text:gsub("#", "")
    local ok, color = pcall(function()
      return Color3.fromHex(text)
    end)
    if ok and typeof(color) == "Color3" then
      obj.Hue, obj.Sat, obj.Vib = color:ToHSV()
      display(false)
    else
      hexBox.Text = "#" .. obj.Value:ToHex()
    end
  end))

  self.Window:Track(UserInputService.InputBegan:Connect(function(input)
    if not picker.Visible then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      if not mouseOverGui(picker) and not mouseOverGui(preview) then
        closePicker()
      end
    end
  end))

  function obj:SetValue(c, silent)
    if typeof(c) ~= "Color3" then return end
    obj.Hue, obj.Sat, obj.Vib = c:ToHSV()
    display(silent)
  end

  function obj:GetValue()
    return obj.Value
  end

  function obj:Destroy()
    if picker and picker.Parent then pcall(function() picker:Destroy() end) end
    BaseControl.Destroy(self)
  end

  if opts.Tooltip then
    self.Window:Track(preview.MouseEnter:Connect(function() ShowTooltip(opts.Tooltip, getMousePos()) end))
    self.Window:Track(preview.MouseLeave:Connect(HideTooltip))
  end

  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  display(true)
  return obj
end

function Groupbox:AddNumericInput(name, opts)
  opts = opts or {}
  local minV = tonumber(opts.Min)
  local maxV = tonumber(opts.Max)
  local default = tonumber(opts.Default) or 0
  local row = createControlFrame(self, nil, true, false)
  Create.create("TextLabel", {
    Parent = row, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    Text = opts.Text or name or "Number", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
  })
  local box = Create.create("TextBox", {
    Parent = row, Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border, Text = tostring(default), ClearTextOnFocus = false,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
  })
  local obj = BaseControl.new("NumericInput", row, self.Window, name)
  obj.Value = default
  obj.Changed = Signal.new()
  local function set(v, silent)
    v = tonumber(v)
    if not v then box.Text = tostring(obj.Value) return end
    if minV then v = math.max(minV, v) end
    if maxV then v = math.min(maxV, v) end
    local prev = obj.Value
    if prev == v then box.Text = tostring(v) return end
    obj.Value = v
    box.Text = tostring(v)
    if not silent then
      obj.Changed:Fire(v, prev)
      if opts.Callback then pcall(opts.Callback, v, prev) end
    end
  end
  self.Window:Track(box.FocusLost:Connect(function() set(box.Text, false) end))
  function obj:SetValue(v, silent) set(v, silent) end
  function obj:GetValue() return obj.Value end
  function obj:SetDisabled(v)
    BaseControl.SetDisabled(self, v)
    box.TextEditable = not v
  end
  function obj:SetReadOnly(v)
    BaseControl.SetReadOnly(self, v)
    box.TextEditable = not v
  end
  if opts.Tooltip then
    self.Window:Track(box.MouseEnter:Connect(function() ShowTooltip(opts.Tooltip, getMousePos()) end))
    self.Window:Track(box.MouseLeave:Connect(HideTooltip))
  end
  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  return obj
end

function Groupbox:AddListBox(name, opts)
  opts = opts or {}
  local values = opts.Values or {}
  local multi = opts.Multi == true
  local height = opts.Height or 100
  local row = createControlFrame(self, nil, true, false)
  Create.create("TextLabel", {
    Parent = row, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    Text = opts.Text or name or "List", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
  })
  local scroll = Create.create("ScrollingFrame", {
    Parent = row, Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border, ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })
  local layout = Create.create("UIListLayout", { Parent = scroll, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) })
  local obj = BaseControl.new("ListBox", row, self.Window, name)
  obj.Value = multi and (type(opts.Default) == "table" and opts.Default or {}) or opts.Default
  obj.Values = values
  obj.Multi = multi
  obj.Changed = Signal.new()
  local function rebuild()
    for _, c in ipairs(scroll:GetChildren()) do
      if c:IsA("TextButton") then c:Destroy() end
    end
    for i, val in ipairs(values) do
      local selected = multi and table.find(obj.Value, val) or (obj.Value == val)
      local item = Create.create("TextButton", {
        Parent = scroll, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = i,
        BackgroundTransparency = selected and 0 or 1, BackgroundColor3 = Theme.Selection,
        Text = (selected and Glyphs.Check .. " " or "  ") .. tostring(val),
        TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Font, TextSize = Theme.TextSize,
        TextColor3 = Theme.Text, AutoButtonColor = false,
      })
      self.Window:Track(item.MouseButton1Click:Connect(function()
        if obj.Disabled or obj.ReadOnly then return end
        if multi then
          local prev = table.clone(obj.Value)
          local idx = table.find(obj.Value, val)
          if idx then table.remove(obj.Value, idx) else table.insert(obj.Value, val) end
          obj.Changed:Fire(obj.Value, prev)
          if opts.Callback then pcall(opts.Callback, obj.Value, prev) end
        else
          local prev = obj.Value
          obj.Value = val
          obj.Changed:Fire(val, prev)
          if opts.Callback then pcall(opts.Callback, val, prev) end
        end
        rebuild()
      end))
    end
    scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
  end
  rebuild()
  function obj:SetValues(newVals)
    values = newVals or {}
    obj.Values = values
    rebuild()
  end
  function obj:SetValue(v, silent)
    obj.Value = v
    rebuild()
    if not silent then obj.Changed:Fire(v) end
  end
  function obj:GetValue() return obj.Value end
  function obj:Destroy() BaseControl.Destroy(self) end
  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  return obj
end

function Groupbox:AddTree(name, opts)
  opts = opts or {}
  local nodes = opts.Nodes or {}
  local height = opts.Height or 140
  local row = createControlFrame(self, nil, true, false)
  Create.create("TextLabel", {
    Parent = row, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    Text = opts.Text or name or "Tree", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
  })
  local scroll = Create.create("ScrollingFrame", {
    Parent = row, Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border, ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })
  local layout = Create.create("UIListLayout", { Parent = scroll, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) })
  local obj = BaseControl.new("Tree", row, self.Window, name)
  obj.Nodes = nodes
  obj.Value = nil
  obj.Changed = Signal.new()
  local expanded = {}
  local function rebuild(list, depth, order)
    depth = depth or 0
    order = order or { n = 0 }
    for _, node in ipairs(list or {}) do
      order.n += 1
      local hasChildren = type(node.Children) == "table" and #node.Children > 0
      local isExp = expanded[node] == true
      local prefix = string.rep("  ", depth) .. (hasChildren and (isExp and Glyphs.ArrowDown or Glyphs.ArrowRight) or " ")
      local item = Create.create("TextButton", {
        Parent = scroll, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order.n,
        BackgroundTransparency = (obj.Value == node) and 0 or 1, BackgroundColor3 = Theme.Selection,
        Text = prefix .. " " .. tostring(node.Text or node.Name or "?"),
        TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Font, TextSize = Theme.TextSize,
        TextColor3 = Theme.Text, AutoButtonColor = false,
      })
      self.Window:Track(item.MouseButton1Click:Connect(function()
        if hasChildren then
          expanded[node] = not isExp
          for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
          end
          rebuild(nodes, 0, { n = 0 })
          scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
        else
          local prev = obj.Value
          obj.Value = node
          obj.Changed:Fire(node, prev)
          if opts.Callback then pcall(opts.Callback, node, prev) end
          for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
          end
          rebuild(nodes, 0, { n = 0 })
          scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
        end
      end))
      if hasChildren and isExp then
        rebuild(node.Children, depth + 1, order)
      end
    end
  end
  rebuild(nodes)
  scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
  function obj:SetNodes(newNodes)
    nodes = newNodes or {}
    obj.Nodes = nodes
    for _, c in ipairs(scroll:GetChildren()) do
      if c:IsA("TextButton") then c:Destroy() end
    end
    rebuild(nodes)
    scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
  end
  function obj:AddNode(text, parentNode)
    local node = { Text = text, Children = {} }
    if parentNode and parentNode.Children then
      table.insert(parentNode.Children, node)
    else
      table.insert(nodes, node)
    end
    obj:SetNodes(nodes)
    return node
  end
  function obj:GetValue() return obj.Value end
  function obj:Destroy() BaseControl.Destroy(self) end
  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  return obj
end

function Groupbox:AddTable(name, opts)
  opts = opts or {}
  local columns = opts.Columns or { "Col1", "Col2" }
  local rows = opts.Rows or {}
  local height = opts.Height or 120
  assert(type(columns) == "table" and #columns > 0, "AddTable: Columns must be a nonempty array")
  assert(type(rows) == "table", "AddTable: Rows must be an array")
  assert(type(height) == "number" and height > 0 and height < math.huge, "AddTable: invalid Height")
  local rowFrame = createControlFrame(self, nil, true, false)
  Create.create("TextLabel", {
    Parent = rowFrame, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    Text = opts.Text or name or "Table", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
  })
  local header = Create.create("Frame", {
    Parent = rowFrame, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = Theme.PanelAlt, BorderSizePixel = 0,
  })
  local colW = 1 / math.max(#columns, 1)
  for i, col in ipairs(columns) do
    Create.create("TextLabel", {
      Parent = header, Size = UDim2.new(colW, 0, 1, 0), Position = UDim2.new(colW * (i - 1), 0, 0, 0),
      BackgroundTransparency = 1, Text = " " .. tostring(col), TextXAlignment = Enum.TextXAlignment.Left,
      Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Warning,
    })
  end
  local scroll = Create.create("ScrollingFrame", {
    Parent = rowFrame, LayoutOrder = 3, Size = UDim2.new(1, 0, 0, height),
    BackgroundColor3 = Theme.Background, BorderColor3 = Theme.Border, ScrollBarThickness = 6,
    ScrollBarImageColor3 = Theme.Scroll, CanvasSize = UDim2.new(),
  })
  local layout = Create.create("UIListLayout", { Parent = scroll, SortOrder = Enum.SortOrder.LayoutOrder })
  local obj = BaseControl.new("Table", rowFrame, self.Window, name)
  obj.Columns = columns
  obj.Rows = rows
  obj.Changed = Signal.new()
  local function rebuild()
    for _, c in ipairs(scroll:GetChildren()) do
      if c:IsA("Frame") then c:Destroy() end
    end
    for ri, rowData in ipairs(rows) do
      local r = Create.create("Frame", {
        Parent = scroll, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = ri,
      })
      for ci, col in ipairs(columns) do
        local cell = rowData[col]
        if cell == nil then cell = rowData[ci] end
        if cell == nil then cell = "" end
        Create.create("TextLabel", {
          Parent = r, Size = UDim2.new(colW, 0, 1, 0), Position = UDim2.new(colW * (ci - 1), 0, 0, 0),
          BackgroundTransparency = 1, Text = " " .. tostring(cell), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
          Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Text,
        })
      end
    end
    scroll.CanvasSize = UDim2.fromOffset(0, #rows * 18 + 4)
  end
  rebuild()
  function obj:SetRows(newRows)
    assert(newRows == nil or type(newRows) == "table", "SetRows: expected an array")
    if self.Destroyed then return end
    local previous = rows
    rows = newRows or {}
    obj.Rows = rows
    rebuild()
    obj.Changed:Fire(rows, previous)
  end
  function obj:GetRows() return obj.Rows end
  function obj:Destroy()
    if self.Destroyed then return end
    self.Changed:Destroy()
    BaseControl.Destroy(self)
  end
  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  return obj
end

-- Presentation only: the caller supplies actual data and debugging operations.
function Window:AddDebuggerTab(name)
  name = name or "CPU"
  assert(type(name) == "string" and name ~= "", "AddDebuggerTab: invalid name")
  assert(not self.Tabs[name], "AddDebuggerTab: tab already exists")
  local tab = self:AddTab(name)
  local disassembly = tab:AddLeftGroupbox("Disassembly")
  local dump = tab:AddLeftGroupbox("Memory dump")
  local registers = tab:AddRightGroupbox("Registers")
  local stack = tab:AddRightGroupbox("Stack")
  local watch = tab:AddRightGroupbox("Watch")
  return {
    Tab = tab,
    Disassembly = disassembly:AddTable(nil, {
      Text = "Instructions", Columns = { "Address", "Bytes", "Instruction", "Comment" }, Height = 260,
    }),
    Dump = dump:AddTable(nil, {
      Text = "Memory", Columns = { "Address", "Bytes", "Text" }, Height = 160,
    }),
    Registers = registers:AddTable(nil, {
      Text = "Registers", Columns = { "Register", "Value", "Comment" }, Height = 180,
    }),
    Stack = stack:AddTable(nil, {
      Text = "Stack", Columns = { "Address", "Value", "Comment" }, Height = 150,
    }),
    Watch = watch:AddTable(nil, {
      Text = "Expressions", Columns = { "Expression", "Value" }, Height = 100,
    }),
  }
end

function Tab:AddLabel(...) return self:GetDefaultGroupbox():AddLabel(...) end
function Tab:AddButton(...) return self:GetDefaultGroupbox():AddButton(...) end
function Tab:AddToggle(...) return self:GetDefaultGroupbox():AddToggle(...) end
function Tab:AddSlider(...) return self:GetDefaultGroupbox():AddSlider(...) end
function Tab:AddDropdown(...) return self:GetDefaultGroupbox():AddDropdown(...) end
function Tab:AddInput(...) return self:GetDefaultGroupbox():AddInput(...) end
function Tab:AddKeyPicker(...) return self:GetDefaultGroupbox():AddKeyPicker(...) end
function Tab:AddDivider(...) return self:GetDefaultGroupbox():AddDivider(...) end
function Tab:AddColorPicker(...) return self:GetDefaultGroupbox():AddColorPicker(...) end
function Tab:AddNumericInput(...) return self:GetDefaultGroupbox():AddNumericInput(...) end
function Tab:AddListBox(...) return self:GetDefaultGroupbox():AddListBox(...) end
function Tab:AddTree(...) return self:GetDefaultGroupbox():AddTree(...) end
function Tab:AddTable(...) return self:GetDefaultGroupbox():AddTable(...) end

-- ==================== COMMAND REGISTRY ====================

function X64UI:RegisterCommand(name, options)
  assert(type(name) == "string", "Command name must be a string")
  assert(type(options) == "table", "Command options must be a table")
  assert(type(options.Callback) == "function", "Command callback is required")

  local command = {
    Name = name,
    Description = options.Description or "",
    Keywords = options.Keywords or {},
    Callback = options.Callback,
  }

  self.Commands[name] = command

  if not table.find(self.CommandOrder, name) then
    table.insert(self.CommandOrder, name)
  end

  return command
end

function X64UI:UnregisterCommand(name)
  self.Commands[name] = nil

  local index = table.find(self.CommandOrder, name)
  if index then
    table.remove(self.CommandOrder, index)
  end
end

function X64UI:ExecuteCommand(name, ...)
  local command = self.Commands[name]

  if not command then
    return false, "Unknown command: " .. tostring(name)
  end

  local args = table.pack(...)

  local ok, result = xpcall(function()
    return command.Callback(unpack(args, 1, args.n))
  end, traceback)

  if not ok then
    Log.warn("Command failed:\n" .. tostring(result))
    return false, result
  end

  return true, result
end

-- ==================== WINDOW CREATION ====================

function X64UI:CreateWindow(options)
  options = options or {}

  if self._IntegrityError then
    warn("[X64UI] " .. tostring(self._IntegrityError))
    pcall(function()
      self:Notify({
        Title = "X64UI integrity",
        Description = tostring(self._IntegrityError),
        Time = 8,
      })
    end)
    return nil
  end

  if options.SingleInstance ~= false and self.ActiveWindow and not self.ActiveWindow.Destroyed then
    self.ActiveWindow:Destroy()
  end

  local win = setmetatable({}, Window)

  win.Maid = Maid.new()

  win.Events = {
    Changed = Signal.new(),
    Focused = Signal.new(),
    VisibilityChanged = Signal.new(),
    Destroying = Signal.new(),
  }

  win.Maid:Give(win.Events.Changed)
  win.Maid:Give(win.Events.Focused)
  win.Maid:Give(win.Events.VisibilityChanged)
  win.Maid:Give(win.Events.Destroying)

  win.History = History.new(150)
  win.Registry = Registry.new()

  win.State = {
    Visible = State.new(true),
    Minimized = State.new(false),
    Maximized = State.new(false),
    ActiveTab = State.new(nil),
  }

  win.Maid:Give(win.State.Visible)
  win.Maid:Give(win.State.Minimized)
  win.Maid:Give(win.State.Maximized)
  win.Maid:Give(win.State.ActiveTab)

  win.Tabs = {}
  win.TabOrder = {}
  win.Dropdowns = {}
  win.Lines = {}

  win.Title = options.Title or "x64dbg UI"
  win.ConsoleVisible = options.Console ~= false
  win.StatusVisible = options.Status ~= false
  win.TopOffset = 102
  win.Minimized = false
  win.Maximized = false
  win.Destroyed = false
  win.PickingKey = false
  win.IntroPlayed = false
  win.CommandModifierDown = false

  local viewport = getViewportSize()
  local width = options.Width or 1020
  local height = options.Height or 660

  win.Gui = Create.create("ScreenGui", {
    Name = options.Name or "X64UI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = options.DisplayOrder or 10000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = getParent(),
  })

  win.Main = Create.create("Frame", {
    Parent = win.Gui,
    Name = "MainWindow",
    AnchorPoint = Vector2.zero,
    Size = UDim2.fromOffset(width, height),
    Position = UDim2.fromOffset(
      math.clamp((viewport.X / 2) - (width / 2), 8, viewport.X - 8),
      math.clamp((viewport.Y / 2) - (height / 2), 8, viewport.Y - 8)
    ),
    BackgroundColor3 = Theme.Background,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
  })

  local defaultScale = 1
  if viewport.Y >= 1440 then
    defaultScale = 1.15
  elseif viewport.Y < 900 then
    defaultScale = 0.9
  end
  win.Scale = tonumber(options.Scale) or defaultScale
  win.UIScale = Create.create("UIScale", {
    Parent = win.Main,
    Scale = win.Scale,
  })
  function win:SetScale(scale)
    scale = math.clamp(tonumber(scale) or 1, 0.5, 2)
    self.Scale = scale
    if self.UIScale then self.UIScale.Scale = scale end
  end

  win.TitleBar = Create.create("Frame", {
    Parent = win.Main,
    Size = UDim2.new(1, 0, 0, 24),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
  })

  Create.create("TextLabel", {
    Parent = win.TitleBar,
    Position = UDim2.fromOffset(8, 0),
    Size = UDim2.new(1, -100, 1, 0),
    BackgroundTransparency = 1,
    Text = win.Title,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  win.MinButton = Create.create("TextButton", {
    Parent = win.TitleBar,
    Position = UDim2.new(1, -60, 0, 2),
    Size = UDim2.fromOffset(28, 20),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
    Text = Glyphs.Minimize,
    Font = Theme.Font,
    TextSize = 13,
    TextColor3 = Theme.Text,
  })

  win.CloseButton = Create.create("TextButton", {
    Parent = win.TitleBar,
    Position = UDim2.new(1, -30, 0, 2),
    Size = UDim2.fromOffset(28, 20),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
    Text = Glyphs.Close,
    Font = Theme.Font,
    TextSize = 13,
    TextColor3 = Theme.Text,
  })

  win:Track(win.MinButton.MouseEnter:Connect(function()
    win.MinButton.BackgroundColor3 = Theme.PanelAlt
  end))

  win:Track(win.MinButton.MouseLeave:Connect(function()
    win.MinButton.BackgroundColor3 = Theme.TitleBar
  end))

  win:Track(win.CloseButton.MouseEnter:Connect(function()
    win.CloseButton.BackgroundColor3 = Theme.Bad
  end))

  win:Track(win.CloseButton.MouseLeave:Connect(function()
    win.CloseButton.BackgroundColor3 = Theme.TitleBar
  end))

  win:Track(win.MinButton.MouseButton1Click:Connect(function()
    win:SetMinimized(not win.Minimized)
  end))

  win:Track(win.CloseButton.MouseButton1Click:Connect(function()
    win:Destroy()
  end))

  local lastTitleClick = 0

  win:Track(win.TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

    local now = os.clock()

    if now - lastTitleClick <= 0.24 then
      win:SetMaximized(not win.Maximized)
      lastTitleClick = 0
    else
      lastTitleClick = now
    end
  end))


  -- menu bar (always present)
  win.MenuBar = Create.create("Frame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(0, 24),
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundColor3 = Theme.Menu,
    BorderSizePixel = 0,
    ZIndex = 20,
  })
  Create.create("UIListLayout", {
    Parent = win.MenuBar,
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 2),
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  -- parent to ScreenGui so it renders above page content
  win.MenuDropdown = Create.create("Frame", {
    Parent = win.Gui,
    Visible = false,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
    ZIndex = 3000,
    AutomaticSize = Enum.AutomaticSize.None,
  })
  Create.create("UIListLayout", {
    Parent = win.MenuDropdown,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 1),
  })
  Create.create("UIPadding", {
    Parent = win.MenuDropdown,
    PaddingTop = UDim.new(0, 2),
    PaddingBottom = UDim.new(0, 2),
  })

  local openMenuName = nil
  local menus = {
    File = {
      { Text = "Unload", Callback = function() win:Destroy() end },
      { Text = "Exit", Callback = function() win:Destroy() end },
    },
    View = {
      { Text = "Toggle Console", Callback = function()
        if win.ToggleConsole then win:ToggleConsole() end
      end },
      { Text = "Toggle Status Bar", Callback = function()
        if win.ToggleStatusBar then
          win:ToggleStatusBar()
        else
          win.StatusVisible = not win.StatusVisible
          win:UpdateLayout()
        end
      end },
      { Text = "Command Palette", Callback = function()
        if win.OpenCommandPalette then
          win:OpenCommandPalette()
        elseif win.ToggleCommandPalette then
          win:ToggleCommandPalette()
        end
      end },
    },
    Options = {
      { Text = "Save Config", Callback = function()
        if win.SaveConfig then win:SaveConfig("x64ui_config.json") end
      end },
      { Text = "Load Config", Callback = function()
        if win.LoadConfig then win:LoadConfig("x64ui_config.json") end
      end },
    },
    Help = {
      { Text = "About", Callback = function()
        X64UI:Notify({
          Title = "X64UI",
          Description = "x64dbg-inspired ui · v" .. tostring(X64UI.Version or "?"),
          Time = 4,
        })
      end },
    },
  }

  local function clearMenuItems()
    for _, child in ipairs(win.MenuDropdown:GetChildren()) do
      if child:IsA("TextButton") then
        child:Destroy()
      end
    end
  end

  local function closeMenu()
    openMenuName = nil
    win.MenuDropdown.Visible = false
    for _, child in ipairs(win.MenuBar:GetChildren()) do
      if child:IsA("TextButton") then
        child.BackgroundTransparency = 1
        child.BackgroundColor3 = Theme.Menu
      end
    end
  end

  win.CloseMenu = closeMenu

  local function openMenu(name, sourceButton)
    if openMenuName == name and win.MenuDropdown.Visible then
      closeMenu()
      return
    end

    openMenuName = name
    clearMenuItems()

    local items = menus[name] or {}
    for i, item in ipairs(items) do
      local itemBtn = Create.create("TextButton", {
        Parent = win.MenuDropdown,
        LayoutOrder = i,
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        BackgroundColor3 = Theme.Selection,
        Text = "  " .. item.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Theme.Font,
        TextSize = Theme.TextSize,
        TextColor3 = Theme.Text,
        AutoButtonColor = false,
        ZIndex = 3001,
      })
      win:Track(itemBtn.MouseEnter:Connect(function()
        itemBtn.BackgroundTransparency = 0
      end))
      win:Track(itemBtn.MouseLeave:Connect(function()
        itemBtn.BackgroundTransparency = 1
      end))
      win:Track(itemBtn.MouseButton1Click:Connect(function()
        closeMenu()
        if item.Callback then
          pcall(item.Callback)
        end
      end))
    end

    -- position in screen space (parent is ScreenGui)
    local btnPos = sourceButton.AbsolutePosition
    local btnSize = sourceButton.AbsoluteSize
    local width = math.max(btnSize.X, 180)
    local height = (#items * 22) + 6

    win.MenuDropdown.Size = UDim2.fromOffset(width, height)
    win.MenuDropdown.Position = UDim2.fromOffset(btnPos.X, btnPos.Y + btnSize.Y)
    win.MenuDropdown.Visible = true

    for _, child in ipairs(win.MenuBar:GetChildren()) do
      if child:IsA("TextButton") then
        if child == sourceButton then
          child.BackgroundColor3 = Theme.PanelAlt
          child.BackgroundTransparency = 0
        else
          child.BackgroundTransparency = 1
        end
      end
    end
  end

  local function addMenuButton(name, order)
    local b = Create.create("TextButton", {
      Parent = win.MenuBar,
      LayoutOrder = order or 0,
      Size = UDim2.fromOffset(0, 20),
      AutomaticSize = Enum.AutomaticSize.X,
      BackgroundTransparency = 1,
      BackgroundColor3 = Theme.PanelAlt,
      Text = "  " .. name .. "  ",
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
      AutoButtonColor = false,
      ZIndex = 21,
    })
    win:Track(b.MouseButton1Click:Connect(function()
      openMenu(name, b)
    end))
    win:Track(b.MouseEnter:Connect(function()
      if openMenuName then
        -- windows-style: hover switches open menu
        if openMenuName ~= name then
          openMenu(name, b)
        end
      else
        b.BackgroundColor3 = Theme.PanelAlt
        b.BackgroundTransparency = 0
      end
    end))
    win:Track(b.MouseLeave:Connect(function()
      if openMenuName ~= name then
        b.BackgroundTransparency = 1
      end
    end))
    return b
  end

  addMenuButton("File", 1)
  addMenuButton("View", 2)
  addMenuButton("Options", 3)
  addMenuButton("Help", 4)

  -- close menu on outside click
  win:Track(UserInputService.InputBegan:Connect(function(input)
    if not win.MenuDropdown.Visible then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    task.defer(function()
      if not win.MenuDropdown or not win.MenuDropdown.Visible then return end
      local overMenu = mouseOverGui(win.MenuDropdown)
      local overBar = mouseOverGui(win.MenuBar)
      if not overMenu and not overBar then
        closeMenu()
      end
    end)
  end))

  -- toolbar (always present)
  win.Toolbar = Create.create("Frame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(0, 46),
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = Theme.Toolbar or Theme.Menu,
    BorderSizePixel = 0,
  })
  Create.create("UIListLayout", {
    Parent = win.Toolbar,
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 2),
    VerticalAlignment = Enum.VerticalAlignment.Center,
  })
  Create.create("UIPadding", {
    Parent = win.Toolbar,
    PaddingLeft = UDim.new(0, 4),
  })

  local function addToolButton(text, callback)
    local b = Create.create("TextButton", {
      Parent = win.Toolbar,
      Size = UDim2.fromOffset(60, 22),
      BackgroundColor3 = Theme.Toolbar or Theme.Menu,
      BorderColor3 = Theme.Border,
      Text = text,
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
    })
    win:Track(b.MouseEnter:Connect(function()
      b.BackgroundColor3 = Theme.PanelAlt
    end))
    win:Track(b.MouseLeave:Connect(function()
      b.BackgroundColor3 = Theme.Toolbar or Theme.Menu
    end))
    win:Track(b.MouseButton1Click:Connect(function()
      if callback then pcall(callback) end
    end))
    return b
  end

  local function addToolSeparator()
    Create.create("Frame", {
      Parent = win.Toolbar,
      Size = UDim2.fromOffset(1, 18),
      BackgroundColor3 = Theme.Border,
      BorderSizePixel = 0,
    })
  end

  addToolButton("Run", function() win:Log("Toolbar: Run") end)
  addToolButton("Pause", function() win:Log("Toolbar: Pause") end)
  addToolButton("Step", function() win:Log("Toolbar: Step") end)
  addToolButton("Over", function() win:Log("Toolbar: Step Over") end)
  addToolSeparator()
  addToolButton("Clear", function() win:ClearLog() end)
  addToolButton("Undo", function()
    if win.History then win.History:UndoLast() end
  end)
  addToolButton("Redo", function()
    if win.History then win.History:RedoLast() end
  end)

  win.TabBar = Create.create("ScrollingFrame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(0, 74),
    Size = UDim2.new(1, 0, 0, 26),
    BackgroundColor3 = Theme.Menu,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    ScrollingDirection = Enum.ScrollingDirection.X,
    CanvasSize = UDim2.new(),
  })

  local tabLayout = Create.create("UIListLayout", {
    Parent = win.TabBar,
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 1),
  })

  win:Track(tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    win.TabBar.CanvasSize = UDim2.fromOffset(tabLayout.AbsoluteContentSize.X + 8, 0)
  end))

  win.Pages = Create.create("Frame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(4, win.TopOffset),
    Size = UDim2.new(1, -8, 1, -(win.TopOffset + 160 + 22 + 8)),
    BackgroundColor3 = Theme.Background,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
  })

  win.Console = Create.create("Frame", {
    Parent = win.Main,
    Visible = win.ConsoleVisible,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
  })

  local consoleHeader = Create.create("Frame", {
    Parent = win.Console,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
  })

  Create.create("TextLabel", {
    Parent = consoleHeader,
    Position = UDim2.fromOffset(6, 0),
    Size = UDim2.new(1, -110, 1, 0),
    BackgroundTransparency = 1,
    Text = "Log",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Warning,
  })

  local clearButton = Create.create("TextButton", {
    Parent = consoleHeader,
    Position = UDim2.new(1, -56, 0, 0),
    Size = UDim2.fromOffset(56, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
    Text = "Clear",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  win:Track(clearButton.MouseButton1Click:Connect(function()
    win:ClearLog()
  end))

  win.LogScroll = Create.create("ScrollingFrame", {
    Parent = win.Console,
    Position = UDim2.fromOffset(0, 20),
    Size = UDim2.new(1, 0, 1, -20),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    ScrollBarThickness = 8,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })

  win.LogLabel = Create.create("TextLabel", {
    Parent = win.LogScroll,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Text = "",
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
    RichText = true,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  Create.create("UIPadding", {
    Parent = win.LogScroll,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  win.StatusBar = Create.create("Frame", {
    Parent = win.Main,
    Position = UDim2.new(0, 0, 1, -22),
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
  })

  win.StatusLabel = Create.create("TextLabel", {
    Parent = win.StatusBar,
    Position = UDim2.fromOffset(8, 0),
    Size = UDim2.new(0.6, -16, 1, 0),
    BackgroundTransparency = 1,
    Text = "Ready",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  win.StatusRight = Create.create("TextLabel", {
    Parent = win.StatusBar,
    Position = UDim2.new(0.6, 0, 0, 0),
    Size = UDim2.new(0.4, -8, 1, 0),
    BackgroundTransparency = 1,
    Text = "FPS: --",
    TextXAlignment = Enum.TextXAlignment.Right,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Dim,
  })

  win.Grip = Create.create("TextButton", {
    Parent = win.Main,
    Position = UDim2.new(1, -14, 1, -14),
    Size = UDim2.fromOffset(14, 14),
    BackgroundTransparency = 1,
    Text = Glyphs.Grip,
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.Dim,
  })

  win:MakeDraggable(win.Main, win.TitleBar)
  win:MakeResizable(win.Main, win.Grip)
  win:CreateCommandPalette()

  win:Track(win.Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      win:Focus()
    end
  end))

  win:Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType == Enum.UserInputType.Keyboard then
      if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        win.CommandModifierDown = true
      end

      if (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl))
        and input.KeyCode == Enum.KeyCode.P then
        win:ToggleCommandPalette()
        return
      end
    end

    if win.PickingKey then return end
    if InputManager and InputManager.Capturing then return end
    if InputRouter and #InputRouter.CaptureStack > 0 then return end
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end

    local key = X64UI.MenuKeybind
    local matched = false

    if typeof(key) == "EnumItem" then
      if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key then
        matched = true
      end
    elseif typeof(key) == "string" then
      matched = InputMatchesBind(input, key)
    end

    if matched then
      win:Toggle()
    end
  end))

  win:Track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
      if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        win.CommandModifierDown = false
      end
    end
  end))

  -- Clear sticky modifiers on focus loss (alt-tab while holding Ctrl)
  win:Track(UserInputService.WindowFocusReleased:Connect(function()
    win.CommandModifierDown = false
    win.PickingKey = false
  end))

  win:Track(win.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    if not win.Destroyed and not win.Maximized and not win.Minimized then
      win:ClampToViewport()
    end
  end))

  win:Track(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

    task.defer(function()
      if win.Destroyed then return end

      if win.CommandPalette and win.CommandPalette.Visible then
        if not mouseOverGui(win.CommandPalette) then
          win:CloseCommandPalette()
        end
      end

      for _, dropdown in ipairs(win.Dropdowns) do
        if dropdown.List and dropdown.List.Visible then
          local tooSoon = os.clock() - dropdown.OpenedAt < 0.05

          if not tooSoon and not mouseOverGui(dropdown.Button) and not mouseOverGui(dropdown.List) then
            dropdown:Close()
          end
        end
      end
    end)
  end))

  win:Track(RunService.RenderStepped:Connect(function()
    if win.Destroyed then return end

    for _, dropdown in ipairs(win.Dropdowns) do
      if dropdown.List and dropdown.List.Visible then
        if not win.Main.Visible or win.Minimized then
          dropdown:Close()
        else
          dropdown:RefreshPosition()
        end
      end
    end
  end))

  local frames = 0
  local last = os.clock()

  win:Track(RunService.RenderStepped:Connect(function()
    frames += 1

    if os.clock() - last >= 1 then
      if win.StatusRight and win.StatusRight.Parent then
        win.StatusRight.Text = string.format("FPS: %d | %s", frames, os.date("%X"))
      end

      frames = 0
      last = os.clock()
    end
  end))

  win:Track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    task.defer(function()
      if win.Destroyed then return end

      if win.Maximized then
        local newViewport = getViewportSize()
        win.Main.Position = UDim2.fromOffset(0, 0)
        win.Main.Size = UDim2.fromOffset(newViewport.X, newViewport.Y)
        win:UpdateLayout()
      else
        win:ClampToViewport()
      end
    end)
  end))

  win:UpdateLayout()
  win:PlayIntro()

  -- integrity: full chrome is mandatory (not optional / handpicked)
  local function failIntegrity(issue)
    local detail = "[X64UI] window integrity failed: " .. tostring(issue)
    warn(detail)
    pcall(function()
      X64UI:Notify({
        Title = "X64UI integrity",
        Description = tostring(issue),
        Time = 8,
      })
    end)
    pcall(function()
      if win and not win.Destroyed then
        win:Destroy()
      end
    end)
    return nil
  end

  local required = {
    { key = "Gui", label = "ScreenGui root missing" },
    { key = "Main", label = "main window frame missing" },
    { key = "TitleBar", label = "title bar missing" },
    { key = "MenuBar", label = "menu bar missing (File/View/Options/Help required)" },
    { key = "Toolbar", label = "toolbar missing (Run/Pause/Step chrome required)" },
    { key = "TabBar", label = "tab bar missing" },
    { key = "Pages", label = "pages container missing" },
    { key = "Console", label = "log console missing" },
    { key = "StatusBar", label = "status bar missing" },
    { key = "Registry", label = "control registry missing" },
    { key = "History", label = "history stack missing" },
    { key = "Maid", label = "maid cleanup missing" },
  }

  for _, item in ipairs(required) do
    local value = win[item.key]
    if value == nil then
      return failIntegrity(item.label)
    end
    if typeof(value) == "Instance" and not value.Parent then
      return failIntegrity(item.label .. " (instance has no parent)")
    end
  end

  -- menu buttons must exist
  local menuNames = { File = false, View = false, Options = false, Help = false }
  for _, child in ipairs(win.MenuBar:GetChildren()) do
    if child:IsA("TextButton") then
      local t = (child.Text or ""):gsub("%s+", "")
      for name in pairs(menuNames) do
        if t:find(name) then menuNames[name] = true end
      end
    end
  end
  for name, ok in pairs(menuNames) do
    if not ok then
      return failIntegrity("menu bar incomplete — missing '" .. name .. "'")
    end
  end

  -- toolbar must have at least a few tool buttons
  local toolCount = 0
  for _, child in ipairs(win.Toolbar:GetChildren()) do
    if child:IsA("TextButton") then toolCount += 1 end
  end
  if toolCount < 4 then
    return failIntegrity("toolbar incomplete — expected tool buttons, found " .. tostring(toolCount))
  end

  -- layout offsets must match full chrome (title+menu+toolbar+tabs)
  if (win.TopOffset or 0) < 90 then
    return failIntegrity("TopOffset too small (" .. tostring(win.TopOffset) .. ") — full chrome requires menu+toolbar")
  end

  table.insert(self.Windows, win)
  self.ActiveWindow = win
  return win
end

-- ==================== NOTIFICATIONS ====================

function X64UI:Notify(opts)
  opts = opts or {}

  local parent

  if self.ActiveWindow and not self.ActiveWindow.Destroyed and self.ActiveWindow.Gui and self.ActiveWindow.Gui.Parent then
    parent = self.ActiveWindow.Gui
  else
    if not self.NotifyGui or not self.NotifyGui.Parent then
      self.NotifyGui = Create.create("ScreenGui", {
        Name = "X64Notify",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 32767,
        Parent = getParent(),
      })
    end

    parent = self.NotifyGui
  end

  local container = parent:FindFirstChild("X64Notifications")

  if not container then
    container = Create.create("Frame", {
      Parent = parent,
      Name = "X64Notifications",
      AnchorPoint = Vector2.new(1, 1),
      Position = UDim2.new(1, -12, 1, -12),
      Size = UDim2.fromOffset(280, 0),
      AutomaticSize = Enum.AutomaticSize.Y,
      BackgroundTransparency = 1,
      ZIndex = 10000,
    })

    Create.create("UIListLayout", {
      Parent = container,
      Padding = UDim.new(0, 8),
      SortOrder = Enum.SortOrder.LayoutOrder,
      HorizontalAlignment = Enum.HorizontalAlignment.Right,
      VerticalAlignment = Enum.VerticalAlignment.Bottom,
    })
  end

  while #container:GetChildren() > 6 do
    local child = container:GetChildren()[2]
    if child then child:Destroy() end
  end

  local toastMaid = Maid.new()
  local toast = Create.create("CanvasGroup", {
    Parent = container,
    Size = UDim2.new(1, 0, 0, 58),
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    GroupTransparency = 1,
    LayoutOrder = math.floor(os.clock() * 1000),
    ZIndex = 10001,
  })

  toastMaid:Give(toast)

  Create.create("TextLabel", {
    Parent = toast,
    Position = UDim2.fromOffset(8, 4),
    Size = UDim2.new(1, -16, 0, 18),
    BackgroundTransparency = 1,
    Text = opts.Title or "Notification",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.AccentText,
    ZIndex = 10002,
  })

  Create.create("TextLabel", {
    Parent = toast,
    Position = UDim2.fromOffset(8, 24),
    Size = UDim2.new(1, -16, 0, 28),
    BackgroundTransparency = 1,
    Text = opts.Description or "",
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    ZIndex = 10002,
  })

  TweenService:Create(
    toast,
    TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { GroupTransparency = 0 }
  ):Play()

  local hideThread = task.delay(opts.Time or 3, function()
    if toast and toast.Parent then
      local tween = TweenService:Create(
        toast,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { GroupTransparency = 1 }
      )

      tween:Play()

      tween.Completed:Connect(function()
        toastMaid:Destroy()
      end)
    end
  end)
  
  toastMaid:Give(hideThread)
end

-- library surface integrity (api surface must be complete)
do
  local requiredApi = {
    "CreateWindow",
    "Notify",
    "RegisterCommand",
    "Theme",
    "Version",
  }
  local missing = {}
  for _, name in ipairs(requiredApi) do
    if X64UI[name] == nil then
      table.insert(missing, name)
    end
  end
  if #missing > 0 then
    local msg = "x64ui api incomplete — missing: " .. table.concat(missing, ", ")
    warn("[X64UI] " .. msg)
    -- cannot Notify yet (may not have full ui), but mark flag
    X64UI._IntegrityError = msg
  end
end



function X64UI.SerializeValue(control)
  if not control then return nil end
  local t = control.Type
  local v = control.Value
  if t == "ColorPicker" and typeof(v) == "Color3" then
    return { t = "Color3", r = v.R, g = v.G, b = v.B }
  end
  if t == "Dropdown" and type(v) == "table" then
    return { t = "Multi", v = v }
  end
  if t == "Toggle" or t == "Slider" or t == "NumericInput" or t == "KeyPicker" or t == "Input" then
    return v
  end
  if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
    return v
  end
  return nil -- skip non-json-safe
end

function X64UI.DeserializeValue(control, raw)
  if not control or raw == nil then return nil end
  if type(raw) == "table" and raw.t == "Color3" then
    return Color3.new(raw.r or 0, raw.g or 0, raw.b or 0)
  end
  if type(raw) == "table" and raw.t == "Multi" then
    return raw.v
  end
  return raw
end


function X64UI:SetWatermark(text)
  if not self._WatermarkGui or not self._WatermarkGui.Parent then
    self._WatermarkGui = Create.create("ScreenGui", {
      Name = "X64Watermark",
      ResetOnSpawn = false,
      IgnoreGuiInset = true,
      DisplayOrder = 100,
      Parent = getParent(),
    })
    self._WatermarkLabel = Create.create("TextLabel", {
      Parent = self._WatermarkGui,
      Position = UDim2.fromOffset(12, 12),
      Size = UDim2.fromOffset(0, 0),
      AutomaticSize = Enum.AutomaticSize.XY,
      BackgroundColor3 = Theme.Panel,
      BorderColor3 = Theme.Border,
      Text = "",
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
      TextXAlignment = Enum.TextXAlignment.Left,
    })
    Create.create("UIPadding", {
      Parent = self._WatermarkLabel,
      PaddingLeft = UDim.new(0, 6),
      PaddingRight = UDim.new(0, 6),
      PaddingTop = UDim.new(0, 3),
      PaddingBottom = UDim.new(0, 3),
    })
  end
  if text == nil or text == false or text == "" then
    self._WatermarkGui.Enabled = false
  else
    self._WatermarkGui.Enabled = true
    self._WatermarkLabel.Text = tostring(text)
  end
end


function X64UI:SetKeybindList(enabled)
  if enabled == false then
    if self._KeybindListGui then
      self._KeybindListGui.Enabled = false
    end
    return
  end

  if not self._KeybindListGui or not self._KeybindListGui.Parent then
    self._KeybindListGui = Create.create("ScreenGui", {
      Name = "X64KeybindList",
      ResetOnSpawn = false,
      IgnoreGuiInset = true,
      DisplayOrder = 150,
      Parent = getParent(),
    })
    self._KeybindListFrame = Create.create("Frame", {
      Parent = self._KeybindListGui,
      AnchorPoint = Vector2.new(1, 0),
      Position = UDim2.new(1, -12, 0, 12),
      Size = UDim2.fromOffset(200, 0),
      AutomaticSize = Enum.AutomaticSize.Y,
      BackgroundColor3 = Theme.Panel,
      BorderColor3 = Theme.Border,
    })
    Create.create("UIListLayout", {
      Parent = self._KeybindListFrame,
      Padding = UDim.new(0, 2),
      SortOrder = Enum.SortOrder.LayoutOrder,
    })
    Create.create("TextLabel", {
      Parent = self._KeybindListFrame,
      Size = UDim2.new(1, 0, 0, 18),
      BackgroundColor3 = Theme.TitleBar,
      BorderSizePixel = 0,
      Text = " keybinds ",
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.AccentText,
      TextXAlignment = Enum.TextXAlignment.Left,
    })
  end

  self._KeybindListGui.Enabled = true

  -- refresh rows from registered keypickers across windows
  for _, child in ipairs(self._KeybindListFrame:GetChildren()) do
    if child:IsA("TextLabel") and child.LayoutOrder > 0 then
      child:Destroy()
    end
  end

  local order = 1
  for _, win in ipairs(self.Windows or {}) do
    if win.Registry and win.Registry.Options then
      for name, opt in pairs(win.Registry.Options) do
        if opt.Type == "KeyPicker" and opt.Value and opt.Value ~= "None" then
          local state = ""
          if opt.GetState then
            state = opt:GetState() and " [ON]" or ""
          end
          Create.create("TextLabel", {
            Parent = self._KeybindListFrame,
            LayoutOrder = order,
            Size = UDim2.new(1, -8, 0, 16),
            BackgroundTransparency = 1,
            Text = string.format(" %s: %s%s", name, tostring(opt.Value), state),
            Font = Theme.Font,
            TextSize = Theme.TextSize - 1,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
          })
          order += 1
        end
      end
    end
  end
end


function X64UI:GetCapabilities()
  return {
    writefile = Platform.CanWrite == true,
    readfile = Platform.CanRead == true,
    delfile = Platform.CanDelete == true,
    gethui = type(gethui) == "function",
    request = type(request) == "function",
    getgenv = type(getgenv) == "function",
    hookfunction = type(hookfunction) == "function",
    Drawing = type(Drawing) == "table",
  }
end

function X64UI:ReportCapabilities(window)
  local c = self:GetCapabilities()
  local parts = {}
  for k, v in pairs(c) do
    parts[#parts + 1] = k .. "=" .. (v and "yes" or "no")
  end
  table.sort(parts)
  local msg = "caps: " .. table.concat(parts, " ")
  if window and window.Log then
    window:Log(msg, "accent")
  else
    Log.info(msg)
  end
  return c
end

function X64UI:Unload()
  if self.Unloaded then return end
  self.Unloaded = true

  if InputRouter and InputRouter.Disconnect then
    pcall(function() InputRouter:Disconnect() end)
  end

  for i = #self.Windows, 1, -1 do
    local win = self.Windows[i]
    if win and type(win.Destroy) == "function" then
      pcall(function() win:Destroy() end)
    end
  end
  table.clear(self.Windows)
  self.ActiveWindow = nil

  if self.NotifyGui then
    pcall(function() self.NotifyGui:Destroy() end)
    self.NotifyGui = nil
  end
  if TooltipGui then
    TooltipGui:Destroy()
    TooltipGui, TooltipLabel = nil, nil
  end
  if self._WatermarkGui then
    self._WatermarkGui:Destroy()
    self._WatermarkGui, self._WatermarkLabel = nil, nil
  end
  if self._KeybindListGui then
    self._KeybindListGui:Destroy()
    self._KeybindListGui, self._KeybindListFrame = nil, nil
  end
  table.clear(ThemeBindings)

end

-- Keep window positions fixed during a resize and handle UIScale in pixels.
do
  local function bounds(win)
    local viewport = getViewportSize(win.Gui)
    local scale = math.max((win.UIScale and win.UIScale.Scale) or 1, 0.01)
    return viewport, scale
  end

  function Window:ClampToViewport()
    if self.Destroyed or self.Maximized or self.Minimized or self._Dragging or self._Resizing then return end
    if not self.Main or not self.Main.Parent then return end
    local viewport, scale = bounds(self)
    local availableX, availableY = math.max(1, viewport.X - 16), math.max(1, viewport.Y - 16)
    local width = math.clamp(self.Main.AbsoluteSize.X / scale, math.min(760, availableX / scale), availableX / scale)
    local height = math.clamp(self.Main.AbsoluteSize.Y / scale, math.min(420, availableY / scale), availableY / scale)
    local size = self.Main.Size
    if size.X.Scale ~= 0 or size.Y.Scale ~= 0 or math.abs(size.X.Offset - width) > 0.5 or math.abs(size.Y.Offset - height) > 0.5 then
      self.Main.Size = UDim2.fromOffset(width, height)
      self:UpdateLayout()
    end
    local pos = self.Main.Position
    local x = math.clamp(pos.X.Offset, 8, math.max(8, viewport.X - 8 - width * scale))
    local y = math.clamp(pos.Y.Offset, 8, math.max(8, viewport.Y - 8 - height * scale))
    if pos.X.Scale ~= 0 or pos.Y.Scale ~= 0 or pos.X.Offset ~= x or pos.Y.Offset ~= y then
      self.Main.Position = UDim2.fromOffset(x, y)
    end
  end

  function Window:MakeResizable(frame, grip)
    local resizing, startMouse, startSize = false, Vector2.zero, Vector2.zero
    local function beginResize(input)
      if resizing or self.Destroyed or not frame.Parent or not grip.Parent or not grip.Visible
        or not self.Main.Visible or self.Minimized or self.Maximized
        or UserInputService:GetFocusedTextBox() then return end
      local _, scale = bounds(self)
      resizing, self._Resizing = true, true
      startMouse = getMousePos()
      startSize = frame.AbsoluteSize / scale
      self:Focus()
    end
    self:Track(grip.InputBegan:Connect(function(input)
      if input.UserInputType == Enum.UserInputType.MouseButton1 then beginResize(input) end
    end))
    self:Track(UserInputService.InputBegan:Connect(function(input)
      if input.UserInputType == Enum.UserInputType.MouseButton1 and mouseOverGui(grip) then beginResize(input) end
    end))
    self:Track(UserInputService.InputChanged:Connect(function(input)
      if not resizing or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
      local viewport, scale = bounds(self)
      local pos, delta = frame.Position, getMousePos() - startMouse
      local maxX = math.max(1, (viewport.X - 8 - pos.X.Offset) / scale)
      local maxY = math.max(1, (viewport.Y - 8 - pos.Y.Offset) / scale)
      local width = math.clamp(startSize.X + delta.X / scale, math.min(760, maxX), maxX)
      local height = math.clamp(startSize.Y + delta.Y / scale, math.min(420, maxY), maxY)
      frame.Size = UDim2.fromOffset(width, height)
      self:UpdateLayout()
    end))
    local function finishResize()
      if not resizing then return end
      resizing, self._Resizing = false, false
      self:ClampToViewport()
    end
    self:Track(UserInputService.InputEnded:Connect(function(input)
      if input.UserInputType == Enum.UserInputType.MouseButton1 then finishResize() end
    end))
    self:Track(UserInputService.WindowFocusReleased:Connect(finishResize))
  end
end

return X64UI

end
X64UI = createBundledX64UI()
assert(validLibrary(X64UI), "FORGE: bundled x64ui could not initialize")

-- ESP uses Roblox GUI layering instead of executor Drawing primitives.
local espGui = Instance.new("ScreenGui")
espGui.Name = "ForgeESP"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
espGui.DisplayOrder = 20
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
espGui.Parent = playerGui

local function createEspPrimitive(class)
    local node
    if class == "Text" then
        node = Instance.new("TextLabel")
        node.BackgroundTransparency = 1
        node.BorderSizePixel = 0
        node.Font = Enum.Font.Code
        node.Text = ""
        node.TextColor3 = Color3.new(1, 1, 1)
        node.TextStrokeTransparency = 1
        node.TextXAlignment = Enum.TextXAlignment.Center
        node.TextYAlignment = Enum.TextYAlignment.Top
        node.Size = UDim2.fromOffset(600, 14)
    else
        node = Instance.new("Frame")
        node.BorderSizePixel = 0
        node.BackgroundColor3 = Color3.new(1, 1, 1)
        node.BackgroundTransparency = class == "Square" and 1 or 0
    end
    node.Name = "ESP" .. class
    node.Visible = false
    node.Parent = espGui

    local stroke
    if class == "Square" then
        stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color = Color3.new(1, 1, 1)
        stroke.Parent = node
    end

    local properties = {
        Position = Vector2.zero, Size = class == "Text" and 13 or Vector2.zero,
        From = Vector2.zero, To = Vector2.zero, Color = Color3.new(1, 1, 1),
        Transparency = 1, Visible = false, Thickness = 1, Filled = false,
        ZIndex = 1, Text = "", Center = true, Outline = false, OutlineColor = Color3.new(),
    }
    local removed = false
    local function apply(key, value)
        if removed then return end
        properties[key] = value
        if key == "Visible" then
            node.Visible = value
        elseif key == "ZIndex" then
            node.ZIndex = value
        elseif class == "Text" then
            if key == "Position" or key == "Center" then
                node.AnchorPoint = properties.Center and Vector2.new(0.5, 0) or Vector2.zero
                node.Position = UDim2.fromOffset(properties.Position.X, properties.Position.Y)
            elseif key == "Size" then
                node.TextSize = value
                node.Size = UDim2.fromOffset(600, value + 2)
            elseif key == "Text" then
                node.Text = value
            elseif key == "Color" then
                node.TextColor3 = value
            elseif key == "Transparency" then
                node.TextTransparency = 1 - value
                node.TextStrokeTransparency = properties.Outline and 1 - value or 1
            elseif key == "Outline" then
                node.TextStrokeTransparency = value and 1 - properties.Transparency or 1
            elseif key == "OutlineColor" then
                node.TextStrokeColor3 = value
            end
        elseif class == "Square" then
            if key == "Position" then
                node.Position = UDim2.fromOffset(value.X, value.Y)
            elseif key == "Size" then
                node.Size = UDim2.fromOffset(value.X, value.Y)
            elseif key == "Color" then
                node.BackgroundColor3 = value
                stroke.Color = value
            elseif key == "Transparency" or key == "Filled" then
                node.BackgroundTransparency = properties.Filled and 1 - properties.Transparency or 1
                stroke.Enabled = not properties.Filled
                stroke.Transparency = 1 - properties.Transparency
            elseif key == "Thickness" then
                stroke.Thickness = value
            end
        elseif class == "Line" then
            if key == "From" or key == "To" or key == "Thickness" then
                local a, b = properties.From, properties.To
                local delta = b - a
                node.AnchorPoint = Vector2.new(0.5, 0.5)
                node.Position = UDim2.fromOffset((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5)
                node.Size = UDim2.fromOffset(delta.Magnitude, properties.Thickness)
                node.Rotation = math.deg(math.atan2(delta.Y, delta.X))
            elseif key == "Color" then
                node.BackgroundColor3 = value
            elseif key == "Transparency" then
                node.BackgroundTransparency = 1 - value
            end
        end
    end
    local object = {}
    return setmetatable(object, {
        __index = function(_, key)
            if key == "Remove" then
                return function()
                    if removed then return end
                    removed = true
                    node:Destroy()
                end
            end
            return properties[key]
        end,
        __newindex = function(_, key, value)
            if properties[key] ~= value then apply(key, value) end
        end,
    })
end

local function removeDrawing(object)
    object:Remove()
end

local function destroyEsp(esp)
    if not esp then return end
    for index = #esp.list, 1, -1 do
        removeDrawing(esp.list[index])
        esp.list[index] = nil
    end
end

local function createEsp()
    local black = Color3.new(0, 0, 0)
    local esp = { list = {}, visible = false, lastDist = -1, lastName = "" }

    local function add(class, props)
        local object = createEspPrimitive(class)
        esp.list[#esp.list + 1] = object
        for key, value in pairs(props) do
            object[key] = value
        end
        return object
    end

    local ok = pcall(function()
        esp.boxOutline = add("Square", {
            Thickness = 3, Filled = false, Color = black, Transparency = 1, Visible = false, ZIndex = 1,
        })
        esp.box = add("Square", {
            Thickness = 1, Filled = false, Transparency = 1, Visible = false, ZIndex = 2,
        })
        esp.hpBack = add("Square", {
            Thickness = 1, Filled = true, Color = black, Transparency = 0.6, Visible = false, ZIndex = 2,
        })
        esp.hpFill = add("Square", {
            Thickness = 1, Filled = true, Transparency = 1, Visible = false, ZIndex = 3,
        })
        esp.name = add("Text", {
            Text = "", Size = 13, Center = true, Outline = true, OutlineColor = black, Visible = false, ZIndex = 4,
        })
        esp.dist = add("Text", {
            Text = "", Size = 13, Center = true, Outline = true, OutlineColor = black, Visible = false, ZIndex = 4,
        })
        esp.tracer = add("Line", {
            Thickness = 1, Transparency = 1, Visible = false, ZIndex = 1,
        })
    end)

    if not ok then
        destroyEsp(esp)
        return nil
    end
    return esp
end

-- Skeleton lines are created lazily, only when the option is used.
local function ensureSkeleton(esp)
    if esp.skeleton then return true end

    local lines = {}
    local ok = pcall(function()
        for index = 1, 14 do
            local line = createEspPrimitive("Line")
            esp.list[#esp.list + 1] = line
            line.Thickness = 1
            line.Transparency = 1
            line.Visible = false
            line.ZIndex = 1
            lines[index] = line
        end
    end)

    if not ok then
        for _, line in ipairs(lines) do line:Remove() end
        return false
    end
    esp.skeleton = lines
    return true
end

local function hideEsp(esp)
    if esp and esp.visible then
        esp.visible = false
        for _, object in ipairs(esp.list) do
            object.Visible = false
        end
    end
end

-- Entity registry ---------------------------------------------------------

local records = {}      -- [Model] = record
local playerConns = {}  -- [Player] = { connections }
local npcConns = {}
local friendCache = {}  -- [UserId] = boolean
local ignoreNames = {}  -- lowercase set
local includeTerms, excludeTerms = {}, {}
local npcToken = 0
local npcDirty = true
local lastNpcBuild = 0

local function clearTarget()
    state.target = nil
    state.targetPart = nil
    state.targetCamera = nil
    state.targetPosition = nil
end

local function removeRecord(model)
    local rec = records[model]
    if not rec then return end
    records[model] = nil
    destroyEsp(rec.esp)
    if state.target == rec then
        clearTarget()
    end
end

local function addRecord(model, kind, player)
    local existing = records[model]
    if existing then
        if existing.kind == kind then
            return existing
        end
        removeRecord(model)
    end

    local rec = {
        model = model,
        kind = kind,
        player = player,
        parts = {},
        exact = {},
        height = 5,
        heightAt = -math.huge,
        seen = false,
    }
    records[model] = rec
    return rec
end

local function humanoidOf(rec)
    local humanoid = rec.humanoid
    if humanoid and humanoid.Parent == rec.model then
        return humanoid
    end
    humanoid = rec.model:FindFirstChildOfClass("Humanoid")
    rec.humanoid = humanoid
    return humanoid
end

local function healthOf(rec)
    local humanoid = humanoidOf(rec)
    if humanoid then
        return humanoid.Health, humanoid.MaxHealth
    end

    local attribute = CONFIG.NPCHealthAttribute
    if rec.kind == "NPC" and attribute ~= "" then
        local health = rec.model:GetAttribute(attribute)
        if type(health) == "number" then
            local maxAttribute = CONFIG.NPCMaxHealthAttribute
            local maximum = maxAttribute ~= "" and rec.model:GetAttribute(maxAttribute) or nil
            return health, type(maximum) == "number" and maximum or nil
        end
    end
    return nil
end

local function isAlive(rec)
    if rec.kind == "NPC" and CONFIG.NPCRequireHumanoid and not humanoidOf(rec) then
        return false
    end
    local health = healthOf(rec)
    if health then
        return health > 0
    end
    return true -- no health source available; cannot prove dead
end

local FALLBACK_PARTS = { "HumanoidRootPart", "UpperTorso", "Torso", "Head" }

local function partOf(rec, name)
    local model = rec.model
    local cached = rec.parts[name]
    if cached and cached.Parent == model then
        return cached
    end

    local part = model:FindFirstChild(name)
    if not (part and part:IsA("BasePart")) then
        part = nil
        for _, fallback in ipairs(FALLBACK_PARTS) do
            local candidate = model:FindFirstChild(fallback)
            if candidate and candidate:IsA("BasePart") then
                part = candidate
                break
            end
        end
        part = part or model.PrimaryPart
    end

    rec.parts[name] = part
    return part
end

-- Exact-name lookup without fallbacks (skeleton joints, head).
local function exactPart(rec, name)
    local cached = rec.exact[name]
    if cached and cached.Parent == rec.model then
        return cached
    end
    local part = rec.model:FindFirstChild(name)
    if part and part:IsA("BasePart") then
        rec.exact[name] = part
        return part
    end
    rec.exact[name] = nil
    return nil
end

local function getHeight(rec, now)
    if now - rec.heightAt > 1 then
        rec.heightAt = now
        rec.height = math.clamp(rec.model:GetExtentsSize().Y, 1, 40)
    end
    return rec.height
end

-- Ignore list / friends -----------------------------------------------------

local function parseIgnore()
    table.clear(ignoreNames)
    if type(CONFIG.IgnoreList) ~= "string" then return end
    for term in string.gmatch(CONFIG.IgnoreList, "[^,]+") do
        term = string.lower(term:match("^%s*(.-)%s*$"))
        if term ~= "" then
            ignoreNames[term] = true
        end
    end
end

local function playerIgnored(player)
    if ignoreNames[string.lower(player.Name)] or ignoreNames[string.lower(player.DisplayName)] then
        return true
    end
    return CONFIG.IgnoreFriends and friendCache[player.UserId] == true
end

-- NPC / bot discovery -----------------------------------------------------

local function parseTerms(text)
    local out = {}
    if type(text) ~= "string" then return out end
    for term in string.gmatch(text, "[^,]+") do
        term = string.lower(term:match("^%s*(.-)%s*$"))
        if term ~= "" then
            out[#out + 1] = term
        end
    end
    return out
end

local function nameAllowed(name)
    local lowered = string.lower(name)
    for _, term in ipairs(excludeTerms) do
        if string.find(lowered, term, 1, true) then return false end
    end
    if #includeTerms == 0 then return true end
    for _, term in ipairs(includeTerms) do
        if string.find(lowered, term, 1, true) then return true end
    end
    return false
end

local function npcTracking()
    return CONFIG.NPCEnabled or (CONFIG.ESPEnabled and CONFIG.ESPNPCs)
end

local function considerNpc(model)
    if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
    if not model:IsDescendantOf(Workspace) then return end
    if records[model] then return end
    if model == localPlayer.Character or Players:GetPlayerFromCharacter(model) then return end

    if CONFIG.NPCSource == "Container" then
        local root = state.npcRoot
        if not root or not (model == root or model:IsDescendantOf(root)) then return end
    end

    if not nameAllowed(model.Name) then return end
    addRecord(model, "NPC")
end

local function candidateModel(instance)
    if instance.ClassName == "Humanoid" then
        return instance.Parent
    end
    if not CONFIG.NPCRequireHumanoid then
        local name = instance.Name
        if (name == "HumanoidRootPart" or name == "Head") and instance:IsA("BasePart") then
            return instance.Parent
        end
    end
    return nil
end

local function resolvePath(path)
    path = type(path) == "string" and path:match("^%s*(.-)%s*$") or ""
    if path == "" then
        return nil, "container path is empty"
    end

    local parts = string.split(path, ".")
    local index = 1
    if parts[index] == "game" then index += 1 end
    if parts[index] == "Workspace" or parts[index] == "workspace" then index += 1 end

    local current = Workspace
    for i = index, #parts do
        local child = current:FindFirstChild(parts[i])
        if not child then
            return nil, "not found: " .. parts[i]
        end
        current = child
    end

    if current == Workspace then
        return nil, "select a container below Workspace"
    end
    return current
end

local function removeNpcRecords()
    local doomed = {}
    for model, rec in pairs(records) do
        if rec.kind == "NPC" then
            doomed[#doomed + 1] = model
        end
    end
    for _, model in ipairs(doomed) do
        removeRecord(model)
    end
end

local function countKind(kind)
    local count = 0
    for _, rec in pairs(records) do
        if rec.kind == kind then count += 1 end
    end
    return count
end

local function rebuildNpcs()
    npcToken += 1
    local token = npcToken

    disconnectList(npcConns)
    removeNpcRecords()
    state.npcRoot = nil
    includeTerms = parseTerms(CONFIG.NPCInclude)
    excludeTerms = parseTerms(CONFIG.NPCExclude)

    if not npcTracking() then return end

    if CONFIG.NPCSource == "Container" then
        local root, err = resolvePath(CONFIG.NPCPath)
        if not root then
            say("NPC source: " .. err)
            return
        end
        state.npcRoot = root
        npcConns[#npcConns + 1] = root.AncestryChanged:Connect(function()
            if not root:IsDescendantOf(Workspace) then
                npcDirty = true
            end
        end)
    end

    task.spawn(function()
        local scope = state.npcRoot or Workspace
        if state.npcRoot then
            considerNpc(state.npcRoot)
        end

        local descendants = scope:GetDescendants()
        for index, instance in ipairs(descendants) do
            if token ~= npcToken or not state.alive then return end
            local model = candidateModel(instance)
            if model then
                considerNpc(model)
            end
            if index % 3000 == 0 then
                task.wait()
            end
        end

        if state.alive and token == npcToken then
            say(("NPC scan complete: %d tracked"):format(countKind("NPC")))
        end
    end)
end

-- Reports where non-player Humanoid models live, to help fill in the container path.
local detectBusy = false

local function detectContainers()
    if detectBusy then return end
    detectBusy = true

    task.spawn(function()
        local counts, samples, order = {}, {}, {}
        local descendants = Workspace:GetDescendants()

        for index, instance in ipairs(descendants) do
            if not state.alive then
                detectBusy = false
                return
            end

            if instance.ClassName == "Humanoid" then
                local model = instance.Parent
                if typeof(model) == "Instance" and model:IsA("Model")
                    and model ~= localPlayer.Character
                    and not Players:GetPlayerFromCharacter(model)
                then
                    local parent = model.Parent
                    local key = parent and parent:GetFullName() or "nil"
                    if not counts[key] then
                        counts[key] = 0
                        samples[key] = model.Name
                        order[#order + 1] = key
                    end
                    counts[key] += 1
                end
            end

            if index % 3000 == 0 then
                task.wait()
            end
        end

        table.sort(order, function(a, b) return counts[a] > counts[b] end)

        if #order == 0 then
            say("No non-player Humanoid models found. Try 'Require Humanoid' off.")
        else
            for rank = 1, math.min(#order, 5) do
                local key = order[rank]
                say(("%s  x%d  (e.g. %s)"):format(key, counts[key], samples[key]))
            end
        end
        detectBusy = false
    end)
end

local function trackPlayer(player)
    if player == localPlayer or playerConns[player] then return end

    local conns = {}
    playerConns[player] = conns

    local function onCharacter(character)
        if character then
            addRecord(character, "Player", player)
        end
    end

    conns[1] = player.CharacterAdded:Connect(onCharacter)
    conns[2] = player.CharacterRemoving:Connect(removeRecord)
    onCharacter(player.Character)

    task.spawn(function()
        local ok, result = pcall(localPlayer.IsFriendsWith, localPlayer, player.UserId)
        if ok and state.alive and playerConns[player] == conns then
            friendCache[player.UserId] = result == true
        end
    end)
end

local function untrackPlayer(player)
    local conns = playerConns[player]
    if conns then
        disconnectList(conns)
        playerConns[player] = nil
    end
    if player.Character then
        removeRecord(player.Character)
    end
    friendCache[player.UserId] = nil
end

parseIgnore()

for _, player in ipairs(Players:GetPlayers()) do
    trackPlayer(player)
end

connect(Players.PlayerAdded, trackPlayer)
connect(Players.PlayerRemoving, untrackPlayer)

connect(Workspace.DescendantAdded, function(instance)
    if not npcTracking() then return end
    local model = candidateModel(instance)
    if model then
        considerNpc(model)
    end
end)

connect(Workspace.DescendantRemoving, function(instance)
    if records[instance] then
        removeRecord(instance)
    end
end)

-- A previous version's hook cannot be restored here; disable its pass-through state.
do
    local oldBridge = env.FORGE_NAMECALL_BRIDGE
    if type(oldBridge) == "table" then
        oldBridge.Enabled = false
        oldBridge.Camera = nil
        oldBridge.Position = nil
    end
end

-- Temporary optical zoom, independent of any game-specific scope implementation.
-- A high-priority action sinks the wheel only while the configured key is held.
do
    local actions = game:GetService("ContextActionService")
    local actionName = "ForgeScope_" .. HttpService:GenerateGUID(false)
    local scope = { held = false }

    local function stopScope()
        actions:UnbindAction(actionName)
        if scope.camera and scope.camera.Parent and scope.lastWritten
            and math.abs(scope.camera.FieldOfView - scope.lastWritten) < 0.05 then
            scope.camera.FieldOfView = scope.base
        end
        scope.held, scope.camera, scope.lastWritten = false, nil, nil
    end

    local function wheel(_, inputState, input)
        if inputState == Enum.UserInputState.Change and scope.held
            and CONFIG.ScopeEnabled and not UserInputService:GetFocusedTextBox() then
            local minimum = math.clamp(CONFIG.ScopeMinFov, 1, scope.base)
            scope.target = math.clamp(scope.target - input.Position.Z * CONFIG.ScopeStep, minimum, scope.base)
            return Enum.ContextActionResult.Sink
        end
        return Enum.ContextActionResult.Pass
    end

    function state.scopeBegin(input)
        if not CONFIG.ScopeEnabled or scope.held or input.KeyCode.Name ~= CONFIG.ScopeKey then return end
        local camera = Workspace.CurrentCamera
        if not camera then return end
        scope.held, scope.camera = true, camera
        scope.base, scope.target, scope.lastWritten = camera.FieldOfView, camera.FieldOfView, nil
        actions:BindActionAtPriority(actionName, wheel, false, 3000, Enum.UserInputType.MouseWheel)
    end
    function state.scopeEnd(input)
        if scope.held and input.KeyCode.Name == CONFIG.ScopeKey then stopScope() end
    end
    function state.scopeUpdate(dt, camera)
        if not scope.held then return end
        if not CONFIG.ScopeEnabled or camera ~= scope.camera then stopScope() return end
        -- Respect game-side changes when another camera script writes an FOV.
        local current = camera.FieldOfView
        if scope.lastWritten and math.abs(current - scope.lastWritten) > 0.05 then
            scope.base = current
            scope.target = math.min(scope.target, scope.base)
            current = scope.lastWritten -- keep smoothing even if the game writes every frame
        end
        local alpha = 1 - math.exp(-CONFIG.ScopeResponse * dt)
        local nextFov = current + (scope.target - current) * alpha
        camera.FieldOfView = math.clamp(nextFov, 1, 120)
        scope.lastWritten = camera.FieldOfView
    end
    state.scopeStop = stopScope
end

-- UI toolkit --------------------------------------------------------------

local function newInstance(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function merge(base, extra)
    for key, value in pairs(extra) do
        base[key] = value
    end
    return base
end

-- radius: number of pixels or a UDim. Returns the UIStroke when a stroke color is given.
local function styleFrame(frame, radius, strokeColor, strokeTransparency)
    if radius then
        newInstance("UICorner", {
            CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius),
        }, frame)
    end
    if strokeColor then
        return newInstance("UIStroke", {
            Color = strokeColor,
            Thickness = 1,
            Transparency = strokeTransparency or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, frame)
    end
    return nil
end

local function newLabel(parent, props)
    return newInstance("TextLabel", merge({
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = THEME.Font,
        Text = "",
        TextSize = 12,
        TextColor3 = THEME.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, props), parent)
end

-- Auto-sizing chip.
local function newPill(parent, props)
    local pill = newInstance("TextLabel", merge({
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.fromOffset(0, 22),
        BackgroundColor3 = THEME.Panel,
        BackgroundTransparency = 0.1,
        BorderSizePixel = 0,
        Font = THEME.FontBold,
        Text = "",
        TextSize = 11,
        TextColor3 = THEME.Text,
        RichText = true,
    }, props), parent)
    newInstance("UIPadding", {
        PaddingLeft = UDim.new(0, 9),
        PaddingRight = UDim.new(0, 9),
    }, pill)
    local stroke = styleFrame(pill, nil, THEME.Stroke)
    return pill, stroke
end

local function newButton(parent, props)
    local button = newInstance("TextButton", merge({
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        Font = THEME.FontBold,
        Text = "",
        TextSize = 11,
        TextColor3 = THEME.Text,
        AutoButtonColor = true,
    }, props), parent)
    local stroke = styleFrame(button, nil, THEME.Stroke)
    return button, stroke
end

local function easeOut(t)
    return 1 - (1 - t) * (1 - t) * (1 - t)
end

-- Overlay -----------------------------------------------------------------

local overlay = Instance.new("ScreenGui")
overlay.Name = "ForgeOverlay"
overlay.ResetOnSpawn = false
overlay.IgnoreGuiInset = true
overlay.ScreenInsets = Enum.ScreenInsets.None
overlay.DisplayOrder = 100
overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
overlay.Parent = playerGui

local ring = newInstance("Frame", {
    Name = "Fov",
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Visible = false,
}, overlay)
newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
newInstance("UIStroke", { Color = THEME.Accent, Thickness = 1, Transparency = 0.35 }, ring)

local arrow = newLabel(overlay, {
    Name = "TargetArrow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(32, 30),
    Font = THEME.FontBold,
    Text = "▼",
    TextSize = 25,
    TextColor3 = THEME.Bad,
    TextStrokeColor3 = Color3.new(0, 0, 0),
    TextXAlignment = Enum.TextXAlignment.Center,
    Visible = false,
})

-- Target HUD
local hud = newInstance("Frame", {
    Name = "TargetHud",
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 56),
    Size = UDim2.fromOffset(300, 92),
    BackgroundColor3 = X64UI.Theme.Background,
    BorderColor3 = X64UI.Theme.Border,
    BorderSizePixel = 1,
    Visible = false,
}, overlay)
local hudInfo = {}
hudInfo.header = newInstance("Frame", {
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundColor3 = X64UI.Theme.TitleBar,
    BorderSizePixel = 0,
}, hud)
hudInfo.title = newLabel(hudInfo.header, {
    Position = UDim2.fromOffset(7, 0),
    Size = UDim2.new(1, -14, 1, 0),
    Font = Enum.Font.Code,
    Text = "TARGET PROFILE",
    TextSize = 13,
    TextColor3 = X64UI.Theme.AccentText,
})
hudInfo.kind = newLabel(hudInfo.header, {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -7, 0, 0),
    Size = UDim2.fromOffset(72, 22),
    Font = Enum.Font.Code,
    TextSize = 12,
    TextColor3 = X64UI.Theme.Dim,
    TextXAlignment = Enum.TextXAlignment.Right,
})

local hudName = newLabel(hud, {
    Position = UDim2.fromOffset(8, 29),
    Size = UDim2.new(1, -92, 0, 17),
    Font = Enum.Font.Code,
    TextSize = 14,
    TextColor3 = X64UI.Theme.Text,
    TextTruncate = Enum.TextTruncate.AtEnd,
})
local hudDist = newLabel(hud, {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -8, 0, 30),
    Size = UDim2.fromOffset(80, 16),
    Font = Enum.Font.Code,
    TextSize = 12,
    TextColor3 = X64UI.Theme.Dim,
    TextXAlignment = Enum.TextXAlignment.Right,
})
local hudBarBack = newInstance("Frame", {
    Position = UDim2.fromOffset(8, 75),
    Size = UDim2.new(1, -16, 0, 7),
    BackgroundColor3 = X64UI.Theme.PanelAlt,
    BorderSizePixel = 0,
}, hud)
local hudBarFill = newInstance("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = X64UI.Theme.Accent,
    BorderSizePixel = 0,
}, hudBarBack)
local hudHp = newLabel(hud, {
    Position = UDim2.fromOffset(8, 53),
    Size = UDim2.new(0.6, 0, 0, 16),
    Font = Enum.Font.Code,
    TextColor3 = X64UI.Theme.Text,
    TextSize = 12,
})
local hudBadge = newLabel(hud, {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -8, 0, 53),
    Size = UDim2.fromOffset(100, 16),
    Font = Enum.Font.Code,
    TextColor3 = X64UI.Theme.Dim,
    TextSize = 12,
    TextTruncate = Enum.TextTruncate.AtEnd,
    TextXAlignment = Enum.TextXAlignment.Right,
})

-- Radar
local radarFrame = newInstance("Frame", {
    Name = "Radar",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 16, 1, -16),
    Size = UDim2.fromOffset(CONFIG.RadarSize, CONFIG.RadarSize),
    BackgroundColor3 = THEME.Panel,
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
    Visible = false,
}, overlay)
styleFrame(radarFrame, UDim.new(1, 0), THEME.Stroke)

local radarInner = newInstance("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromScale(0.5, 0.5),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, radarFrame)
styleFrame(radarInner, UDim.new(1, 0), THEME.Stroke, 0.5)

local radarH = newInstance("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(1, -8, 0, 1),
    BackgroundColor3 = THEME.Stroke,
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
}, radarFrame)
local radarV = newInstance("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0, 1, 1, -8),
    BackgroundColor3 = THEME.Stroke,
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
}, radarFrame)

local radarNorth = newLabel(radarFrame, {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(14, 14),
    Font = THEME.FontBold,
    Text = "N",
    TextSize = 10,
    TextColor3 = THEME.Muted,
    TextXAlignment = Enum.TextXAlignment.Center,
    ZIndex = 2,
})

local radarSelf = newInstance("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(8, 8),
    BackgroundColor3 = THEME.Accent,
    BorderSizePixel = 0,
    ZIndex = 4,
}, radarFrame)
styleFrame(radarSelf, UDim.new(1, 0), THEME.Panel)

local radarDots = {} -- [record] = Frame

-- CCTV monitor ------------------------------------------------------------
-- Scoped in a do-block so its ~90 locals do not count toward the main chunk's
-- 200-local limit. Names used after the block are forward-declared here.

local cctv, cctvFrame, drag
local CCTV_MODES, CCTV_DEFAULT_POSITION, CCTV_DEFAULT_SIZE
local closeCctv, switchCctv, updateCctv

do
CCTV_DEFAULT_POSITION = UDim2.fromOffset(16, 16)
CCTV_DEFAULT_SIZE = UDim2.fromOffset(380, 270)
local CCTV_MIN = Vector2.new(260, 190)
local CCTV_MAX = Vector2.new(960, 700)
CCTV_MODES = { "Behind", "Front", "Overhead", "Orbit" }
local FULL = UDim2.fromScale(1, 1)

cctv = {
    rec = nil,
    camCF = nil,
    dir = nil,
    live = nil,
    liveFor = nil,
    selfLive = nil,
    selfFor = nil,
    others = {},          -- [record] = live clone
    othersAt = 0,
    othersSyncAt = 0,
    othersPending = {},
    scene = nil,
    sceneOrigin = nil,    -- [clone] = original part (weak)
    sceneCenter = nil,
    sceneAt = 0,
    sceneToken = 0,
    sceneBusy = false,
    terrain = nil,
    terrainCenter = nil,
    terrainAt = 0,
    terrainToken = 0,
    terrainBusy = false,
    skyClone = nil,
    skySource = nil,
    envAt = -math.huge,
    lostAt = nil,
    anim = 0,
    closing = false,
    dismissed = nil,
    flash = 0,
    selfRecord = nil,
    selfDismissed = false,
    locationAt = 0,
}

cctvFrame = newInstance("Frame", {
    Name = "CctvFeed",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = CCTV_DEFAULT_POSITION,
    Size = CCTV_DEFAULT_SIZE,
    Visible = false,
}, overlay)

local panel = newInstance("Frame", {
    Name = "Panel",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(2, 2),
    BackgroundColor3 = THEME.PanelAlt,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, cctvFrame)
local content = newInstance("Frame", {
    Name = "Content",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = CCTV_DEFAULT_SIZE,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Visible = false,
}, panel)

local viewArea = newInstance("Frame", {
    Name = "View",
    Position = UDim2.fromOffset(0, 0),
    Size = FULL,
    BackgroundColor3 = Color3.new(0, 0, 0),
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
}, content)

local feed = newInstance("ViewportFrame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = FULL,
    BackgroundColor3 = CONFIG.CCTVBackground,
    BorderSizePixel = 0,
    Ambient = Color3.fromRGB(150, 150, 150),
    LightColor = Color3.new(1, 1, 1),
    LightDirection = Vector3.new(-1, -2, -1),
    ZIndex = 1,
}, viewArea)

local feedCamera = newInstance("Camera", { FieldOfView = CONFIG.CCTVFov }, feed)
feed.CurrentCamera = feedCamera

local locationLabel = newLabel(viewArea, {
    Name = "SelfLocation",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 8, 1, -8),
    Size = UDim2.new(1, -36, 0, 20),
    BackgroundColor3 = X64UI.Theme.Background,
    BackgroundTransparency = 0.2,
    Font = Enum.Font.Code,
    TextSize = 13,
    TextColor3 = X64UI.Theme.Text,
    TextStrokeTransparency = 0.4,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 8,
    Visible = false,
})

local noSignal = newInstance("Frame", {
    Size = FULL,
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 6,
}, viewArea)

local inputSurface = newInstance("TextButton", {
    Name = "InputSurface",
    Size = FULL,
    Text = "",
    AutoButtonColor = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 10,
}, content)

local resizeGrip = newInstance("TextButton", {
    Name = "ResizeGrip",
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.fromScale(1, 1),
    Size = UDim2.fromOffset(CONFIG.CCTVResizeGrip, CONFIG.CCTVResizeGrip),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "◢",
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextColor3 = Color3.new(1, 1, 1),
    TextStrokeColor3 = Color3.new(0, 0, 0),
    TextStrokeTransparency = 0.15,
    ZIndex = 11,
}, content)

local flashFrame = newInstance("Frame", {
    Size = FULL,
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 20,
    Active = false,
}, panel)

-- Drag and resize (`drag` is forward-declared above)
local function beginCctvDrag(mode, input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local mouse = UserInputService:GetMouseLocation()
    local screen = overlay.AbsoluteSize
    local current = cctvFrame.Position
    local position = Vector2.new(
        current.X.Scale * screen.X + current.X.Offset,
        current.Y.Scale * screen.Y + current.Y.Offset
    )
    local size = cctvFrame.AbsoluteSize
    drag = {
        mode = mode,
        from = mouse,
        position = position,
        size = size,
    }
end

connect(inputSurface.InputBegan, function(input)
    beginCctvDrag("move", input)
end)
connect(resizeGrip.InputBegan, function(input)
    beginCctvDrag("size", input)
end)

connect(UserInputService.InputChanged, function(input)
    if not drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

    local delta = UserInputService:GetMouseLocation() - drag.from
    local screen = overlay.AbsoluteSize

    if drag.mode == "move" then
        local position = drag.position + delta
        cctvFrame.Position = UDim2.fromOffset(
            math.clamp(position.X, math.min(0, drag.position.X), math.max(screen.X - drag.size.X, drag.position.X, 0)),
            math.clamp(position.Y, math.min(0, drag.position.Y), math.max(screen.Y - drag.size.Y, drag.position.Y, 0))
        )
    else
        local size = drag.size + delta
        local available = screen - drag.position
        local maxX = math.max(CCTV_MIN.X, math.min(CCTV_MAX.X, available.X))
        local maxY = math.max(CCTV_MIN.Y, math.min(CCTV_MAX.Y, available.Y))
        cctvFrame.Size = UDim2.fromOffset(
            math.clamp(size.X, CCTV_MIN.X, maxX),
            math.clamp(size.Y, CCTV_MIN.Y, maxY)
        )
    end
end)

connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        drag = nil
    end
end)

-- Cloning helpers
local function cloneInstance(instance)
    if instance.Archivable then
        local ok, clone = pcall(instance.Clone, instance)
        return ok and clone or nil
    end
    if not CONFIG.CCTVForceArchivable then
        return nil
    end
    -- Temporary client-side flag flip; restored immediately after the clone.
    if not pcall(function() instance.Archivable = true end) then
        return nil
    end
    local ok, clone = pcall(instance.Clone, instance)
    pcall(function() instance.Archivable = false end)
    return ok and clone or nil
end

local function stripLive(clone)
    for _, descendant in ipairs(clone:GetDescendants()) do
        if descendant:IsA("LuaSourceContainer") or descendant:IsA("Sound")
            or descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui")
            or descendant:IsA("ParticleEmitter") or descendant:IsA("Animator")
            or descendant:IsA("ForceField")
        then
            descendant:Destroy()
        elseif descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanQuery = false
            descendant.CanTouch = false
        elseif descendant:IsA("Humanoid") then
            descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end
    end
end

local function pairParts(original, clone, out)
    local used = {}
    for _, child in ipairs(original:GetChildren()) do
        local match
        for _, candidate in ipairs(clone:GetChildren()) do
            if not used[candidate]
                and candidate.Name == child.Name
                and candidate.ClassName == child.ClassName
            then
                match = candidate
                used[candidate] = true
                break
            end
        end
        if match then
            if child:IsA("BasePart") then
                out[#out + 1] = { child, match }
            end
            pairParts(child, match, out)
        end
    end
end

local function buildLive(model)
    local clone = cloneInstance(model)
    if not clone then return nil end

    stripLive(clone)
    local list = {}
    pairParts(model, clone, list)
    clone.Parent = feed
    return { model = clone, pairs = list }
end

local function syncLive(live)
    if not live then return end
    for _, pair in ipairs(live.pairs) do
        local original = pair[1]
        if original.Parent then
            pair[2].CFrame = original.CFrame
        end
    end
end

local function destroyLive(live)
    if live then
        live.model:Destroy()
    end
end

local function destroyOthers()
    for _, live in pairs(cctv.others) do
        destroyLive(live)
    end
    table.clear(cctv.others)
    table.clear(cctv.othersPending)
end

local function syncOthers(center, now)
    if not CONFIG.CCTVOthers then
        if next(cctv.others) then
            destroyOthers()
        end
        return
    end

    if now - cctv.othersAt >= 1 then
        cctv.othersAt = now

        local candidates = {}
        local radiusSquared = CONFIG.CCTVRadius * CONFIG.CCTVRadius
        for _, rec in pairs(records) do
            if rec ~= cctv.rec and isAlive(rec) then
                local root = partOf(rec, "HumanoidRootPart")
                if root then
                    local offset = root.Position - center
                    local distanceSquared = offset:Dot(offset)
                    if distanceSquared <= radiusSquared then
                        candidates[#candidates + 1] = { rec, distanceSquared }
                    end
                end
            end
        end
        table.sort(candidates, function(a, b) return a[2] < b[2] end)

        local keep = {}
        for index = 1, math.min(#candidates, CONFIG.CCTVMaxOthers) do
            keep[candidates[index][1]] = true
        end

        for rec, live in pairs(cctv.others) do
            if not keep[rec] then
                destroyLive(live)
                cctv.others[rec] = nil
            end
        end
        table.clear(cctv.othersPending)
        for index = 1, math.min(#candidates, CONFIG.CCTVMaxOthers) do
            local rec = candidates[index][1]
            if not cctv.others[rec] then
                cctv.othersPending[#cctv.othersPending + 1] = rec
            end
        end
    end

    -- At most one expensive model clone per frame, rather than 30 at once.
    local rec = table.remove(cctv.othersPending, 1)
    if rec and records[rec.model] == rec and rec.model.Parent then
        local ok, live = pcall(buildLive, rec.model)
        if ok and live then cctv.others[rec] = live end
    end
    if now - cctv.othersSyncAt >= 1 / 30 then
        cctv.othersSyncAt = now
        for _, live in pairs(cctv.others) do
            syncLive(live)
        end
    end
end

-- Retire old snapshots in slices; destroying thousands of parts at once hitches.
local function retireFolder(folder)
    if not folder then return end
    task.spawn(function()
        local children = folder:GetChildren()
        for index, child in ipairs(children) do
            child:Destroy()
            if index % 20 == 0 then task.wait() end
        end
        folder:Destroy()
    end)
end

-- Static part snapshot (batched so cloning never hitches a frame)
local function cloneScenePart(part)
    if part.Transparency >= 0.99 or part:IsA("Terrain") then return nil end

    -- Tracked characters are only ever shown as live clones, never as frozen ghosts.
    local ancestor = part.Parent
    while ancestor and ancestor ~= Workspace do
        if records[ancestor] then return nil end
        ancestor = ancestor.Parent
    end

    local clone = cloneInstance(part)
    if not clone then return nil end

    for _, child in ipairs(clone:GetChildren()) do
        if not (child:IsA("DataModelMesh") or child:IsA("Decal") or child:IsA("Texture")
            or child:IsA("SurfaceAppearance") or child:IsA("Light"))
        then
            child:Destroy()
        end
    end

    clone.Anchored = true
    clone.CanCollide = false
    clone.CanQuery = false
    clone.CanTouch = false
    return clone
end

local function syncSceneParts(folder, entries, token)
    task.spawn(function()
        local index = 1
        while state.alive and token == cctv.sceneToken and cctv.scene == folder do
            local stopAt = math.min(index + math.max(1, CONFIG.CCTVSceneSyncPerStep) - 1, #entries)
            for i = index, stopAt do
                local original, clone = entries[i][1], entries[i][2]
                if not original:IsDescendantOf(Workspace) then
                    if clone.Parent then clone:Destroy() end
                elseif clone.Parent then
                    if clone.CFrame ~= original.CFrame then clone.CFrame = original.CFrame end
                    if clone.Size ~= original.Size then clone.Size = original.Size end
                    if clone.Color ~= original.Color then clone.Color = original.Color end
                    if clone.Transparency ~= original.Transparency then clone.Transparency = original.Transparency end
                    if clone.Material ~= original.Material then clone.Material = original.Material end
                end
            end
            index = stopAt + 1
            if index > #entries then
                index = 1
                task.wait(0.1)
            else
                task.wait()
            end
        end
    end)
end

do
    local registry = {}
    local connections = {}
    local generation = 0
    local active = false
    local function stopRegistry()
        if not active then return end
        active = false
        generation += 1
        for _, connection in ipairs(connections) do connection:Disconnect() end
        table.clear(connections)
        table.clear(registry)
    end
    local function startRegistry()
        if active then return end
        active = true
        generation += 1
        local token = generation
        local function add(instance)
            if instance:IsA("BasePart") and not instance:IsA("Terrain") then
                registry[instance] = true
                cctv.sceneDirty = true
            end
        end
        connections[1] = Workspace.DescendantAdded:Connect(add)
        connections[2] = Workspace.DescendantRemoving:Connect(function(instance)
            if registry[instance] then
                registry[instance] = nil
                cctv.sceneDirty = true
            end
        end)
        task.spawn(function()
            local list = Workspace:GetDescendants()
            for i, instance in ipairs(list) do
                if not state.alive or not active or generation ~= token then return end
                if instance:IsDescendantOf(Workspace) then add(instance) end
                if i % 500 == 0 then task.wait() end
            end
        end)
    end
    function cctv.sceneTracking(activeWanted)
        if activeWanted then startRegistry() else stopRegistry() end
    end
    function cctv.addNonQueryable(entries, center, radius, token)
        if not active then return end
        local scanned = 0
        local radius2 = radius * radius
        for part in pairs(registry) do
            if not state.alive or token ~= cctv.sceneToken then return end
            local character = localPlayer.Character
            local target = cctv.rec and cctv.rec.model
            if part.Parent and not part.CanQuery and part:IsDescendantOf(Workspace)
                and not (character and part:IsDescendantOf(character))
                and not (target and part:IsDescendantOf(target))
            then
                local offset = part.Position - center
                local distance = offset:Dot(offset)
                if distance <= radius2 then entries[#entries + 1] = { part, distance } end
            end
            scanned += 1
            if scanned % 300 == 0 then task.wait() end
        end
    end
end

local function rebuildScene(center, targetModel)
    cctv.sceneToken += 1
    local token = cctv.sceneToken
    cctv.sceneBusy = true
    cctv.sceneCenter = center
    cctv.sceneAt = os.clock()
    cctv.sceneDirty = false

    local ignore = { targetModel }
    if localPlayer.Character then
        ignore[#ignore + 1] = localPlayer.Character
    end

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.MaxParts = math.max(CONFIG.CCTVMaxParts, math.floor(CONFIG.CCTVMaxParts * CONFIG.CCTVSceneQueryMultiplier))

    task.spawn(function()
        -- Keep the spatial query and sorting out of the render callback.
        task.wait()
        if token ~= cctv.sceneToken or not state.alive then return end
        local ok, found = pcall(Workspace.GetPartBoundsInRadius, Workspace, center, CONFIG.CCTVRadius, params)
        if not ok then
            if token == cctv.sceneToken then
                cctv.sceneBusy = false
                cctv.sceneAt = os.clock()
            end
            return
        end
        local entries = table.create(#found)
        for index, part in ipairs(found) do
            local offset = part.Position - center
            entries[index] = { part, offset:Dot(offset) }
            if index % 300 == 0 then
                task.wait()
                if token ~= cctv.sceneToken or not state.alive then return end
            end
        end
        if CONFIG.CCTVSceneTracking then
            cctv.addNonQueryable(entries, center, CONFIG.CCTVRadius, token)
            if token ~= cctv.sceneToken or not state.alive then return end
        end
        table.sort(entries, function(a, b) return a[2] < b[2] end)
        local folder = Instance.new("Folder")
        folder.Name = "Scene"
        if not cctv.scene then folder.Parent = feed end
        local origin = setmetatable({}, { __mode = "k" })
        local synced = {}
        local sliceStart = os.clock()
        for index = 1, #entries do
            if #synced >= CONFIG.CCTVMaxParts then break end
            if token ~= cctv.sceneToken or not state.alive then
                retireFolder(folder)
                return
            end

            local original = entries[index][1]
            if original.Parent then
                local clone = cloneScenePart(original)
                if clone then
                    clone.Parent = folder
                    origin[clone] = original
                    synced[#synced + 1] = { original, clone }
                end
            end

            if index % 10 == 0 or os.clock() - sliceStart > 0.002 then
                task.wait()
                sliceStart = os.clock()
            end
        end

        if token ~= cctv.sceneToken or not state.alive then
            retireFolder(folder)
            return
        end

        local old = cctv.scene
        cctv.scene = folder
        cctv.sceneOrigin = origin
        if old then old.Parent = nil end
        folder.Parent = feed
        retireFolder(old)
        syncSceneParts(folder, synced, token)
        cctv.sceneAt = os.clock()
        cctv.sceneBusy = false
    end)
end

-- Terrain approximation (ViewportFrame cannot render Terrain itself)
local TERRAIN_TILE = 8 -- smaller reads reduce worst-case per-call stalls
local AIR, WATER = Enum.Material.Air, Enum.Material.Water

local function terrainSolid(materials, occupancies, x, y, z)
    local material = materials[x][y][z]
    return material ~= AIR and material ~= WATER and occupancies[x][y][z] >= 0.5
end

local function buildTerrain(center)
    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if not terrain then return end

    cctv.terrainToken += 1
    local token = cctv.terrainToken
    cctv.terrainBusy = true
    cctv.terrainCenter = center
    cctv.terrainAt = os.clock()

    local radius = CONFIG.CCTVTerrainRadius
    local halfHeight = CONFIG.CCTVTerrainHeight
    local totalX = math.ceil(radius * 2 / 4)
    local totalY = math.ceil(halfHeight * 2 / 4)
    local originX = math.floor((center.X - radius) / 4) * 4
    local originY = math.floor((center.Y - halfHeight) / 4) * 4
    local originZ = math.floor((center.Z - radius) / 4) * 4
    local maxParts = CONFIG.CCTVTerrainMaxParts
    local waterColor = terrain.WaterColor
    local waterTransparency = math.max(terrain.WaterTransparency, 0.25)
    local colors = {}

    task.spawn(function()
        task.wait()
        local folder = Instance.new("Folder")
        folder.Name = "TerrainApprox"
        if not cctv.terrain then folder.Parent = feed end

        local count, processed = 0, 0
        local stop = false

        local function cancelled()
            return token ~= cctv.terrainToken or not state.alive
        end

        local function emitRun(minCorner, iy, iz, startIx, length, material, height, slope)
            if count >= maxParts then
                stop = true
                return
            end
            count += 1

            local part = Instance.new(slope and "WedgePart" or "Part")
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
            part.CastShadow = false
            part.Size = Vector3.new(length * 4, 4 * height, 4)
            part.Position = Vector3.new(
                minCorner.X + (startIx - 2 + length * 0.5) * 4,
                minCorner.Y + (iy - 2) * 4 + 2 * height,
                minCorner.Z + (iz - 2) * 4 + 2
            )
            if slope then
                part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, slope, 0)
            end

            if material == WATER then
                part.Material = Enum.Material.SmoothPlastic
                part.Color = waterColor
                part.Transparency = waterTransparency
            else
                local color = colors[material]
                if not color then
                    color = terrain:GetMaterialColor(material)
                    colors[material] = color
                end
                part.Material = material
                part.Color = color
            end

            part.Parent = folder
        end

        local tiles = {}
        for tileX = 0, totalX - 1, TERRAIN_TILE do
            for tileZ = 0, totalX - 1, TERRAIN_TILE do
                local width = math.min(TERRAIN_TILE, totalX - tileX)
                local depth = math.min(TERRAIN_TILE, totalX - tileZ)
                local dx = originX + (tileX + width * 0.5) * 4 - center.X
                local dz = originZ + (tileZ + depth * 0.5) * 4 - center.Z
                tiles[#tiles + 1] = { tileX, tileZ, dx * dx + dz * dz }
            end
        end
        table.sort(tiles, function(a, b) return a[3] < b[3] end)
        for _, tile in ipairs(tiles) do
                if stop then break end
                local tileX, tileZ = tile[1], tile[2]
                if cancelled() then
                    retireFolder(folder)
                    return
                end

                local innerX = math.min(TERRAIN_TILE, totalX - tileX)
                local innerZ = math.min(TERRAIN_TILE, totalX - tileZ)
                local minCorner = Vector3.new(originX + tileX * 4, originY, originZ + tileZ * 4)
                -- One-cell margin on every side so edge cells can test their neighbors.
                local region = Region3.new(
                    minCorner - Vector3.new(4, 4, 4),
                    minCorner + Vector3.new(innerX * 4 + 4, totalY * 4 + 4, innerZ * 4 + 4)
                )

                local ok, materials, occupancies = pcall(terrain.ReadVoxels, terrain, region, 4)
                if ok and materials and occupancies then
                    local sizeX, sizeY, sizeZ = innerX + 2, totalY + 2, innerZ + 2

                    for iz = 2, sizeZ - 1 do
                        if stop then break end
                        for iy = 2, sizeY - 1 do
                            if stop then break end

                            local runMaterial, runHeight, runStart
                            for ix = 2, sizeX do
                                local material, height, slope

                                if ix < sizeX then
                                    local cellMaterial = materials[ix][iy][iz]
                                    local occupancy = occupancies[ix][iy][iz]

                                    if cellMaterial ~= AIR and occupancy >= 0.05 then
                                        local exposed
                                        if cellMaterial == WATER then
                                            exposed = materials[ix][iy + 1][iz] ~= WATER
                                        else
                                            exposed = not (
                                                terrainSolid(materials, occupancies, ix - 1, iy, iz)
                                                and terrainSolid(materials, occupancies, ix + 1, iy, iz)
                                                and terrainSolid(materials, occupancies, ix, iy - 1, iz)
                                                and terrainSolid(materials, occupancies, ix, iy + 1, iz)
                                                and terrainSolid(materials, occupancies, ix, iy, iz - 1)
                                                and terrainSolid(materials, occupancies, ix, iy, iz + 1)
                                            )
                                        end

                                        if exposed then
                                            material = cellMaterial
                                            height = math.clamp(math.floor(occupancy * 4 + 0.5) / 4, 0.25, 1)
                                            if CONFIG.CCTVSmoothTerrain and cellMaterial ~= WATER
                                                and not terrainSolid(materials, occupancies, ix, iy + 1, iz)
                                            then
                                                local xDiff = occupancies[ix + 1][iy][iz] - occupancies[ix - 1][iy][iz]
                                                local zDiff = occupancies[ix][iy][iz + 1] - occupancies[ix][iy][iz - 1]
                                                if math.max(math.abs(xDiff), math.abs(zDiff)) >= 0.45 then
                                                    if math.abs(xDiff) > math.abs(zDiff) then
                                                        slope = xDiff > 0 and math.pi * 0.5 or -math.pi * 0.5
                                                    else
                                                        slope = zDiff > 0 and 0 or math.pi
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end

                                -- Greedy merge along X: same material and height share one part.
                                if material ~= runMaterial or height ~= runHeight or slope then
                                    if runMaterial then
                                        emitRun(minCorner, iy, iz, runStart, ix - runStart, runMaterial, runHeight)
                                    end
                                    if slope then
                                        emitRun(minCorner, iy, iz, ix, 1, material, height, slope)
                                        runMaterial, runHeight, runStart = nil, nil, nil
                                    else
                                        runMaterial, runHeight, runStart = material, height, ix
                                    end
                                end
                            end

                            processed += sizeX
                            if processed >= 1200 then
                                processed = 0
                                task.wait()
                                if cancelled() then
                                    retireFolder(folder)
                                    return
                                end
                            end
                        end
                    end
                end

                task.wait()
        end

        if cancelled() then
            retireFolder(folder)
            return
        end

        local old = cctv.terrain
        cctv.terrain = folder
        if old then old.Parent = nil end
        folder.Parent = feed
        retireFolder(old)
        cctv.terrainAt = os.clock()
        cctv.terrainBusy = false
    end)
end

-- Sky, lighting
local function scaleColor(color, factor)
    return Color3.new(
        math.clamp(color.R * factor, 0, 1),
        math.clamp(color.G * factor, 0, 1),
        math.clamp(color.B * factor, 0, 1)
    )
end

local function syncEnvironment()
    if CONFIG.CCTVMatchLighting then
        local sun = Lighting:GetSunDirection()
        local daylight = sun.Y > 0
        local direction = daylight and sun or Lighting:GetMoonDirection()
        local strength = daylight and math.clamp(sun.Y * 3, 0.2, 1) or 0.25
        local tint = Color3.new(1, 1, 1):Lerp(Lighting.ColorShift_Top, 0.5)

        feed.LightDirection = -direction -- light travels away from the sun
        feed.LightColor = scaleColor(tint, strength * math.clamp(Lighting.Brightness / 2, 0.4, 1.5))
        feed.Ambient = Lighting.Ambient:Lerp(Lighting.OutdoorAmbient, 0.5)
    end

    local wanted = CONFIG.CCTVSky and Lighting:FindFirstChildOfClass("Sky") or nil
    if wanted ~= cctv.skySource then
        if cctv.skyClone then
            cctv.skyClone:Destroy()
            cctv.skyClone = nil
        end
        cctv.skySource = wanted
        if wanted then
            local clone = cloneInstance(wanted)
            if clone then
                clone.Parent = feed
                cctv.skyClone = clone
            end
        end
    end
end

-- CCTV lifecycle ------------------------------------------------------------

local function releaseCctv()
    cctv.sceneTracking(false)
    drag = nil
    cctv.sceneToken += 1
    cctv.sceneBusy = false
    cctv.terrainToken += 1
    cctv.terrainBusy = false

    cctv.rec = nil
    cctv.camCF = nil
    cctv.dir = nil
    cctv.lostAt = nil
    cctv.liveFor = nil
    cctv.selfFor = nil
    cctv.sceneCenter = nil
    cctv.terrainCenter = nil
    cctv.skySource = nil
    cctv.envAt = -math.huge
    cctv.anim = 0
    cctv.closing = false
    cctv.flash = 0

    destroyLive(cctv.live)
    destroyLive(cctv.selfLive)
    cctv.live, cctv.selfLive = nil, nil
    destroyOthers()

    if cctv.scene then
        retireFolder(cctv.scene)
        cctv.scene = nil
    end
    cctv.sceneOrigin = nil

    if cctv.terrain then
        retireFolder(cctv.terrain)
        cctv.terrain = nil
    end

    if cctv.skyClone then
        cctv.skyClone:Destroy()
        cctv.skyClone = nil
    end

    feed.Size = FULL

    noSignal.Visible = false
    content.Visible = false
    cctvFrame.Visible = false
end

-- Animated close (the monitor collapses to a line, then a dot).
function closeCctv(manual)
    if not cctv.rec then return end
    if manual then
        cctv.dismissed = cctv.rec
        if CONFIG.CCTVSource == "Self" then
            cctv.selfDismissed = true
        end
    end
    cctv.closing = true
end

local function purgeFromScene(model)
    local origin = cctv.sceneOrigin
    if not origin then return end
    for clone, original in pairs(origin) do
        if original:IsDescendantOf(model) then
            clone:Destroy()
            origin[clone] = nil
        end
    end
end

-- Switching target keeps terrain, sky and your own clone; only target-specific state resets.
function switchCctv(rec)
    local wasOpen = cctv.anim > 0 and not cctv.closing

    destroyLive(cctv.live)
    cctv.live, cctv.liveFor = nil, nil
    destroyOthers()

    cctv.rec = rec
    cctv.camCF = nil
    cctv.dir = nil
    cctv.lostAt = nil
    cctv.closing = false
    cctv.dismissed = nil

    purgeFromScene(rec.model)
    cctv.sceneToken += 1 -- an in-flight snapshot still contains the new target
    cctv.sceneBusy = false
    cctv.sceneCenter = nil

    if wasOpen then
        cctv.flash = 0.7 -- channel change
    end
end

local function applyAnimation()
    local full = cctvFrame.AbsoluteSize
    local p = cctv.anim
    local widthT = easeOut(math.clamp(p / 0.4, 0, 1))
    local heightT = easeOut(math.clamp((p - 0.25) / 0.75, 0, 1))

    panel.Size = UDim2.fromOffset(math.max(full.X * widthT, 2), math.max(full.Y * heightT, 2))
    panel.BackgroundColor3 = Color3.new(1, 1, 1):Lerp(THEME.PanelAlt, math.clamp(heightT * 4, 0, 1))

    local showContent = heightT > 0.2
    if content.Visible ~= showContent then
        content.Visible = showContent
    end
    if showContent then
        local size = UDim2.fromOffset(full.X, full.Y)
        if content.Size ~= size then
            content.Size = size
        end
    end

    local openFlash = math.clamp(1 - math.abs(p - 0.3) / 0.2, 0, 1) * 0.5
    flashFrame.BackgroundTransparency = 1 - math.max(openFlash, cctv.flash)
end

function updateCctv(dt)
    local now = os.clock()
    cctv.sceneTracking(CONFIG.CCTVEnabled and CONFIG.CCTVSceneTracking and cctv.rec ~= nil and not cctv.closing)
    cctv.flash = math.max(cctv.flash - dt * 2.5, 0)

    local wantOpen = CONFIG.CCTVEnabled and cctv.rec ~= nil and not cctv.closing
    local speed = 1 / math.max(CONFIG.CCTVOpenSeconds, 0.05)
    if wantOpen then
        cctv.anim = math.min(cctv.anim + dt * speed, 1)
    else
        cctv.anim = math.max(cctv.anim - dt * speed * 1.6, 0)
    end

    if cctv.anim <= 0 then
        if cctv.rec or cctvFrame.Visible then
            releaseCctv()
        end
        return
    end

    cctvFrame.Visible = true
    applyAnimation()

    local rec = cctv.rec
    if not rec or not wantOpen then return end -- closing: the last frame stays frozen

    local registered = records[rec.model] == rec
        or (rec == cctv.selfRecord and rec.model == localPlayer.Character)
    local root = registered and rec.model:IsDescendantOf(Workspace)
        and isAlive(rec) and partOf(rec, "HumanoidRootPart") or nil
    if not root then
        cctv.lostAt = cctv.lostAt or now
        noSignal.Visible = true
        if now - cctv.lostAt > CONFIG.CCTVLostSeconds then
            closeCctv(false)
        end
        return
    end

    cctv.lostAt = nil
    noSignal.Visible = false

    local mode = CONFIG.CCTVMode

    -- Live characters
    if cctv.liveFor ~= rec then
        cctv.liveFor = rec
        destroyLive(cctv.live)
        cctv.live = buildLive(rec.model)
    end

    local character = localPlayer.Character
    if CONFIG.CCTVShowSelf and character and rec.model ~= character then
        if cctv.selfFor ~= character then
            cctv.selfFor = character
            destroyLive(cctv.selfLive)
            cctv.selfLive = buildLive(character)
        end
    elseif cctv.selfLive then
        destroyLive(cctv.selfLive)
        cctv.selfLive, cctv.selfFor = nil, nil
    end

    syncLive(cctv.live)
    syncLive(cctv.selfLive)
    syncOthers(root.Position, now)

    if now - cctv.envAt >= 0.5 then
        cctv.envAt = now
        syncEnvironment()
    end

    -- Camera
    local look = root.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then
        flat = cctv.dir or Vector3.new(0, 0, -1)
    end
    flat = flat.Unit

    if cctv.dir then
        local blended = cctv.dir:Lerp(flat, 1 - math.exp(-6 * dt))
        cctv.dir = blended.Magnitude > 0.05 and blended.Unit or flat
    else
        cctv.dir = flat
    end

    local distance, height = CONFIG.CCTVDistance, CONFIG.CCTVHeight
    local focus = root.Position + Vector3.new(0, 1.5, 0)
    local lift = Vector3.new(0, height, 0)
    local desired
    local smoothing = CONFIG.CCTVSmoothing

    if mode == "Overhead" then
        desired = CFrame.lookAt(root.Position + Vector3.new(0, distance * 2 + height, 0), focus, cctv.dir)
    elseif mode == "Orbit" then
        local angle = now * 0.6
        desired = CFrame.lookAt(
            root.Position + Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance),
            focus
        )
    elseif mode == "Front" then
        desired = CFrame.lookAt(root.Position + cctv.dir * distance + lift, focus)
    else
        desired = CFrame.lookAt(root.Position - cctv.dir * distance + lift, focus)
    end

    if cctv.camCF then
        cctv.camCF = cctv.camCF:Lerp(desired, 1 - math.exp(-smoothing * dt))
    else
        cctv.camCF = desired
    end

    local fovValue = CONFIG.CCTVFov

    if feed.Size ~= FULL then
        feed.Size = FULL
    end

    feedCamera.CFrame = cctv.camCF
    feedCamera.FieldOfView = fovValue
    feed.BackgroundColor3 = CONFIG.CCTVBackground
    locationLabel.Visible = CONFIG.CCTVShowLocation
    if locationLabel.Visible and now - cctv.locationAt >= 0.2 then
        cctv.locationAt = now
        local selfRoot = character and character:FindFirstChild("HumanoidRootPart")
        if selfRoot and selfRoot:IsA("BasePart") and selfRoot:IsDescendantOf(Workspace) then
            local p = selfRoot.Position
            locationLabel.Text = (" SELF  X %+.0f  Y %+.0f  Z %+.0f"):format(p.X, p.Y, p.Z)
        else
            locationLabel.Text = " SELF  LOCATION UNAVAILABLE"
        end
    end

    -- World streaming
    if not cctv.sceneBusy and not cctv.terrainBusy and (
        not cctv.sceneCenter
        or (CONFIG.CCTVSceneTracking and cctv.sceneDirty and now - cctv.sceneAt >= 1)
        or ((root.Position - cctv.sceneCenter).Magnitude > CONFIG.CCTVRadius * 0.35
            and now - cctv.sceneAt >= 1)
        or now - cctv.sceneAt > CONFIG.CCTVSceneRefresh
    ) then
        rebuildScene(root.Position, rec.model)
    end

    if CONFIG.CCTVTerrain then
        if not cctv.terrainBusy and not cctv.sceneBusy and (
            not cctv.terrainCenter
            or ((root.Position - cctv.terrainCenter).Magnitude > CONFIG.CCTVTerrainRadius * 0.4
                and now - cctv.terrainAt >= 1)
            or now - cctv.terrainAt > CONFIG.CCTVTerrainRefresh
        ) then
            buildTerrain(root.Position)
        end
    elseif cctv.terrain or cctv.terrainBusy then
        cctv.terrainToken += 1
        cctv.terrainBusy = false
        cctv.terrainCenter = nil
        if cctv.terrain then
            retireFolder(cctv.terrain)
            cctv.terrain = nil
        end
    end

end

end -- do CCTV monitor

-- Aim logic ---------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = false

local lastCharacter
local exclusions = {}

local function updateRayFilter()
    local character = localPlayer.Character
    if character == lastCharacter then return end
    lastCharacter = character
    table.clear(exclusions)
    if character then
        exclusions[1] = character
    end
    rayParams.FilterDescendantsInstances = exclusions
end

local function getCenter(camera)
    if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
        return camera.ViewportSize * 0.5
    end
    if UserInputService.MouseEnabled then
        return UserInputService:GetMouseLocation()
    end
    return camera.ViewportSize * 0.5
end

local function chooseTarget(camera)
    updateRayFilter()
    if UserInputService:GetFocusedTextBox() then return nil end
    local center = getCenter(camera)
    local origin = camera.CFrame.Position
    local radius = math.max(0, CONFIG.FovRadius)
    local maxDistance = math.max(0, CONFIG.MaxDistance)
    local bestRec, bestPart, bestScore
    for _, rec in pairs(records) do
        local allowed = rec.kind == "Player" and CONFIG.PlayersEnabled
            or rec.kind == "NPC" and CONFIG.NPCEnabled
        if allowed and rec.kind == "Player" then
            allowed = not playerIgnored(rec.player)
                and not (CONFIG.TeamCheck and localPlayer.Team and rec.player.Team == localPlayer.Team)
        end
        if allowed and rec.model:IsDescendantOf(Workspace) and isAlive(rec)
            and not (CONFIG.ForceFieldCheck and rec.model:FindFirstChildOfClass("ForceField"))
        then
            local target = partOf(rec, CONFIG.TargetPart)
            if target then
                local offset = target.Position - origin
                local distance = offset.Magnitude
                local projected, onScreen = camera:WorldToViewportPoint(target.Position)
                local dx, dy = projected.X - center.X, projected.Y - center.Y
                local score = dx * dx + dy * dy
                if projected.Z > 0 and onScreen and (radius == 0 or score <= radius * radius)
                    and (maxDistance == 0 or distance <= maxDistance)
                    and (not bestScore or score < bestScore)
                then
                    local blocked = false
                    if CONFIG.AimWallCheck and distance > 0.01 then
                        local hit = Workspace:Raycast(origin, offset, rayParams)
                        blocked = hit ~= nil and not hit.Instance:IsDescendantOf(rec.model)
                    end
                    if not blocked then
                        bestRec, bestPart, bestScore = rec, target, score
                    end
                end
            end
        end
    end
    return bestRec, bestPart
end

-- Line-of-sight color for ESP, throttled.
local lastSeenAt = 0

local function updateVisibility(now)
    if not (CONFIG.ESPEnabled and CONFIG.ESPVisibleCheck) or now - lastSeenAt < 0.2 then return end
    lastSeenAt = now

    local camera = Workspace.CurrentCamera
    if not camera then return end
    updateRayFilter()

    local origin = camera.CFrame.Position
    for _, rec in pairs(records) do
        local root = partOf(rec, "HumanoidRootPart")
        if root then
            local hit = Workspace:Raycast(origin, root.Position - origin, rayParams)
            rec.seen = hit == nil or hit.Instance:IsDescendantOf(rec.model)
        else
            rec.seen = false
        end
    end
end

local function invalidateSelection()
    clearTarget()
    state.selectElapsed = math.huge
end

-- Feature switches shared by the UI and the hotkeys
local function setEsp(value, fromUi)
    value = value == true
    CONFIG.ESPEnabled = value
    npcDirty = true
    if not fromUi then syncControl(espToggle, value) end
end

local function setCctv(value, fromUi)
    CONFIG.CCTVEnabled = value == true
    if CONFIG.CCTVEnabled then
        cctv.selfDismissed = false
    end
    state.selectElapsed = math.huge
    if not fromUi then syncControl(cctvToggle, CONFIG.CCTVEnabled) end
end

local hotkeys = {}
local function isAimActivation(input)
    local selected = CONFIG.AimActivation
    if selected == "MouseButton2" then return input.UserInputType == Enum.UserInputType.MouseButton2 end
    if selected == "MouseButton1" then return input.UserInputType == Enum.UserInputType.MouseButton1 end
    if selected == "MouseButton3" then return input.UserInputType == Enum.UserInputType.MouseButton3 end
    return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == selected
end

local function resolveHotkeys()
    local map = {
        Panic = CONFIG.PanicKey,
        ESP = CONFIG.ESPKey,
        CCTV = CONFIG.CCTVKey,
    }
    for slot, name in pairs(map) do
        local ok, code = pcall(function() return Enum.KeyCode[name] end)
        hotkeys[slot] = ok and code or nil
    end
end

resolveHotkeys()

connect(UserInputService.InputBegan, function(input, processed)
    if processed or UserInputService:GetFocusedTextBox() then return end
    state.scopeBegin(input)
    if isAimActivation(input) then
        state.aimHeld = true
        state.selectElapsed = math.huge
    end

    local key = input.KeyCode
    if key ~= Enum.KeyCode.Unknown then
        if key == hotkeys.Panic then
            shutdown()
            return
        end
        if key == hotkeys.ESP then setEsp(not CONFIG.ESPEnabled) end
        if key == hotkeys.CCTV then setCctv(not CONFIG.CCTVEnabled) end
    end

end)

connect(UserInputService.InputEnded, function(input)
    state.scopeEnd(input)
    if isAimActivation(input) then
        state.aimHeld = false
        invalidateSelection()
    end
end)

connect(UserInputService.WindowFocusReleased, function()
    state.scopeStop()
    state.aimHeld = false
    drag = nil
    invalidateSelection()
end)

-- Dex++ / config / diagnostics ---------------------------------------------

local dexBusy = false

local function loadDex()
    if env.FORGE_DEX_LOADED == true then
        say("Dex++ already loaded")
        return
    end
    if dexBusy then return end
    dexBusy = true

    task.spawn(function()
        local ok, err = runRemote(CONFIG.DexURL)
        dexBusy = false
        if ok then
            env.FORGE_DEX_LOADED = true
            say("Dex++ loaded")
        else
            say("Dex++ failed: " .. tostring(err))
        end
    end)
end

local function saveConfig()
    local ok, result
    if type(window.SaveConfig) == "function" then
        ok, result = pcall(window.SaveConfig, window, CONFIG.ConfigFile)
    elseif type(X64UI.SaveConfig) == "function" then
        ok, result = pcall(X64UI.SaveConfig, X64UI)
    else
        ok, result = false, "no SaveConfig in library"
    end
    say(ok and result == true and ("Config saved: " .. CONFIG.ConfigFile)
        or ("Config save failed: " .. tostring(result)))
end

local function loadConfig()
    local options = { Silent = false, FireCallbacks = true, RecordHistory = false, ApplyLayout = true }
    local ok, result
    if type(window.LoadConfig) == "function" then
        ok, result = pcall(window.LoadConfig, window, CONFIG.ConfigFile, options)
    elseif type(X64UI.LoadConfig) == "function" then
        ok, result = pcall(X64UI.LoadConfig, X64UI, options)
    else
        ok, result = false, "no LoadConfig in library"
    end
    invalidateSelection()
    npcDirty = true
    say(ok and result == true and ("Config loaded: " .. CONFIG.ConfigFile)
        or ("Config load failed: " .. tostring(result)))
end

local CAPABILITIES = {
    "Drawing", "hookmetamethod", "getnamecallmethod", "checkcaller", "request", "loadstring",
    "readfile", "writefile", "isfile", "listfiles", "newcclosure", "gethui", "cloneref",
}

local function reportCapabilities()
    local present, missing = {}, {}
    for _, name in ipairs(CAPABILITIES) do
        local value = env[name]
        local available = name == "Drawing"
            and type(value) == "table" and type(value.new) == "function"
            or name ~= "Drawing" and type(value) == "function"
        if available then
            present[#present + 1] = name
        else
            missing[#missing + 1] = name
        end
    end
    say("Present: " .. table.concat(present, ", "))
    say("Missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
end

-- Menu --------------------------------------------------------------------
-- Scoped in a do-block: its widget locals are not needed after construction.

do
pcall(function()
    X64UI.MenuKeybind = Enum.KeyCode[CONFIG.MenuKey]
end)

window = X64UI:CreateWindow({
    Name = "ForgeWindow",
    Title = CONFIG.WindowTitle,
    Width = 1050,
    Height = 680,
    SingleInstance = true,
})
assert(window, "FORGE: x64ui could not create a window")

local function addToggle(group, id, text, key, after)
    return group:AddToggle(id, {
        Text = text,
        Default = CONFIG[key],
        Callback = function(value)
            CONFIG[key] = value == true
            if after then after(CONFIG[key]) end
        end,
    })
end

local function addSlider(group, id, text, key, minimum, maximum, rounding, suffix)
    return group:AddSlider(id, {
        Text = text,
        Min = minimum,
        Max = maximum,
        Default = CONFIG[key],
        Rounding = rounding or 0,
        Suffix = suffix,
        Callback = function(value)
            CONFIG[key] = value
            state.selectElapsed = math.huge
        end,
    })
end

local function addDropdown(group, id, text, key, values, after)
    return group:AddDropdown(id, {
        Text = text,
        Values = values,
        Default = CONFIG[key],
        Multi = false,
        Callback = function(value)
            CONFIG[key] = value
            if after then after(value) end
        end,
    })
end

local function addInput(group, id, text, key, placeholder, after)
    return group:AddInput(id, {
        Text = text,
        Placeholder = placeholder or "",
        Default = CONFIG[key],
        Callback = function(value)
            CONFIG[key] = tostring(value or "")
            if after then after(CONFIG[key]) end
        end,
    })
end

local function addColor(group, id, text, key)
    if type(group.AddColorPicker) ~= "function" then return end
    return group:AddColorPicker(id, {
        Text = text,
        Default = CONFIG[key],
        Callback = function(value)
            CONFIG[key] = value
        end,
    })
end

local function markNpcDirty()
    npcDirty = true
end

local aimTab = window:AddTab("Aim")
local targetTab = window:AddTab("Targets")
local espTab = window:AddTab("ESP")
local cctvTab = window:AddTab("CCTV")
local overlayTab = window:AddTab("Overlay")
local settingsTab = window:AddTab("Settings")

-- Aim
local aimGroup = aimTab:AddLeftGroupbox("Camera aim")
local filterGroup = aimTab:AddLeftGroupbox("Filters")
local tuneGroup = aimTab:AddRightGroupbox("Tuning")
aimGroup:AddLabel("Hold the aim input to select a target. Strength 0 selects without moving the camera.", true)
addToggle(aimGroup, "forge_camera_aim", "Enable camera aim", "CameraAimEnabled", function()
    state.aimHeld = false
    invalidateSelection()
end)
addDropdown(aimGroup, "forge_aim_input", "Hold input", "AimActivation",
    { "MouseButton2", "MouseButton1", "MouseButton3", "E", "Q", "F", "LeftShift", "LeftControl", "LeftAlt" },
    function()
        state.aimHeld = false
        invalidateSelection()
    end)
addDropdown(aimGroup, "forge_part", "Target part", "TargetPart",
    { "Head", "HumanoidRootPart", "UpperTorso", "Torso" }, invalidateSelection)

addToggle(filterGroup, "forge_team", "Skip teammates", "TeamCheck", invalidateSelection)
addToggle(filterGroup, "forge_ff", "Skip ForceField", "ForceFieldCheck", invalidateSelection)
addToggle(filterGroup, "forge_aim_wall", "Require line of sight", "AimWallCheck", invalidateSelection)

addSlider(tuneGroup, "forge_aim_strength", "Camera strength (0 = off)", "AimStrength", 0, 50, 1)
addSlider(tuneGroup, "forge_aim_lead", "Prediction lead", "AimLeadSeconds", 0, 1, 2, " s")
addSlider(tuneGroup, "forge_fov", "Circle radius (0 = unlimited)", "FovRadius", 0, 600, 0, " px")
addSlider(tuneGroup, "forge_distance", "Max distance (0 = unlimited)", "MaxDistance", 0, 5000, 0, " st")
addSlider(tuneGroup, "forge_rate", "Selection rate (0 = every frame)", "SelectionRate", 0, 60, 0, " Hz")

local scopeGroup = aimTab:AddLeftGroupbox("Long scope (WIP)")
addToggle(scopeGroup, "forge_scope", "Enable hold-to-scope", "ScopeEnabled", function(value)
    if not value then state.scopeStop() end
end)
addDropdown(scopeGroup, "forge_scope_key", "Hold key", "ScopeKey",
    { "V", "B", "C", "X", "Z", "Q", "E", "F", "LeftAlt", "LeftControl", "LeftShift" },
    function() state.scopeStop() end)
addSlider(scopeGroup, "forge_scope_min", "Minimum FOV", "ScopeMinFov", 1, 60, 0, "°")
addSlider(scopeGroup, "forge_scope_step", "Wheel step", "ScopeStep", 1, 15, 0, "°")
addSlider(scopeGroup, "forge_scope_response", "Zoom response", "ScopeResponse", 2, 30, 0)
scopeGroup:AddLabel("Hold the scope key and scroll. Release to restore the previous FOV.", true)


-- Targets
local playerGroup = targetTab:AddLeftGroupbox("Players")
local npcGroup = targetTab:AddRightGroupbox("NPCs and bots")

addToggle(playerGroup, "forge_players", "Target players", "PlayersEnabled", invalidateSelection)
addToggle(playerGroup, "forge_ignore_friends", "Ignore friends", "IgnoreFriends", invalidateSelection)
addInput(playerGroup, "forge_ignore_list", "Ignore list", "IgnoreList", "name1, name2", function()
    parseIgnore()
    invalidateSelection()
end)

addToggle(npcGroup, "forge_npcs", "Target NPCs and bots", "NPCEnabled", function()
    invalidateSelection()
    markNpcDirty()
end)
addDropdown(npcGroup, "forge_npc_source", "Source", "NPCSource", { "Auto", "Container" }, markNpcDirty)
npcGroup:AddLabel("Auto tracks every non-player Model with a Humanoid. Container limits it to one path.", true)
addInput(npcGroup, "forge_npc_path", "Container path", "NPCPath", "Workspace.Bots", markNpcDirty)
addInput(npcGroup, "forge_npc_include", "Name contains", "NPCInclude", "bot, enemy", markNpcDirty)
addInput(npcGroup, "forge_npc_exclude", "Name excludes", "NPCExclude", "dummy", markNpcDirty)
addToggle(npcGroup, "forge_npc_humanoid", "Require Humanoid", "NPCRequireHumanoid", markNpcDirty)
addInput(npcGroup, "forge_npc_hp", "Health attribute", "NPCHealthAttribute", "", markNpcDirty)
addInput(npcGroup, "forge_npc_maxhp", "Max health attribute", "NPCMaxHealthAttribute", "", markNpcDirty)
npcGroup:AddButton({ Text = "Rescan", Callback = markNpcDirty })
npcGroup:AddButton({ Text = "Detect containers", Callback = detectContainers })

-- ESP
local espGroup = espTab:AddLeftGroupbox("Elements")
local espColors = espTab:AddLeftGroupbox("Colors")
local espStyle = espTab:AddRightGroupbox("Style")

espToggle = espGroup:AddToggle("forge_esp", {
    Text = "Enable ESP",
    Default = false,
    Callback = function(value)
        setEsp(value, true)
    end,
})
addToggle(espGroup, "forge_esp_players", "Players", "ESPPlayers")
addToggle(espGroup, "forge_esp_npcs", "NPCs and bots", "ESPNPCs", markNpcDirty)
addToggle(espGroup, "forge_esp_box", "Boxes", "ESPBox")
addToggle(espGroup, "forge_esp_name", "Names", "ESPName")
addToggle(espGroup, "forge_esp_dist", "Distance", "ESPDistance")
addToggle(espGroup, "forge_esp_hp", "Health bars", "ESPHealth")
addToggle(espGroup, "forge_esp_tracer", "Tracers", "ESPTracer")
addToggle(espGroup, "forge_esp_skeleton", "Skeleton", "ESPSkeleton")

addToggle(espColors, "forge_esp_teamcolor", "Team colors", "ESPTeamColor")
addToggle(espColors, "forge_esp_hideteam", "Hide teammates", "ESPHideTeammates")
addToggle(espColors, "forge_esp_visible", "Recolor when visible", "ESPVisibleCheck")
addColor(espColors, "forge_esp_pcolor", "Player", "ESPPlayerColor")
addColor(espColors, "forge_esp_ncolor", "NPC", "ESPNPCColor")
addColor(espColors, "forge_esp_vcolor", "Visible", "ESPVisibleColor")

addSlider(espStyle, "forge_esp_maxdist", "Max distance", "ESPMaxDistance", 50, 5000, 0, " st")
addSlider(espStyle, "forge_esp_text", "Text size", "ESPTextSize", 10, 24, 0)
addSlider(espStyle, "forge_esp_aspect", "Box aspect", "ESPBoxAspect", 0.3, 1, 2)
addSlider(espStyle, "forge_esp_opacity", "Opacity", "ESPOpacity", 0.1, 1, 2)

-- CCTV
local cctvGroup = cctvTab:AddLeftGroupbox("Monitor")
local cctvCamera = cctvTab:AddRightGroupbox("Camera")
local worldGroup = cctvTab:AddRightGroupbox("World")
local cctvDetail = cctvTab:AddRightGroupbox("Detail limits")

cctvToggle = cctvGroup:AddToggle("forge_cctv", {
    Text = "Enable CCTV",
    Default = false,
    Callback = function(value)
        setCctv(value, true)
    end,
})
cctvGroup:AddLabel("Target follows your selection; Self follows your character. Drag the screen to move it or the corner to resize.", true)
addDropdown(cctvGroup, "forge_cctv_source", "Feed source", "CCTVSource", { "Target", "Self" }, function()
    cctv.selfDismissed = false
    cctv.dismissed = nil
    if cctv.rec then closeCctv(false) end
end)
addToggle(cctvGroup, "forge_cctv_pin", "Pin feed", "CCTVPin")
addToggle(cctvGroup, "forge_cctv_self", "Show my character", "CCTVShowSelf")
addToggle(cctvGroup, "forge_cctv_location", "Show my coordinates", "CCTVShowLocation")
addSlider(cctvGroup, "forge_cctv_open", "Power-on time", "CCTVOpenSeconds", 0.1, 1.5, 2, " s")
cctvGroup:AddButton({
    Text = "Reset window",
    Callback = function()
        cctvFrame.Position = CCTV_DEFAULT_POSITION
        cctvFrame.Size = CCTV_DEFAULT_SIZE
    end,
})
cctvGroup:AddButton({
    Text = "Power off",
    Callback = function()
        closeCctv(true)
    end,
})

addDropdown(cctvCamera, "forge_cctv_mode", "Mode", "CCTVMode", CCTV_MODES, function()
    cctv.camCF = nil
end)
addSlider(cctvCamera, "forge_cctv_dist", "Distance", "CCTVDistance", 3, 30, 1, " st")
addSlider(cctvCamera, "forge_cctv_height", "Height", "CCTVHeight", 0, 15, 1, " st")
addSlider(cctvCamera, "forge_cctv_fov", "Field of view", "CCTVFov", 30, 100, 0, "°")
addSlider(cctvCamera, "forge_cctv_smooth", "Smoothing", "CCTVSmoothing", 1, 20, 0)
addColor(cctvCamera, "forge_cctv_bg", "Background", "CCTVBackground")

addToggle(worldGroup, "forge_cctv_terrain", "Terrain (voxel approximation)", "CCTVTerrain")
addToggle(worldGroup, "forge_cctv_smoothterrain", "Smoother terrain (WIP)", "CCTVSmoothTerrain", function()
    cctv.terrainCenter = nil
end)
addToggle(worldGroup, "forge_cctv_scenetracking", "Scene tracking (WIP)", "CCTVSceneTracking", function()
    cctv.sceneCenter = nil
end)
addToggle(worldGroup, "forge_cctv_sky", "Skybox", "CCTVSky", function()
    cctv.envAt = -math.huge
end)
addToggle(worldGroup, "forge_cctv_light", "Match lighting", "CCTVMatchLighting")
addToggle(worldGroup, "forge_cctv_others", "Other characters (live)", "CCTVOthers")
addToggle(worldGroup, "forge_cctv_archivable", "Clone non-archivable", "CCTVForceArchivable", function()
    cctv.liveFor = nil
    cctv.selfFor = nil
end)
worldGroup:AddButton({
    Text = "Rebuild world",
    Callback = function()
        cctv.sceneCenter = nil
        cctv.terrainCenter = nil
    end,
})

addSlider(cctvDetail, "forge_cctv_radius", "Part radius", "CCTVRadius", 50, 600, 0, " st")
addSlider(cctvDetail, "forge_cctv_parts", "Max parts", "CCTVMaxParts", 100, 4000, 0)
addSlider(cctvDetail, "forge_cctv_refresh", "Part refresh", "CCTVSceneRefresh", 1, 10, 0, " s")
addSlider(cctvDetail, "forge_cctv_trad", "Terrain radius", "CCTVTerrainRadius", 64, 400, 0, " st")
addSlider(cctvDetail, "forge_cctv_theight", "Terrain half-height", "CCTVTerrainHeight", 16, 128, 0, " st")
addSlider(cctvDetail, "forge_cctv_tparts", "Terrain max parts", "CCTVTerrainMaxParts", 500, 8000, 0)
addSlider(cctvDetail, "forge_cctv_trefresh", "Terrain refresh", "CCTVTerrainRefresh", 5, 120, 0, " s")
addSlider(cctvDetail, "forge_cctv_maxothers", "Max live characters", "CCTVMaxOthers", 0, 30, 0)

-- Overlay
local indicatorGroup = overlayTab:AddLeftGroupbox("Indicators")
local radarGroup = overlayTab:AddRightGroupbox("Radar")
addToggle(indicatorGroup, "forge_show_fov", "FOV circle", "ShowFov")
addToggle(indicatorGroup, "forge_show_arrow", "Target arrow", "ShowArrow")
addToggle(indicatorGroup, "forge_bounce", "Arrow bounce", "ArrowBounce")
addToggle(indicatorGroup, "forge_hud", "Target card", "HudEnabled")
addDropdown(indicatorGroup, "forge_arrow_death", "On target loss", "ArrowDeathMode", { "Fade", "Glide to next" })
addSlider(indicatorGroup, "forge_arrow_height", "Arrow height", "ArrowHeight", 1, 10, 1, " st")

addToggle(radarGroup, "forge_radar", "Enable radar", "RadarEnabled")
addToggle(radarGroup, "forge_radar_rotate", "Rotate with camera", "RadarRotate")
addSlider(radarGroup, "forge_radar_size", "Size", "RadarSize", 110, 300, 0, " px")
addSlider(radarGroup, "forge_radar_range", "Range", "RadarRange", 50, 1000, 0, " st")

-- Settings
local configGroup = settingsTab:AddLeftGroupbox("Profile")
local hotkeyGroup = settingsTab:AddLeftGroupbox("Hotkeys")
local toolsGroup = settingsTab:AddRightGroupbox("Tools")

configGroup:AddKeyPicker("forge_menukey", {
    Text = "Menu key",
    Default = CONFIG.MenuKey,
    Callback = function(value)
        local ok, keyCode = pcall(function() return Enum.KeyCode[value] end)
        if ok and keyCode then
            X64UI.MenuKeybind = keyCode
            CONFIG.MenuKey = value
        end
    end,
})
addInput(configGroup, "forge_cfg_file", "File name", "ConfigFile", "forge_config.json", function(value)
    local clean = (value:gsub("[^%w_%-%.]", ""))
    if clean == "" then
        clean = "forge_config.json"
    elseif not string.find(clean, "%.json$") then
        clean = clean .. ".json"
    end
    CONFIG.ConfigFile = clean
end)
configGroup:AddButton({ Text = "Save", Callback = saveConfig })
configGroup:AddButton({ Text = "Load", Callback = loadConfig })

local HOTKEY_VALUES = {
    "None", "End", "Delete", "Insert", "Home", "PageUp", "PageDown",
    "F6", "F7", "F8", "F9", "F10", "F11", "F12",
}
addDropdown(hotkeyGroup, "forge_hk_panic", "Panic (unload)", "PanicKey", HOTKEY_VALUES, resolveHotkeys)
addDropdown(hotkeyGroup, "forge_hk_esp", "Toggle ESP", "ESPKey", HOTKEY_VALUES, resolveHotkeys)
addDropdown(hotkeyGroup, "forge_hk_cctv", "Toggle CCTV", "CCTVKey", HOTKEY_VALUES, resolveHotkeys)

toolsGroup:AddLabel("Dex++ runs third-party code from CONFIG.DexURL.", true)
toolsGroup:AddButton({ Text = "Load Dex++", Callback = loadDex })
toolsGroup:AddButton({ Text = "Capability report", Callback = reportCapabilities })
toolsGroup:AddButton({ Text = "Unload FORGE", Callback = function() shutdown() end })
end -- do menu

-- Frame loops -------------------------------------------------------------

connect(RunService.Heartbeat, function(dt)
    if not state.alive then return end

    -- Opportunistic read; harmless if the library does not expose the field.
    if window.Destroyed == true then
        state.windowGone = true
        shutdown()
        return
    end

    if npcDirty and os.clock() - lastNpcBuild > 0.25 then
        npcDirty = false
        lastNpcBuild = os.clock()
        rebuildNpcs()
    end

    updateVisibility(os.clock())
    if CONFIG.CCTVEnabled and CONFIG.CCTVSource == "Self" then
        local character = localPlayer.Character
        if character and character:IsDescendantOf(Workspace) then
            if not cctv.selfRecord or cctv.selfRecord.model ~= character then
                cctv.selfRecord = {
                    model = character, kind = "Player", player = localPlayer,
                    parts = {}, exact = {}, height = 5, heightAt = -math.huge,
                }
                cctv.selfDismissed = false
            end
            local root = partOf(cctv.selfRecord, "HumanoidRootPart")
            if not cctv.selfDismissed and root and isAlive(cctv.selfRecord)
                and (cctv.rec ~= cctv.selfRecord or cctv.closing) then
                switchCctv(cctv.selfRecord)
            end
        elseif cctv.rec == cctv.selfRecord and cctv.rec then
            closeCctv(false)
            cctv.selfRecord = nil
        end
    end
    -- CCTV cloning and world bookkeeping do not belong in the render callback.
    updateCctv(math.clamp(dt, 0, 0.25))

    local camera = Workspace.CurrentCamera
    if not camera or not state.aimHeld
        or (not CONFIG.CameraAimEnabled and not CONFIG.CCTVEnabled)
        or UserInputService:GetFocusedTextBox()
    then
        clearTarget()
        cctv.dismissed = nil
        return
    end

    if state.targetCamera and state.targetCamera ~= camera then
        clearTarget()
        state.selectElapsed = math.huge
    end

    state.selectElapsed += dt
    if CONFIG.SelectionRate <= 0 or state.selectElapsed >= 1 / CONFIG.SelectionRate then
        state.selectElapsed = 0
        local rec, part = chooseTarget(camera)
        state.target = rec
        state.targetPart = part
        state.targetCamera = rec and camera or nil
    end

    local rec, part = state.target, state.targetPart
    if rec and part and part.Parent == rec.model and records[rec.model] == rec and isAlive(rec) then
        state.targetPosition = part.Position
    else
        clearTarget()
    end

    -- The monitor follows the selected target unless pinned or dismissed.
    local aimed = state.target
    if aimed ~= cctv.dismissed then
        cctv.dismissed = nil
    end
    if CONFIG.CCTVEnabled and CONFIG.CCTVSource == "Target" and aimed and aimed ~= cctv.dismissed then
        local pinned = CONFIG.CCTVPin and cctv.rec ~= nil and not cctv.closing
        if (cctv.rec ~= aimed or cctv.closing) and not pinned then
            switchCctv(aimed)
        end
    end
end)

local function updateArrow(dt, camera, valid)
    local a = state.arrow

    if valid then
        local desired = state.targetPart.Position + Vector3.new(0, CONFIG.ArrowHeight, 0)
        if a.rec ~= state.target then
            if a.pos and a.alpha > 0 and CONFIG.ArrowDeathMode == "Glide to next" then
                a.gliding = true
            else
                a.pos = desired
                a.gliding = false
            end
            a.rec = state.target
        end

        a.idle = 0
        a.alpha = 1

        if a.gliding then
            local k = 1 - math.exp(-CONFIG.ArrowGlideResponse * dt)
            a.pos = a.pos:Lerp(desired, k)
            if (a.pos - desired).Magnitude < 0.1 then
                a.gliding = false
            end
        else
            a.pos = desired
        end
    else
        a.rec = nil
        a.gliding = false
        if a.pos then
            a.idle += dt
            local hold = CONFIG.ArrowDeathMode == "Glide to next" and CONFIG.ArrowHoldSeconds or 0
            local fadeTime = a.idle - hold
            if fadeTime <= 0 then
                a.alpha = 1
            else
                a.alpha = math.clamp(1 - fadeTime / math.max(CONFIG.ArrowFadeSeconds, 0.01), 0, 1)
            end
            if a.alpha <= 0 then
                a.pos = nil
            end
        end
    end

    if not CONFIG.ShowArrow or not a.pos then
        arrow.Visible = false
        return
    end

    local position = a.pos
    if CONFIG.ArrowBounce then
        position += Vector3.new(0, math.sin(os.clock() * 5) * 0.35, 0)
    end

    local point, onScreen = camera:WorldToViewportPoint(position)
    arrow.Visible = onScreen and point.Z > 0
    if arrow.Visible then
        arrow.Position = UDim2.fromOffset(point.X, point.Y)
        arrow.TextTransparency = 1 - a.alpha
        arrow.TextStrokeTransparency = 1 - a.alpha * 0.75
    end
end

local function entityColor(rec)
    if CONFIG.ESPVisibleCheck and rec.seen then
        return CONFIG.ESPVisibleColor
    end
    if rec.kind == "Player" then
        if CONFIG.ESPTeamColor and rec.player.Team then
            return rec.player.TeamColor.Color
        end
        return CONFIG.ESPPlayerColor
    end
    return CONFIG.ESPNPCColor
end

local R15_RIG = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local R6_RIG = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local function rigOf(rec, now)
    if rec.rig == nil or (rec.rig == false and now - rec.rigAt > 1) then
        local model = rec.model
        if model:FindFirstChild("UpperTorso") then
            rec.rig = R15_RIG
        elseif model:FindFirstChild("Torso") then
            rec.rig = R6_RIG
        else
            rec.rig = false
        end
        rec.rigAt = now
    end
    return rec.rig or nil
end

local function drawSkeleton(rec, esp, camera, color, alpha, now)
    local wanted = CONFIG.ESPSkeleton
    if wanted and not esp.skeleton and not esp.skeletonFailed then
        if not ensureSkeleton(esp) then
            esp.skeletonFailed = true
        end
    end

    local lines = esp.skeleton
    if not lines then return end

    local last = 0
    local rig = wanted and rigOf(rec, now) or nil

    if rig then
        for index, pair in ipairs(rig) do
            local line = lines[index]
            local a = exactPart(rec, pair[1])
            local b = exactPart(rec, pair[2])

            if line and a and b then
                local pa = camera:WorldToViewportPoint(a.Position)
                local pb = camera:WorldToViewportPoint(b.Position)
                if pa.Z > 0 and pb.Z > 0 then
                    line.From = Vector2.new(pa.X, pa.Y)
                    line.To = Vector2.new(pb.X, pb.Y)
                    line.Color = color
                    line.Transparency = alpha
                    line.Visible = true
                    last = index
                else
                    line.Visible = false
                end
            elseif line then
                line.Visible = false
            end
        end
    end

    for index = last + 1, #lines do
        lines[index].Visible = false
    end
end

-- Drawing coordinates match WorldToViewportPoint output (screen pixels).
local function drawEsp(rec, esp, camera, camPos, viewport, now)
    local root = partOf(rec, "HumanoidRootPart")
    if not root or not isAlive(rec) then return false end

    local position = root.Position
    local distance = (position - camPos).Magnitude
    if distance > CONFIG.ESPMaxDistance then return false end

    local half = getHeight(rec, now) * 0.5
    local top = camera:WorldToViewportPoint(position + Vector3.new(0, half, 0))
    local bottom = camera:WorldToViewportPoint(position - Vector3.new(0, half, 0))
    if top.Z <= 0 or bottom.Z <= 0 then return false end

    local centerX = (top.X + bottom.X) * 0.5
    if centerX < -100 or centerX > viewport.X + 100 then return false end

    local height = math.abs(bottom.Y - top.Y)
    local width = height * CONFIG.ESPBoxAspect
    local left = centerX - width * 0.5
    local topY = math.min(top.Y, bottom.Y)
    local color = entityColor(rec)
    local alpha = CONFIG.ESPOpacity

    esp.visible = true

    local showBox = CONFIG.ESPBox
    esp.boxOutline.Visible = showBox
    esp.box.Visible = showBox
    if showBox then
        local boxPosition = Vector2.new(left, topY)
        local boxSize = Vector2.new(width, height)
        esp.boxOutline.Position = boxPosition
        esp.boxOutline.Size = boxSize
        esp.boxOutline.Transparency = alpha
        esp.box.Position = boxPosition
        esp.box.Size = boxSize
        esp.box.Color = color
        esp.box.Transparency = alpha
    end

    local health, maxHealth = healthOf(rec)
    local showHealth = CONFIG.ESPHealth and health ~= nil and maxHealth ~= nil and maxHealth > 0
    esp.hpBack.Visible = showHealth
    esp.hpFill.Visible = showHealth
    if showHealth then
        local ratio = math.clamp(health / maxHealth, 0, 1)
        local barX = left - 6
        esp.hpBack.Position = Vector2.new(barX - 1, topY - 1)
        esp.hpBack.Size = Vector2.new(4, height + 2)
        esp.hpFill.Position = Vector2.new(barX, topY + height * (1 - ratio))
        esp.hpFill.Size = Vector2.new(2, height * ratio)
        esp.hpFill.Color = Color3.fromHSV(ratio * 0.33, 1, 1)
        esp.hpFill.Transparency = alpha
    end

    local showName = CONFIG.ESPName
    esp.name.Visible = showName
    if showName then
        local label = rec.player and rec.player.DisplayName or rec.model.Name
        if esp.lastName ~= label then
            esp.lastName = label
            esp.name.Text = label
        end
        esp.name.Size = CONFIG.ESPTextSize
        esp.name.Color = color
        esp.name.Transparency = alpha
        esp.name.Position = Vector2.new(centerX, topY - CONFIG.ESPTextSize - 3)
    end

    local showDistance = CONFIG.ESPDistance
    esp.dist.Visible = showDistance
    if showDistance then
        local rounded = math.floor(distance + 0.5)
        if esp.lastDist ~= rounded then
            esp.lastDist = rounded
            esp.dist.Text = tostring(rounded) .. "m"
        end
        esp.dist.Size = CONFIG.ESPTextSize
        esp.dist.Color = color
        esp.dist.Transparency = alpha
        esp.dist.Position = Vector2.new(centerX, topY + height + 2)
    end

    local showTracer = CONFIG.ESPTracer
    esp.tracer.Visible = showTracer
    if showTracer then
        esp.tracer.From = Vector2.new(viewport.X * 0.5, viewport.Y)
        esp.tracer.To = Vector2.new(centerX, topY + height)
        esp.tracer.Color = color
        esp.tracer.Transparency = alpha
    end

    drawSkeleton(rec, esp, camera, color, alpha, now)

    return true
end

local espWasActive = false

local function updateEsp(camera)
    if not CONFIG.ESPEnabled then
        if espWasActive then
            espWasActive = false
            for _, rec in pairs(records) do
                hideEsp(rec.esp)
            end
        end
        return
    end
    espWasActive = true

    local camPos = camera.CFrame.Position
    local viewport = camera.ViewportSize
    local now = os.clock()
    local localTeam = localPlayer.Team

    for _, rec in pairs(records) do
        local wanted = (rec.kind == "Player" and CONFIG.ESPPlayers)
            or (rec.kind == "NPC" and CONFIG.ESPNPCs)

        if wanted and rec.kind == "Player" and CONFIG.ESPHideTeammates
            and localTeam ~= nil and rec.player.Team == localTeam
        then
            wanted = false
        end

        local shown = false
        if wanted then
            if not rec.esp then
                rec.esp = createEsp()
                if not rec.esp then
                    CONFIG.ESPEnabled = false
                    syncControl(espToggle, false)
                    say("ESP disabled: GUI object creation failed")
                    return
                end
            end
            shown = drawEsp(rec, rec.esp, camera, camPos, viewport, now)
        end

        if not shown then
            hideEsp(rec.esp)
        end
    end
end

local function radarPoint(offset, forward, right, scale)
    return offset:Dot(right) * scale, -offset:Dot(forward) * scale
end

local function updateRadar(camera)
    if not CONFIG.RadarEnabled then
        if radarFrame.Visible then
            radarFrame.Visible = false
        end
        return
    end
    radarFrame.Visible = true

    local size = CONFIG.RadarSize
    if radarFrame.Size.X.Offset ~= size then
        radarFrame.Size = UDim2.fromOffset(size, size)
    end

    local radius = size * 0.5
    local scale = radius / math.max(CONFIG.RadarRange, 1)

    local forward
    if CONFIG.RadarRotate then
        local look = camera.CFrame.LookVector
        forward = Vector3.new(look.X, 0, look.Z)
        forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0, 0, -1)
    else
        forward = Vector3.new(0, 0, -1)
    end
    local right = forward:Cross(Vector3.yAxis)

    -- North marker follows the camera rotation.
    local nx, ny = radarPoint(Vector3.new(0, 0, -1), forward, right, 1)
    radarNorth.Position = UDim2.fromOffset(radius + nx * (radius - 10), radius + ny * (radius - 10))

    local character = localPlayer.Character
    local selfRoot = character and character:FindFirstChild("HumanoidRootPart")
    local center = selfRoot and selfRoot:IsA("BasePart") and selfRoot.Position or camera.CFrame.Position

    for rec, dot in pairs(radarDots) do
        if records[rec.model] ~= rec then
            dot:Destroy()
            radarDots[rec] = nil
        end
    end

    local limit = radius - 5

    for _, rec in pairs(records) do
        local root = partOf(rec, "HumanoidRootPart")
        local dot = radarDots[rec]

        if root and isAlive(rec) then
            local px, py = radarPoint(root.Position - center, forward, right, scale)

            local magnitude = math.sqrt(px * px + py * py)
            if magnitude > limit then
                px = px / magnitude * limit
                py = py / magnitude * limit
            end

            if not dot then
                dot = newInstance("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Size = UDim2.fromOffset(7, 7),
                    BorderSizePixel = 0,
                    ZIndex = 3,
                }, radarFrame)
                newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
                radarDots[rec] = dot
            end

            dot.Position = UDim2.fromOffset(radius + px, radius + py)
            dot.BackgroundColor3 = entityColor(rec)
            dot.Visible = true
        elseif dot then
            dot.Visible = false
        end
    end
end

local hudAt = 0

local function updateHud(valid, camera, now)
    if not (CONFIG.HudEnabled and valid) then
        if hud.Visible then
            hud.Visible = false
        end
        return
    end

    hud.Visible = true
    if state.target == hudInfo.record and now - hudAt < 0.1 then return end
    hudAt = now

    local rec = state.target
    hudInfo.record = rec
    hudName.Text = rec.player and rec.player.DisplayName or rec.model.Name
    hudDist.Text = math.floor((state.targetPart.Position - camera.CFrame.Position).Magnitude + 0.5) .. " st"
    hudInfo.kind.Text = rec.kind == "Player" and "PLAYER" or "NPC"

    local health, maxHealth = healthOf(rec)
    if health and maxHealth and maxHealth > 0 then
        local ratio = math.clamp(health / maxHealth, 0, 1)
        hudBarBack.Visible = true
        hudBarFill.Size = UDim2.fromScale(ratio, 1)
        hudBarFill.BackgroundColor3 = ratio <= 0.25 and X64UI.Theme.Bad or X64UI.Theme.Accent
        hudHp.Text = ("HEALTH  %d / %d"):format(math.floor(health + 0.5), math.floor(maxHealth + 0.5))
    else
        hudBarBack.Visible = false
        hudHp.Text = health and ("HEALTH  %d"):format(math.floor(health + 0.5)) or "HEALTH  --"
    end
    hudBadge.Text = rec.player and ("@" .. rec.player.Name) or "MODEL"
end

local function onRender(dt)
    if not state.alive then return end
    dt = math.clamp(dt, 0, 0.25)
    local now = os.clock()

    local camera = Workspace.CurrentCamera
    if not camera then
        state.scopeStop()
        ring.Visible = false
        arrow.Visible = false
        hud.Visible = false
        radarFrame.Visible = false
        espGui.Enabled = false
        return
    end
    espGui.Enabled = true

    local center = getCenter(camera)
    ring.Visible = CONFIG.ShowFov
    if ring.Visible then
        local diameter = CONFIG.FovRadius * 2
        ring.Position = UDim2.fromOffset(center.X, center.Y)
        ring.Size = UDim2.fromOffset(diameter, diameter)
    end

    local rec, part = state.target, state.targetPart
    local valid = rec ~= nil
        and part ~= nil
        and state.targetCamera == camera
        and records[rec.model] == rec
        and part.Parent == rec.model

    if valid and state.aimHeld and CONFIG.CameraAimEnabled and CONFIG.AimStrength > 0
        and not UserInputService:GetFocusedTextBox()
    then
        local current = camera.CFrame
        local targetPosition = part.Position + part.AssemblyLinearVelocity * math.max(CONFIG.AimLeadSeconds, 0)
        local targetDirection = targetPosition - current.Position
        if targetDirection.Magnitude > 0.001 then
            local cursorRay = camera:ViewportPointToRay(center.X, center.Y)
            local from = cursorRay.Direction.Unit
            local to = targetDirection.Unit
            local axis = from:Cross(to)
            local sine = axis.Magnitude
            local cosine = math.clamp(from:Dot(to), -1, 1)
            if sine <= 1e-6 and cosine < 0 then
                axis = from:Cross(current.UpVector)
                if axis.Magnitude <= 1e-6 then
                    axis = from:Cross(current.RightVector)
                end
                sine = axis.Magnitude
                if sine > 1e-6 then
                    local alpha = 1 - math.exp(-CONFIG.AimStrength * dt)
                    camera.CFrame = CFrame.new(current.Position)
                        * CFrame.fromAxisAngle(axis / sine, math.pi * alpha)
                        * (current - current.Position)
                end
            elseif sine > 1e-6 then
                local angle = math.atan2(sine, cosine)
                local alpha = 1 - math.exp(-CONFIG.AimStrength * dt)
                camera.CFrame = CFrame.new(current.Position)
                    * CFrame.fromAxisAngle(axis / sine, angle * alpha)
                    * (current - current.Position)
            end
        end
    end

    state.scopeUpdate(dt, camera)
    updateArrow(dt, camera, valid)
    updateHud(valid, camera, now)
    updateEsp(camera)
    updateRadar(camera)
end

function shutdown()
    if not state.alive then return end
    state.scopeStop()
    state.alive = false
    state.aimHeld = false
    cctv.sceneTracking(false)
    npcToken += 1
    cctv.sceneToken += 1
    cctv.terrainToken += 1

    pcall(RunService.UnbindFromRenderStep, RunService, renderName)
    disconnectList(state.connections)
    disconnectList(npcConns)
    for _, conns in pairs(playerConns) do
        disconnectList(conns)
    end
    table.clear(playerConns)

    for _, rec in pairs(records) do
        destroyEsp(rec.esp)
    end
    table.clear(records)

    overlay:Destroy() -- also removes the monitor, radar, HUD, frustum parts, sky and every clone
    espGui:Destroy()

    if window and not state.windowGone and window.Destroyed ~= true then
        window:Destroy()
    end

    if X64UI and type(X64UI.Unload) == "function" then
        X64UI:Unload()
    end

    if env.FORGE_SESSION == state then
        env.FORGE_SESSION = nil
    end
end

state.Shutdown = shutdown
env.FORGE_SESSION = state

if type(window.Events) == "table" and window.Events.Destroying
    and type(window.Events.Destroying.Connect) == "function"
then
    connect(window.Events.Destroying, function()
        state.windowGone = true
        shutdown()
    end)
end

RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, onRender)

if CONFIG.AutoLoadConfig then
    loadConfig()
end

say("FORGE ready. Hold " .. CONFIG.AimActivation .. " to select; strength 0 disables camera movement.")