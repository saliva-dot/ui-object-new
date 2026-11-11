if getgenv and getgenv().library_object and getgenv().library_object.Unload then
    pcall(getgenv().library_object.Unload, getgenv().library_object)
end

local LoadingTick = os.clock()

-- Executor shims (so the file still runs where these are missing)
local cloneref = cloneref or function(Object) return Object end
local HasFileSystem = typeof(writefile) == "function" and typeof(isfile) == "function"
    and typeof(isfolder) == "function" and typeof(makefolder) == "function"
    and typeof(readfile) == "function" and typeof(listfiles) == "function"
local HasCustomAssets = HasFileSystem and typeof(getcustomasset) == "function"

local Players = cloneref(game:GetService("Players"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))
local TweenService = cloneref(game:GetService("TweenService"))
local HttpService = cloneref(game:GetService("HttpService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local GuiService = cloneref(game:GetService("GuiService"))
local Stats = cloneref(game:GetService("Stats"))
local MarketplaceService = cloneref(game:GetService("MarketplaceService"))
local TextService = cloneref(game:GetService("TextService"))

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local FromRGB = Color3.fromRGB
local UDim2New = UDim2.new
local UDimNew = UDim.new
local Vector2New = Vector2.new
local MathClamp = math.clamp
local MathFloor = math.floor
local TableInsert = table.insert
local TableFind = table.find
local TableRemove = table.remove

local GetHui = function()
    if typeof(gethui) == "function" then
        local Ok, Result = pcall(gethui)
        if Ok and Result then return Result end
    end

    local Ok = pcall(function() return CoreGui.Name end)
    if Ok and not RunService:IsStudio() then
        return CoreGui
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local library_object = {
    Name = "kimikahax",

    Flags = { },
    SetFlags = { },

    Theme = {
        ["Accent"]                  = FromRGB(104, 105, 169),
        ["Background"]              = FromRGB(17, 19, 19),
        ["Inline"]                  = FromRGB(22, 25, 25),
        ["Contrast"]                = FromRGB(26, 28, 28),
        ["Outline"]                 = FromRGB(10, 11, 11),
        ["Tab Button Low Contrast"] = FromRGB(14, 16, 16),
        ["Text Color"]              = FromRGB(200, 200, 200),
        ["Disabled Text Color"]     = FromRGB(84, 84, 84),
        ["Text Border"]             = FromRGB(0, 0, 0),
        ["Risky"]                   = FromRGB(214, 72, 72),
    },

    -- order + labels used by the Theming section (matches the original menu)
    ThemeOrder = {
        "Disabled Text Color", "Tab Button Low Contrast", "Outline", "Contrast",
        "Inline", "Background", "Text Color", "Accent",
    },

    -- menu open/close animation (editable from the settings page)
    Tween = {
        Time = 0.3,
        Style = Enum.EasingStyle.Exponential,
        Direction = Enum.EasingDirection.InOut,
    },

    FontSize = 13,
    BoldFontSize = 13,
    Font = Font.fromEnum(Enum.Font.Arial),
    BoldFont = Font.fromEnum(Enum.Font.ArialBold),
    MenuKeybind = Enum.KeyCode.Insert,

    Folders = {
        Directory = "kimikahax",
        Configs = "kimikahax/Configs",
        Assets = "kimikahax/Assets",
    },

    GlowSettings = { Animated = false, Speed = 0.35, Darkness = 0.75 },

    -- internal
    Connections = { },
    ThemeItems = { },
    ThemeMap = setmetatable({ }, { __mode = "k" }),
    OriginalTransparency = setmetatable({ }, { __mode = "k" }),
    FadeTokens = setmetatable({ }, { __mode = "k" }),
    ThemeTweens = setmetatable({ }, { __mode = "k" }),
    NameLabels = { },
    LayoutItems = { },
    NoFade = setmetatable({ }, { __mode = "k" }),
    Glows = { },
    Rainbows = { },
    OpenPopup = nil,
    Windows = { },
    UnnamedFlags = 0,
    Unloaded = false,
}

local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local KeyNames = {
    MouseButton1 = "MB1", MouseButton2 = "MB2", MouseButton3 = "MB3",
    One = "1", Two = "2", Three = "3", Four = "4", Five = "5",
    Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
    LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
    LeftAlt = "LAlt", RightAlt = "RAlt", Return = "Enter", Backspace = "Back",
}

library_object.DefaultName = library_object.Name

-- Renames the menu: the window title and the watermark follow (empty text falls back to the default)
function library_object:SetName(Name)
    Name = type(Name) == "string" and Name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if Name == "" then Name = self.DefaultName end
    self.Name = Name
    for _, Label in self.NameLabels do
        Label.Instance.Text = Name
    end
end

--#region Filesystem / fonts
if HasFileSystem then
    for _, Folder in { library_object.Folders.Directory, library_object.Folders.Configs, library_object.Folders.Assets } do
        if not isfolder(Folder) then
            makefolder(Folder)
        end
    end
end

-- Registers one .ttf as a font family (downloaded once). Returns a Font or nil; never errors.
function library_object:LoadFont(Name, File, Url, Weight)
    if not HasCustomAssets then return nil end

    local Ok, Result = pcall(function()
        local Path = self.Folders.Assets .. "/" .. File
        if not isfile(Path) then
            local Data = game:HttpGet(Url)
            -- only accept real TrueType/OpenType data (not an HTML error page)
            local Magic = type(Data) == "string" and Data:sub(1, 4) or ""
            assert(Magic == "\0\1\0\0" or Magic == "OTTO" or Magic == "true", "bad font data")
            writefile(Path, Data)
        end

        local JsonPath = self.Folders.Assets .. "/" .. Name .. ".json"
        writefile(JsonPath, HttpService:JSONEncode({
            name = Name,
            faces = { { name = "Regular", weight = Weight or 400, style = "normal", assetId = getcustomasset(Path) } },
        }))

        return Font.new(getcustomasset(JsonPath), Weight == 700 and Enum.FontWeight.Bold or Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    end)

    return Ok and Result or nil
end

-- Decodes base64 (uses the executor's decoder when it has one)
local Base64Decode = function(Data)
    Data = Data:gsub("[^%w%+/=]", "")
    for _, Decoder in {
        typeof(crypt) == "table" and crypt.base64decode,
        typeof(crypt) == "table" and typeof(crypt.base64) == "table" and crypt.base64.decode,
        base64_decode,
    } do
        if typeof(Decoder) == "function" then
            local Ok, Result = pcall(Decoder, Data)
            if Ok and type(Result) == "string" and #Result > 0 then return Result end
        end
    end

    local Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local Lookup = { }
    for Index = 1, 64 do Lookup[Alphabet:sub(Index, Index)] = Index - 1 end

    local Out, Bits, Count = { }, 0, 0
    for Index = 1, #Data do
        local Value = Lookup[Data:sub(Index, Index)]
        if Value then
            Bits = Bits * 64 + Value
            Count += 6
            if Count >= 8 then
                Count -= 8
                local Byte = math.floor(Bits / 2 ^ Count) % 256
                Out[#Out + 1] = string.char(Byte)
                Bits = Bits % 2 ^ Count
            end
        end
    end
    return table.concat(Out)
end

-- Registers an embedded .ttf (base64) as a font family. Returns a Font or nil; never errors.
function library_object:LoadEmbeddedFont(Name, File, Data, Weight)
    if not HasCustomAssets then return nil end

    local Ok, Result = pcall(function()
        local Path = self.Folders.Assets .. "/" .. File
        writefile(Path, Base64Decode(Data))

        local JsonPath = self.Folders.Assets .. "/" .. Name .. ".json"
        writefile(JsonPath, HttpService:JSONEncode({
            name = Name,
            faces = { { name = "Regular", weight = Weight or 400, style = "normal", assetId = getcustomasset(Path) } },
        }))

        return Font.new(getcustomasset(JsonPath), Weight == 700 and Enum.FontWeight.Bold or Enum.FontWeight.Regular, Enum.FontStyle.Normal)
    end)

    return Ok and Result or nil
end

local BoldFontData = loadstring(game:HttpGet('https://raw.githubusercontent.com/saliva-dot/ui-object-new/refs/heads/main/font-data/base-font.luau'))()
do
    local Regular = library_object:LoadFont("kimikahax_regular", "open-sans-px.ttf",
        "https://github.com/saliva-dot/ui-object-new/blob/main/font-data/open-sans-px.ttf", 400)
    local Bold = library_object:LoadEmbeddedFont("kimikahax_bold", "kimikahax-bold.ttf", BoldFontData, 700)

    if Regular then
        library_object.Font = Regular
        library_object.FontSize = 14
    end

    if Bold then
        library_object.BoldFont = Bold
        library_object.BoldFontSize = 14
    end
end
--#endregion

--#region Core helpers
function library_object:SafeCall(Function, ...)
    if type(Function) ~= "function" then return end

    local Ok, Error = pcall(Function, ...)
    if not Ok then
        warn("[" .. self.Name .. "] callback error: " .. tostring(Error))
    end
end

function library_object:Connect(Signal, Callback)
    local Connection = Signal:Connect(Callback)
    TableInsert(self.Connections, Connection)
    return Connection
end

function library_object:NextFlag()
    self.UnnamedFlags += 1
    return "Flag_" .. self.UnnamedFlags
end

function library_object:Round(Number, Step)
    Step = Step or 1
    if Step <= 0 then return Number end
    local Result = MathFloor(Number / Step + 0.5) * Step
    return tonumber(string.format("%.4f", Result))
end

function library_object:IsMouseOver(Target)
    local Mouse = UserInputService:GetMouseLocation() - Vector2New(0, GuiService:GetGuiInset().Y)
    local Position, Size = Target.AbsolutePosition, Target.AbsoluteSize
    return Mouse.X >= Position.X and Mouse.X <= Position.X + Size.X
        and Mouse.Y >= Position.Y and Mouse.Y <= Position.Y + Size.Y
end

function library_object:KeyName(Key)
    if not Key then return "None" end
    local Name = typeof(Key) == "EnumItem" and Key.Name or tostring(Key)
    return KeyNames[Name] or Name
end

local IsClick = function(Input)
    return Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch
end

local IsMove = function(Input)
    return Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch
end
--#endregion

--#region Object wrapper
local Object = { }
Object.__index = Object

function library_object:Create(Class, Properties)
    local Created = Instance.new(Class)
    local Wrapped = setmetatable({ Instance = Created, Class = Class }, Object)

    if Class == "TextLabel" or Class == "TextButton" or Class == "TextBox" then
        Created.FontFace = library_object.Font
        Created.TextSize = library_object.FontSize
        Created.BackgroundTransparency = 1
        Created.TextColor3 = library_object.Theme["Text Color"]
    end

    if Class == "TextButton" or Class == "ImageButton" then
        Created.AutoButtonColor = false
    end

    if Class == "TextButton" then
        Created.Text = ""
    end

    if Created:IsA("GuiObject") then
        Created.BorderSizePixel = 0
    end

    local Parent = nil
    for Property, Value in Properties or { } do
        if Property == "Parent" then
            Parent = Value
        elseif Property == "Bold" then
            if Value then
                Created.FontFace = library_object.BoldFont
                Created.TextSize = library_object.BoldFontSize
            end
        else
            Created[Property] = Value
        end
    end

    Created.Name = "\0"

    if Parent then
        Created.Parent = typeof(Parent) == "table" and Parent.Instance or Parent
    end

    return Wrapped
end

-- Swap a text object between the regular pixel font and the bold font (each has its own size)
function Object:SetBold(Bool)
    self.Instance.FontFace = Bool and library_object.BoldFont or library_object.Font
    self.Instance.TextSize = Bool and library_object.BoldFontSize or library_object.FontSize
    return self
end

function Object:Theme(Properties)
    library_object:AddToTheme(self.Instance, Properties)
    return self
end

function Object:Tween(Goal, Info)
    local Tween = TweenService:Create(self.Instance,
        Info or TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), Goal)
    Tween:Play()
    return Tween
end

-- Tween to a theme key AND rebind, so a later ChangeTheme keeps the state color
function Object:TweenTheme(Properties)
    local Goal = { }
    for Property, Key in Properties do
        Goal[Property] = library_object.Theme[Key]
    end
    -- rebind WITHOUT applying: applying first would make the tween start at its end value
    library_object:AddToTheme(self.Instance, Properties, true, true)
    local Tween = self:Tween(Goal)
    -- remembered so a theme change can stop it from finishing on the old color
    library_object.ThemeTweens[self.Instance] = Tween
    return Tween
end

function Object:Connect(EventName, Callback)
    local Event = self.Instance[EventName]

    if IsMobile and (EventName == "MouseButton1Down" or EventName == "MouseButton1Click") then
        Event = self.Instance.Activated
    end

    return library_object:Connect(Event, Callback)
end

function Object:OnHover(Enter, Leave)
    if Enter then library_object:Connect(self.Instance.MouseEnter, Enter) end
    if Leave then library_object:Connect(self.Instance.MouseLeave, Leave) end
    return self
end

function Object:Stroke(ThemeKey, Thickness, Transparency)
    return library_object:Create("UIStroke", {
        Parent = self.Instance,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Miter,
        Thickness = Thickness or 1,
        Transparency = Transparency or 0,
        Color = library_object.Theme[ThemeKey],
    }):Theme({ Color = ThemeKey })
end

-- The signature kimikahax edge: dark 1px outline outside + 1px lighter highlight just inside
function Object:Bevel(OutlineKey, HighlightKey)
    self:Stroke(OutlineKey or "Outline")

    local Highlight = library_object:Create("Frame", {
        Parent = self.Instance,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 1, 0, 1),
        Size = UDim2New(1, -2, 1, -2),
        ZIndex = self.Instance.ZIndex,
    })
    Highlight:Stroke(HighlightKey or "Contrast", 1, 0.35)
    self.Highlight = Highlight

    return self
end

-- Vertical shading: multiplies the fill from full brightness (top) to Bottom (grey)
function Object:Shade(Bottom)
    local Gradient = library_object:Create("UIGradient", {
        Parent = self.Instance,
        Rotation = 90,
        Color = ColorSequence.new(FromRGB(255, 255, 255), Bottom or FromRGB(175, 175, 175)),
    })
    self.Gradient = Gradient
    return self
end

-- Black 1px text outline, as on every label of the original
function Object:TextStroke()
    library_object:Create("UIStroke", {
        Parent = self.Instance,
        LineJoinMode = Enum.LineJoinMode.Miter,
        Color = library_object.Theme["Text Border"],
        Transparency = 0.15,
    }):Theme({ Color = "Text Border" })
    return self
end

function Object:MakeDraggable(Handle)
    local Gui = self.Instance
    local DragHandle = Handle and Handle.Instance or Gui
    local Dragging, DragStart, StartPosition = false, nil, nil

    library_object:Connect(DragHandle.InputBegan, function(Input)
        if IsClick(Input) then
            Dragging = true
            DragStart = Input.Position
            StartPosition = Gui.Position
        end
    end)

    library_object:Connect(UserInputService.InputEnded, function(Input)
        if IsClick(Input) then Dragging = false end
    end)

    library_object:Connect(UserInputService.InputChanged, function(Input)
        if not Dragging or not IsMove(Input) then return end

        local Delta = Input.Position - DragStart
        local ScreenSize = Gui.Parent.AbsoluteSize
        local GuiSize = Gui.AbsoluteSize

        local X = MathClamp(StartPosition.X.Offset + Delta.X, 0, math.max(0, ScreenSize.X - GuiSize.X))
        local Y = MathClamp(StartPosition.Y.Offset + Delta.Y, 0, math.max(0, ScreenSize.Y - GuiSize.Y))

        self:Tween({ Position = UDim2New(0, X, 0, Y) }, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
    end)

    return self
end

function Object:MakeResizable(MinimumSize)
    local Gui = self.Instance
    local Grip = library_object:Create("TextButton", {
        Parent = Gui,
        AnchorPoint = Vector2New(1, 1),
        Position = UDim2New(1, 0, 1, 0),
        Size = UDim2New(0, 10, 0, 10),
        ZIndex = 50,
    })

    local Resizing, StartMouse, StartSize = false, nil, nil

    Grip:Connect("InputBegan", function(Input)
        if IsClick(Input) then
            Resizing = true
            StartMouse = Input.Position
            StartSize = Gui.AbsoluteSize
        end
    end)

    library_object:Connect(UserInputService.InputEnded, function(Input)
        if IsClick(Input) then Resizing = false end
    end)

    library_object:Connect(UserInputService.InputChanged, function(Input)
        if not Resizing or not IsMove(Input) then return end
        local Delta = Input.Position - StartMouse
        Gui.Size = UDim2New(0, math.max(MinimumSize.X, StartSize.X + Delta.X), 0, math.max(MinimumSize.Y, StartSize.Y + Delta.Y))
    end)

    return self
end
--#endregion

--#region Layout (window/overlay positions and sizes, saved in configs)
function library_object:TrackLayout(Name, Wrapper, WithSize)
    self.LayoutItems[Name] = { Wrapper = Wrapper, WithSize = WithSize }
end

local PackUDim2 = function(Value)
    return { Value.X.Scale, Value.X.Offset, Value.Y.Scale, Value.Y.Offset }
end

local UnpackUDim2 = function(Value)
    if type(Value) ~= "table" or #Value ~= 4 then return nil end
    for _, Number in Value do
        if type(Number) ~= "number" then return nil end
    end
    return UDim2New(Value[1], Value[2], Value[3], Value[4])
end

function library_object:GetLayout()
    local Layout = { }
    for Name, Item in self.LayoutItems do
        local Instance = Item.Wrapper.Instance
        Layout[Name] = {
            Position = PackUDim2(Instance.Position),
            Size = Item.WithSize and PackUDim2(Instance.Size) or nil,
        }
    end
    return Layout
end

function library_object:ApplyLayout(Layout)
    if type(Layout) ~= "table" then return end

    local Screen = self.Holder.Instance.AbsoluteSize
    for Name, Saved in Layout do
        local Item = self.LayoutItems[Name]
        if not Item or type(Saved) ~= "table" then continue end
        local Instance = Item.Wrapper.Instance

        local Size = Item.WithSize and UnpackUDim2(Saved.Size)
        if Size then
            Item.Wrapper:Tween({ Size = Size }, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        end

        local Position = UnpackUDim2(Saved.Position)
        if Position then
            -- keep it reachable if the config came from a bigger screen
            if Screen.X > 0 and Screen.Y > 0 and Position.X.Scale == 0 and Position.Y.Scale == 0 then
                local Width = Size and Size.X.Offset or Instance.AbsoluteSize.X
                local Height = Size and Size.Y.Offset or Instance.AbsoluteSize.Y
                Position = UDim2New(0, MathClamp(Position.X.Offset, 0, math.max(0, Screen.X - Width)),
                    0, MathClamp(Position.Y.Offset, 0, math.max(0, Screen.Y - Height)))
            end
            Item.Wrapper:Tween({ Position = Position }, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
        end
    end
end

library_object.SetFlags["__layout"] = function(Value) library_object:ApplyLayout(Value) end
--#endregion

--#region Theme
function library_object:AddToTheme(Target, Properties, Merge, NoApply)
    local Entry = self.ThemeMap[Target]

    if not Entry then
        Entry = { Instance = Target, Properties = { } }
        self.ThemeMap[Target] = Entry
        TableInsert(self.ThemeItems, Entry)
    elseif not Merge then
        Entry.Properties = { }
    end

    for Property, Key in Properties do
        Entry.Properties[Property] = Key
        if not NoApply and self.Theme[Key] ~= nil then
            Target[Property] = self.Theme[Key]
        end
    end
end

function library_object:ChangeTheme(Key, Color)
    self.Theme[Key] = Color

    for _, Entry in self.ThemeItems do
        local Uses = false
        for _, ThemeKey in Entry.Properties do
            if ThemeKey == Key then Uses = true break end
        end

        if Uses then
            -- a state tween still running (hover, toggle, tab...) would otherwise land on the OLD color,
            -- which is why elements needed a nudge after loading a config: stop it and snap every bound
            -- property to its current theme value
            local Running = self.ThemeTweens[Entry.Instance]
            if Running then
                Running:Cancel()
                self.ThemeTweens[Entry.Instance] = nil
            end

            for Property, ThemeKey in Entry.Properties do
                if self.Theme[ThemeKey] ~= nil then
                    Entry.Instance[Property] = self.Theme[ThemeKey]
                end
            end
        end
    end
end
--#endregion

--#region Fading (caches original transparency so interrupted fades never lose a value)
local TransparencyProperties = function(Target)
    if Target:IsA("TextLabel") or Target:IsA("TextButton") or Target:IsA("TextBox") then
        return { "TextTransparency", "BackgroundTransparency" }
    elseif Target:IsA("ImageLabel") or Target:IsA("ImageButton") then
        return { "ImageTransparency", "BackgroundTransparency" }
    elseif Target:IsA("ScrollingFrame") then
        return { "ScrollBarImageTransparency", "BackgroundTransparency" }
    elseif Target:IsA("Frame") then
        return { "BackgroundTransparency" }
    elseif Target:IsA("UIStroke") then
        return { "Transparency" }
    end
end

function library_object:Fade(Root, Visible, Info, OnComplete)
    Info = Info or TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local Items = Root:GetDescendants()
    TableInsert(Items, Root)

    -- a newer fade on the same root cancels the pending hide of an older one
    local Token = (self.FadeTokens[Root] or 0) + 1
    self.FadeTokens[Root] = Token

    if Visible then Root.Visible = true end

    for _, Item in Items do
        if self.NoFade[Item] then continue end
        local Properties = TransparencyProperties(Item)
        if not Properties then continue end

        local Cache = self.OriginalTransparency[Item]
        if not Cache then
            Cache = { }
            for _, Property in Properties do Cache[Property] = Item[Property] end
            self.OriginalTransparency[Item] = Cache
        end

        for _, Property in Properties do
            if Cache[Property] >= 1 then continue end
            if Visible then Item[Property] = 1 end
            TweenService:Create(Item, Info, { [Property] = Visible and Cache[Property] or 1 }):Play()
        end
    end

    task.delay(Info.Time, function()
        if self.FadeTokens[Root] ~= Token then return end
        if not Visible then
            Root.Visible = false
            for _, Item in Items do
                local Cache = self.OriginalTransparency[Item]
                if Cache then
                    for Property, Value in Cache do Item[Property] = Value end
                end
            end
        end
        if OnComplete then OnComplete() end
    end)
end
--#endregion

--#region Popups (one open at a time, closes on outside click, follows its anchor)
function library_object:ClosePopup()
    if self.OpenPopup then
        local Popup = self.OpenPopup
        self.OpenPopup = nil
        Popup.Close()
    end
end

function library_object:RegisterPopup(Frame, Anchor, Close, OffsetY, AlignRight, Extras)
    self:ClosePopup()
    self.OpenPopup = { Frame = Frame, Anchor = Anchor, Close = Close, OffsetY = OffsetY or 0, AlignRight = AlignRight, Extras = Extras }
end

local PopupInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
library_object.PopupInfo = PopupInfo

-- Smooth open/close for popups: fades everything, and unrolls vertically when Height is given
function library_object:AnimatePopup(Wrapper, Open, Height)
    local Instance = Wrapper.Instance
    if Height then
        local Width = Instance.Size.X
        if Open then
            Instance.Size = UDim2New(Width.Scale, Width.Offset, 0, 0)
        end
        Wrapper:Tween({ Size = UDim2New(Width.Scale, Width.Offset, 0, Open and Height or 0) }, PopupInfo)
    end
    self:Fade(Instance, Open, PopupInfo)
end
--#endregion

--#region Holder
library_object.Holder = library_object:Create("ScreenGui", {
    Parent = GetHui(),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999,
})

library_object.NotificationHolder = library_object:Create("Frame", {
    Parent = library_object.Holder,
    BackgroundTransparency = 1,
    Position = UDim2New(0, 12, 0, 50),
    Size = UDim2New(0, 320, 1, -62),
})

library_object:Create("UIListLayout", {
    Parent = library_object.NotificationHolder,
    Padding = UDimNew(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
})

library_object.TooltipLabel = library_object:Create("TextLabel", {
    Parent = library_object.Holder,
    AutomaticSize = Enum.AutomaticSize.XY,
    BackgroundTransparency = 0,
    BackgroundColor3 = library_object.Theme.Background,
    Visible = false,
    ZIndex = 200,
}):Theme({ BackgroundColor3 = "Background", TextColor3 = "Text Color" }):TextStroke()
library_object.TooltipLabel:Stroke("Outline")
library_object:Create("UIPadding", {
    Parent = library_object.TooltipLabel,
    PaddingLeft = UDimNew(0, 5), PaddingRight = UDimNew(0, 5),
    PaddingTop = UDimNew(0, 3), PaddingBottom = UDimNew(0, 4),
})

function library_object:AttachTooltip(Target, Text)
    if not Text then return end

    Target:OnHover(function()
        self.TooltipLabel.Instance.Text = Text
        self:Fade(self.TooltipLabel.Instance, true, TweenInfo.new(0.12))
    end, function()
        self:Fade(self.TooltipLabel.Instance, false, TweenInfo.new(0.12))
    end)
end
--#endregion

--#region Accent line with glow, logo, glow rings
-- A 1px accent line with a soft two-step glow around it (active tabs, section headers)
function library_object:AccentLine(Parent, Vertical, Position, Size, ZIndex)
    local Line = self:Create("Frame", {
        Parent = Parent,
        Position = Position,
        Size = Size,
        BackgroundColor3 = self.Theme.Accent,
        ZIndex = ZIndex or 2,
    }):Theme({ BackgroundColor3 = "Accent" })

    for Index, Transparency in { 0.72, 0.88 } do
        local Spread = Index * 2 + 1
        self:Create("Frame", {
            Parent = Line,
            AnchorPoint = Vector2New(0.5, 0.5),
            Position = UDim2New(0.5, 0, 0.5, 0),
            Size = Vertical and UDim2New(0, Spread, 1, 0) or UDim2New(1, 0, 0, Spread),
            BackgroundColor3 = self.Theme.Accent,
            BackgroundTransparency = Transparency,
            ZIndex = ZIndex or 2,
        }):Theme({ BackgroundColor3 = "Accent" })
    end

    return Line
end

-- The kimikahax bird, rebuilt from the original's pixels (19x17): {row, x, width, transparency}.
-- Pass Icon = "rbxassetid://..." to use an image instead.
local LogoRuns = {
    {0,0,2,0.5}, {0,8,1,0.5}, {1,1,3,0.5}, {1,8,2,0.5}, {2,1,4,0.5}, {2,8,3,0.5}, {3,2,5,0.5}, {3,8,2,0.5},
    {3,10,1,0}, {3,11,1,0.5}, {4,2,8,0.5}, {4,10,2,0}, {4,12,1,0.5}, {5,2,3,0.5}, {5,5,4,0}, {5,9,2,0.5},
    {5,11,3,0}, {6,2,3,0.5}, {6,5,6,0}, {6,11,1,0.5}, {6,12,2,0}, {6,14,4,0.5}, {7,3,3,0.5}, {7,6,6,0},
    {7,12,2,0.5}, {7,14,4,0}, {7,18,1,0.5}, {8,4,2,0.5}, {8,6,11,0}, {8,17,2,0.5}, {9,3,3,0.5}, {9,6,10,0},
    {9,16,1,0.5}, {10,3,3,0.5}, {10,6,8,0}, {10,14,1,0.5}, {11,5,2,0.5}, {11,7,6,0}, {11,13,1,0.5},
    {12,7,2,0.5}, {12,9,2,0}, {12,11,1,0.5}, {13,8,1,0.5}, {13,9,1,0}, {13,10,1,0.5}, {14,7,3,0.5},
    {15,7,1,0.5}, {16,6,1,0.5},
}

function library_object:CreateLogo(Parent, Icon, ZIndex)
    local Holder = self:Create("Frame", {
        Parent = Parent,
        BackgroundTransparency = 1,
        Size = UDim2New(0, 19, 0, 17),
        ZIndex = ZIndex or 2,
    })

    if Icon and Icon ~= "" then
        self:Create("ImageLabel", {
            Parent = Holder,
            BackgroundTransparency = 1,
            Size = UDim2New(1, 0, 1, 0),
            Image = Icon,
            ImageColor3 = self.Theme.Accent,
            ZIndex = ZIndex or 2,
        }):Theme({ ImageColor3 = "Accent" })
        return Holder
    end

    for _, Run in LogoRuns do
        self:Create("Frame", {
            Parent = Holder,
            Position = UDim2New(0, Run[2], 0, Run[1]),
            Size = UDim2New(0, Run[3], 0, 1),
            BackgroundColor3 = self.Theme.Accent,
            BackgroundTransparency = Run[4] > 0 and 0.45 or 0,
            ZIndex = ZIndex or 2,
        }):Theme({ BackgroundColor3 = "Accent" })
    end

    return Holder
end

-- Soft dark glow (drop shadow) around a frame, as behind the original watermark.
-- Darkness = opacity, the animation makes it breathe. Rings sit in a sibling holder so they never
-- affect the target's automatic size.
function library_object:CreateGlow(Target, Layers)
    local Glow = { Strokes = { } }

    local Holder = self:Create("Frame", {
        Parent = Target.Instance.Parent,
        BackgroundTransparency = 1,
        ZIndex = Target.Instance.ZIndex,
    })
    self.NoFade[Holder.Instance] = true

    local Sync = function()
        Holder.Instance.Position = Target.Instance.Position
        Holder.Instance.Size = UDim2New(0, Target.Instance.AbsoluteSize.X, 0, Target.Instance.AbsoluteSize.Y)
        Holder.Instance.Visible = Target.Instance.Visible
    end
    self:Connect(Target.Instance:GetPropertyChangedSignal("AbsoluteSize"), Sync)
    self:Connect(Target.Instance:GetPropertyChangedSignal("Position"), Sync)
    self:Connect(Target.Instance:GetPropertyChangedSignal("Visible"), Sync)
    Sync()

    for Index = 1, Layers or 6 do
        local Ring = self:Create("Frame", {
            Parent = Holder,
            BackgroundTransparency = 1,
            Position = UDim2New(0, -Index, 0, -Index),
            Size = UDim2New(1, Index * 2, 1, Index * 2),
            ZIndex = Target.Instance.ZIndex,
        })
        local Stroke = self:Create("UIStroke", {
            Parent = Ring,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            LineJoinMode = Enum.LineJoinMode.Round,
            Color = FromRGB(0, 0, 0),
            Transparency = 1,
        })
        TableInsert(Glow.Strokes, Stroke)
    end

    TableInsert(self.Glows, Glow)
    self:UpdateGlows(os.clock())
    return Glow
end

function library_object:UpdateGlows(Time)
    local Settings = self.GlowSettings
    local Pulse = Settings.Animated and (0.55 + 0.45 * math.sin(Time * Settings.Speed * math.pi * 2)) or 1

    for _, Glow in self.Glows do
        local Count = #Glow.Strokes
        for Index, Stroke in Glow.Strokes do
            local Strength = Settings.Darkness * Pulse * (1 - (Index - 1) / Count) * 0.45
            Stroke.Instance.Transparency = 1 - MathClamp(Strength, 0, 1)
        end
    end
end

-- One RenderStepped drives tooltip, popup positioning, glow pulse and rainbow colorpickers
library_object:Connect(RunService.RenderStepped, function()
    local Mouse = UserInputService:GetMouseLocation()

    if library_object.TooltipLabel.Instance.Visible then
        library_object.TooltipLabel.Instance.Position = UDim2New(0, Mouse.X + 12, 0, Mouse.Y + 12)
    end

    local Popup = library_object.OpenPopup
    if Popup and Popup.Anchor then
        -- AbsolutePosition excludes the topbar inset, but the holder ignores it: add it back
        local Anchor = Popup.Anchor.Instance
        local Frame = Popup.Frame.Instance
        local Inset = GuiService:GetGuiInset().Y
        local Screen = library_object.Holder.Instance.AbsoluteSize

        local X = Anchor.AbsolutePosition.X
        if Popup.AlignRight then
            X = Anchor.AbsolutePosition.X + Anchor.AbsoluteSize.X - Frame.AbsoluteSize.X
        end
        X = MathClamp(X, 4, math.max(4, Screen.X - Frame.AbsoluteSize.X - 4))

        Frame.Position = UDim2New(0, X, 0, Anchor.AbsolutePosition.Y + Anchor.AbsoluteSize.Y + Popup.OffsetY + Inset)
    end

    local Now = os.clock()
    library_object:UpdateGlows(Now)

    if next(library_object.Rainbows) then
        local Hue = (Now * 0.15) % 1
        for Picker in library_object.Rainbows do
            Picker.Hue = Hue
            Picker:Refresh()
        end
    end
end)

library_object:Connect(UserInputService.InputBegan, function(Input)
    if not IsClick(Input) then return end

    local Popup = library_object.OpenPopup
    if not Popup then return end

    task.defer(function()
        if library_object.OpenPopup ~= Popup then return end
        if library_object:IsMouseOver(Popup.Frame.Instance) then return end
        if Popup.Anchor and library_object:IsMouseOver(Popup.Anchor.Instance) then return end
        for _, Extra in Popup.Extras or { } do
            if Extra.Instance.Visible and library_object:IsMouseOver(Extra.Instance) then return end
        end
        library_object:ClosePopup()
    end)
end)
--#endregion

--#region Notifications
-- Styled like the keybind list: bevel box, glowing accent bar on the left, draining accent line at the bottom.
-- Sizes are computed from the text (no AutomaticSize, which stretched boxes containing scale-sized children).
local NotifyInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function library_object:Notification(Text, Duration, Color)
    Duration = Duration or 4
    local Height = 24

    local Slot = self:Create("Frame", {
        Parent = self.NotificationHolder,
        BackgroundTransparency = 1,
        Size = UDim2New(0, 120, 0, Height),
    })

    local Box = self:Create("Frame", {
        Parent = Slot,
        Position = UDim2New(0, -16, 0, 0),
        Size = UDim2New(1, 0, 1, 0),
        BackgroundColor3 = self.Theme.Contrast,
        Visible = false,
    }):Theme({ BackgroundColor3 = "Contrast" })
    self:Create("UIGradient", {
        Parent = Box,
        Rotation = 90,
        Color = ColorSequence.new(FromRGB(255, 255, 255), FromRGB(170, 170, 170)),
    })
    Box:Bevel()

    local Bar = self:AccentLine(Box, true, UDim2New(0, 1, 0, 1), UDim2New(0, 1, 1, -2), 3)
    if Color then
        Bar.Instance.BackgroundColor3 = Color
        for _, Child in Bar.Instance:GetChildren() do
            if Child:IsA("Frame") then Child.BackgroundColor3 = Color end
        end
    end

    local Label = self:Create("TextLabel", {
        Parent = Box,
        Text = Text,
        Position = UDim2New(0, 11, 0, 0),
        Size = UDim2New(1, -11, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 2,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    local Progress = self:Create("Frame", {
        Parent = Box,
        Position = UDim2New(0, 2, 1, -2),
        Size = UDim2New(1, -3, 0, 1),
        BackgroundColor3 = Color or self.Theme.Accent,
        BackgroundTransparency = 0.35,
        ZIndex = 3,
    })
    if not Color then Progress:Theme({ BackgroundColor3 = "Accent" }) end

    local Resize = function()
        Slot.Instance.Size = UDim2New(0, Label.Instance.TextBounds.X + 22, 0, Height)
    end
    self:Connect(Label.Instance:GetPropertyChangedSignal("TextBounds"), Resize)
    Resize()

    -- slide in from the left while fading in, drain, then slide back out
    Box:Tween({ Position = UDim2New(0, 0, 0, 0) }, NotifyInfo)
    self:Fade(Box.Instance, true, NotifyInfo)
    Progress:Tween({ Size = UDim2New(0, 0, 0, 1) }, TweenInfo.new(Duration, Enum.EasingStyle.Linear))

    task.delay(Duration, function()
        if self.Unloaded then return end
        Box:Tween({ Position = UDim2New(0, -16, 0, 0) }, NotifyInfo)
        self:Fade(Box.Instance, false, NotifyInfo, function()
            Slot.Instance:Destroy()
        end)
    end)
end
--#endregion

--#region Watermark
local WatermarkParts = { "Title", "Fps", "Ping", "Game Name", "User ID", "Local Time" }

-- Measured from the original: 225x38 inside a 1px outline, 1px highlight, accent line on the first
-- inner row, 19x17 bird at x=8, bold title at x=34, stats after it, 9px right padding.
function library_object:Watermark()
    if self.WatermarkObject then return self.WatermarkObject end

    local Watermark = { Parts = { "Title", "Fps", "Ping" }, RefreshRate = 0.1, Fps = 0, GameName = "Game" }
    local Height = 38

    local Frame = self:Create("Frame", {
        Parent = self.Holder,
        Position = UDim2New(0, math.max(12, Camera.ViewportSize.X - 300), 0, 12),
        Size = UDim2New(0, 225, 0, Height),
        BackgroundColor3 = self.Theme.Contrast,
        ZIndex = 2,
    }):Theme({ BackgroundColor3 = "Contrast" })
    self:Create("UIGradient", {
        Parent = Frame,
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, FromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(0.6, FromRGB(172, 172, 172)),
            ColorSequenceKeypoint.new(1, FromRGB(165, 165, 165)),
        }),
    })
    Frame:Bevel()
    Frame:MakeDraggable()
    self:TrackLayout("Watermark", Frame, false)

    self:CreateGlow(Frame, 6)

    -- bright accent line along the top (accent washed toward the text color, like the original)
    local Line = self:AccentLine(Frame, false, UDim2New(0, 1, 0, 1), UDim2New(1, -2, 0, 1), 4)
    self:Create("Frame", {
        Parent = Line,
        Size = UDim2New(1, 0, 1, 0),
        BackgroundColor3 = self.Theme["Text Color"],
        BackgroundTransparency = 0.7,
        ZIndex = 5,
    }):Theme({ BackgroundColor3 = "Text Color" })

    local Content = self:Create("Frame", {
        Parent = Frame,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 0, 0, 1),
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2New(0, 0, 0, Height - 1),
        ZIndex = 3,
    })
    self:Create("UIListLayout", {
        Parent = Content,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDimNew(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    self:Create("UIPadding", { Parent = Content, PaddingLeft = UDimNew(0, 8), PaddingRight = UDimNew(0, 9) })

    local Logo = self:CreateLogo(Content, nil, 4)
    Logo.Instance.LayoutOrder = 1

    local Title = self:Create("TextLabel", {
        Parent = Content,
        Text = self.Name,
        Bold = true,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2New(0, 0, 0, Height - 1),
        LayoutOrder = 2,
        ZIndex = 4,
    }):Theme({ TextColor3 = "Accent" }):TextStroke()
    TableInsert(self.NameLabels, Title)

    local Info = self:Create("TextLabel", {
        Parent = Content,
        Text = "",
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2New(0, 0, 0, Height - 1),
        LayoutOrder = 3,
        ZIndex = 4,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    -- the frame follows its content width smoothly
    self:Connect(Content.Instance:GetPropertyChangedSignal("AbsoluteSize"), function()
        Frame:Tween({ Size = UDim2New(0, Content.Instance.AbsoluteSize.X, 0, Height) })
    end)

    task.spawn(function()
        local Ok, Result = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
        if Ok and type(Result) == "table" and Result.Name then Watermark.GameName = Result.Name end
    end)

    local GetPing = function()
        local Ok, Ping = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        return Ok and MathFloor(tonumber(Ping) or 0) or 0
    end

    function Watermark:Update()
        local Show = function(Part) return TableFind(self.Parts, Part) ~= nil end
        local Pieces = { }

        if Show("Fps") then TableInsert(Pieces, self.Fps .. " fps") end
        if Show("Ping") then TableInsert(Pieces, GetPing() .. " ping") end
        if Show("Game Name") then TableInsert(Pieces, self.GameName) end
        if Show("User ID") then TableInsert(Pieces, tostring(LocalPlayer.UserId)) end
        if Show("Local Time") then TableInsert(Pieces, os.date("%H:%M:%S")) end

        Title.Instance.Visible = Show("Title")
        Logo.Instance.Visible = Show("Title")

        local Text = table.concat(Pieces, " - ")
        if Show("Title") and Text ~= "" then Text = " - " .. Text end
        Info.Instance.Text = Text
        Info.Instance.Visible = Text ~= ""
    end

    function Watermark:SetParts(Parts)
        self.Parts = type(Parts) == "table" and Parts or { }
        self:Update()
    end

    function Watermark:SetVisibility(Bool)
        if Frame.Instance.Visible == Bool then return end
        library_object:Fade(Frame.Instance, Bool, library_object.PopupInfo)
    end

    local Frames, Last = 0, os.clock()
    self:Connect(RunService.RenderStepped, function()
        Frames += 1
        local Now = os.clock()
        if Now - Last >= 1 then
            Watermark.Fps = MathFloor(Frames / (Now - Last) + 0.5)
            Frames, Last = 0, Now
        end
    end)

    task.spawn(function()
        while not library_object.Unloaded do
            Watermark:Update()
            task.wait(math.max(Watermark.RefreshRate, 0.05))
        end
    end)

    Watermark:Update()
    self.WatermarkObject = Watermark
    return Watermark
end
--#endregion

--#region Keybind list
-- Measured from the original: 169px wide inside the outline, 25px header (gradient + accent bar
-- + bold title at x=11), highlight separator, rows of [6px square] Name (Key) - (Mode).
function library_object:KeybindList(StartVisible)
    if self.KeyList then return self.KeyList end

    local List = { Entries = { } }

    local Frame = self:Create("Frame", {
        Parent = self.Holder,
        Position = UDim2New(0, 12, 0.42, 0),
        Size = UDim2New(0, 169, 0, 36),
        BackgroundColor3 = self.Theme.Background,
        Visible = StartVisible ~= false,
    }):Theme({ BackgroundColor3 = "Background" }):Bevel()
    Frame:MakeDraggable()
    self:TrackLayout("KeybindList", Frame, false)

    local Header = self:Create("Frame", {
        Parent = Frame,
        Size = UDim2New(1, 0, 0, 25),
        BackgroundColor3 = self.Theme.Contrast,
        ZIndex = 2,
    }):Theme({ BackgroundColor3 = "Contrast" }):Shade(FromRGB(185, 185, 185))

    self:AccentLine(Header, true, UDim2New(0, 1, 0, 1), UDim2New(0, 1, 1, -1), 4)

    self:Create("TextLabel", {
        Parent = Header,
        Text = "Keybinds",
        Bold = true,
        Position = UDim2New(0, 11, 0, 0),
        Size = UDim2New(1, -22, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    -- the original separates header and body with a lighter line, not a dark one
    self:Create("Frame", {
        Parent = Frame,
        Position = UDim2New(0, 0, 0, 25),
        Size = UDim2New(1, 0, 0, 1),
        BackgroundColor3 = self.Theme.Contrast,
        ZIndex = 3,
    }):Theme({ BackgroundColor3 = "Contrast" })

    local Content = self:Create("Frame", {
        Parent = Frame,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 0, 0, 26),
        Size = UDim2New(0, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        ZIndex = 2,
    })
    self:Create("UIListLayout", { Parent = Content, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDimNew(0, 2) })
    self:Create("UIPadding", {
        Parent = Content,
        PaddingLeft = UDimNew(0, 7), PaddingRight = UDimNew(0, 10),
        PaddingTop = UDimNew(0, 5), PaddingBottom = UDimNew(0, 5),
    })

    -- explicit size from the content (width never below the original 169px)
    self:Connect(Content.Instance:GetPropertyChangedSignal("AbsoluteSize"), function()
        local Size = Content.Instance.AbsoluteSize
        Frame:Tween({ Size = UDim2New(0, math.max(169, Size.X), 0, 26 + math.max(Size.Y, 10)) })
    end)

    local Order = 0

    function List:Update(Keybind)
        local Entry = self.Entries[Keybind]

        if not Entry then
            Order += 1
            local Row = library_object:Create("Frame", {
                Parent = Content,
                BackgroundTransparency = 1,
                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2New(0, 0, 0, 15),
                LayoutOrder = Order,
                Visible = false,
                ZIndex = 2,
            })
            library_object:Create("UIListLayout", {
                Parent = Row,
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                Padding = UDimNew(0, 5),
                SortOrder = Enum.SortOrder.LayoutOrder,
            })

            -- 8px slot so the name starts 13px after the square's left edge, as in the original
            local SquareSlot = library_object:Create("Frame", {
                Parent = Row,
                BackgroundTransparency = 1,
                Size = UDim2New(0, 8, 0, 6),
                LayoutOrder = 1,
            })
            local Square = library_object:Create("Frame", {
                Parent = SquareSlot,
                Size = UDim2New(0, 6, 0, 6),
                BackgroundColor3 = library_object.Theme.Accent,
                ZIndex = 3,
            }):Theme({ BackgroundColor3 = "Accent" }):Shade(FromRGB(200, 200, 200))

            local MakeText = function(Bold, ThemeKey, LayoutOrder)
                return library_object:Create("TextLabel", {
                    Parent = Row,
                    Bold = Bold,
                    AutomaticSize = Enum.AutomaticSize.X,
                    Size = UDim2New(0, 0, 0, 15),
                    LayoutOrder = LayoutOrder,
                    ZIndex = 3,
                }):Theme({ TextColor3 = ThemeKey }):TextStroke()
            end

            Entry = {
                Row = Row,
                Square = Square,
                Name = MakeText(true, "Text Color", 3),
                Key = MakeText(true, "Accent", 4),
                Mode = MakeText(false, "Disabled Text Color", 5),
                Shown = false,
            }
            self.Entries[Keybind] = Entry
        end

        Entry.Name.Instance.Text = Keybind.Name
        Entry.Key.Instance.Text = "(" .. library_object:KeyName(Keybind.Key) .. ")"
        Entry.Mode.Instance.Text = "- (" .. Keybind.Mode .. ")"

        local Show = Keybind.Active and Keybind.Key ~= nil and Keybind.ShowInList
        if Show ~= Entry.Shown then
            Entry.Shown = Show
            library_object:Fade(Entry.Row.Instance, Show, library_object.PopupInfo)
        end
    end

    function List:SetVisibility(Bool)
        if Frame.Instance.Visible == Bool then return end
        library_object:Fade(Frame.Instance, Bool, library_object.PopupInfo)
    end

    self.KeyList = List
    return List
end
--#endregion

--#region Small shared builders
-- Tab strip button used by the main tabs, multi-sections and the colorpicker.
-- Width comes from the text (no AutomaticSize, so the accent line can span it); the accent line grows from the center.
local TabInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local CreateSubTab = function(Parent, Name, Order, ZIndex, Padding)
    Padding = Padding or 13
    ZIndex = ZIndex or 2

    local Button = library_object:Create("TextButton", {
        Parent = Parent,
        Size = UDim2New(0, 40, 1, 0),
        BackgroundTransparency = 0,
        BackgroundColor3 = library_object.Theme["Tab Button Low Contrast"],
        Text = Name,
        LayoutOrder = Order,
        ZIndex = ZIndex,
    }):Theme({ BackgroundColor3 = "Tab Button Low Contrast", TextColor3 = "Disabled Text Color" }):TextStroke()

    local Resize = function()
        Button.Instance.Size = UDim2New(0, Button.Instance.TextBounds.X + Padding * 2, 1, 0)
    end
    library_object:Connect(Button.Instance:GetPropertyChangedSignal("TextBounds"), Resize)
    Resize()

    -- right separator (sits in the 1px gap of the tab row)
    library_object:Create("Frame", {
        Parent = Button,
        Position = UDim2New(1, 0, 0, 0),
        Size = UDim2New(0, 1, 1, 0),
        BackgroundColor3 = library_object.Theme.Outline,
        ZIndex = ZIndex + 1,
    }):Theme({ BackgroundColor3 = "Outline" })

    local Line = library_object:AccentLine(Button, false, UDim2New(0.5, 0, 0, 0), UDim2New(0, 0, 0, 1), ZIndex + 1)
    Line.Instance.AnchorPoint = Vector2New(0.5, 0)

    local Tab = { Button = Button, Line = Line, Active = false }

    function Tab:SetActive(Bool)
        self.Active = Bool
        Line:Tween({ Size = UDim2New(Bool and 1 or 0, 0, 0, 1) }, TabInfo)
        Button:TweenTheme({
            BackgroundColor3 = Bool and "Background" or "Tab Button Low Contrast",
            TextColor3 = Bool and "Text Color" or "Disabled Text Color",
        })
    end

    Button:OnHover(function()
        if not Tab.Active then Button:TweenTheme({ TextColor3 = "Text Color" }) end
    end, function()
        if not Tab.Active then Button:TweenTheme({ TextColor3 = "Disabled Text Color" }) end
    end)

    return Tab
end

-- Check box as in the original: 12px, shaded fill, lighter 1px edge and a faint accent halo when on.
-- State only changes colors (never transparency) so window fades always restore correctly.
local CreateCheckBox = function(Parent, ZIndex)
    local Box = library_object:Create("Frame", {
        Parent = Parent,
        AnchorPoint = Vector2New(0, 0.5),
        Position = UDim2New(0, 1, 0.5, 0),
        Size = UDim2New(0, 12, 0, 12),
        BackgroundColor3 = library_object.Theme.Inline,
        ZIndex = ZIndex,
    }):Theme({ BackgroundColor3 = "Inline" }):Shade(FromRGB(140, 140, 140))

    local Halo = library_object:Create("UIStroke", {
        Parent = Box,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Miter,
        Color = library_object.Theme.Background,
        Transparency = 0.75,
    }):Theme({ Color = "Background" })

    local EdgeFrame = library_object:Create("Frame", {
        Parent = Box,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 1, 0, 1),
        Size = UDim2New(1, -2, 1, -2),
        ZIndex = ZIndex,
    })
    local Edge = library_object:Create("UIStroke", {
        Parent = EdgeFrame,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Miter,
        Color = library_object.Theme.Outline,
        Transparency = 0.45,
    }):Theme({ Color = "Outline" })

    local Check = { Box = Box }
    function Check:Set(Bool)
        Box:TweenTheme({ BackgroundColor3 = Bool and "Accent" or "Inline" })
        Halo:TweenTheme({ Color = Bool and "Accent" or "Background" })
        Edge:TweenTheme({ Color = Bool and "Text Color" or "Outline" })
    end
    function Check:Hover(Bool, On)
        if On then return end
        Box:TweenTheme({ BackgroundColor3 = Bool and "Contrast" or "Inline" })
    end
    return Check
end

-- Standard boxed control (dropdown box, textbox, button): Inline fill, soft shading, bevel edge
local CreateBox = function(Class, Parent, Properties)
    Properties.Parent = Parent
    Properties.BackgroundColor3 = library_object.Theme.Inline
    if Class ~= "Frame" then Properties.BackgroundTransparency = 0 end
    return library_object:Create(Class, Properties):Theme({ BackgroundColor3 = "Inline" }):Shade(FromRGB(185, 185, 185)):Bevel()
end

-- A small check box + label row (used inside popups)
local CreateCheck = function(Parent, Text, Order, ZIndex)
    local Row = library_object:Create("TextButton", {
        Parent = Parent,
        Size = UDim2New(1, 0, 0, 14),
        LayoutOrder = Order,
        ZIndex = ZIndex,
    })
    local Box = CreateCheckBox(Row, ZIndex)
    local Label = library_object:Create("TextLabel", {
        Parent = Row,
        Text = Text,
        Position = UDim2New(0, 21, 0, 0),
        Size = UDim2New(1, -21, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = ZIndex,
    }):Theme({ TextColor3 = "Disabled Text Color" }):TextStroke()

    local Check = { Row = Row, Value = false }
    function Check:Set(Bool)
        self.Value = Bool
        Box:Set(Bool)
        Label:TweenTheme({ TextColor3 = Bool and "Text Color" or "Disabled Text Color" })
    end
    Row:OnHover(function() Box:Hover(true, Check.Value) end, function() Box:Hover(false, Check.Value) end)
    return Check
end
--#endregion

--#region Colorpicker (palette/hue/alpha are drawn with UIGradients: no image downloads)
local HueSequence = ColorSequence.new({
    ColorSequenceKeypoint.new(0.000, FromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.167, FromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.333, FromRGB(0, 255, 0)),
    ColorSequenceKeypoint.new(0.500, FromRGB(0, 255, 255)),
    ColorSequenceKeypoint.new(0.667, FromRGB(0, 0, 255)),
    ColorSequenceKeypoint.new(0.833, FromRGB(255, 0, 255)),
    ColorSequenceKeypoint.new(1.000, FromRGB(255, 0, 0)),
})

-- hard-edged two-tone sequence, fakes a checkerboard row behind the alpha bar
local CheckerSequence = function(Invert)
    local Points, Segments = { }, 9
    local A, B = FromRGB(95, 95, 95), FromRGB(150, 150, 150)
    for Segment = 0, Segments - 1 do
        local Color = ((Segment % 2 == 0) ~= Invert) and A or B
        local Start = Segment / Segments
        TableInsert(Points, ColorSequenceKeypoint.new(Segment == 0 and 0 or Start + 0.001, Color))
        TableInsert(Points, ColorSequenceKeypoint.new(Segment == Segments - 1 and 1 or (Segment + 1) / Segments, Color))
    end
    return ColorSequence.new(Points)
end

function library_object:CreateColorpicker(Parent, Data)
    local Colorpicker = {
        Name = Data.Name or Data.name or "Color",
        Flag = Data.Flag or Data.flag or self:NextFlag(),
        Callback = Data.Callback or Data.callback,
        Hue = 0, Saturation = 0, Value = 1, Alpha = 0,
        Color = FromRGB(255, 255, 255),
        Rainbow = false,
        Open = false,
    }

    local Default = Data.Default or Data.default or FromRGB(255, 255, 255)
    local DefaultAlpha = Data.Alpha or Data.alpha or 0
    if type(DefaultAlpha) ~= "number" then DefaultAlpha = 0 end

    local Swatch = self:Create("TextButton", {
        Parent = Parent.Holder,
        Size = UDim2New(0, 26, 0, 10),
        BackgroundTransparency = 0,
        BackgroundColor3 = Default,
        LayoutOrder = -(Data.Count or 0),
    })
    Swatch:Stroke("Outline")
    Swatch:Shade(FromRGB(150, 150, 150))

    -- popup window
    local Window = self:Create("Frame", {
        Parent = self.Holder,
        Size = UDim2New(0, 250, 0, 250),
        BackgroundColor3 = self.Theme.Background,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 100,
    }):Theme({ BackgroundColor3 = "Background" }):Bevel()

    local TabRow = self:Create("Frame", {
        Parent = Window,
        Position = UDim2New(0, 1, 0, 1),
        Size = UDim2New(1, -2, 0, 21),
        BackgroundColor3 = self.Theme.Inline,
        ZIndex = 101,
    }):Theme({ BackgroundColor3 = "Inline" }):Shade(FromRGB(180, 180, 180))
    self:Create("UIListLayout", {
        Parent = TabRow,
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDimNew(0, 1),
    })
    self:Create("Frame", {
        Parent = Window,
        Position = UDim2New(0, 0, 0, 22),
        Size = UDim2New(1, 0, 0, 1),
        BackgroundColor3 = self.Theme.Outline,
        ZIndex = 102,
    }):Theme({ BackgroundColor3 = "Outline" })

    local ColorPage = self:Create("Frame", {
        Parent = Window,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 0, 0, 23),
        Size = UDim2New(1, 0, 1, -23),
        ZIndex = 101,
    })

    local SettingsPage = self:Create("Frame", {
        Parent = Window,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 8, 0, 31),
        Size = UDim2New(1, -16, 1, -39),
        Visible = false,
        ZIndex = 101,
    })
    self:Create("UIListLayout", { Parent = SettingsPage, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDimNew(0, 6) })

    local Tabs = {
        Color = CreateSubTab(TabRow, "Color", 1, 102),
        Settings = CreateSubTab(TabRow, "Settings", 2, 102),
    }
    local CurrentTab = nil
    local SelectTab = function(Name)
        if CurrentTab == Name then return end
        local First = CurrentTab == nil
        CurrentTab = Name
        Tabs.Color:SetActive(Name == "Color")
        Tabs.Settings:SetActive(Name == "Settings")
        local Show, Hide = ColorPage, SettingsPage
        if Name == "Settings" then Show, Hide = SettingsPage, ColorPage end
        Hide.Instance.Visible = false
        if First then
            Show.Instance.Visible = true
        else
            library_object:Fade(Show.Instance, true, PopupInfo)
        end
    end
    Tabs.Color.Button:Connect("MouseButton1Click", function() SelectTab("Color") end)
    Tabs.Settings.Button:Connect("MouseButton1Click", function() SelectTab("Settings") end)
    SelectTab("Color")

    -- saturation / value square
    local Palette = self:Create("TextButton", {
        Parent = ColorPage,
        Position = UDim2New(0, 8, 0, 7),
        Size = UDim2New(1, -36, 0, 168),
        BackgroundTransparency = 0,
        BackgroundColor3 = FromRGB(255, 0, 0),
        ZIndex = 102,
    })
    Palette:Stroke("Outline")

    local White = self:Create("Frame", {
        Parent = Palette, Size = UDim2New(1, 0, 1, 0), BackgroundColor3 = FromRGB(255, 255, 255), ZIndex = 103,
    })
    self:Create("UIGradient", { Parent = White, Transparency = NumberSequence.new(0, 1) })

    local Black = self:Create("Frame", {
        Parent = Palette, Size = UDim2New(1, 0, 1, 0), BackgroundColor3 = FromRGB(0, 0, 0), ZIndex = 104,
    })
    self:Create("UIGradient", { Parent = Black, Rotation = 90, Transparency = NumberSequence.new(1, 0) })

    local PaletteCursor = self:Create("Frame", {
        Parent = Palette,
        AnchorPoint = Vector2New(0.5, 0.5),
        Size = UDim2New(0, 3, 0, 3),
        BackgroundColor3 = FromRGB(255, 255, 255),
        ZIndex = 106,
    })
    PaletteCursor:Stroke("Outline")

    local HueBar = self:Create("TextButton", {
        Parent = ColorPage,
        AnchorPoint = Vector2New(1, 0),
        Position = UDim2New(1, -8, 0, 7),
        Size = UDim2New(0, 12, 0, 168),
        BackgroundTransparency = 0,
        BackgroundColor3 = FromRGB(255, 255, 255),
        ZIndex = 102,
    })
    HueBar:Stroke("Outline")
    self:Create("UIGradient", { Parent = HueBar, Rotation = 90, Color = HueSequence })

    local HueCursor = self:Create("Frame", {
        Parent = HueBar,
        AnchorPoint = Vector2New(0, 0.5),
        Size = UDim2New(1, 0, 0, 2),
        BackgroundColor3 = FromRGB(255, 255, 255),
        ZIndex = 103,
    })
    HueCursor:Stroke("Outline")

    -- transparency bar: fake checkerboard + color fading in from the left
    local AlphaBar = self:Create("TextButton", {
        Parent = ColorPage,
        Position = UDim2New(0, 8, 0, 183),
        Size = UDim2New(1, -36, 0, 10),
        BackgroundTransparency = 0,
        BackgroundColor3 = FromRGB(255, 255, 255),
        ZIndex = 102,
    })
    AlphaBar:Stroke("Outline")

    for Row = 0, 1 do
        local Checker = self:Create("Frame", {
            Parent = AlphaBar,
            Position = UDim2New(0, 0, Row * 0.5, 0),
            Size = UDim2New(1, 0, 0.5, 0),
            BackgroundColor3 = FromRGB(255, 255, 255),
            ZIndex = 103,
        })
        self:Create("UIGradient", { Parent = Checker, Color = CheckerSequence(Row == 1) })
    end

    local AlphaFill = self:Create("Frame", {
        Parent = AlphaBar, Size = UDim2New(1, 0, 1, 0), BackgroundColor3 = FromRGB(255, 255, 255), ZIndex = 104,
    })
    self:Create("UIGradient", { Parent = AlphaFill, Transparency = NumberSequence.new(1, 0) })

    local AlphaCursor = self:Create("Frame", {
        Parent = AlphaBar,
        AnchorPoint = Vector2New(0.5, 0),
        Size = UDim2New(0, 2, 1, 0),
        BackgroundColor3 = FromRGB(255, 255, 255),
        ZIndex = 105,
    })
    AlphaCursor:Stroke("Outline")

    local Preview = self:Create("Frame", {
        Parent = ColorPage,
        AnchorPoint = Vector2New(1, 0),
        Position = UDim2New(1, -8, 0, 183),
        Size = UDim2New(0, 12, 0, 10),
        BackgroundColor3 = Default,
        ZIndex = 102,
    })
    Preview:Stroke("Outline")
    self.NoFade[Preview.Instance] = true -- its transparency shows the picked alpha

    local HexFrame = CreateBox("Frame", ColorPage, {
        Position = UDim2New(0, 8, 0, 200),
        Size = UDim2New(1, -16, 0, 19),
        ZIndex = 102,
    })

    local HexBox = self:Create("TextBox", {
        Parent = HexFrame,
        Position = UDim2New(0, 6, 0, 0),
        Size = UDim2New(1, -12, 1, 0),
        Text = "",
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 103,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    function Colorpicker:Refresh(SkipCallback)
        local Color = Color3.fromHSV(self.Hue, self.Saturation, self.Value)
        self.Color = Color

        Swatch.Instance.BackgroundColor3 = Color
        Preview.Instance.BackgroundColor3 = Color
        Preview.Instance.BackgroundTransparency = self.Alpha
        Palette.Instance.BackgroundColor3 = Color3.fromHSV(self.Hue, 1, 1)
        AlphaFill.Instance.BackgroundColor3 = Color
        PaletteCursor.Instance.Position = UDim2New(self.Saturation, 0, 1 - self.Value, 0)
        HueCursor.Instance.Position = UDim2New(0, 0, self.Hue, 0)
        AlphaCursor.Instance.Position = UDim2New(1 - self.Alpha, 0, 0, 0)

        local Hex = "#" .. Color:ToHex():upper() .. string.format("%02X", MathFloor(self.Alpha * 255 + 0.5))
        if not HexBox.Instance:IsFocused() then HexBox.Instance.Text = Hex end

        library_object.Flags[self.Flag] = { Color = Color, Alpha = self.Alpha, Hex = Color:ToHex(), Rainbow = self.Rainbow }

        if not SkipCallback then
            library_object:SafeCall(self.Callback, Color, self.Alpha)
        end
    end

    function Colorpicker:Set(Color, Alpha)
        if type(Color) == "string" then
            local Ok, Parsed = pcall(Color3.fromHex, Color)
            if not Ok then return end
            Color = Parsed
        elseif type(Color) == "table" then
            Color = FromRGB(Color[1], Color[2], Color[3])
        end

        self.Hue, self.Saturation, self.Value = Color:ToHSV()
        self.Alpha = Alpha or self.Alpha or 0
        self:Refresh()
    end

    function Colorpicker:Get() return self.Color, self.Alpha end

    function Colorpicker:SetRainbow(Bool)
        self.Rainbow = Bool
        library_object.Rainbows[self] = Bool or nil
        self:Refresh(true)
    end

    function Colorpicker:SetOpen(Bool)
        self.Open = Bool
        if Bool then
            library_object:RegisterPopup(Window, Swatch, function()
                Colorpicker.Open = false
                library_object:AnimatePopup(Window, false, 250)
            end, 4, true)
            library_object:AnimatePopup(Window, true, 250)
        elseif library_object.OpenPopup and library_object.OpenPopup.Frame == Window then
            library_object:ClosePopup()
        end
    end

    Swatch:Connect("MouseButton1Click", function()
        Colorpicker:SetOpen(not Colorpicker.Open)
    end)

    HexBox:Connect("FocusLost", function()
        local Text = HexBox.Instance.Text:gsub("#", ""):gsub("%s", "")
        if #Text == 6 or #Text == 8 then
            local Alpha = #Text == 8 and tonumber(Text:sub(7, 8), 16)
            local Ok, Color = pcall(Color3.fromHex, Text:sub(1, 6))
            if Ok and Color then
                Colorpicker:Set(Color, Alpha and library_object:Round(Alpha / 255, 0.01) or Colorpicker.Alpha)
                return
            end
        end
        Colorpicker:Refresh(true)
    end)

    -- settings tab: copy / paste / rainbow
    local CopyButton = CreateBox("TextButton", SettingsPage, {
        Size = UDim2New(1, 0, 0, 20), Text = "Copy", LayoutOrder = 1, ZIndex = 102,
    })
    CopyButton:Theme({ BackgroundColor3 = "Inline", TextColor3 = "Text Color" }):TextStroke()
    CopyButton:Connect("MouseButton1Click", function()
        library_object.CopiedColor = { Color = Colorpicker.Color, Alpha = Colorpicker.Alpha }
        if typeof(setclipboard) == "function" then
            pcall(setclipboard, "#" .. Colorpicker.Color:ToHex():upper())
        end
    end)

    local PasteButton = CreateBox("TextButton", SettingsPage, {
        Size = UDim2New(1, 0, 0, 20), Text = "Paste", LayoutOrder = 2, ZIndex = 102,
    })
    PasteButton:Theme({ BackgroundColor3 = "Inline", TextColor3 = "Text Color" }):TextStroke()
    PasteButton:Connect("MouseButton1Click", function()
        if library_object.CopiedColor then
            Colorpicker:Set(library_object.CopiedColor.Color, library_object.CopiedColor.Alpha)
        end
    end)

    local RainbowCheck = CreateCheck(SettingsPage, "Rainbow", 3, 102)
    RainbowCheck.Row:Connect("MouseButton1Click", function()
        RainbowCheck:Set(not RainbowCheck.Value)
        Colorpicker:SetRainbow(RainbowCheck.Value)
    end)

    -- dragging
    local Dragging = nil
    local UpdateDrag = function(Position)
        if Dragging == "Palette" then
            local P, S = Palette.Instance.AbsolutePosition, Palette.Instance.AbsoluteSize
            Colorpicker.Saturation = MathClamp((Position.X - P.X) / math.max(S.X, 1), 0, 1)
            Colorpicker.Value = 1 - MathClamp((Position.Y - P.Y) / math.max(S.Y, 1), 0, 1)
        elseif Dragging == "Hue" then
            local P, S = HueBar.Instance.AbsolutePosition, HueBar.Instance.AbsoluteSize
            Colorpicker.Hue = MathClamp((Position.Y - P.Y) / math.max(S.Y, 1), 0, 0.999)
        elseif Dragging == "Alpha" then
            local P, S = AlphaBar.Instance.AbsolutePosition, AlphaBar.Instance.AbsoluteSize
            Colorpicker.Alpha = library_object:Round(1 - MathClamp((Position.X - P.X) / math.max(S.X, 1), 0, 1), 0.01)
        end
        Colorpicker:Refresh()
    end

    local BeginDrag = function(Name)
        return function(Input)
            if IsClick(Input) then
                Dragging = Name
                UpdateDrag(Vector2New(Input.Position.X, Input.Position.Y))
            end
        end
    end

    Palette:Connect("InputBegan", BeginDrag("Palette"))
    HueBar:Connect("InputBegan", BeginDrag("Hue"))
    AlphaBar:Connect("InputBegan", BeginDrag("Alpha"))

    library_object:Connect(UserInputService.InputChanged, function(Input)
        if Dragging and IsMove(Input) then
            UpdateDrag(Vector2New(Input.Position.X, Input.Position.Y))
        end
    end)

    library_object:Connect(UserInputService.InputEnded, function(Input)
        if IsClick(Input) then Dragging = nil end
    end)

    self.SetFlags[Colorpicker.Flag] = function(Value)
        if type(Value) == "table" and Value.Color then
            if Value.Rainbow ~= nil and Value.Rainbow ~= Colorpicker.Rainbow then
                RainbowCheck:Set(Value.Rainbow == true)
                Colorpicker:SetRainbow(Value.Rainbow == true)
            end
            Colorpicker:Set(Value.Color, Value.Alpha)
        end
    end

    Colorpicker.Hue, Colorpicker.Saturation, Colorpicker.Value = Default:ToHSV()
    Colorpicker.Alpha = DefaultAlpha
    Colorpicker:Refresh(true)

    return Colorpicker
end
--#endregion

--#region Keybind
-- Modes: "Hold" (active while held), "Toggle" (press flips), "Always" (always active)
local KeybindModes = { "Hold", "Toggle", "Always" }

function library_object:CreateKeybind(Parent, Data)
    local Keybind = {
        Name = Data.Name or Data.name or "Keybind",
        Flag = Data.Flag or Data.flag or self:NextFlag(),
        Key = Data.Default or Data.default,
        Mode = Data.Mode or Data.mode or "Toggle",
        Callback = Data.Callback or Data.callback,
        OnKeyChanged = Data.OnKeyChanged,
        ShowInList = not (Data.NoList or false),
        Active = false,
        Binding = false,
    }

    if Keybind.Mode == "Always" then Keybind.Active = true end

    local Button = self:Create("TextButton", {
        Parent = Parent.Holder,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2New(0, 0, 0, 14),
        BackgroundTransparency = 0,
        BackgroundColor3 = self.Theme.Inline,
        Bold = true,
        Text = "",
        LayoutOrder = -(Data.Count or 0),
    }):Theme({ BackgroundColor3 = "Inline", TextColor3 = "Text Color" }):TextStroke()
    self:Create("UIPadding", { Parent = Button, PaddingLeft = UDimNew(0, 7), PaddingRight = UDimNew(0, 7) })
    self:Create("UISizeConstraint", { Parent = Button, MinSize = Vector2New(24, 14) })
    Button:OnHover(function() Button:TweenTheme({ BackgroundColor3 = "Contrast" }) end,
        function() Button:TweenTheme({ BackgroundColor3 = "Inline" }) end)

    -- right-click settings popup (as in the original: "Show in list" + "Mode")
    local Menu = self:Create("Frame", {
        Parent = self.Holder,
        Size = UDim2New(0, 150, 0, 110),
        BackgroundColor3 = self.Theme.Background,
        Visible = false,
        ZIndex = 100,
    }):Theme({ BackgroundColor3 = "Background" }):Bevel()

    local Header = self:Create("Frame", {
        Parent = Menu,
        Size = UDim2New(1, 0, 0, 22),
        BackgroundColor3 = self.Theme.Contrast,
        ZIndex = 101,
    }):Theme({ BackgroundColor3 = "Contrast" }):Shade(FromRGB(170, 170, 170))
    self:AccentLine(Header, true, UDim2New(0, 1, 0, 1), UDim2New(0, 1, 1, -1), 103)
    self:Create("TextLabel", {
        Parent = Header,
        Text = "Settings",
        Position = UDim2New(0, 10, 0, 0),
        Size = UDim2New(1, -20, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 102,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    local Body = self:Create("Frame", {
        Parent = Menu,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 8, 0, 29),
        Size = UDim2New(1, -16, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 101,
    })
    self:Create("UIListLayout", { Parent = Body, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDimNew(0, 5) })
    -- explicit height (AutomaticSize would stretch a frame that has scale-sized bevel children)
    self:Connect(Body.Instance:GetPropertyChangedSignal("AbsoluteSize"), function()
        Menu.Instance.Size = UDim2New(0, 150, 0, 29 + Body.Instance.AbsoluteSize.Y + 8)
    end)

    local ListCheck = CreateCheck(Body, "Show in list", 1, 102)

    self:Create("TextLabel", {
        Parent = Body,
        Text = "Mode",
        Size = UDim2New(1, 0, 0, 13),
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 2,
        ZIndex = 102,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    local ModeBox = CreateBox("TextButton", Body, { Size = UDim2New(1, 0, 0, 19), LayoutOrder = 3, ZIndex = 102 })
    local ModeText = self:Create("TextLabel", {
        Parent = ModeBox,
        Position = UDim2New(0, 6, 0, 0),
        Size = UDim2New(1, -24, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 103,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()
    self:Create("TextLabel", {
        Parent = ModeBox,
        AnchorPoint = Vector2New(1, 0),
        Position = UDim2New(1, -6, 0, 0),
        Size = UDim2New(0, 10, 1, 0),
        Text = "+",
        ZIndex = 103,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    -- the mode list drops out below the box, overlapping the popup edge like the original
    local ModeListHeight = #KeybindModes * 19 + 4
    local ModeList = self:Create("Frame", {
        Parent = ModeBox,
        Position = UDim2New(0, 0, 1, 3),
        Size = UDim2New(1, 0, 0, ModeListHeight),
        BackgroundColor3 = self.Theme.Background,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 110,
    }):Theme({ BackgroundColor3 = "Background" })
    ModeList:Stroke("Outline")
    local ModeHolder = self:Create("Frame", {
        Parent = ModeList,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 7, 0, 2),
        Size = UDim2New(1, -7, 0, ModeListHeight - 4),
        ZIndex = 110,
    })
    self:Create("UIListLayout", { Parent = ModeHolder, SortOrder = Enum.SortOrder.LayoutOrder })

    local ModeListOpen = false
    local SetModeList = function(Bool)
        if ModeListOpen == Bool then return end
        ModeListOpen = Bool
        library_object:AnimatePopup(ModeList, Bool, ModeListHeight)
    end

    local ModeButtons = { }
    for Index, Mode in KeybindModes do
        local ModeButton = self:Create("TextButton", {
            Parent = ModeHolder,
            Size = UDim2New(1, 0, 0, 19),
            Text = Mode,
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = Index,
            ZIndex = 111,
        }):Theme({ TextColor3 = "Text Color" }):TextStroke()
        ModeButtons[Mode] = ModeButton

        ModeButton:Connect("MouseButton1Click", function()
            Keybind:SetMode(Mode)
            SetModeList(false)
        end)
        ModeButton:OnHover(function()
            if Keybind.Mode ~= Mode then ModeButton:TweenTheme({ TextColor3 = "Accent" }) end
        end, function()
            if Keybind.Mode ~= Mode then ModeButton:TweenTheme({ TextColor3 = "Text Color" }) end
        end)
    end

    ModeBox:Connect("MouseButton1Click", function()
        SetModeList(not ModeListOpen)
    end)

    local WriteFlag = function()
        library_object.Flags[Keybind.Flag] = {
            Key = Keybind.Key and Keybind.Key.Name,
            KeyType = Keybind.Key and tostring(Keybind.Key.EnumType),
            Mode = Keybind.Mode,
            ShowInList = Keybind.ShowInList,
            Active = Keybind.Active,
        }
    end

    function Keybind:Display()
        Button.Instance.Text = self.Binding and "..." or library_object:KeyName(self.Key)
        Button:TweenTheme({ TextColor3 = self.Binding and "Accent" or "Text Color" })
        ModeText.Instance.Text = self.Mode
        for Name, ModeButton in ModeButtons do
            ModeButton:SetBold(Name == self.Mode)
            ModeButton:TweenTheme({ TextColor3 = Name == self.Mode and "Accent" or "Text Color" })
        end
        ListCheck:Set(self.ShowInList)
        if library_object.KeyList then library_object.KeyList:Update(self) end
    end

    function Keybind:SetActive(Bool)
        if self.Mode == "Always" then Bool = true end
        if self.Active == Bool then return end
        self.Active = Bool
        WriteFlag()
        self:Display()
        library_object:SafeCall(self.Callback, Bool)
        if self.OnActiveChanged then self.OnActiveChanged(Bool) end
    end

    function Keybind:SetMode(Mode)
        if not TableFind(KeybindModes, Mode) then return end
        local Previous = self.Mode
        self.Mode = Mode
        -- only force the state when entering/leaving "Always", so re-applying a mode never flips a toggle
        if Mode == "Always" then
            self:SetActive(true)
        elseif Previous == "Always" then
            self:SetActive(false)
        end
        WriteFlag()
        self:Display()
    end

    function Keybind:SetShowInList(Bool)
        self.ShowInList = Bool and true or false
        WriteFlag()
        self:Display()
    end

    function Keybind:Set(Key)
        self.Key = Key
        self.Binding = false
        WriteFlag()
        self:Display()
        if self.OnKeyChanged then library_object:SafeCall(self.OnKeyChanged, Key) end
    end

    function Keybind:Get() return self.Key, self.Mode, self.Active end

    ListCheck.Row:Connect("MouseButton1Click", function()
        Keybind:SetShowInList(not Keybind.ShowInList)
    end)

    Button:Connect("MouseButton1Click", function()
        Keybind.Binding = true
        Keybind:Display()
    end)

    Button:Connect("MouseButton2Click", function()
        if library_object.OpenPopup and library_object.OpenPopup.Frame == Menu then
            library_object:ClosePopup()
            return
        end
        ModeListOpen = false
        ModeList.Instance.Visible = false
        library_object:RegisterPopup(Menu, Button, function()
            SetModeList(false)
            library_object:Fade(Menu.Instance, false, PopupInfo)
        end, 3, true, { ModeList })
        library_object:Fade(Menu.Instance, true, PopupInfo)
    end)

    local Matches = function(Input)
        if not Keybind.Key then return false end
        if Keybind.Key.EnumType == Enum.KeyCode then
            return Input.KeyCode == Keybind.Key
        end
        return Input.UserInputType == Keybind.Key
    end

    library_object:Connect(UserInputService.InputBegan, function(Input, Processed)
        if Keybind.Binding then
            if Input.UserInputType == Enum.UserInputType.Keyboard then
                if Input.KeyCode == Enum.KeyCode.Escape or Input.KeyCode == Enum.KeyCode.Backspace then
                    Keybind:Set(nil)
                else
                    Keybind:Set(Input.KeyCode)
                end
            elseif Input.UserInputType == Enum.UserInputType.MouseButton1
                or Input.UserInputType == Enum.UserInputType.MouseButton2
                or Input.UserInputType == Enum.UserInputType.MouseButton3 then
                task.defer(function()
                    if Keybind.Binding then Keybind:Set(Input.UserInputType) end
                end)
            end
            return
        end

        if Processed or not Matches(Input) then return end

        if Keybind.Mode == "Toggle" then
            Keybind:SetActive(not Keybind.Active)
        elseif Keybind.Mode == "Hold" then
            Keybind:SetActive(true)
        end
    end)

    library_object:Connect(UserInputService.InputEnded, function(Input)
        if Keybind.Mode == "Hold" and Matches(Input) then
            Keybind:SetActive(false)
        end
    end)

    self.SetFlags[Keybind.Flag] = function(Value)
        if type(Value) ~= "table" then return end
        local Key = nil
        if Value.Key then
            local EnumSet = Value.KeyType == "UserInputType" and Enum.UserInputType or Enum.KeyCode
            pcall(function() Key = EnumSet[Value.Key] end)
        end
        Keybind:Set(Key)
        if Value.Mode then Keybind:SetMode(Value.Mode) end
        if Value.ShowInList ~= nil then Keybind:SetShowInList(Value.ShowInList) end
    end

    WriteFlag()
    Keybind:Display()

    return Keybind
end
--#endregion

--#region Window / Page / Section
local Window = { }
Window.__index = Window

local Page = { }
Page.__index = Page

local Section = { }
Section.__index = Section

function library_object:Window(Data)
    Data = Data or { }

    local NewWindow = setmetatable({
        Name = Data.Name or Data.name or library_object.Name,
        SubTitle = Data.SubTitle or Data.subtitle or "for Counter-Strike: Global Offensive",
        Size = Data.Size or Data.size or UDim2New(0, 618, 0, 536),
        Pages = { },
        IsOpen = true,
        Fading = false,
    }, Window)

    if Data.MenuKeybind then library_object.MenuKeybind = Data.MenuKeybind end

    local Viewport = Camera.ViewportSize

    local Main = library_object:Create("Frame", {
        Parent = library_object.Holder,
        Size = NewWindow.Size,
        Position = UDim2New(0, (Viewport.X - NewWindow.Size.X.Offset) / 2, 0, (Viewport.Y - NewWindow.Size.Y.Offset) / 2),
        BackgroundColor3 = library_object.Theme.Background,
    }):Theme({ BackgroundColor3 = "Background" }):Bevel()
    Main:MakeResizable(Vector2New(480, 360))
    library_object:TrackLayout("Window" .. (#library_object.Windows + 1), Main, true)

    -- title area: soft gradient that fades into the window body
    local TitleArea = library_object:Create("Frame", {
        Parent = Main,
        Position = UDim2New(0, 2, 0, 2),
        Size = UDim2New(1, -4, 0, 30),
        BackgroundColor3 = library_object.Theme.Contrast,
    }):Theme({ BackgroundColor3 = "Contrast" })
    library_object:Create("UIGradient", {
        Parent = TitleArea,
        Rotation = 90,
        Color = ColorSequence.new(FromRGB(255, 255, 255), FromRGB(170, 170, 170)),
    })

    local TitleBar = library_object:Create("TextButton", {
        Parent = Main,
        Size = UDim2New(1, 0, 0, 33),
        ZIndex = 2,
    })
    Main:MakeDraggable(TitleBar)

    local TitleContent = library_object:Create("Frame", {
        Parent = TitleBar,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 9, 0, 1),
        Size = UDim2New(1, -18, 1, 0),
        ZIndex = 2,
    })
    library_object:Create("UIListLayout", {
        Parent = TitleContent,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDimNew(0, 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local Logo = library_object:CreateLogo(TitleContent, Data.Icon, 3)
    Logo.Instance.LayoutOrder = 1

    library_object:Create("Frame", { Parent = TitleContent, BackgroundTransparency = 1, Size = UDim2New(0, 7, 0, 1), LayoutOrder = 2 })

    local TitleLabel = library_object:Create("TextLabel", {
        Parent = TitleContent,
        Text = NewWindow.Name,
        Bold = true,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2New(0, 0, 1, 0),
        LayoutOrder = 3,
        ZIndex = 3,
    }):Theme({ TextColor3 = "Accent" }):TextStroke()
    TableInsert(library_object.NameLabels, TitleLabel)

    local SubTitleLabel = library_object:Create("TextLabel", {
        Parent = TitleContent,
        Text = " " .. NewWindow.SubTitle,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2New(0, 0, 1, 0),
        LayoutOrder = 4,
        ZIndex = 3,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    -- tab strip
    local TabBar = library_object:Create("Frame", {
        Parent = Main,
        Position = UDim2New(0, 10, 0, 34),
        Size = UDim2New(1, -20, 0, 32),
        BackgroundColor3 = library_object.Theme.Inline,
        ZIndex = 2,
    }):Theme({ BackgroundColor3 = "Inline" }):Shade(FromRGB(185, 185, 185)):Bevel()

    local Tabs = library_object:Create("Frame", {
        Parent = TabBar,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 1, 0, 1),
        Size = UDim2New(1, -2, 1, -1),
        ZIndex = 3,
    })
    library_object:Create("UIListLayout", {
        Parent = Tabs,
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDimNew(0, 1),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local Content = library_object:Create("Frame", {
        Parent = Main,
        Position = UDim2New(0, 10, 0, 66),
        Size = UDim2New(1, -20, 1, -76),
        BackgroundColor3 = library_object.Theme.Background,
    }):Theme({ BackgroundColor3 = "Background" }):Bevel()

    NewWindow.Items = { Main = Main, Tabs = Tabs, Content = Content, Title = TitleLabel, SubTitle = SubTitleLabel }

    function NewWindow:SetTitle(Name, SubTitle)
        if Name then TitleLabel.Instance.Text = Name end
        if SubTitle then SubTitleLabel.Instance.Text = " " .. SubTitle end
    end

    library_object:Connect(UserInputService.InputBegan, function(Input, Processed)
        if Processed then return end
        if Input.KeyCode == library_object.MenuKeybind or Input.UserInputType == library_object.MenuKeybind then
            NewWindow:SetOpen(not NewWindow.IsOpen)
        end
    end)

    if IsMobile then
        local Toggle = library_object:Create("TextButton", {
            Parent = library_object.Holder,
            Position = UDim2New(0.5, -30, 0, 10),
            Size = UDim2New(0, 60, 0, 24),
            Text = "menu",
            BackgroundTransparency = 0,
            BackgroundColor3 = library_object.Theme.Background,
            ZIndex = 150,
        }):Theme({ BackgroundColor3 = "Background", TextColor3 = "Text Color" }):TextStroke()
        Toggle:Stroke("Accent")
        Toggle:MakeDraggable()
        library_object:TrackLayout("MobileToggle", Toggle, false)
        Toggle:Connect("MouseButton1Click", function() NewWindow:SetOpen(not NewWindow.IsOpen) end)

        library_object:Create("UIScale", { Parent = Main, Scale = 0.8 })
    end

    TableInsert(library_object.Windows, NewWindow)
    return NewWindow
end

function Window:SetOpen(Bool)
    if self.Fading then return end
    self.IsOpen = Bool
    self.Fading = true
    library_object:ClosePopup()
    library_object.TooltipLabel.Instance.Visible = false

    local Info = TweenInfo.new(library_object.Tween.Time, library_object.Tween.Style, library_object.Tween.Direction)
    library_object:Fade(self.Items.Main.Instance, Bool, Info, function() self.Fading = false end)
end

function Window:Page(Data)
    Data = Data or { }

    local NewPage = setmetatable({
        Window = self,
        Name = Data.Name or Data.name or "Page",
        Columns = Data.Columns or Data.columns or 2,
        ColumnFrames = { },
        Active = false,
    }, Page)

    local Tab = CreateSubTab(self.Items.Tabs, NewPage.Name, #self.Pages + 1, 4, 15)

    local Container = library_object:Create("Frame", {
        Parent = self.Items.Content,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 8, 0, 6),
        Size = UDim2New(1, -16, 1, -12),
        Visible = false,
    })
    library_object:Create("UIListLayout", {
        Parent = Container,
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,
        Padding = UDimNew(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    for Index = 1, NewPage.Columns do
        local Column = library_object:Create("ScrollingFrame", {
            Parent = Container,
            BackgroundTransparency = 1,
            Size = UDim2New(0, 0, 1, 0),
            CanvasSize = UDim2New(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 0,
            ScrollBarImageColor3 = library_object.Theme.Accent,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            LayoutOrder = Index,
        }):Theme({ ScrollBarImageColor3 = "Accent" })

        library_object:Create("UIListLayout", { Parent = Column, Padding = UDimNew(0, 9), SortOrder = Enum.SortOrder.LayoutOrder })
        library_object:Create("UIPadding", {
            Parent = Column,
            PaddingTop = UDimNew(0, 2), PaddingBottom = UDimNew(0, 2),
            PaddingLeft = UDimNew(0, 2), PaddingRight = UDimNew(0, 2),
        })

        NewPage.ColumnFrames[Index] = Column
    end

    NewPage.Items = { Tab = Tab, Container = Container }

    Tab.Button:Connect("MouseButton1Click", function() NewPage:Turn() end)

    TableInsert(self.Pages, NewPage)
    if #self.Pages == 1 then NewPage:Turn() else Tab:SetActive(false) end

    return NewPage
end

local PageInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Page:Turn()
    if self.Active then return end
    library_object:ClosePopup()

    local First = true
    for _, Other in self.Window.Pages do
        if Other.Active then First = false end
        Other.Active = false
        Other.Items.Container.Instance.Visible = false
        Other.Items.Tab:SetActive(false)
    end

    self.Active = true
    self.Items.Tab:SetActive(true)

    local Container = self.Items.Container
    if First then
        Container.Instance.Visible = true
    else
        -- fade + slight rise of the new page
        Container.Instance.Position = UDim2New(0, 8, 0, 12)
        Container:Tween({ Position = UDim2New(0, 8, 0, 6) }, PageInfo)
        library_object:Fade(Container.Instance, true, PageInfo)
    end
end

-- Outer box shared by Section and MultiSection
local CreateSectionFrame = function(PageObject, Side)
    local Column = PageObject.ColumnFrames[MathClamp(Side or 1, 1, PageObject.Columns)]
    PageObject.SectionCount = (PageObject.SectionCount or 0) + 1

    return library_object:Create("Frame", {
        Parent = Column,
        Size = UDim2New(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = library_object.Theme.Background,
        LayoutOrder = PageObject.SectionCount,
    }):Theme({ BackgroundColor3 = "Background" }):Bevel()
end

local CreateSectionContent = function(Frame, Top)
    local Content = library_object:Create("Frame", {
        Parent = Frame,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 0, 0, Top),
        Size = UDim2New(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    library_object:Create("UIListLayout", { Parent = Content, Padding = UDimNew(0, 5), SortOrder = Enum.SortOrder.LayoutOrder })
    library_object:Create("UIPadding", {
        Parent = Content,
        PaddingLeft = UDimNew(0, 9), PaddingRight = UDimNew(0, 9),
        PaddingTop = UDimNew(0, 8), PaddingBottom = UDimNew(0, 10),
    })
    return Content
end

local CreateHeaderSeparator = function(Frame, Y)
    library_object:Create("Frame", {
        Parent = Frame,
        Position = UDim2New(0, 1, 0, Y),
        Size = UDim2New(1, -2, 0, 1),
        BackgroundColor3 = library_object.Theme.Outline,
        ZIndex = 3,
    }):Theme({ BackgroundColor3 = "Outline" })
end

function Page:Section(Data)
    Data = Data or { }

    local NewSection = setmetatable({
        Page = self,
        Window = self.Window,
        Name = Data.Name or Data.name or "Section",
    }, Section)

    local Frame = CreateSectionFrame(self, Data.Side or Data.side)
    local HasHeader = Data.Header ~= false

    if HasHeader then
        local Header = library_object:Create("Frame", {
            Parent = Frame,
            Position = UDim2New(0, 1, 0, 1),
            Size = UDim2New(1, -2, 0, 25),
            BackgroundColor3 = library_object.Theme.Contrast,
            ZIndex = 2,
        }):Theme({ BackgroundColor3 = "Contrast" }):Shade(FromRGB(172, 172, 172))

        library_object:AccentLine(Header, true, UDim2New(0, 0, 0, 0), UDim2New(0, 1, 1, 0), 4)

        NewSection.Title = library_object:Create("TextLabel", {
            Parent = Header,
            Text = NewSection.Name,
            Position = UDim2New(0, 10, 0, 0),
            Size = UDim2New(1, -20, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 3,
        }):Theme({ TextColor3 = "Text Color" }):TextStroke()

        CreateHeaderSeparator(Frame, 26)
    end

    local Content = CreateSectionContent(Frame, HasHeader and 27 or 0)

    NewSection.Items = { Frame = Frame, Content = Content }

    function NewSection:SetVisibility(Bool) Frame.Instance.Visible = Bool end

    return NewSection
end

-- Tabs inside one box (e.g. "Silent / Settings / FOV"). Returns the sections in order, also keyed by name.
function Page:MultiSection(Data)
    Data = Data or { }
    local Names = Data.Sections or Data.sections or Data.Tabs or { "Section" }

    local Frame = CreateSectionFrame(self, Data.Side or Data.side)

    local TabRow = library_object:Create("Frame", {
        Parent = Frame,
        Position = UDim2New(0, 1, 0, 1),
        Size = UDim2New(1, -2, 0, 24),
        BackgroundColor3 = library_object.Theme.Inline,
        ZIndex = 2,
    }):Theme({ BackgroundColor3 = "Inline" }):Shade(FromRGB(185, 185, 185))
    library_object:Create("UIListLayout", {
        Parent = TabRow,
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDimNew(0, 1),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    CreateHeaderSeparator(Frame, 25)

    local Result = { }
    local Entries = { }

    local Current = nil
    local Select = function(Target)
        if Current == Target then return end
        local First = Current == nil
        Current = Target
        library_object:ClosePopup()
        for _, Entry in Entries do
            local Active = Entry == Target
            Entry.Tab:SetActive(Active)
            if not Active then Entry.Content.Instance.Visible = false end
        end
        if First then
            Target.Content.Instance.Visible = true
        else
            library_object:Fade(Target.Content.Instance, true, PageInfo)
        end
    end

    for Index, Name in Names do
        local Tab = CreateSubTab(TabRow, Name, Index, 3, 13)
        local Content = CreateSectionContent(Frame, 26)

        local NewSection = setmetatable({
            Page = self,
            Window = self.Window,
            Name = Name,
            Items = { Frame = Frame, Content = Content },
        }, Section)

        local Entry = { Tab = Tab, Content = Content }
        TableInsert(Entries, Entry)

        function NewSection:Select() Select(Entry) end
        function NewSection:SetVisibility(Bool) Frame.Instance.Visible = Bool end

        Tab.Button:Connect("MouseButton1Click", function() Select(Entry) end)

        Result[Index] = NewSection
        Result[Name] = NewSection
    end

    Select(Entries[1])
    return Result
end
--#endregion

--#region Row addons (colorpickers / keybinds on the right of a row)
local CreateAddonHolder = function(Row)
    local Holder = library_object:Create("Frame", {
        Parent = Row,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2New(1, 0),
        Position = UDim2New(1, 0, 0, 0),
        Size = UDim2New(0.5, 0, 0, 14),
        ZIndex = 2,
    })
    library_object:Create("UIListLayout", {
        Parent = Holder,
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDimNew(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    return Holder
end

local AttachAddons = function(Element, Row)
    Element.AddonCount = 0

    function Element:Colorpicker(Data)
        Data = Data or { }
        self.AddonHolder = self.AddonHolder or CreateAddonHolder(Row)
        self.AddonCount += 1
        Data.Count = self.AddonCount
        Data.Name = Data.Name or Data.name or self.Name
        return library_object:CreateColorpicker({ Holder = self.AddonHolder }, Data)
    end

    function Element:Keybind(Data)
        Data = Data or { }
        self.AddonHolder = self.AddonHolder or CreateAddonHolder(Row)
        self.AddonCount += 1
        Data.Count = self.AddonCount
        Data.Name = Data.Name or Data.name or self.Name
        local Keybind = library_object:CreateKeybind({ Holder = self.AddonHolder }, Data)

        -- a keybind on a toggle drives the toggle
        if self.Class == "Toggle" then
            self.LinkedKeybind = Keybind
            Keybind.Active = self.Value
            Keybind:Display()
            Keybind.OnActiveChanged = function(Active) self:Set(Active) end
        end

        return Keybind
    end
end

local CreateTitle = function(Parent, Text, ZIndex)
    return library_object:Create("TextLabel", {
        Parent = Parent,
        Text = Text,
        Size = UDim2New(1, 0, 0, 13),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = ZIndex or 1,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()
end

local HasText = function(Text) return type(Text) == "string" and Text ~= "" end
--#endregion

--#region Toggle
function Section:Toggle(Data)
    Data = Data or { }

    local Toggle = {
        Class = "Toggle",
        Name = Data.Name or Data.name or "Toggle",
        Flag = Data.Flag or Data.flag or library_object:NextFlag(),
        Callback = Data.Callback or Data.callback,
        Value = false,
    }

    local Row = library_object:Create("TextButton", {
        Parent = self.Items.Content,
        Size = UDim2New(1, 0, 0, 14),
    })

    local Box = CreateCheckBox(Row, 1)

    local Label = library_object:Create("TextLabel", {
        Parent = Row,
        Text = Toggle.Name,
        Position = UDim2New(0, 21, 0, 0),
        Size = UDim2New(1, -21, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
    }):Theme({ TextColor3 = Data.Risky and "Risky" or "Disabled Text Color" }):TextStroke()

    function Toggle:Set(Bool)
        if Bool == nil then Bool = not self.Value end
        self.Value = Bool and true or false
        library_object.Flags[self.Flag] = self.Value

        local Linked = self.LinkedKeybind
        if Linked and Linked.Mode ~= "Always" and Linked.Active ~= self.Value then
            Linked.Active = self.Value
            Linked:Display()
        end

        Box:Set(self.Value)
        if not Data.Risky then
            Label:TweenTheme({ TextColor3 = self.Value and "Text Color" or "Disabled Text Color" })
        end

        library_object:SafeCall(self.Callback, self.Value)
    end

    function Toggle:Get() return self.Value end
    function Toggle:SetVisibility(Bool) Row.Instance.Visible = Bool end
    function Toggle:SetText(Text) Label.Instance.Text = Text end

    Row:Connect("MouseButton1Click", function() Toggle:Set() end)
    Row:OnHover(function()
        Box:Hover(true, Toggle.Value)
        if not Toggle.Value and not Data.Risky then Label:TweenTheme({ TextColor3 = "Text Color" }) end
    end, function()
        Box:Hover(false, Toggle.Value)
        if not Toggle.Value and not Data.Risky then Label:TweenTheme({ TextColor3 = "Disabled Text Color" }) end
    end)
    library_object:AttachTooltip(Row, Data.Tooltip or Data.tooltip)

    AttachAddons(Toggle, Row)

    library_object.SetFlags[Toggle.Flag] = function(Value) Toggle:Set(Value == true) end
    library_object.Flags[Toggle.Flag] = false

    local Default = Data.Default
    if Default == nil then Default = Data.default end
    if Default then Toggle:Set(true) end

    return Toggle
end
--#endregion

--#region Button
function Section:Button(Data)
    Data = Data or { }

    local Button = { Class = "Button" }

    local Row = library_object:Create("Frame", {
        Parent = self.Items.Content,
        BackgroundTransparency = 1,
        Size = UDim2New(1, 0, 0, 21),
    })
    library_object:Create("UIListLayout", {
        Parent = Row,
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalFlex = Enum.UIFlexAlignment.Fill,
        Padding = UDimNew(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local Count = 0
    function Button:Add(Name, Callback, Confirm)
        Count += 1

        local Btn = CreateBox("TextButton", Row, {
            Size = UDim2New(0, 0, 1, 0),
            Text = Name,
            LayoutOrder = Count,
        })
        Btn:Theme({ BackgroundColor3 = "Inline", TextColor3 = "Text Color" }):TextStroke()

        local Armed = false
        Btn:Connect("MouseButton1Click", function()
            if Confirm and not Armed then
                Armed = true
                Btn.Instance.Text = "Confirm?"
                Btn:TweenTheme({ TextColor3 = "Accent" })
                task.delay(2, function()
                    if Armed then
                        Armed = false
                        Btn.Instance.Text = Name
                        Btn:TweenTheme({ TextColor3 = "Text Color" })
                    end
                end)
                return
            end

            Armed = false
            Btn.Instance.Text = Name
            Btn:Tween({ TextColor3 = library_object.Theme.Accent }, TweenInfo.new(0.05))
            task.delay(0.15, function() Btn:TweenTheme({ TextColor3 = "Text Color" }) end)
            library_object:SafeCall(Callback)
        end)

        Btn:OnHover(function() Btn:TweenTheme({ BackgroundColor3 = "Contrast" }) end,
            function() Btn:TweenTheme({ BackgroundColor3 = "Inline" }) end)

        return Button
    end

    function Button:SetVisibility(Bool) Row.Instance.Visible = Bool end

    Button:Add(Data.Name or Data.name or "Button", Data.Callback or Data.callback, Data.Confirm or Data.confirm)
    return Button
end
--#endregion

--#region Slider / RangeSlider
-- Value text in bold Verdana riding the end of the fill, clamped inside the bar
local SliderInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--[[
    Slider geometry, measured from the original:
      track 14px tall, 1px lighter ring, no dark outline
      fill sits 1px inside the track (so 0% and 100% line up exactly with the ring),
      has its own lighter 1px edge and a faint accent halo, and disappears completely at 0
      value text (Verdana Bold) is centered on the fill edge, 3px below the bar's middle,
      and clamped so it never leaves the track (1px from either end)
]]
local InnerX = function(Width, Percent) return 1 + Percent * (Width - 2) end

-- Returns the clamped center X for a label of TextWidth centered at Percent
local ClampLabel = function(Width, TextWidth, Percent)
    local Half = TextWidth / 2
    return MathClamp(InnerX(Width, Percent), 1 + Half, math.max(1 + Half, Width - 1 - Half))
end

local MoveLabel = function(Label, X, Width, Percent)
    if Width <= 0 then
        Label.Instance.Position = UDim2New(Percent, 0, 0.5, 3)
        return
    end
    -- whole pixels keep the bold text crisp; the tween keeps it gliding with the fill
    Label:Tween({ Position = UDim2New(0, MathFloor(X + 0.5), 0.5, 3) }, SliderInfo)
end

-- Tween the fill between two percentages; hides it at zero width so no halo/edge sliver remains
local SetFill = function(Fill, A, B)
    local Span = B - A
    Fill.FillToken = (Fill.FillToken or 0) + 1
    local Token = Fill.FillToken

    if Span > 0 then Fill.Instance.Visible = true end
    Fill:Tween({
        Position = UDim2New(A, 1 - 2 * A, 0, 1),
        Size = UDim2New(Span, -2 * Span, 1, -2),
    }, SliderInfo)

    if Span <= 0 then
        task.delay(SliderInfo.Time, function()
            if Fill.FillToken == Token then Fill.Instance.Visible = false end
        end)
    end
end

local CreateSliderBase = function(Section, Name)
    local Named = HasText(Name)

    local Row = library_object:Create("Frame", {
        Parent = Section.Items.Content,
        BackgroundTransparency = 1,
        Size = UDim2New(1, 0, 0, Named and 36 or 20),
    })

    if Named then CreateTitle(Row, Name) end

    local Bar = library_object:Create("TextButton", {
        Parent = Row,
        Position = UDim2New(0, 0, 0, Named and 19 or 2),
        Size = UDim2New(1, 0, 0, 14),
        BackgroundTransparency = 0,
        BackgroundColor3 = library_object.Theme.Contrast,
    }):Theme({ BackgroundColor3 = "Contrast" }):Shade(FromRGB(165, 165, 165))

    -- lighter ring on the track's outermost pixel
    local Ring = library_object:Create("Frame", {
        Parent = Bar,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 1, 0, 1),
        Size = UDim2New(1, -2, 1, -2),
    })
    Ring:Stroke("Contrast", 1, 0)

    local Fill = library_object:Create("Frame", {
        Parent = Bar,
        Position = UDim2New(0, 1, 0, 1),
        Size = UDim2New(0, 0, 1, -2),
        BackgroundColor3 = library_object.Theme.Accent,
        Visible = false,
        ZIndex = 2,
    }):Theme({ BackgroundColor3 = "Accent" }):Shade(FromRGB(115, 115, 115))

    -- faint halo just outside the fill (drawn over the track ring)
    Fill:Stroke("Accent", 1, 0.8)

    -- lighter 1px edge on the fill's outermost pixel
    local Edge = library_object:Create("Frame", {
        Parent = Fill,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 1, 0, 1),
        Size = UDim2New(1, -2, 1, -2),
        ZIndex = 2,
    })
    Edge:Stroke("Text Color", 1, 0.55)

    local MakeLabel = function()
        return library_object:Create("TextLabel", {
            Parent = Bar,
            AnchorPoint = Vector2New(0.5, 0.5),
            AutomaticSize = Enum.AutomaticSize.X,
            Size = UDim2New(0, 0, 0, 12),
            Bold = true,
            ZIndex = 4,
        }):Theme({ TextColor3 = "Text Color" }):TextStroke()
    end

    return Row, Bar, Fill, MakeLabel
end

function Section:Slider(Data)
    Data = Data or { }

    local Slider = {
        Class = "Slider",
        Name = Data.Name or Data.name,
        Flag = Data.Flag or Data.flag or library_object:NextFlag(),
        Min = Data.Min or Data.min or 0,
        Max = Data.Max or Data.max or 100,
        Decimals = Data.Decimals or Data.decimals or 1,
        Suffix = Data.Suffix or Data.suffix or "",
        Format = Data.Format or Data.format,
        Callback = Data.Callback or Data.callback,
        Value = nil,
        Sliding = false,
    }

    local Row, Bar, Fill, MakeLabel = CreateSliderBase(self, Slider.Name)
    local ValueLabel = MakeLabel()

    local Percent = function()
        return (Slider.Max == Slider.Min) and 0 or (Slider.Value - Slider.Min) / (Slider.Max - Slider.Min)
    end

    local Place = function()
        local Width = Bar.Instance.AbsoluteSize.X
        MoveLabel(ValueLabel, ClampLabel(Width, ValueLabel.Instance.TextBounds.X, Percent()), Width, Percent())
    end

    function Slider:Set(Value)
        Value = tonumber(Value) or self.Min
        self.Value = library_object:Round(MathClamp(Value, self.Min, self.Max), self.Decimals)
        library_object.Flags[self.Flag] = self.Value

        SetFill(Fill, 0, Percent())

        local Text = tostring(self.Value) .. self.Suffix
        if self.Format then
            local Ok, Result = pcall(self.Format, self.Value)
            if Ok and Result ~= nil then Text = tostring(Result) end
        end
        ValueLabel.Instance.Text = Text
        Place()

        library_object:SafeCall(self.Callback, self.Value)
    end

    function Slider:Get() return self.Value end
    function Slider:SetVisibility(Bool) Row.Instance.Visible = Bool end

    local FromInput = function(Input)
        local Position, Size = Bar.Instance.AbsolutePosition, Bar.Instance.AbsoluteSize
        local Amount = MathClamp((Input.Position.X - Position.X - 1) / math.max(Size.X - 2, 1), 0, 1)
        Slider:Set(Slider.Min + (Slider.Max - Slider.Min) * Amount)
    end

    Bar:Connect("InputBegan", function(Input)
        if IsClick(Input) then
            Slider.Sliding = true
            FromInput(Input)
        end
    end)

    library_object:Connect(UserInputService.InputChanged, function(Input)
        if Slider.Sliding and IsMove(Input) then FromInput(Input) end
    end)

    library_object:Connect(UserInputService.InputEnded, function(Input)
        if Slider.Sliding and IsClick(Input) then Slider.Sliding = false end
    end)

    library_object:Connect(Bar.Instance:GetPropertyChangedSignal("AbsoluteSize"), Place)
    library_object:Connect(ValueLabel.Instance:GetPropertyChangedSignal("TextBounds"), Place)
    library_object:AttachTooltip(Row, Data.Tooltip or Data.tooltip)

    library_object.SetFlags[Slider.Flag] = function(Value) Slider:Set(Value) end
    Slider:Set(Data.Default or Data.default or Slider.Min)

    return Slider
end

function Section:RangeSlider(Data)
    Data = Data or { }

    local Slider = {
        Class = "RangeSlider",
        Name = Data.Name or Data.name,
        Flag = Data.Flag or Data.flag or library_object:NextFlag(),
        Min = Data.Min or Data.min or 0,
        Max = Data.Max or Data.max or 100,
        Decimals = Data.Decimals or Data.decimals or 1,
        Suffix = Data.Suffix or Data.suffix or "",
        Callback = Data.Callback or Data.callback,
        Value = { 0, 0 },
    }

    local Row, Bar, Fill, MakeLabel = CreateSliderBase(self, Slider.Name)
    local LowLabel, HighLabel = MakeLabel(), MakeLabel()

    local ToPercent = function(Value)
        return (Slider.Max == Slider.Min) and 0 or (Value - Slider.Min) / (Slider.Max - Slider.Min)
    end

    local Gap = 6
    local Place = function()
        local Width = Bar.Instance.AbsoluteSize.X
        local A, B = ToPercent(Slider.Value[1]), ToPercent(Slider.Value[2])
        local LowWidth, HighWidth = LowLabel.Instance.TextBounds.X, HighLabel.Instance.TextBounds.X

        local Low = ClampLabel(Width, LowWidth, A)
        local High = ClampLabel(Width, HighWidth, B)

        -- keep the two values from overlapping: spread them around their midpoint, then keep both inside the track
        local Needed = LowWidth / 2 + Gap + HighWidth / 2
        if High - Low < Needed then
            local Middle = (Low + High) / 2
            Low, High = Middle - Needed / 2, Middle + Needed / 2
            local MinLow, MaxHigh = 1 + LowWidth / 2, Width - 1 - HighWidth / 2
            if Low < MinLow then Low, High = MinLow, MinLow + Needed end
            if High > MaxHigh then High, Low = MaxHigh, MaxHigh - Needed end
        end

        MoveLabel(LowLabel, Low, Width, A)
        MoveLabel(HighLabel, High, Width, B)
    end

    function Slider:Set(Low, High)
        if type(Low) == "table" then Low, High = Low[1], Low[2] end
        Low = library_object:Round(MathClamp(tonumber(Low) or self.Min, self.Min, self.Max), self.Decimals)
        High = library_object:Round(MathClamp(tonumber(High) or self.Max, self.Min, self.Max), self.Decimals)
        if Low > High then Low, High = High, Low end

        self.Value = { Low, High }
        library_object.Flags[self.Flag] = { Low, High }

        SetFill(Fill, ToPercent(Low), ToPercent(High))

        LowLabel.Instance.Text = tostring(Low) .. self.Suffix
        HighLabel.Instance.Text = tostring(High) .. self.Suffix
        Place()

        library_object:SafeCall(self.Callback, self.Value)
    end

    function Slider:Get() return self.Value[1], self.Value[2] end
    function Slider:SetVisibility(Bool) Row.Instance.Visible = Bool end

    local Handle = nil
    local FromInput = function(Input)
        local Position, Size = Bar.Instance.AbsolutePosition, Bar.Instance.AbsoluteSize
        local Amount = MathClamp((Input.Position.X - Position.X - 1) / math.max(Size.X - 2, 1), 0, 1)
        local Value = Slider.Min + (Slider.Max - Slider.Min) * Amount

        if not Handle then
            Handle = math.abs(Value - Slider.Value[1]) <= math.abs(Value - Slider.Value[2]) and 1 or 2
        end

        if Handle == 1 then
            if Value > Slider.Value[2] then Handle = 2 end
        elseif Value < Slider.Value[1] then
            Handle = 1
        end

        if Handle == 1 then Slider:Set(Value, Slider.Value[2]) else Slider:Set(Slider.Value[1], Value) end
    end

    Bar:Connect("InputBegan", function(Input)
        if IsClick(Input) then
            Handle = nil
            Slider.Sliding = true
            FromInput(Input)
        end
    end)

    library_object:Connect(UserInputService.InputChanged, function(Input)
        if Slider.Sliding and IsMove(Input) then FromInput(Input) end
    end)

    library_object:Connect(UserInputService.InputEnded, function(Input)
        if Slider.Sliding and IsClick(Input) then Slider.Sliding = false; Handle = nil end
    end)

    library_object:Connect(Bar.Instance:GetPropertyChangedSignal("AbsoluteSize"), Place)
    library_object:Connect(LowLabel.Instance:GetPropertyChangedSignal("TextBounds"), Place)
    library_object:Connect(HighLabel.Instance:GetPropertyChangedSignal("TextBounds"), Place)

    library_object.SetFlags[Slider.Flag] = function(Value)
        if type(Value) == "table" then Slider:Set(Value[1], Value[2]) end
    end

    local Default = Data.Default or Data.default or { Slider.Min, Slider.Max }
    Slider:Set(Default[1], Default[2])

    return Slider
end
--#endregion

--#region Option list (shared by Dropdown popups and Listboxes)
-- Selected options are bold + accent; listboxes also show a small accent square
local CreateOptionList = function(Owner, Scroll, ItemHeight, ShowIndicator, ZIndex)
    local List = { Buttons = { } }

    local IsSelected = function(Option)
        if Owner.Multi then
            return type(Owner.Value) == "table" and TableFind(Owner.Value, Option) ~= nil
        end
        return Owner.Value == Option
    end

    function List:Render()
        for Option, Entry in self.Buttons do
            local Selected = IsSelected(Option)
            Entry.Text:SetBold(Selected)
            Entry.Text:TweenTheme({ TextColor3 = Selected and "Accent" or "Text Color" })
            if Entry.Indicator then
                local Size = Selected and 6 or 0
                Entry.Indicator:Tween({ Size = UDim2New(0, Size, 0, Size) }, SliderInfo)
                Entry.Text:Tween({ Position = UDim2New(0, Selected and 22 or 6, 0, 0) }, SliderInfo)
            end
        end
    end

    function List:Add(Option, Index)
        local Button = library_object:Create("TextButton", {
            Parent = Scroll,
            Size = UDim2New(1, 0, 0, ItemHeight),
            LayoutOrder = Index,
            ZIndex = ZIndex,
        })

        local Indicator
        if ShowIndicator then
            Indicator = library_object:Create("Frame", {
                Parent = Button,
                AnchorPoint = Vector2New(0.5, 0.5),
                Position = UDim2New(0, 10, 0.5, 0),
                Size = UDim2New(0, 0, 0, 0),
                BackgroundColor3 = library_object.Theme.Accent,
                ZIndex = ZIndex,
            }):Theme({ BackgroundColor3 = "Accent" }):Shade(FromRGB(150, 150, 150))
        end

        local Text = library_object:Create("TextLabel", {
            Parent = Button,
            Text = tostring(Option),
            Position = UDim2New(0, ShowIndicator and 6 or 7, 0, 0),
            Size = UDim2New(1, -24, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = ZIndex,
        }):Theme({ TextColor3 = "Text Color" }):TextStroke()

        Button:Connect("MouseButton1Click", function()
            if Owner.Multi then
                local Current = table.clone(Owner.Value or { })
                local Found = TableFind(Current, Option)
                if Found then TableRemove(Current, Found) else TableInsert(Current, Option) end
                Owner:Set(Current)
            else
                Owner:Set(Option)
                if Owner.OnPicked then Owner.OnPicked() end
            end
        end)

        Button:OnHover(function()
            if not IsSelected(Option) then Text:TweenTheme({ TextColor3 = "Accent" }) end
        end, function()
            if not IsSelected(Option) then Text:TweenTheme({ TextColor3 = "Text Color" }) end
        end)

        self.Buttons[Option] = { Button = Button, Text = Text, Indicator = Indicator }
    end

    function List:Clear()
        for _, Entry in self.Buttons do Entry.Button.Instance:Destroy() end
        self.Buttons = { }
    end

    function List:Remove(Option)
        local Entry = self.Buttons[Option]
        if Entry then
            Entry.Button.Instance:Destroy()
            self.Buttons[Option] = nil
        end
    end

    function List:Filter(Query)
        Query = (Query or ""):lower()
        local Visible = 0
        for Option, Entry in self.Buttons do
            local Show = Query == "" or string.find(tostring(Option):lower(), Query, 1, true) ~= nil
            Entry.Button.Instance.Visible = Show
            if Show then Visible += 1 end
        end
        return Visible
    end

    return List
end

-- Set/Refresh/Add/Remove shared by Dropdown and Listbox
local AttachOptionMethods = function(Owner, List, Display)
    function Owner:Set(Value)
        if self.Multi then
            local NewValue = { }
            if type(Value) == "table" then
                for _, Option in Value do
                    if TableFind(self.Items, Option) and not TableFind(NewValue, Option) then TableInsert(NewValue, Option) end
                end
            elseif Value ~= nil and TableFind(self.Items, Value) then
                NewValue = { Value }
            end
            self.Value = NewValue
        else
            self.Value = TableFind(self.Items, Value) and Value or nil
        end

        library_object.Flags[self.Flag] = self.Value
        List:Render()
        if Display then Display() end
        library_object:SafeCall(self.Callback, self.Value)
    end

    function Owner:Get() return self.Value end

    function Owner:Refresh(NewItems)
        List:Clear()
        self.Items = table.clone(NewItems or { })
        for Index, Option in self.Items do List:Add(Option, Index) end
        self:Set(self.Value)
    end

    function Owner:Add(Option)
        if TableFind(self.Items, Option) then return end
        TableInsert(self.Items, Option)
        List:Add(Option, #self.Items)
        List:Render()
    end

    function Owner:Remove(Option)
        local Index = TableFind(self.Items, Option)
        if not Index then return end
        TableRemove(self.Items, Index)
        List:Remove(Option)
        self:Set(self.Value)
    end
end

local ApplyDefault = function(Owner, Data, AllowEmpty)
    local Default = Data.Default or Data.default
    if Owner.Multi then
        Owner:Set(type(Default) == "table" and Default or (Default and { Default } or { }))
    elseif Default ~= nil or AllowEmpty then
        Owner:Set(Default)
    else
        Owner:Set(Owner.Items[1])
    end
end
--#endregion

--#region Dropdown
function Section:Dropdown(Data)
    Data = Data or { }

    local Dropdown = {
        Class = "Dropdown",
        Name = Data.Name or Data.name,
        Flag = Data.Flag or Data.flag or library_object:NextFlag(),
        Items = table.clone(Data.Items or Data.items or Data.Options or Data.options or { }),
        Multi = Data.Multi or Data.multi or false,
        Callback = Data.Callback or Data.callback,
        Value = nil,
        Open = false,
    }

    local Named = HasText(Dropdown.Name)
    local Searchable = Data.Search or Data.search or #Dropdown.Items > 12
    local ItemHeight = 18

    local Row = library_object:Create("Frame", {
        Parent = self.Items.Content,
        BackgroundTransparency = 1,
        Size = UDim2New(1, 0, 0, Named and 37 or 20),
    })

    if Named then CreateTitle(Row, Dropdown.Name) end

    local Box = CreateBox("TextButton", Row, {
        AnchorPoint = Vector2New(0, 1),
        Position = UDim2New(0, 0, 1, 0),
        Size = UDim2New(1, 0, 0, 20),
    })

    local Selected = library_object:Create("TextLabel", {
        Parent = Box,
        Position = UDim2New(0, 7, 0, 0),
        Size = UDim2New(1, -36, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 2,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    library_object:Create("Frame", {
        Parent = Box,
        Position = UDim2New(1, -22, 0, 1),
        Size = UDim2New(0, 1, 1, -2),
        BackgroundColor3 = library_object.Theme.Outline,
        ZIndex = 2,
    }):Theme({ BackgroundColor3 = "Outline" })

    local Arrow = library_object:Create("TextLabel", {
        Parent = Box,
        Position = UDim2New(1, -21, 0, 0),
        Size = UDim2New(0, 21, 1, 0),
        Text = "+",
        ZIndex = 2,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()

    -- popup
    local Popup = library_object:Create("Frame", {
        Parent = library_object.Holder,
        Size = UDim2New(0, 100, 0, 0),
        BackgroundColor3 = library_object.Theme.Background,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 100,
    }):Theme({ BackgroundColor3 = "Background" })
    Popup:Stroke("Outline")

    local SearchBox
    if Searchable then
        local SearchFrame = CreateBox("Frame", Popup, {
            Position = UDim2New(0, 4, 0, 4),
            Size = UDim2New(1, -8, 0, 18),
            ZIndex = 101,
        })
        SearchBox = library_object:Create("TextBox", {
            Parent = SearchFrame,
            Position = UDim2New(0, 5, 0, 0),
            Size = UDim2New(1, -10, 1, 0),
            Text = "",
            PlaceholderText = "Search...",
            ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 102,
        }):Theme({ TextColor3 = "Text Color", PlaceholderColor3 = "Disabled Text Color" })
    end

    local ListTop = Searchable and 25 or 2
    local Scroll = library_object:Create("ScrollingFrame", {
        Parent = Popup,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 0, 0, ListTop),
        Size = UDim2New(1, 0, 1, -ListTop - 2),
        CanvasSize = UDim2New(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = library_object.Theme.Accent,
        ZIndex = 101,
    }):Theme({ ScrollBarImageColor3 = "Accent" })
    library_object:Create("UIListLayout", { Parent = Scroll, SortOrder = Enum.SortOrder.LayoutOrder })

    local List = CreateOptionList(Dropdown, Scroll, ItemHeight, false, 102)

    local Display = function()
        if Dropdown.Multi then
            Selected.Instance.Text = (#Dropdown.Value > 0) and table.concat(Dropdown.Value, ", ") or "None"
        else
            Selected.Instance.Text = Dropdown.Value ~= nil and tostring(Dropdown.Value) or "None"
        end
    end

    AttachOptionMethods(Dropdown, List, Display)

    local PopupHeight = function(VisibleCount)
        local Rows = math.max(1, math.min(VisibleCount, 8))
        return Rows * ItemHeight + ListTop + 2
    end

    local Resize = function(VisibleCount)
        if not Dropdown.Open then return end
        Popup:Tween({ Size = UDim2New(0, math.max(Box.Instance.AbsoluteSize.X, 80), 0, PopupHeight(VisibleCount)) }, PopupInfo)
    end

    function Dropdown:SetOpen(Bool)
        self.Open = Bool
        Arrow.Instance.Text = Bool and "-" or "+"

        if Bool then
            if SearchBox then SearchBox.Instance.Text = "" end
            Popup.Instance.Size = UDim2New(0, math.max(Box.Instance.AbsoluteSize.X, 80), 0, 0)
            library_object:RegisterPopup(Popup, Box, function()
                Dropdown.Open = false
                Arrow.Instance.Text = "+"
                library_object:AnimatePopup(Popup, false, PopupHeight(#Dropdown.Items))
            end, 2)
            library_object:AnimatePopup(Popup, true, PopupHeight(List:Filter("")))
        elseif library_object.OpenPopup and library_object.OpenPopup.Frame == Popup then
            library_object:ClosePopup()
        end
    end

    Dropdown.OnPicked = function() Dropdown:SetOpen(false) end

    if SearchBox then
        library_object:Connect(SearchBox.Instance:GetPropertyChangedSignal("Text"), function()
            Resize(List:Filter(SearchBox.Instance.Text))
        end)
    end

    function Dropdown:SetVisibility(Bool) Row.Instance.Visible = Bool end

    Box:Connect("MouseButton1Click", function() Dropdown:SetOpen(not Dropdown.Open) end)
    Box:OnHover(function() Box:TweenTheme({ BackgroundColor3 = "Contrast" }) end,
        function() Box:TweenTheme({ BackgroundColor3 = "Inline" }) end)
    library_object:AttachTooltip(Row, Data.Tooltip or Data.tooltip)

    for Index, Option in Dropdown.Items do List:Add(Option, Index) end

    library_object.SetFlags[Dropdown.Flag] = function(Value) Dropdown:Set(Value) end
    ApplyDefault(Dropdown, Data, Data.AllowNone)

    return Dropdown
end
--#endregion

--#region Listbox (always-open list inside the section, optional search)
function Section:Listbox(Data)
    Data = Data or { }

    local Listbox = {
        Class = "Listbox",
        Name = Data.Name or Data.name,
        Flag = Data.Flag or Data.flag or library_object:NextFlag(),
        Items = table.clone(Data.Items or Data.items or Data.Options or Data.options or { }),
        Multi = Data.Multi or Data.multi or false,
        Callback = Data.Callback or Data.callback,
        Value = nil,
    }

    local Rows = Data.Rows or Data.rows or 7
    local ItemHeight = 19

    local Row = library_object:Create("Frame", {
        Parent = self.Items.Content,
        BackgroundTransparency = 1,
        Size = UDim2New(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    library_object:Create("UIListLayout", { Parent = Row, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDimNew(0, 5) })

    if HasText(Listbox.Name) then CreateTitle(Row, Listbox.Name).Instance.LayoutOrder = 1 end

    local SearchBox
    if Data.Search or Data.search then
        local SearchFrame = CreateBox("Frame", Row, { Size = UDim2New(1, 0, 0, 20), LayoutOrder = 2 })
        SearchBox = library_object:Create("TextBox", {
            Parent = SearchFrame,
            Position = UDim2New(0, 7, 0, 0),
            Size = UDim2New(1, -14, 1, 0),
            Text = "",
            PlaceholderText = "Search...",
            ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 2,
        }):Theme({ TextColor3 = "Text Color", PlaceholderColor3 = "Disabled Text Color" })
    end

    local Box = library_object:Create("Frame", {
        Parent = Row,
        Size = UDim2New(1, 0, 0, Rows * ItemHeight + 4),
        BackgroundColor3 = library_object.Theme.Inline,
        LayoutOrder = 3,
    }):Theme({ BackgroundColor3 = "Inline" }):Bevel()

    local Scroll = library_object:Create("ScrollingFrame", {
        Parent = Box,
        BackgroundTransparency = 1,
        Position = UDim2New(0, 0, 0, 2),
        Size = UDim2New(1, -2, 1, -4),
        CanvasSize = UDim2New(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = library_object.Theme.Accent,
        VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
        ZIndex = 2,
    }):Theme({ ScrollBarImageColor3 = "Accent" })
    library_object:Create("UIListLayout", { Parent = Scroll, SortOrder = Enum.SortOrder.LayoutOrder })

    local List = CreateOptionList(Listbox, Scroll, ItemHeight, true, 3)
    AttachOptionMethods(Listbox, List)

    if SearchBox then
        library_object:Connect(SearchBox.Instance:GetPropertyChangedSignal("Text"), function()
            List:Filter(SearchBox.Instance.Text)
        end)
    end

    function Listbox:SetVisibility(Bool) Row.Instance.Visible = Bool end

    for Index, Option in Listbox.Items do List:Add(Option, Index) end

    library_object.SetFlags[Listbox.Flag] = function(Value) Listbox:Set(Value) end
    ApplyDefault(Listbox, Data, true)

    return Listbox
end
--#endregion

--#region Textbox / Label / Divider
function Section:Textbox(Data)
    Data = Data or { }

    local Textbox = {
        Class = "Textbox",
        Name = Data.Name or Data.name,
        Flag = Data.Flag or Data.flag or library_object:NextFlag(),
        Numeric = Data.Numeric or Data.numeric or false,
        Finished = Data.Finished or Data.finished or false,
        Callback = Data.Callback or Data.callback,
        Value = "",
    }

    local Named = HasText(Textbox.Name)
    local Row = library_object:Create("Frame", {
        Parent = self.Items.Content,
        BackgroundTransparency = 1,
        Size = UDim2New(1, 0, 0, Named and 37 or 20),
    })

    if Named then CreateTitle(Row, Textbox.Name) end

    local Frame = CreateBox("Frame", Row, {
        AnchorPoint = Vector2New(0, 1),
        Position = UDim2New(0, 0, 1, 0),
        Size = UDim2New(1, 0, 0, 20),
    })

    local Box = library_object:Create("TextBox", {
        Parent = Frame,
        Position = UDim2New(0, 7, 0, 0),
        Size = UDim2New(1, -14, 1, 0),
        Text = "",
        PlaceholderText = Data.Placeholder or Data.placeholder or "",
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 2,
    }):Theme({ TextColor3 = "Text Color", PlaceholderColor3 = "Disabled Text Color" }):TextStroke()

    function Textbox:Set(Value, FromTyping)
        Value = tostring(Value or "")
        if self.Numeric and Value ~= "" and not tonumber(Value) then
            Value = self.Value
        end

        self.Value = Value
        if not FromTyping then Box.Instance.Text = Value end
        library_object.Flags[self.Flag] = Value
        library_object:SafeCall(self.Callback, Value)
    end

    function Textbox:Get() return self.Value end
    function Textbox:SetVisibility(Bool) Row.Instance.Visible = Bool end

    local Outline = Frame.Instance:FindFirstChildOfClass("UIStroke")
    Box:Connect("Focused", function()
        if Outline then Outline.Color = library_object.Theme.Accent end
    end)
    Box:Connect("FocusLost", function()
        if Outline then Outline.Color = library_object.Theme.Outline end
        if Textbox.Finished then Textbox:Set(Box.Instance.Text) end
        if Textbox.Numeric and Box.Instance.Text ~= Textbox.Value then Box.Instance.Text = Textbox.Value end
    end)

    if not Textbox.Finished then
        library_object:Connect(Box.Instance:GetPropertyChangedSignal("Text"), function()
            if Box.Instance.Text ~= Textbox.Value then Textbox:Set(Box.Instance.Text, true) end
        end)
    end

    library_object.SetFlags[Textbox.Flag] = function(Value) Textbox:Set(Value) end
    Textbox:Set(Data.Default or Data.default or "")

    return Textbox
end

function Section:Label(Data)
    if type(Data) == "string" then Data = { Name = Data } end
    Data = Data or { }

    local Label = { Class = "Label", Name = Data.Name or Data.name or "Label" }

    local Row = library_object:Create("Frame", {
        Parent = self.Items.Content,
        BackgroundTransparency = 1,
        Size = UDim2New(1, 0, 0, 14),
        AutomaticSize = Enum.AutomaticSize.Y,
    })

    local Text = library_object:Create("TextLabel", {
        Parent = Row,
        Text = Label.Name,
        Size = UDim2New(1, 0, 0, 14),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        LineHeight = 13 / library_object.FontSize, -- the original paragraphs use a 13px line pitch
        TextXAlignment = Enum.TextXAlignment[Data.Alignment or "Left"],
        TextYAlignment = Enum.TextYAlignment.Top,
    }):Theme({ TextColor3 = "Text Color" }):TextStroke()
    library_object:Create("UIPadding", { Parent = Text, PaddingTop = UDimNew(0, 1) })

    function Label:SetText(NewText) Text.Instance.Text = NewText end
    function Label:SetVisibility(Bool) Row.Instance.Visible = Bool end

    AttachAddons(Label, Row)
    return Label
end

function Section:Divider()
    local Line = library_object:Create("Frame", {
        Parent = self.Items.Content,
        Size = UDim2New(1, 0, 0, 1),
        BackgroundColor3 = library_object.Theme.Outline,
    }):Theme({ BackgroundColor3 = "Outline" })

    library_object:Create("Frame", {
        Parent = Line,
        Position = UDim2New(0, 0, 1, 0),
        Size = UDim2New(1, 0, 0, 1),
        BackgroundColor3 = library_object.Theme.Contrast,
    }):Theme({ BackgroundColor3 = "Contrast" })
end

function Section:Keybind(Data)
    Data = Data or { }
    return self:Label({ Name = Data.Name or Data.name or "Keybind" }):Keybind(Data)
end

function Section:Colorpicker(Data)
    Data = Data or { }
    return self:Label({ Name = Data.Name or Data.name or "Color" }):Colorpicker(Data)
end
--#endregion

--#region Configs
function library_object:GetConfig()
    local Config = { }

    for Flag, Value in self.Flags do
        if type(Value) == "table" and Value.Color then
            Config[Flag] = { Color = Value.Color:ToHex(), Alpha = Value.Alpha, Rainbow = Value.Rainbow }
        elseif type(Value) == "table" and Value.Mode then
            Config[Flag] = { Key = Value.Key, KeyType = Value.KeyType, Mode = Value.Mode, ShowInList = Value.ShowInList }
        else
            Config[Flag] = Value
        end
    end

    Config["__layout"] = self:GetLayout()

    return HttpService:JSONEncode(Config)
end

function library_object:LoadConfig(Json)
    local Ok, Decoded = pcall(HttpService.JSONDecode, HttpService, Json)
    if not Ok or type(Decoded) ~= "table" then
        self:Notification("Failed to read config", 4, self.Theme.Risky)
        return false
    end

    local Apply = function(Flag, Value)
        local Setter = self.SetFlags[Flag]
        if Setter then
            local SetOk, Error = pcall(Setter, Value)
            if not SetOk then warn("[" .. self.Name .. "] config flag '" .. Flag .. "': " .. tostring(Error)) end
        end
    end

    -- theme first (so every element restyles onto the final colors), then values, then layout
    for Flag, Value in Decoded do
        if Flag:sub(1, 8) == "__theme_" then Apply(Flag, Value) end
    end
    for Flag, Value in Decoded do
        if Flag:sub(1, 8) ~= "__theme_" and Flag ~= "__layout" then Apply(Flag, Value) end
    end
    Apply("__layout", Decoded["__layout"])

    return true
end

function library_object:ListConfigs()
    if not HasFileSystem then return { } end

    local Names = { }
    for _, Path in listfiles(self.Folders.Configs) do
        local Name = Path:match("([^/\\]+)%.json$")
        if Name then TableInsert(Names, Name) end
    end
    table.sort(Names)
    return Names
end

function library_object:SaveConfigFile(Name)
    if not HasFileSystem or not Name or Name == "" then return false end
    writefile(self.Folders.Configs .. "/" .. Name .. ".json", self:GetConfig())
    return true
end

function library_object:LoadConfigFile(Name)
    if not HasFileSystem or not Name then return false end
    local Path = self.Folders.Configs .. "/" .. Name .. ".json"
    if not isfile(Path) then return false end
    return self:LoadConfig(readfile(Path))
end

function library_object:DeleteConfigFile(Name)
    if not HasFileSystem or not Name or typeof(delfile) ~= "function" then return false end
    local Path = self.Folders.Configs .. "/" .. Name .. ".json"
    if isfile(Path) then
        delfile(Path)
        return true
    end
    return false
end
--#endregion

--#region Settings page (layout of the original "Settings" tab)
local EasingStyles = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Bounce", "Elastic" }
local EasingDirections = { "In", "Out", "InOut" }

function library_object:CreateSettingsPage(TargetWindow)
    local Settings = TargetWindow:Page({ Name = "Settings", Columns = 2 })

    -- left: configuration
    local Configuration = Settings:Section({ Name = "Configuration", Side = 1 })
    Configuration:Label({ Name = "Configs" })
    local ConfigList = Configuration:Listbox({
        Flag = "__settings_config_list",
        Items = self:ListConfigs(),
        Search = true,
        Rows = 6,
    })
    local ConfigName = Configuration:Textbox({ Name = "Config Name", Flag = "__settings_config_name", Placeholder = "name..." })

    local Refresh = function() ConfigList:Refresh(self:ListConfigs()) end
    local Target = function()
        local Typed = ConfigName:Get()
        if Typed ~= "" then return Typed end
        return ConfigList:Get()
    end

    Configuration:Button({ Name = "Save", Callback = function()
        local Name = Target()
        if not Name then return self:Notification("Enter a config name", 3, self.Theme.Risky) end
        if self:SaveConfigFile(Name) then self:Notification("Saved config " .. Name, 3) end
        Refresh()
    end }):Add("Load", function()
        local Name = ConfigList:Get() or Target()
        if Name and self:LoadConfigFile(Name) then self:Notification("Loaded config " .. Name, 3) end
    end)

    Configuration:Button({ Name = "Delete", Confirm = true, Callback = function()
        local Name = ConfigList:Get()
        if Name and self:DeleteConfigFile(Name) then self:Notification("Deleted config " .. Name, 3) end
        Refresh()
    end }):Add("Refresh", Refresh)

    if not HasFileSystem then
        Configuration:Label({ Name = "File functions unavailable: configs are disabled." })
    end

    -- left: menu
    local Menu = Settings:Section({ Name = "Menu", Side = 1 })

    Menu:Dropdown({
        Name = "Easing Style",
        Flag = "__settings_easing_style",
        Items = EasingStyles,
        Default = self.Tween.Style.Name,
        Callback = function(Value)
            if Value then pcall(function() self.Tween.Style = Enum.EasingStyle[Value] end) end
        end,
    })

    Menu:Dropdown({
        Name = "Easing Direction",
        Flag = "__settings_easing_direction",
        Items = EasingDirections,
        Default = self.Tween.Direction.Name,
        Callback = function(Value)
            if Value then pcall(function() self.Tween.Direction = Enum.EasingDirection[Value] end) end
        end,
    })

    Menu:Slider({
        Name = "Tweening Speed",
        Flag = "__settings_tween_time",
        Min = 0.05, Max = 1, Decimals = 0.05, Suffix = "s",
        Default = self.Tween.Time,
        Callback = function(Value) self.Tween.Time = Value end,
    })

    Menu:Keybind({
        Name = "Menu Bind",
        Flag = "__settings_menu_key",
        Default = self.MenuKeybind,
        Mode = "Toggle",
        NoList = true,
        OnKeyChanged = function(Key)
            if Key then self.MenuKeybind = Key end
        end,
    })

    Menu:Button({ Name = "Unload", Confirm = true, Callback = function() self:Unload() end })

    -- right: overlays (no header, as in the original)
    local Overlay = Settings:Section({ Name = "Overlay", Side = 2, Header = false })
    local Watermark = self:Watermark()
    local KeyList = self:KeybindList(false)

    Overlay:Toggle({ Name = "Watermark", Flag = "__settings_watermark", Default = true,
        Callback = function(Bool) Watermark:SetVisibility(Bool) end })

    Overlay:Dropdown({
        Name = "Options",
        Flag = "__settings_watermark_parts",
        Items = WatermarkParts,
        Multi = true,
        Default = { "Title", "Fps", "Ping" },
        Callback = function(Value) Watermark:SetParts(Value) end,
    })

    Overlay:Slider({ Name = "Refresh Rate", Flag = "__settings_watermark_rate", Min = 0.05, Max = 1, Decimals = 0.05,
        Suffix = "s", Default = 0.1, Callback = function(Value) Watermark.RefreshRate = Value end })

    Overlay:Toggle({ Name = "Watermark Glow Animation", Flag = "__settings_glow_animated",
        Callback = function(Bool) self.GlowSettings.Animated = Bool end })

    Overlay:Slider({ Name = "Watermark Glow Speed", Flag = "__settings_glow_speed", Min = 0.05, Max = 2, Decimals = 0.05,
        Default = 0.35, Callback = function(Value) self.GlowSettings.Speed = Value end })

    Overlay:Slider({ Name = "Watermark Glow Darkness", Flag = "__settings_glow_darkness", Min = 0, Max = 100, Decimals = 1,
        Suffix = "%", Default = 75, Callback = function(Value) self.GlowSettings.Darkness = Value / 100 end })

    Overlay:Toggle({ Name = "Keybind List", Flag = "__settings_keybind_list",
        Callback = function(Bool) KeyList:SetVisibility(Bool) end })

    Overlay:Textbox({
        Name = "library_object Name",
        Flag = "__settings_library_object_name",
        Default = self.Name,
        Placeholder = self.DefaultName,
        Callback = function(Text) self:SetName(Text) end,
    })

    -- right: theming
    local Theming = Settings:Section({ Name = "Theming", Side = 2 })
    for _, Key in self.ThemeOrder do
        Theming:Colorpicker({
            Name = Key,
            Flag = "__theme_" .. Key,
            Default = self.Theme[Key],
            Callback = function(Color) self:ChangeTheme(Key, Color) end,
        })
    end

    return Settings
end
--#endregion

function library_object:Unload()
    if self.Unloaded then return end
    self.Unloaded = true

    for _, Connection in self.Connections do
        pcall(function() Connection:Disconnect() end)
    end
    self.Connections = { }
    self.Rainbows = { }
    self.Glows = { }
    self.OpenPopup = nil

    if self.Holder then self.Holder.Instance:Destroy() end

    if getgenv then getgenv().library_object = nil end
end

if getgenv then getgenv().library_object = library_object end
return library_object
