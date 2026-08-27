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

function TodoApplication:showTaskDetails(index)
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local margin_span = HorizontalSpan:new{ width = Size.padding.large }
    local todo = self.todos[index]
    local details_width = screen_width - Screen:scaleBySize(60)

    local function detailsLabel(text)
        local label = TextWidget:new{
            text = text,
            face = Font:getFace("cfont"),
            bold = true,
        }
        return LeftContainer:new{
            dimen = Geom:new{ w = details_width, h = label:getSize().h },
            label,
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

    local details_list = VerticalGroup:new{
        align = "center",
        
        detailsLabel(_("Task Name:")),
        Button:new{
            text = (todo.text and todo.text ~= "") and todo.text or _("[Tap to enter name]"),
            width = details_width,
            bordersize = 1,
            padding = Screen:scaleBySize(10),
            text_font_face = "smallinfofont",
            text_font_size = 18,
            text_font_bold = false,
            callback = function() editField(_("Edit Name"), "text", _("Enter task name")) end,
        },
        VerticalSpan:new{width = Size.padding.large},

        detailsLabel(_("Due Date:")),
        Button:new{
            text = (todo.due_date and todo.due_date ~= "") and todo.due_date or _("[Tap to enter due date]"),
            width = details_width,
            bordersize = 1,
            padding = Screen:scaleBySize(10),
            text_font_face = "smallinfofont",
            text_font_size = 18,
            text_font_bold = false,
            callback = function() editField(_("Edit Due Date"), "due_date", _("e.g. DD/MM/YYYY")) end,
        },
        VerticalSpan:new{width = Size.padding.large},

        detailsLabel(_("Description / Notes:")),
        Button:new{
            text = (todo.description and todo.description ~= "") and todo.description or _("[Tap to enter description]"),
            width = details_width,
            bordersize = 1,
            padding = Screen:scaleBySize(10),
            text_font_face = "smallinfofont",
            text_font_size = 18,
            text_font_bold = false,
            callback = function() editField(_("Edit Description"), "description", _("Enter task description/notes")) end,
        },
    }

    -- Sub-tasks Header
    table.insert(details_list, VerticalSpan:new{width = Size.padding.large})
    table.insert(details_list, LineWidget:new{ dimen = Geom:new{ w = details_width, h = 2 } })
    table.insert(details_list, VerticalSpan:new{width = Size.padding.large})
    table.insert(details_list, detailsLabel(_("Sub-tasks:")))
    
    if not todo.subtasks then todo.subtasks = {} end

    local has_completed_subtasks = false
    for sub_index, subtask in ipairs(todo.subtasks) do
        has_completed_subtasks = has_completed_subtasks or subtask.checked
        table.insert(details_list, self:createSubtaskItem(index, sub_index))
        table.insert(details_list, LineWidget:new{ dimen = Geom:new{ w = details_width, h = 1 } })
    end

    table.insert(details_list, Button:new{
        text = _("+ Add Sub-task"),
        width = details_width,
        bordersize = 1,
        padding = Screen:scaleBySize(10),
        text_font_face = "smallinfofont",
        text_font_size = 18,
        text_font_bold = false,
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
        enabled = has_completed_subtasks,
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

    table.insert(details_list, VerticalSpan:new{width = Size.padding.large})
    table.insert(details_list, Button:new{
        text = _("Remove this task"),
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

    local details_scroll = ScrollableContainer:new{
        dimen = Geom:new{
            w = screen_width - Size.padding.large,
            h = screen_height - Screen:scaleBySize(52) - Size.padding.large
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
                    }
                },
                CenterContainer:new{
                    dimen = Geom:new{ w = screen_width, h = Screen:scaleBySize(50) },
                    TextWidget:new{
                        text = _("Task Details"),
                        face = Font:getFace("cfont"),
                        bold = true,
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

    local task_button = Button:new{
        text = todo.text,
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
        text_font_face = "smallinfofont",
        text_font_size = 18,
        text_font_bold = false,
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
    local scroll_content_width = screen_width - ScrollableContainer:getScrollbarWidth()
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
    for index, todo in ipairs(self.todos) do
        if index > 1 then
            table.insert(todo_list, LineWidget:new{
                dimen = Geom:new{ w = scroll_content_width - Screen:scaleBySize(40), h = 1 }
            })
        end
        table.insert(todo_list, self:createTodoItem(todo, index))
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



    local todo_scroll = ScrollableContainer:new{
        dimen = Geom:new{
            w = screen_width,
            h = screen_height - Screen:scaleBySize(127)
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
