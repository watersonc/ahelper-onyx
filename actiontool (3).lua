-- Скрипт для управления наказаниями игроков через ImGui-интерфейс
script_name("onyxaction") -- Название скрипта для SAMPFUNCS
script_author("vladiksexcy && fletcher") -- Автор скрипта

-- Импорт необходимых библиотек
local imgui = require 'imgui' -- Библиотека для создания GUI
local samp = require 'samp.events' -- Обработка событий SAMP
local cjson = require "cjson" -- Работа с JSON
local encoding = require "encoding" -- Работа с кодировками

-- Настройка кодировки по умолчанию (CP1251 для поддержки кириллицы)
encoding.default = 'CP1251'
u8 = encoding.UTF8 -- Быстрый доступ к UTF8-кодировке

-- Константы для путей к файлам и категориям наказаний
local DATA_FILE = getWorkingDirectory() .. "/config/actiontool_punishments.json" -- Файл с наказаниями
local LOG_FILE = getWorkingDirectory() .. "/config/actiontool_log.txt" -- Файл для логирования (не используется)
local CATEGORIES = {"Ban", "Mute", "Warn", "Jail", "Other"} -- Категории наказаний

-- Переменные состояния интерфейса
local isWindowVisible = imgui.ImBool(false) -- Видимость главного окна
local selectedCategory = nil -- Выбранная категория
local selectedReasonIndex = imgui.ImInt(1) -- Индекс выбранной причины
local inputTarget = imgui.ImBuffer("", 256) -- Буфер для ввода цели (ID или ник)
local searchInput = imgui.ImBuffer("", 256) -- Буфер для поиска по причинам
local newReasonInput = imgui.ImBuffer("", 256) -- Буфер для новой/редактируемой причины
local newCommandInput = imgui.ImBuffer("", 256) -- Буфер для новой/редактируемой команды
local showAddForm = false -- Флаг отображения формы добавления/редактирования
local editIndex = 0 -- Индекс редактируемого наказания (0 - добавление)

-- Размеры окна
local WINDOW_WIDTH = 620
local WINDOW_HEIGHT = 570

-- Менеджер наказаний: хранит, загружает, сохраняет и фильтрует наказания
local PunishmentManager = {
    data = {}, -- Таблица с наказаниями

    -- Сохраняет текущие наказания в файл
    saveData = function(self)
        local file = io.open(DATA_FILE, "w")
        if file then
            file:write(cjson.encode(self.data))
            file:close()
            return true
        end
        return false
    end,

    -- Инициализация стандартных наказаний (вызывается при первом запуске или ошибке загрузки)
    initializeDefaultData = function(self)
        self.data = {
            Ban = { {u8"Реклама", u8"/ban %s 999d"} },
            Mute = { {u8"Флуд", u8"/mute %s 60m"} },
            Warn = { {u8"Оскорбления", u8"/warn %s"} },
            Jail = { {u8"ДМ", u8"/jail %s 60m"} },
            Other = { {u8"Другое", "/kick %s"} }
        }
    end,

    -- Загружает наказания из файла, если файл отсутствует или повреждён — инициализирует стандартные
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

    -- Возвращает список причин по категории с учётом фильтра поиска
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

    -- Получает команду по категории и индексу
    getCommand = function(self, category, index)
        return self.data[category][index][2]
    end,

    -- Добавляет новое наказание в выбранную категорию
    addPunishment = function(self, category, reason, command)
        if not self.data[category] then self.data[category] = {} end
        table.insert(self.data[category], {reason, command})
        return self:saveData()
    end,

    -- Удаляет наказание по индексу из выбранной категории
    removePunishment = function(self, category, index)
        table.remove(self.data[category], index)
        return self:saveData()
    end,

    -- Обновляет существующее наказание по индексу
    updatePunishment = function(self, category, index, reason, command)
        self.data[category][index] = {reason, command}
        return self:saveData()
    end
}

-- Главная функция скрипта (точка входа)
function main()
    repeat wait(0) until isSampfuncsLoaded() and isSampAvailable() -- Ожидание загрузки SAMPFUNCS и SAMP
    sampAddChatMessage("ActionTool: Скрипт загружен", -1) -- Сообщение о загрузке

    PunishmentManager:loadData() -- Загрузка наказаний

    -- Регистрация чат-команды /action для открытия окна
    sampRegisterChatCommand("action", function(param)
        inputTarget.v = param or ""
        isWindowVisible.v = true
    end)

    -- Основной цикл скрипта
    while true do
        wait(0)
        imgui.Process = isWindowVisible.v -- Обработка ImGui только если окно открыто
    end
end

-- Применяет выбранное наказание к цели
function applyPunishment(index)
    if inputTarget.v == "" then return end -- Проверка, что цель указана

    local cmd = PunishmentManager:getCommand(selectedCategory, index)
    local target = inputTarget.v

    -- Автоматическое определение offline-команды, если цель не ID (а ник)
    if not tonumber(target) then
        cmd = cmd:gsub("^/(%w+)", function(cmd)
            return cmd == "ban" and "/offban" or
                   cmd == "mute" and "/offmute" or
                   cmd == "warn" and "/offwarn" or
                   cmd == "jail" and "/offjail" or
                   "/"..cmd
        end)
    end

    sampSendChat(string.format(cmd, target)) -- Отправка команды в чат
    isWindowVisible.v = false -- Закрытие окна после применения
end

-- Основная функция отрисовки окна ImGui
function imgui.OnDrawFrame()
    if isWindowVisible.v then
        -- Центрируем окно, запрещаем ресайз (фиксируем только размер)
        local io = imgui.GetIO()
        local centerX = (io.DisplaySize.x - WINDOW_WIDTH) * 0.5
        local centerY = (io.DisplaySize.y - WINDOW_HEIGHT) * 0.5
        imgui.SetNextWindowPos(imgui.ImVec2(centerX, centerY), imgui.Cond.Once) -- Только при первом открытии
        imgui.SetNextWindowSize(imgui.ImVec2(WINDOW_WIDTH, WINDOW_HEIGHT), imgui.Cond.Always)
        windowFlags = bit.bor(imgui.WindowFlags.NoResize) -- Запрещаем ресайз окна
    end
    
    if imgui.Begin(u8"Наказание игрока", isWindowVisible, windowFlags) then
        imgui.Text(u8"Цель (ID или ник):")
        imgui.InputText("##target", inputTarget)

        imgui.Separator()
        imgui.Text(u8"Категория:")
        -- Переключатели для выбора категории
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
            imgui.Text(u8"Поиск:")
            imgui.InputText("##search", searchInput)

            -- Получение и отображение списка причин по фильтру
            local reasons = PunishmentManager:getFilteredReasons(selectedCategory, searchInput.v)
            local reasonStrings = {}
            for _, v in ipairs(reasons) do
                table.insert(reasonStrings, v.reason)
            end

            -- Список причин (ListBox)
            if imgui.ListBox("##reasons", selectedReasonIndex, reasonStrings, 5) then
                showAddForm = false
            end

            -- Кнопки для выбранной причины (Применить, Редактировать, Удалить)
            if #reasons > 0 then
                local realIndex = reasons[selectedReasonIndex.v + 1] and reasons[selectedReasonIndex.v + 1].index
                if realIndex then
                    if imgui.Button(u8"Применить") then
                        applyPunishment(realIndex)
                    end
                    imgui.SameLine()
                    if imgui.Button(u8"Редактировать") then
                        editIndex = realIndex
                        newReasonInput.v = PunishmentManager.data[selectedCategory][editIndex][1]
                        newCommandInput.v = PunishmentManager.data[selectedCategory][editIndex][2]
                        showAddForm = true
                    end
                    imgui.SameLine()
                    if imgui.Button(u8"Удалить") then
                        if PunishmentManager:removePunishment(selectedCategory, realIndex) then
                            -- Наказание успешно удалено
                        end
                    end
                end
            end

            imgui.Separator()
            -- Кнопка для добавления нового наказания
            if imgui.Button(u8"Добавить наказание") then
                newReasonInput.v = ""
                newCommandInput.v = ""
                showAddForm = true
                editIndex = 0
            end

            -- Форма добавления/редактирования наказания
            if showAddForm then
                imgui.Separator()
                imgui.Text(u8"Причина:")
                imgui.InputText("##newReason", newReasonInput)
                imgui.Text(u8"Команда:")
                imgui.InputText("##newCommand", newCommandInput)

                -- Кнопка сохранения наказания
                if imgui.Button(u8"Сохранить") then
                    if newReasonInput.v ~= "" and newCommandInput.v ~= "" then
                        local success
                        if editIndex > 0 then
                            success = PunishmentManager:updatePunishment(selectedCategory, editIndex, newReasonInput.v, newCommandInput.v)
                        else
                            success = PunishmentManager:addPunishment(selectedCategory, newReasonInput.v, newCommandInput.v)
                        end

                        if success then
                            showAddForm = false
                            -- Наказание успешно сохранено
                        end
                    end
                end
                imgui.SameLine()
                -- Кнопка отмены добавления/редактирования
                if imgui.Button(u8"Отмена") then
                    showAddForm = false
                end
            end
        end
    end
    imgui.End()
end