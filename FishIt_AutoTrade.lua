--[[
    ╔══════════════════════════════════════════════════════════╗
    ║         Fish It — Auto Trade Secret Fish Script          ║
    ║         UI: Fluent UI Library                            ║
    ║         Author : GitHub/YourUsername                     ║
    ║         Version: 1.0.0                                   ║
    ╚══════════════════════════════════════════════════════════╝

    HOW TO LOAD:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/YourUsername/YourRepo/main/FishIt_AutoTrade.lua"))()

    ⚠️  DISCLAIMER: Gunakan script ini dengan tanggung jawab penuh.
        Penggunaan di server publik dapat melanggar ToS Roblox.
]]

-- ============================================================
--  ███████╗ KONFIGURASI UTAMA — UBAH DI SINI JIKA GAME UPDATE
-- ============================================================

-- >>> REMOTE EVENTS (Cek di ReplicatedStorage / RemoteEvents folder)
local REMOTE_TRADE_REQUEST   = "TradeRequest"       -- Remote untuk mengirim / menerima ajakan trade
local REMOTE_TRADE_ACCEPT    = "AcceptTrade"        -- Remote untuk menerima ajakan trade dari player lain
local REMOTE_ADD_ITEM        = "AddItemToTrade"     -- Remote untuk menambah item ke slot trade
local REMOTE_CONFIRM_TRADE   = "ConfirmTrade"       -- Remote untuk menekan tombol Confirm/Lock trade
local REMOTE_CANCEL_TRADE    = "CancelTrade"        -- Remote untuk membatalkan trade (opsional)

-- >>> FOLDER PATH di ReplicatedStorage / RemoteEvents
local REMOTE_FOLDER_PATH     = "RemoteEvents"       -- Nama folder tempat semua Remote berada

-- >>> KATA KUNCI ITEM (filter inventory)
local SECRET_KEYWORD         = "Secret"             -- Kata kunci untuk mendeteksi Secret Fish di inventory

-- >>> FOLDER INVENTORY PLAYER (cek di LocalPlayer atau workspace)
local INVENTORY_FOLDER       = "Inventory"          -- Nama folder inventory di PlayerData / leaderstats

-- >>> JEDA WAKTU (detik) — turunkan jika koneksi cepat, naikkan jika sering error
local LOOP_DELAY             = 0.5   -- Delay antar iterasi loop utama
local ACTION_DELAY           = 0.3   -- Delay antar aksi (add item, confirm, dsb.)

-- ============================================================
--  SERVICES & CORE VARIABLES
-- ============================================================

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local RunService           = game:GetService("RunService")
local UserInputService     = game:GetService("UserInputService")
local TweenService         = game:GetService("TweenService")

local LocalPlayer          = Players.LocalPlayer
local PlayerGui            = LocalPlayer:WaitForChild("PlayerGui")

-- Helper: ambil RemoteEvent dengan aman
local function GetRemote(remoteName)
    -- ⚠️ UBAH PATH INI jika Remote tidak ada di dalam folder khusus
    local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_PATH)
    if folder then
        return folder:FindFirstChild(remoteName)
    end
    -- Fallback: langsung di ReplicatedStorage
    return ReplicatedStorage:FindFirstChild(remoteName)
end

-- ============================================================
--  STATE VARIABLES
-- ============================================================

local State = {
    AntiAFK        = false,
    FPSCap         = false,
    FPSValue       = 60,
    TargetUsername = "",
    AutoAccept     = false,
    AutoAddSecret  = false,
    AutoConfirm    = false,
    TradeActive    = false,   -- apakah sedang dalam sesi trade
    TradePartner   = nil,     -- Player object partner trade
}

-- ============================================================
--  FLUENT UI LIBRARY LOADER
-- ============================================================

-- Fluent UI by Dawid / dawid-scripts (GitHub)
-- ⚠️ Jika Fluent tidak bisa diload, ganti URL di bawah dengan mirror lain
local FluentSuccess, Fluent = pcall(function()
    return loadstring(game:HttpGet(
        "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"
    ))()
end)

if not FluentSuccess then
    -- Fallback notifikasi jika Fluent gagal load
    warn("[FishIt Script] Fluent UI gagal dimuat! Cek koneksi atau URL Fluent.")
    return
end

-- SaveManager & InterfaceManager (opsional, untuk config save)
local SaveManager     = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"
))()
local InterfaceManager = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"
))()

-- ============================================================
--  BUAT WINDOW UTAMA
-- ============================================================

local Window = Fluent:CreateWindow({
    Title        = "Fish It — Secret Trade",
    SubTitle     = "v1.0 | github.com/YourUsername",
    TabWidth     = 160,
    Size         = UDim2.fromOffset(580, 460),
    Acrylic      = true,   -- Efek blur (butuh dukungan executor)
    Theme        = "Dark",
    MinimizeKey  = Enum.KeyCode.RightControl,  -- Tombol minimize/maximize UI
})

-- ============================================================
--  TABS
-- ============================================================

local Tabs = {
    Main     = Window:AddTab({ Title = "Main",     Icon = "home" }),
    Trading  = Window:AddTab({ Title = "Trading",  Icon = "arrow-left-right" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
}

-- ============================================================
--  TAB: MAIN
-- ============================================================

-- >>> Anti-AFK Toggle
Tabs.Main:AddToggle("AntiAFK", {
    Title       = "Auto Anti-AFK",
    Description = "Mencegah Roblox kick karena tidak aktif",
    Default     = false,
    Callback    = function(val)
        State.AntiAFK = val
        -- ⚠️ Logika Anti-AFK dijalankan di loop terpisah di bawah
    end,
})

-- >>> FPS Cap Toggle + Slider
Tabs.Main:AddToggle("FPSCapToggle", {
    Title       = "FPS Cap",
    Description = "Batasi FPS untuk mengurangi beban GPU",
    Default     = false,
    Callback    = function(val)
        State.FPSCap = val
        if val then
            -- ⚠️ setfpscap adalah fungsi executor (mis. Synapse, KRNL)
            if setfpscap then
                setfpscap(State.FPSValue)
            end
        else
            if setfpscap then
                setfpscap(0) -- 0 = unlimited
            end
        end
    end,
})

Tabs.Main:AddSlider("FPSValue", {
    Title   = "FPS Limit",
    Min     = 15,
    Max     = 240,
    Default = 60,
    Rounding = 0,
    Callback = function(val)
        State.FPSValue = val
        if State.FPSCap and setfpscap then
            setfpscap(val) -- Terapkan langsung jika toggle aktif
        end
    end,
})

-- ============================================================
--  TAB: TRADING
-- ============================================================

-- >>> Target Username Input
Tabs.Trading:AddInput("TargetUsername", {
    Title       = "Target Username",
    Description = "Hanya proses trade dari username ini (case-sensitive)",
    Default     = "",
    Placeholder = "Masukkan username...",
    Callback    = function(val)
        State.TargetUsername = val
        -- ⚠️ Pastikan penulisan username SAMA PERSIS dengan nama Roblox target
    end,
})

-- >>> Auto Accept Toggle
Tabs.Trading:AddToggle("AutoAccept", {
    Title       = "Auto Accept Request",
    Description = "Otomatis terima ajakan trade dari target",
    Default     = false,
    Callback    = function(val)
        State.AutoAccept = val
    end,
})

-- >>> Auto Add Secret Toggle
Tabs.Trading:AddToggle("AutoAddSecret", {
    Title       = "Auto Add Secret Fish",
    Description = "Cari item 'Secret' di inventory dan masukkan ke trade",
    Default     = false,
    Callback    = function(val)
        State.AutoAddSecret = val
    end,
})

-- >>> Auto Confirm Toggle
Tabs.Trading:AddToggle("AutoConfirm", {
    Title       = "Auto Confirm Trade",
    Description = "Otomatis tekan Confirm setelah Secret Fish ditambahkan",
    Default     = false,
    Callback    = function(val)
        State.AutoConfirm = val
    end,
})

-- >>> Status Label (informatif)
local StatusLabel = Tabs.Trading:AddParagraph({
    Title = "Status",
    Content = "Menunggu...",
})

local function SetStatus(msg)
    -- Update teks status di UI
    StatusLabel:SetContent(msg)
end

-- ============================================================
--  TAB: SETTINGS
-- ============================================================

Tabs.Settings:AddButton({
    Title       = "Unload Script",
    Description = "Tutup UI dan hentikan semua loop",
    Callback    = function()
        -- Hentikan semua state
        State.AntiAFK    = false
        State.AutoAccept = false
        State.AutoAddSecret = false
        State.AutoConfirm   = false
        -- Destroy UI
        Window:Destroy()
        -- Pulihkan FPS
        if setfpscap then setfpscap(0) end
    end,
})

Tabs.Settings:AddParagraph({
    Title   = "Informasi",
    Content = "Script ini open-source.\nJika Remote berubah setelah update game,\nedit bagian KONFIGURASI UTAMA di atas.",
})

-- ============================================================
--  SETUP: SaveManager & InterfaceManager
-- ============================================================

SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)

-- ⚠️ Ganti "FishItScript" dengan nama unik agar config tidak bentrok
SaveManager:SetFolder("FishItScript")
SaveManager:BuildConfigSection(Tabs.Settings)
InterfaceManager:BuildInterfaceSection(Tabs.Settings)

-- Load config tersimpan (auto load saat script jalan)
SaveManager:LoadAutoloadConfig()

-- ============================================================
--  FUNGSI HELPER: Inventory
-- ============================================================

-- Ambil semua item Secret dari folder inventory player
local function GetSecretItems()
    local items = {}
    -- ⚠️ Sesuaikan path inventory jika berbeda di game Fish It
    local playerData = LocalPlayer:FindFirstChild("PlayerData")
                    or LocalPlayer:FindFirstChild("Data")
                    or LocalPlayer:FindFirstChild(INVENTORY_FOLDER)

    if not playerData then
        -- Coba cari di leaderstats atau folder lain
        playerData = LocalPlayer:FindFirstChildOfClass("Folder")
    end

    if playerData then
        local inv = playerData:FindFirstChild(INVENTORY_FOLDER) or playerData
        for _, item in ipairs(inv:GetChildren()) do
            -- Cek apakah nama item mengandung kata SECRET_KEYWORD
            if string.find(item.Name, SECRET_KEYWORD, 1, true) then
                table.insert(items, item)
            end
        end
    end
    return items
end

-- ============================================================
--  FUNGSI UTAMA: Trade Logic
-- ============================================================

-- Fungsi: Accept trade request dari target
local function TryAcceptTrade(senderPlayer)
    if not State.AutoAccept then return end
    if State.TargetUsername == "" then return end
    if senderPlayer.Name ~= State.TargetUsername then return end

    local remote = GetRemote(REMOTE_TRADE_ACCEPT)
    if remote then
        -- ⚠️ Argumen Remote mungkin berbeda — cek dengan Remote Spy
        remote:FireServer(senderPlayer)
        SetStatus("✅ Trade diterima dari: " .. senderPlayer.Name)
        State.TradeActive  = true
        State.TradePartner = senderPlayer
    else
        SetStatus("⚠️ Remote '" .. REMOTE_TRADE_ACCEPT .. "' tidak ditemukan!")
    end
end

-- Fungsi: Tambah Secret Fish ke slot trade
local function TryAddSecretItems()
    if not State.AutoAddSecret then return end
    if not State.TradeActive   then return end

    local secretItems = GetSecretItems()
    if #secretItems == 0 then
        SetStatus("⚠️ Tidak ada Secret Fish di inventory!")
        return
    end

    local remote = GetRemote(REMOTE_ADD_ITEM)
    if not remote then
        SetStatus("⚠️ Remote '" .. REMOTE_ADD_ITEM .. "' tidak ditemukan!")
        return
    end

    for _, item in ipairs(secretItems) do
        task.wait(ACTION_DELAY) -- Delay agar tidak flood server
        -- ⚠️ Argumen Remote: mungkin perlu ItemId atau ItemName — sesuaikan!
        remote:FireServer(item.Name)
        SetStatus("📦 Menambah: " .. item.Name)
    end
end

-- Fungsi: Confirm trade
local function TryConfirmTrade()
    if not State.AutoConfirm  then return end
    if not State.TradeActive  then return end

    task.wait(ACTION_DELAY)
    local remote = GetRemote(REMOTE_CONFIRM_TRADE)
    if remote then
        -- ⚠️ Beberapa game butuh dua kali Confirm (Lock + Accept) — duplikasi jika perlu
        remote:FireServer()
        SetStatus("🔒 Trade dikonfirmasi!")
        State.TradeActive  = false
        State.TradePartner = nil
    else
        SetStatus("⚠️ Remote '" .. REMOTE_CONFIRM_TRADE .. "' tidak ditemukan!")
    end
end

-- ============================================================
--  LISTENER: Incoming Trade Request dari Server
-- ============================================================

-- ⚠️ Jika game menggunakan OnClientEvent untuk notif trade masuk, pasang di sini
task.spawn(function()
    local remote = GetRemote(REMOTE_TRADE_REQUEST)
    if remote and remote:IsA("RemoteEvent") then
        -- Dengarkan event trade request dari server
        remote.OnClientEvent:Connect(function(senderPlayer)
            -- ⚠️ Parameter 'senderPlayer' mungkin berbeda (bisa berupa UserId atau string)
            if typeof(senderPlayer) == "Instance" and senderPlayer:IsA("Player") then
                TryAcceptTrade(senderPlayer)
            elseif typeof(senderPlayer) == "number" then
                -- Jika server kirim UserId
                local player = Players:GetPlayerByUserId(senderPlayer)
                if player then TryAcceptTrade(player) end
            end
        end)
    else
        warn("[FishIt] Remote '" .. REMOTE_TRADE_REQUEST .. "' tidak ditemukan atau bukan RemoteEvent.")
    end
end)

-- ============================================================
--  LOOP UTAMA: Trade Sequence
-- ============================================================

task.spawn(function()
    while true do
        task.wait(LOOP_DELAY)

        -- Cek apakah sedang dalam trade aktif dan lanjutkan sequence
        if State.TradeActive then
            TryAddSecretItems()   -- Step 1: Tambah item
            TryConfirmTrade()     -- Step 2: Confirm
        end
    end
end)

-- ============================================================
--  LOOP: Anti-AFK
-- ============================================================

task.spawn(function()
    while true do
        task.wait(60) -- Lakukan aksi anti-afk setiap 60 detik
        if State.AntiAFK then
            -- Simulasi gerakan kecil untuk mencegah AFK kick
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                -- ⚠️ Menggerakkan VirtualUser atau simulasi jump
                local VU = game:GetService("VirtualUser")
                VU:CaptureController()
                VU:ClickButton2(Vector2.new())
            end
        end
    end
end)

-- ============================================================
--  NOTIFIKASI AWAL
-- ============================================================

Fluent:Notify({
    Title    = "Fish It Script Loaded ✅",
    Content  = "UI siap! Atur Username target di Tab Trading.",
    Duration = 5,
})

Window:SelectTab(1) -- Buka Tab Main saat startup

-- ============================================================
--  END OF SCRIPT
-- ============================================================
