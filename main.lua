local UiManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local CheckButton = require("ui/widget/checkbutton")
local FrameContainer = require("ui/widget/container/framecontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local TextWidget = require("ui/widget/textwidget")
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
local IconButton = require("ui/widget/iconbutton")
local LineWidget = require("ui/widget/linewidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")

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
    local star_width = Screen:scaleBySize(25)
    local ellipsis_button_width = Screen:scaleBySize(34)
    return IconButton:new{
        icon = "exit",
        width = star_width,
        height = star_width,
        padding = math.floor((ellipsis_button_width - star_width)/2) + Size.padding.button,
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

    if saved_todos and #saved_todos > 0 then
        self.todos = saved_todos
    else
        self.todos = {
            { text = "Sample Todo", checked = false },
        }
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

function TodoApplication:showTaskDetails(index)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local margin_span = HorizontalSpan:new{ width = Size.padding.large }
    local todo = self.todos[index]

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

    local details_list = VerticalGroup:new{
        align = "left",
        
        TextWidget:new{ text = _("Task Name:"), face = Font:getFace("cfont"), bold = true },
        Button:new{
            text = (todo.text and todo.text ~= "") and todo.text or _("[Tap to enter name]"),
            width = screen_width - Screen:scaleBySize(60),
            bordersize = 1,
            padding = Screen:scaleBySize(10),
            callback = function() editField(_("Edit Name"), "text", _("Enter task name")) end,
        },
        VerticalSpan:new{width = Size.padding.large},

        TextWidget:new{ text = _("Due Date:"), face = Font:getFace("cfont"), bold = true },
        Button:new{
            text = (todo.due_date and todo.due_date ~= "") and todo.due_date or _("[Tap to enter due date]"),
            width = screen_width - Screen:scaleBySize(60),
            bordersize = 1,
            padding = Screen:scaleBySize(10),
            callback = function() editField(_("Edit Due Date"), "due_date", _("e.g. DD/MM/YYYY")) end,
        },
        VerticalSpan:new{width = Size.padding.large},

        TextWidget:new{ text = _("Description / Notes:"), face = Font:getFace("cfont"), bold = true },
        Button:new{
            text = (todo.description and todo.description ~= "") and todo.description or _("[Tap to enter description]"),
            width = screen_width - Screen:scaleBySize(60),
            bordersize = 1,
            padding = Screen:scaleBySize(10),
            callback = function() editField(_("Edit Description"), "description", _("Enter task description/notes")) end,
        },
    }

    -- Sub-tasks Header
    table.insert(details_list, VerticalSpan:new{width = Size.padding.large})
    table.insert(details_list, LineWidget:new{ dimen = Geom:new{ w = screen_width - Screen:scaleBySize(60), h = 2 } })
    table.insert(details_list, VerticalSpan:new{width = Size.padding.large})
    table.insert(details_list, TextWidget:new{ text = _("Sub-tasks:"), face = Font:getFace("cfont"), bold = true })
    
    if not todo.subtasks then todo.subtasks = {} end

    for sub_index, subtask in ipairs(todo.subtasks) do
        table.insert(details_list, self:createSubtaskItem(index, sub_index))
        table.insert(details_list, LineWidget:new{ dimen = Geom:new{ w = screen_width - Screen:scaleBySize(60), h = 1 } })
    end

    table.insert(details_list, Button:new{
        text = _("+ Add Sub-task"),
        width = screen_width - Screen:scaleBySize(60),
        bordersize = 1,
        padding = Screen:scaleBySize(10),
        callback = function()
            local InputDialog = require("ui/widget/inputdialog")
            local input_dialog
            input_dialog = InputDialog:new{
                title = _("New Sub-task"),
                input = "",
                input_hint = _("Enter sub-task text"),
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function() UiManager:close(input_dialog) end,
                        },
                        {
                            text = _("Save"),
                            is_enter_default = true,
                            callback = function()
                                local new_text = input_dialog:getInputText()
                                if new_text and new_text ~= "" then
                                    table.insert(self.todos[index].subtasks, { text = new_text, checked = false })
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
        end,
    })

    table.insert(details_list, VerticalSpan:new{width = Size.padding.large})
    table.insert(details_list, Button:new{
        text = _("Remove completed sub-tasks"),
        callback = function()
            local new_subtasks = {}
            for _, subtask in ipairs(todo.subtasks) do
                if not subtask.checked then
                    table.insert(new_subtasks, subtask)
                end
            end
            self.todos[index].subtasks = new_subtasks
            self:saveTodos()
            self:showTaskDetails(index)
        end,
    })

    local details_scroll = ScrollableContainer:new{
        dimen = Geom:new{
            w = screen_width - Size.padding.large,
            h = screen_height - Screen:scaleBySize(52) - Size.padding.large
        },
        details_list
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
            OverlapGroup:new{
                dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(50) },
                LeftContainer:new{
                    dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(50) },
                    HorizontalGroup:new{
                        margin_span,
                        Button:new{
                            text = _("< Back"),
                            padding = Screen:scaleBySize(5),
                            bordersize = 0,
                            callback = function()
                                self:refreshUI()
                            end
                        },
                        margin_span,
                        TextWidget:new{
                            text = _("Task Details"),
                            face = Font:getFace("cfont"),
                            bold = true,
                        },
                    }
                }
            },
            LineWidget:new{ dimen = Geom:new{ w = screen_width - Screen:scaleBySize(20), h = 2 } },
            VerticalSpan:new{width = Size.padding.large},
            
            HorizontalGroup:new{
                margin_span,
                details_scroll
            },
        }
    }
    self.current_frame.cropping_widget = details_scroll
    details_scroll.show_parent = self.current_frame
    UiManager:show(self.current_frame, "ui")
end

function TodoApplication:createTodoItem(todo, index)
    local check_button
    check_button = CheckButton:new{
        checked = todo.checked,
        callback = function()
            self.todos[index].checked = check_button.checked
            self:saveTodos()
            self:repaintCurrentFrame()
        end,
        width = Screen:scaleBySize(30),
    }

    local text_widget = TextWidget:new{
        text = todo.text,
        face = Font:getFace("smallinfofont"),
    }

    local edit_button = Button:new{
        text = _("Edit"),
        padding = Screen:scaleBySize(5),
        bordersize = 0,
        callback = function()
            self:showTaskDetails(index)
        end,
    }

    return HorizontalGroup:new{
        HorizontalSpan:new{ width = Size.padding.large },
        check_button,
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        text_widget,
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        edit_button,
    }
end

function TodoApplication:createSubtaskItem(main_index, sub_index)
    local subtask = self.todos[main_index].subtasks[sub_index]
    local check_button
    check_button = CheckButton:new{
        checked = subtask.checked,
        callback = function()
            self.todos[main_index].subtasks[sub_index].checked = check_button.checked
            self:saveTodos()
            self:repaintCurrentFrame()
        end,
        width = Screen:scaleBySize(30),
    }

    local text_widget = TextWidget:new{
        text = subtask.text,
        face = Font:getFace("smallinfofont"),
    }

    local edit_button = Button:new{
        text = _("Edit"),
        padding = Screen:scaleBySize(5),
        bordersize = 0,
        callback = function()
            local InputDialog = require("ui/widget/inputdialog")
            local input_dialog
            input_dialog = InputDialog:new{
                title = _("Edit Sub-task"),
                input = subtask.text,
                input_hint = _("Enter sub-task text"),
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function() UiManager:close(input_dialog) end,
                        },
                        {
                            text = _("Save"),
                            is_enter_default = true,
                            callback = function()
                                local new_text = input_dialog:getInputText()
                                if new_text and new_text ~= "" then
                                    self.todos[main_index].subtasks[sub_index].text = new_text
                                    self:saveTodos()
                                    self:showTaskDetails(main_index)
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
    }

    return HorizontalGroup:new{
        HorizontalSpan:new{ width = Size.padding.large },
        check_button,
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        text_widget,
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        edit_button,
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
    for index, todo in ipairs(self.todos) do
        if index > 1 then
            table.insert(todo_list, LineWidget:new{
                dimen = Geom:new{ w = screen_width - Screen:scaleBySize(40), h = 1 }
            })
        end
        table.insert(todo_list, self:createTodoItem(todo, index))
    end

    -- Add delete button
    local remove_completed_button = Button:new{
        text = _("Remove completed"),
        callback = function()
            local new_todos = {}
            for _, todo in ipairs(self.todos) do
                if not todo.checked then
                    table.insert(new_todos, todo)
                end
            end
            self.todos = new_todos
            self:saveTodos()
            self:refreshUI()
        end,
    }



    local todo_scroll = ScrollableContainer:new{
        dimen = Geom:new{
            w = screen_width,
            h = screen_height - Screen:scaleBySize(110)
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
                        IconButton:new{
                            icon = "plus",
                            width = Screen:scaleBySize(30),
                            height = Screen:scaleBySize(30),
                            padding = Screen:scaleBySize(5),
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
                                                        self:refreshUI()
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
            HorizontalGroup:new{
                margin_span,
                remove_completed_button,
            }
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
