# KOReader Todo Tracker

A lightweight to-do list plugin for [KOReader](https://koreader.rocks/). Manage tasks directly on your e-reader, with optional due dates, notes, and sub-tasks. This is an enhancement of [matthewashton-k](https://github.com/matthewashton-k/todo-koplugin)'s todo plugin for koreader.

This project removes the Google Task's sync logic, as personally it's not something that I plan to make use of due to my anti-Google stance, if there's enough interest I'll look at reimplementing it.

## Features

- Add and complete to-do items.
- Edit a task's name, due date, and notes.
- Add, edit, and complete sub-tasks.
- Remove completed tasks or sub-tasks in bulk.
- Persist tasks between KOReader sessions.

## Installation

1. Close KOReader.
2. Copy this directory to KOReader's plugins directory and name it `todo.koplugin`:

	```text
	koreader/plugins/todo.koplugin/
	```

3. Confirm that the installed directory contains `_meta.lua` and `main.lua`.
4. Start KOReader. Select **Todo App** from the main menu.

On first launch, the plugin creates a sample task. Your tasks are saved by KOReader in its settings directory as `todos.lua`.


## Compatibility

This plugin requires KOReader.


