local UiManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local FrameContainer = require("ui/widget/container/framecontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local TextWidget = require("ui/widget/textwidget")
local InfoMessage = require("ui/widget/infomessage")
local Button = require("ui/widget/button")
local Screen = require("device").screen
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local logger = require("logger")
local _ = require("gettext")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local LineWidget = require("ui/widget/linewidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local OverlapGroup = require("ui/widget/overlapgroup")

local HeaderActionButton = Button:extend{}

function HeaderActionButton:init()
    Button.init(self)
    self.label_widget.fgcolor = Blitbuffer.COLOR_WHITE
end

local TodoApplication = WidgetContainer:extend({
    name = "todo",
    todos = {},
    current_frame = nil,
    settings = nil,
    save_task = nil,
    settings_file = DataStorage:getSettingsDir() .. "/todos.lua",
})


function TodoApplication:init()
    self.ui.menu:registerToMainMenu(self)
    self:loadSaved()
end

function TodoApplication:addExitButton()
    return Button:new{
        text = "×",
        width = Screen:scaleBySize(40),
        height = Screen:scaleBySize(40),
        padding = 0,
        bordersize = 0,
        text_font_size = 40,
        text_font_bold = false,
        callback = function()
            self:remover()
        end,
    }
end

function TodoApplication:remover()
    self:flushTodos()
    if self.current_frame then
        local old_frame = self.current_frame
        self.current_frame = nil
        UiManager:close(old_frame, "ui")
        old_frame:free()
    end
end


function TodoApplication:loadSaved()
    logger.warn("Loading todos from settings")
    self.settings = LuaSettings:open(self.settings_file)
    local saved_todos = self.settings:readSetting("todos")

    if saved_todos then
        self.todos = saved_todos
    else
        self.todos = {}
    end
end

function TodoApplication:saveTodos()
    self.settings:saveSetting("todos", self.todos)
    if self.save_task then
        return
    end

    self.save_task = function()
        self.save_task = nil
        self.settings:flush()
    end
    UiManager:scheduleIn(1, self.save_task)
end

function TodoApplication:flushTodos()
    if self.save_task then
        UiManager:unschedule(self.save_task)
        self.save_task = nil
        self.settings:flush()
    end
end

function TodoApplication:onFlushSettings()
    self:flushTodos()
end

function TodoApplication:repaintCurrentFrame()
    UiManager:setDirty(self.current_frame, "ui")
end

function TodoApplication:confirmRemoveCompleted(message, callback)
    UiManager:show(ConfirmBox:new{
        text = message,
        ok_text = _("Remove"),
        ok_callback = callback,
    })
end

function TodoApplication:promptText(title, hint, initial, on_save)
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{
        title = title,
        input = initial or "",
        input_hint = hint,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UiManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_text = input_dialog:getInputText()
                        UiManager:close(input_dialog)
                        if new_text and new_text ~= "" then
                            on_save(new_text)
                        end
                    end,
                },
            }
        },
    }
    UiManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function TodoApplication:addSubtask(index)
    self:promptText(_("New Sub-task"), _("Enter sub-task text"), "", function(text)
        if not self.todos[index].subtasks then
            self.todos[index].subtasks = {}
        end
        table.insert(self.todos[index].subtasks, { text = text, checked = false })
        self:saveTodos()
        self:showTaskDetails(index)
    end)
end

function TodoApplication:editSubtask(main_index, sub_index)
    local subtask = self.todos[main_index].subtasks[sub_index]
    self:promptText(_("Edit Sub-task"), _("Enter sub-task text"), subtask.text, function(text)
        self.todos[main_index].subtasks[sub_index].text = text
        self:saveTodos()
        self:showTaskDetails(main_index)
    end)
end

function TodoApplication:removeSubtask(main_index, sub_index)
    self:confirmRemoveCompleted(_("Remove this sub-task?"), function()
        table.remove(self.todos[main_index].subtasks, sub_index)
        self:saveTodos()
        self:showTaskDetails(main_index)
    end)
end

function TodoApplication:countSubtaskProgress(todo)
    local total = todo.subtasks and #todo.subtasks or 0
    local done = 0
    if todo.subtasks then
        for _, subtask in ipairs(todo.subtasks) do
            if subtask.checked then
                done = done + 1
            end
        end
    end
    return done, total
end

function TodoApplication:parseDueDate(value)
    if not value or value == "" then
        return nil
    end
    local year, month, day = value:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
    if not year then
        year, month, day = value:match("^(%d%d%d%d)/(%d%d?)/(%d%d?)$")
    end
    if not year then
        day, month, year = value:match("^(%d%d?)/(%d%d?)/(%d%d%d%d)$")
    end
    if not year then
        day, month, year = value:match("^(%d%d?)%-(%d%d?)%-(%d%d%d%d)$")
    end
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year or not month or not day then
        return nil
    end
    if month < 1 or month > 12 or day < 1 or day > 31 then
        return nil
    end
    return { year = year, month = month, day = day }
end

function TodoApplication:formatDueDate(value)
    local date = self:parseDueDate(value)
    if not date then
        return value
    end
    local ok, timestamp = pcall(os.time, {
        year = date.year,
        month = date.month,
        day = date.day,
        hour = 12,
    })
    if not ok or not timestamp then
        return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
    end
    return os.date("%d %b %Y", timestamp)
end

function TodoApplication:editDueDate(index)
    local DateTimeWidget = require("ui/widget/datetimewidget")
    local todo = self.todos[index]
    local parsed = self:parseDueDate(todo.due_date)
    local now = os.date("*t")
    local year = parsed and parsed.year or now.year
    local month = parsed and parsed.month or now.month
    local day = parsed and parsed.day or now.day

    local date_widget
    date_widget = DateTimeWidget:new{
        year = year,
        month = month,
        day = day,
        year_min = math.min(now.year - 5, year),
        year_max = math.max(now.year + 15, year),
        title_text = _("Due date"),
        info_text = _("Year, month, day"),
        ok_text = _("Set date"),
        extra_text = parsed and _("Clear date") or nil,
        extra_callback = parsed and function()
            self.todos[index].due_date = ""
            self:saveTodos()
            date_widget:onClose()
            self:showTaskDetails(index)
        end or nil,
        callback = function(date)
            self.todos[index].due_date = string.format("%04d-%02d-%02d", date.year, date.month, date.day)
            self:saveTodos()
            self:showTaskDetails(index)
        end,
    }
    UiManager:show(date_widget)
end

function TodoApplication:showTaskDetails(index)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local margin_span = HorizontalSpan:new{ width = Size.padding.large }
    local todo = self.todos[index]
    local details_width = screen_width - Screen:scaleBySize(60)
    local field_gap = Screen:scaleBySize(12)
    local half_width = math.floor((details_width - field_gap) / 2)
    local group_gap = Screen:scaleBySize(16)
    local label_gap = Screen:scaleBySize(4)

    local function detailsLabel(text, width)
        width = width or details_width
        local label = TextWidget:new{
            text = text,
            face = Font:getFace("x_smallinfofont"),
            bold = true,
        }
        return LeftContainer:new{
            dimen = Geom:new{ w = width, h = label:getSize().h },
            label,
        }
    end

    local function detailsField(value, placeholder, callback, width, height)
        local has_value = value and value ~= ""
        return Button:new{
            text = has_value and value or placeholder,
            width = width or details_width,
            height = height,
            align = "left",
            bordersize = Size.border.default,
            padding_h = Screen:scaleBySize(10),
            padding_v = Screen:scaleBySize(10),
            text_font_face = "smallinfofont",
            text_font_size = 18,
            text_font_bold = false,
            callback = callback,
        }
    end

    local function fieldGroup(label, field_widget, width)
        return VerticalGroup:new{
            align = "left",
            detailsLabel(label, width),
            VerticalSpan:new{ width = label_gap },
            field_widget,
        }
    end

    if self.current_frame then
        local old_frame = self.current_frame
        self.current_frame = nil
        UiManager:close(old_frame)
        old_frame:free()
    end

    local function editField(title, field, hint)
        local InputDialog = require("ui/widget/inputdialog")
        local input_dialog
        input_dialog = InputDialog:new{
            title = title,
            input = todo[field] or "",
            input_hint = hint,
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function()
                            UiManager:close(input_dialog)
                        end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            local new_text = input_dialog:getInputText()
                            if new_text then
                                self.todos[index][field] = new_text
                                self:saveTodos()
                                self:showTaskDetails(index)
                            end
                            UiManager:close(input_dialog)
                        end,
                    },
                }
            },
        }
        UiManager:show(input_dialog)
        input_dialog:onShowKeyboard()
    end

    if not todo.subtasks then todo.subtasks = {} end

    local details_list = VerticalGroup:new{ align = "left" }

    table.insert(details_list, fieldGroup(_("Task name"), detailsField(
        todo.text,
        _("Add a name"),
        function() editField(_("Edit Name"), "text", _("Enter task name")) end
    )))
    table.insert(details_list, VerticalSpan:new{ width = group_gap })
    table.insert(details_list, HorizontalGroup:new{
        fieldGroup(_("Category"), detailsField(
            todo.category,
            _("Add category"),
            function() editField(_("Edit Category"), "category", _("Enter category or group name")) end,
            half_width
        ), half_width),
        HorizontalSpan:new{ width = field_gap },
        fieldGroup(_("Due date"), detailsField(
            self:formatDueDate(todo.due_date),
            _("Add due date"),
            function() self:editDueDate(index) end,
            half_width
        ), half_width),
    })
    table.insert(details_list, VerticalSpan:new{ width = group_gap })
    table.insert(details_list, fieldGroup(_("Notes"), detailsField(
        todo.description,
        _("Add notes"),
        function() editField(_("Edit Description"), "description", _("Enter task description/notes")) end,
        details_width,
        Screen:scaleBySize(72)
    )))

    local completed_count, subtask_count = self:countSubtaskProgress(todo)
    local subtasks_heading = _("Sub-tasks")
    if subtask_count > 0 then
        if completed_count == subtask_count then
            subtasks_heading = string.format("%s · %s", _("Sub-tasks"), _("All done"))
        else
            subtasks_heading = string.format("%s · %d/%d", _("Sub-tasks"), completed_count, subtask_count)
        end
    end

    table.insert(details_list, VerticalSpan:new{ width = group_gap })
    table.insert(details_list, LineWidget:new{ dimen = Geom:new{ w = details_width, h = Size.line.medium } })
    table.insert(details_list, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    table.insert(details_list, detailsLabel(subtasks_heading))

    local has_completed_subtasks = completed_count > 0
    if subtask_count == 0 then
        table.insert(details_list, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        local empty_hint = TextWidget:new{
            text = _("No sub-tasks yet"),
            face = Font:getFace("x_smallinfofont"),
        }
        table.insert(details_list, LeftContainer:new{
            dimen = Geom:new{ w = details_width, h = empty_hint:getSize().h },
            empty_hint,
        })
    else
        local row_pad = Screen:scaleBySize(12)
        for sub_index, _ in ipairs(todo.subtasks) do
            table.insert(details_list, VerticalSpan:new{ width = row_pad })
            table.insert(details_list, self:createSubtaskItem(index, sub_index, details_width))
            table.insert(details_list, VerticalSpan:new{ width = row_pad })
            table.insert(details_list, LineWidget:new{ dimen = Geom:new{ w = details_width, h = Size.line.thin } })
        end
    end

    table.insert(details_list, VerticalSpan:new{ width = Screen:scaleBySize(14) })
    table.insert(details_list, Button:new{
        text = _("+ Add sub-task"),
        width = details_width,
        align = "left",
        bordersize = Size.border.default,
        padding = Screen:scaleBySize(10),
        text_font_face = "smallinfofont",
        text_font_size = 18,
        text_font_bold = false,
        callback = function()
            self:addSubtask(index)
        end,
    })

    if has_completed_subtasks then
        table.insert(details_list, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        table.insert(details_list, Button:new{
            text = _("Remove completed sub-tasks"),
            width = details_width,
            align = "left",
            bordersize = Size.border.default,
            padding = Screen:scaleBySize(10),
            text_font_face = "smallinfofont",
            text_font_size = 18,
            text_font_bold = false,
            callback = function()
                self:confirmRemoveCompleted(_("Remove all completed sub-tasks?"), function()
                    local new_subtasks = {}
                    for _, subtask in ipairs(todo.subtasks) do
                        if not subtask.checked then
                            table.insert(new_subtasks, subtask)
                        end
                    end
                    self.todos[index].subtasks = new_subtasks
                    self:saveTodos()
                    self:showTaskDetails(index)
                end)
            end,
        })
    end

    table.insert(details_list, VerticalSpan:new{ width = group_gap })
    table.insert(details_list, LineWidget:new{ dimen = Geom:new{ w = details_width, h = Size.line.medium } })
    table.insert(details_list, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    table.insert(details_list, HeaderActionButton:new{
        text = _("Remove this task"),
        width = details_width,
        height = Screen:scaleBySize(32),
        padding = Screen:scaleBySize(8),
        bordersize = 0,
        background = Blitbuffer.COLOR_BLACK,
        radius = 0,
        text_font_face = "smallinfofont",
        text_font_size = 18,
        text_font_bold = false,
        callback = function()
            self:confirmRemoveCompleted(_("Remove this task?"), function()
                table.remove(self.todos, index)
                self:saveTodos()
                self:refreshUI()
            end)
        end,
    })
    table.insert(details_list, VerticalSpan:new{ width = Screen:scaleBySize(16) })

    local header_title = (todo.text and todo.text ~= "") and todo.text or _("Task Details")
    local top_margin = Screen:scaleBySize(12)
    local details_scroll = ScrollableContainer:new{
        dimen = Geom:new{
            w = screen_width - Size.padding.large,
            h = screen_height - Screen:scaleBySize(52) - Size.padding.large - top_margin
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = screen_width - Size.padding.large,
                h = details_list:getSize().h,
            },
            details_list,
        },
    }

    self.current_frame = OverlapGroup:new{
        dimen = Screen:getSize(),
        FrameContainer:new{
            dimen = Screen:getSize(),
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            WidgetContainer:new{ dimen = Screen:getSize() },
        },
        VerticalGroup:new{
            VerticalSpan:new{ width = top_margin },
            OverlapGroup:new{
                dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(50) },
                LeftContainer:new{
                    dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(50) },
                    HorizontalGroup:new{
                        margin_span,
                        HeaderActionButton:new{
                            text = _("< Back"),
                            height = Screen:scaleBySize(28),
                            padding = Screen:scaleBySize(6),
                            bordersize = 0,
                            background = Blitbuffer.COLOR_BLACK,
                            radius = 0,
                            text_font_size = 18,
                            text_font_bold = false,
                            callback = function()
                                self:refreshUI()
                            end
                        },
                    }
                },
                CenterContainer:new{
                    dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(50) },
                    TextWidget:new{
                        text = header_title,
                        face = Font:getFace("cfont"),
                        bold = true,
                        max_width = screen_width - Screen:scaleBySize(160),
                    },
                },
            },
            LineWidget:new{ dimen = Geom:new{ w = screen_width - Screen:scaleBySize(20), h = 2 } },
            VerticalSpan:new{width = Size.padding.large},
            
            CenterContainer:new{
                dimen = Geom:new{
                    w = screen_width,
                    h = details_scroll.dimen.h,
                },
                details_scroll,
            },
        }
    }
    self.current_frame.cropping_widget = details_scroll
    details_scroll.show_parent = self.current_frame
    UiManager:show(self.current_frame, "ui")
end

function TodoApplication:createTodoItem(todo, index)
    local checkbox_width = Screen:scaleBySize(30)
    local content_margin = Size.padding.large + Screen:scaleBySize(12)
    local row_width = Screen:getWidth() - ScrollableContainer:getScrollbarWidth() - content_margin - checkbox_width - Screen:scaleBySize(10)
    local check_button
    check_button = CheckButton:new{
        checked = todo.checked,
        callback = function()
            self.todos[index].checked = check_button.checked
            self:saveTodos()
            self:repaintCurrentFrame()
        end,
        width = checkbox_width,
    }

    local task_label = todo.text
    local done_count, total_count = self:countSubtaskProgress(todo)
    if total_count > 0 then
        task_label = string.format("%s  (%d/%d)", todo.text, done_count, total_count)
    end

    local task_button = Button:new{
        text = task_label,
        width = row_width,
        height = Screen:scaleBySize(42),
        align = "left",
        bordersize = 0,
        padding = Screen:scaleBySize(5),
        text_font_face = "smallinfofont",
        text_font_bold = false,
        callback = function() self:showTaskDetails(index) end,
    }

    return HorizontalGroup:new{
        HorizontalSpan:new{ width = content_margin },
        check_button,
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        task_button,
    }
end

function TodoApplication:createSubtaskItem(main_index, sub_index, details_width)
    local subtask = self.todos[main_index].subtasks[sub_index]
    details_width = details_width or (Screen:getWidth() - Screen:scaleBySize(60))
    local icon_size = Screen:scaleBySize(22)
    local icon_button_width = Screen:scaleBySize(32)
    local check_width = details_width - icon_button_width * 2

    local function iconButton(icon, callback)
        return Button:new{
            icon = icon,
            icon_width = icon_size,
            icon_height = icon_size,
            width = icon_button_width,
            height = icon_button_width,
            padding = 0,
            bordersize = 0,
            callback = callback,
        }
    end

    local check_button
    check_button = CheckButton:new{
        checked = subtask.checked,
        text = subtask.text,
        single_line = true,
        width = check_width,
        face = Font:getFace("smallinfofont"),
        fgcolor = subtask.checked and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
        callback = function()
            self.todos[main_index].subtasks[sub_index].checked = check_button.checked
            self:saveTodos()
            self:showTaskDetails(main_index)
        end,
        hold_callback = function()
            self:editSubtask(main_index, sub_index)
        end,
    }

    return HorizontalGroup:new{
        align = "center",
        check_button,
        iconButton("edit", function()
            self:editSubtask(main_index, sub_index)
        end),
        iconButton("close", function()
            self:removeSubtask(main_index, sub_index)
        end),
    }
end

function TodoApplication:refreshUI()
    if self.current_frame then
        local old_frame = self.current_frame
        self.current_frame = nil
        UiManager:close(old_frame)
        old_frame:free()
    end
    self:showItems()
end

function TodoApplication:showItems()
    local margin_span = HorizontalSpan:new{ width = Size.padding.large }
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local scroll_content_width = screen_width - ScrollableContainer:getScrollbarWidth()
    local content_margin = Size.padding.large + Screen:scaleBySize(12)
    local add_button_width = math.min(Screen:scaleBySize(175), math.floor(screen_width * 0.40))
    
    if self.current_frame then
        local old_frame = self.current_frame
        self.current_frame = nil
        UiManager:close(old_frame)
        old_frame:free()
    end

    local todo_list = VerticalGroup:new{
        align = "left",
        id = "todo_list",
    }
    local category_order = {}
    local category_tasks = {}
    for index, todo in ipairs(self.todos) do
        local category = (todo.category and todo.category ~= "") and todo.category or _("Uncategorized")
        if not category_tasks[category] then
            category_tasks[category] = {}
            table.insert(category_order, category)
        end
        table.insert(category_tasks[category], { todo = todo, index = index })
    end

    for _, category in ipairs(category_order) do
        table.insert(todo_list, HorizontalGroup:new{
            HorizontalSpan:new{ width = content_margin },
            TextWidget:new{
                text = category,
                face = Font:getFace("cfont"),
                bold = true,
            },
        })
        table.insert(todo_list, HorizontalGroup:new{
            HorizontalSpan:new{ width = content_margin },
            LineWidget:new{
                dimen = Geom:new{ w = scroll_content_width - content_margin - Screen:scaleBySize(40), h = 1 }
            },
        })
        for task_index, task in ipairs(category_tasks[category]) do
            if task_index > 1 then
                table.insert(todo_list, HorizontalGroup:new{
                    HorizontalSpan:new{ width = content_margin },
                    LineWidget:new{
                        dimen = Geom:new{ w = scroll_content_width - content_margin - Screen:scaleBySize(40), h = 1 }
                    },
                })
            end
            table.insert(todo_list, self:createTodoItem(task.todo, task.index))
        end
    end

    if #self.todos == 0 then
        local empty_state = VerticalGroup:new{
            align = "center",
            TextWidget:new{
                text = _("No tasks yet"),
                face = Font:getFace("cfont"),
                bold = true,
            },
            VerticalSpan:new{ width = Size.padding.large },
            TextWidget:new{
                text = _("Tap + to add one."),
                face = Font:getFace("smallinfofont"),
            },
        }
        table.insert(todo_list, VerticalSpan:new{ width = Screen:scaleBySize(24) })
        table.insert(todo_list, CenterContainer:new{
            dimen = Geom:new{ w = screen_width, h = empty_state:getSize().h },
            empty_state,
        })
    end

    -- Add delete button
    local remove_completed_button = HeaderActionButton:new{
        text = _("Remove completed"),
        height = Screen:scaleBySize(28),
        padding = Screen:scaleBySize(6),
        bordersize = 0,
        background = Blitbuffer.COLOR_BLACK,
        radius = 0,
        text_font_size = 18,
        text_font_bold = false,
        callback = function()
            local has_completed = false
            for _, todo in ipairs(self.todos) do
                if todo.checked then
                    has_completed = true
                    break
                end
            end
            if not has_completed then
                UiManager:show(InfoMessage:new{
                    text = _("No completed tasks to remove."),
                })
                return
            end
            self:confirmRemoveCompleted(_("Remove all completed tasks?"), function()
                local new_todos = {}
                for _, todo in ipairs(self.todos) do
                    if not todo.checked then
                        table.insert(new_todos, todo)
                    end
                end
                self.todos = new_todos
                self:saveTodos()
                self:refreshUI()
            end)
        end,
    }



    local top_margin = Screen:scaleBySize(12)
    local todo_scroll = ScrollableContainer:new{
        dimen = Geom:new{
            w = screen_width,
            h = screen_height - Screen:scaleBySize(127) - top_margin
        },
        todo_list
    }

    self.current_frame = OverlapGroup:new{
        dimen = Screen:getSize(),
        FrameContainer:new{
            dimen = Screen:getSize(),
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            WidgetContainer:new{ dimen = Screen:getSize() },
        },
        VerticalGroup:new{
            VerticalSpan:new{ width = top_margin },
            -- Header
            OverlapGroup:new{
                dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(50) },
                LeftContainer:new{
                    dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(50) },
                    HorizontalGroup:new{
                        margin_span,
                        TextWidget:new{
                            text = _("To-do List"),
                            face = Font:getFace("cfont"),
                            bold = true,
                        },
                    }
                },
                RightContainer:new{
                    dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(50) },
                    HorizontalGroup:new{
                        HeaderActionButton:new{
                            text = _("+ Add New Task"),
                            width = add_button_width,
                            height = Screen:scaleBySize(30),
                            padding = Screen:scaleBySize(4),
                            bordersize = 0,
                            background = Blitbuffer.COLOR_BLACK,
                            radius = 0,
                            text_font_size = 18,
                            text_font_bold = false,
                            callback = function()
                                local InputDialog = require("ui/widget/inputdialog")
                                local input_dialog
                                input_dialog = InputDialog:new{
                                    title = _("New Todo"),
                                    input = "",
                                    input_hint = _("Enter todo text"),
                                    description = _("Please enter the todo item text."),
                                    buttons = {
                                        {
                                            {
                                                text = _("Cancel"),
                                                id = "close",
                                                callback = function()
                                                    UiManager:close(input_dialog)
                                                end,
                                            },
                                            {
                                                text = _("Save"),
                                                is_enter_default = true,
                                                callback = function()
                                                    local new_text = input_dialog:getInputText()
                                                    if new_text and new_text ~= "" then
                                                        table.insert(self.todos, { text = new_text, checked = false })
                                                        self:saveTodos()
                                                        self:showTaskDetails(#self.todos)
                                                    else
                                                        logger.warn("Empty todo not added.")
                                                    end
                                                    UiManager:close(input_dialog)
                                                end,
                                            },
                                        }
                                    },
                                }
                                UiManager:show(input_dialog)
                                input_dialog:onShowKeyboard()
                            end,
                        },
                        margin_span,
                        self:addExitButton(),
                        margin_span
                    }
                }
            },
            LineWidget:new{ dimen = Geom:new{ w = screen_width - Screen:scaleBySize(20), h = 2 } },
            VerticalSpan:new{width = Size.padding.large},

            todo_scroll,
            
            VerticalSpan:new{width = Size.padding.large},
            LineWidget:new{ dimen = Geom:new{ w = screen_width - Screen:scaleBySize(20), h = 1 } },
            VerticalSpan:new{width = Screen:scaleBySize(8)},
            HorizontalGroup:new{
                margin_span,
                remove_completed_button,
            },
            VerticalSpan:new{width = Screen:scaleBySize(12)},
        }
    }
    self.current_frame.cropping_widget = todo_scroll
    todo_scroll.show_parent = self.current_frame
    UiManager:show(self.current_frame, "ui")
end

function TodoApplication:addToMainMenu(menu_items)
    menu_items.todo = {
        text = _("Todo App"),
        callback = function()
            self:showItems()
        end
    }
end

return TodoApplication
