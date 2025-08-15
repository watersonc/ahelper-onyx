-- ������ ��� ���������� ����������� ������� ����� ImGui-���������
script_name("onyxaction") -- �������� ������� ��� SAMPFUNCS
script_author("vladiksexcy && fletcher") -- ����� �������

-- ������ ����������� ���������
local imgui = require 'imgui' -- ���������� ��� �������� GUI
local samp = require 'samp.events' -- ��������� ������� SAMP
local cjson = require "cjson" -- ������ � JSON
local encoding = require "encoding" -- ������ � �����������

-- ��������� ��������� �� ��������� (CP1251 ��� ��������� ���������)
encoding.default = 'CP1251'
u8 = encoding.UTF8 -- ������� ������ � UTF8-���������

-- ��������� ��� ����� � ������ � ���������� ���������
local DATA_FILE = getWorkingDirectory() .. "/config/actiontool_punishments.json" -- ���� � �����������
local LOG_FILE = getWorkingDirectory() .. "/config/actiontool_log.txt" -- ���� ��� ����������� (�� ������������)
local CATEGORIES = {"Ban", "Mute", "Warn", "Jail", "Other"} -- ��������� ���������

-- ���������� ��������� ����������
local isWindowVisible = imgui.ImBool(false) -- ��������� �������� ����
local selectedCategory = nil -- ��������� ���������
local selectedReasonIndex = imgui.ImInt(1) -- ������ ��������� �������
local inputTarget = imgui.ImBuffer("", 256) -- ����� ��� ����� ���� (ID ��� ���)
local searchInput = imgui.ImBuffer("", 256) -- ����� ��� ������ �� ��������
local newReasonInput = imgui.ImBuffer("", 256) -- ����� ��� �����/������������� �������
local newCommandInput = imgui.ImBuffer("", 256) -- ����� ��� �����/������������� �������
local showAddForm = false -- ���� ����������� ����� ����������/��������������
local editIndex = 0 -- ������ �������������� ��������� (0 - ����������)

-- ������� ����
local WINDOW_WIDTH = 620
local WINDOW_HEIGHT = 570

-- �������� ���������: ������, ���������, ��������� � ��������� ���������
local PunishmentManager = {
    data = {}, -- ������� � �����������

    -- ��������� ������� ��������� � ����
    saveData = function(self)
        local file = io.open(DATA_FILE, "w")
        if file then
            file:write(cjson.encode(self.data))
            file:close()
            return true
        end
        return false
    end,

    -- ������������� ����������� ��������� (���������� ��� ������ ������� ��� ������ ��������)
    initializeDefaultData = function(self)
        self.data = {
            Ban = { {u8"�������", u8"/ban %s 999d"} },
            Mute = { {u8"����", u8"/mute %s 60m"} },
            Warn = { {u8"�����������", u8"/warn %s"} },
            Jail = { {u8"��", u8"/jail %s 60m"} },
            Other = { {u8"������", "/kick %s"} }
        }
    end,

    -- ��������� ��������� �� �����, ���� ���� ����������� ��� �������� � �������������� �����������
    loadData = function(self)
        local file = io.open(DATA_FILE, "r")
        if file then
            local content = file:read("*a")
            local ok, result = pcall(cjson.decode, content)
            if ok and type(result) == "table" then
                self.data = {}
                for category, punishments in pairs(result) do
                    self.data[category] = {}
                    for _, punishment in ipairs(punishments) do
                        table.insert(self.data[category], {
                            punishment[1],
                            punishment[2]
                        })
                    end
                end
            else
                self:initializeDefaultData()
            end
            file:close()
        else
            self:initializeDefaultData()
            self:saveData()
        end
    end,

    -- ���������� ������ ������ �� ��������� � ������ ������� ������
    getFilteredReasons = function(self, category, filter)
        local reasons = {}
        filter = filter or ""

        if not self.data[category] then return reasons end

        local filterLower = filter:lower()

        for i, v in ipairs(self.data[category]) do
            if v[1] and v[1]:lower():find(filterLower, 1, true) then
                table.insert(reasons, {index = i, reason = v[1]})
            end
        end

        return reasons
    end,

    -- �������� ������� �� ��������� � �������
    getCommand = function(self, category, index)
        return self.data[category][index][2]
    end,

    -- ��������� ����� ��������� � ��������� ���������
    addPunishment = function(self, category, reason, command)
        if not self.data[category] then self.data[category] = {} end
        table.insert(self.data[category], {reason, command})
        return self:saveData()
    end,

    -- ������� ��������� �� ������� �� ��������� ���������
    removePunishment = function(self, category, index)
        table.remove(self.data[category], index)
        return self:saveData()
    end,

    -- ��������� ������������ ��������� �� �������
    updatePunishment = function(self, category, index, reason, command)
        self.data[category][index] = {reason, command}
        return self:saveData()
    end
}

-- ������� ������� ������� (����� �����)
function main()
    repeat wait(0) until isSampfuncsLoaded() and isSampAvailable() -- �������� �������� SAMPFUNCS � SAMP
    sampAddChatMessage("ActionTool: ������ ��������", -1) -- ��������� � ��������

    PunishmentManager:loadData() -- �������� ���������

    -- ����������� ���-������� /action ��� �������� ����
    sampRegisterChatCommand("action", function(param)
        inputTarget.v = param or ""
        isWindowVisible.v = true
    end)

    -- �������� ���� �������
    while true do
        wait(0)
        imgui.Process = isWindowVisible.v -- ��������� ImGui ������ ���� ���� �������
    end
end

-- ��������� ��������� ��������� � ����
function applyPunishment(index)
    if inputTarget.v == "" then return end -- ��������, ��� ���� �������

    local cmd = PunishmentManager:getCommand(selectedCategory, index)
    local target = inputTarget.v

    -- �������������� ����������� offline-�������, ���� ���� �� ID (� ���)
    if not tonumber(target) then
        cmd = cmd:gsub("^/(%w+)", function(cmd)
            return cmd == "ban" and "/offban" or
                   cmd == "mute" and "/offmute" or
                   cmd == "warn" and "/offwarn" or
                   cmd == "jail" and "/offjail" or
                   "/"..cmd
        end)
    end

    sampSendChat(string.format(cmd, target)) -- �������� ������� � ���
    isWindowVisible.v = false -- �������� ���� ����� ����������
end

-- �������� ������� ��������� ���� ImGui
function imgui.OnDrawFrame()
    if isWindowVisible.v then
        -- ���������� ����, ��������� ������ (��������� ������ ������)
        local io = imgui.GetIO()
        local centerX = (io.DisplaySize.x - WINDOW_WIDTH) * 0.5
        local centerY = (io.DisplaySize.y - WINDOW_HEIGHT) * 0.5
        imgui.SetNextWindowPos(imgui.ImVec2(centerX, centerY), imgui.Cond.Once) -- ������ ��� ������ ��������
        imgui.SetNextWindowSize(imgui.ImVec2(WINDOW_WIDTH, WINDOW_HEIGHT), imgui.Cond.Always)
        windowFlags = bit.bor(imgui.WindowFlags.NoResize) -- ��������� ������ ����
    end
    
    if imgui.Begin(u8"��������� ������", isWindowVisible, windowFlags) then
        imgui.Text(u8"���� (ID ��� ���):")
        imgui.InputText("##target", inputTarget)

        imgui.Separator()
        imgui.Text(u8"���������:")
        -- ������������� ��� ������ ���������
        for i, cat in ipairs(CATEGORIES) do
            if imgui.RadioButton(cat, selectedCategory == cat) then
                selectedCategory = cat
                selectedReasonIndex.v = 1
                showAddForm = false
            end
            if i < #CATEGORIES then imgui.SameLine() end
        end

        if selectedCategory then
            imgui.Separator()
            imgui.Text(u8"�����:")
            imgui.InputText("##search", searchInput)

            -- ��������� � ����������� ������ ������ �� �������
            local reasons = PunishmentManager:getFilteredReasons(selectedCategory, searchInput.v)
            local reasonStrings = {}
            for _, v in ipairs(reasons) do
                table.insert(reasonStrings, v.reason)
            end

            -- ������ ������ (ListBox)
            if imgui.ListBox("##reasons", selectedReasonIndex, reasonStrings, 5) then
                showAddForm = false
            end

            -- ������ ��� ��������� ������� (���������, �������������, �������)
            if #reasons > 0 then
                local realIndex = reasons[selectedReasonIndex.v + 1] and reasons[selectedReasonIndex.v + 1].index
                if realIndex then
                    if imgui.Button(u8"���������") then
                        applyPunishment(realIndex)
                    end
                    imgui.SameLine()
                    if imgui.Button(u8"�������������") then
                        editIndex = realIndex
                        newReasonInput.v = PunishmentManager.data[selectedCategory][editIndex][1]
                        newCommandInput.v = PunishmentManager.data[selectedCategory][editIndex][2]
                        showAddForm = true
                    end
                    imgui.SameLine()
                    if imgui.Button(u8"�������") then
                        if PunishmentManager:removePunishment(selectedCategory, realIndex) then
                            -- ��������� ������� �������
                        end
                    end
                end
            end

            imgui.Separator()
            -- ������ ��� ���������� ������ ���������
            if imgui.Button(u8"�������� ���������") then
                newReasonInput.v = ""
                newCommandInput.v = ""
                showAddForm = true
                editIndex = 0
            end

            -- ����� ����������/�������������� ���������
            if showAddForm then
                imgui.Separator()
                imgui.Text(u8"�������:")
                imgui.InputText("##newReason", newReasonInput)
                imgui.Text(u8"�������:")
                imgui.InputText("##newCommand", newCommandInput)

                -- ������ ���������� ���������
                if imgui.Button(u8"���������") then
                    if newReasonInput.v ~= "" and newCommandInput.v ~= "" then
                        local success
                        if editIndex > 0 then
                            success = PunishmentManager:updatePunishment(selectedCategory, editIndex, newReasonInput.v, newCommandInput.v)
                        else
                            success = PunishmentManager:addPunishment(selectedCategory, newReasonInput.v, newCommandInput.v)
                        end

                        if success then
                            showAddForm = false
                            -- ��������� ������� ���������
                        end
                    end
                end
                imgui.SameLine()
                -- ������ ������ ����������/��������������
                if imgui.Button(u8"������") then
                    showAddForm = false
                end
            end
        end
    end
    imgui.End()
end