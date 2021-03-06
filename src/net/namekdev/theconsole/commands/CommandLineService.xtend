package net.namekdev.theconsole.commands

import javafx.event.EventHandler
import javafx.scene.input.KeyCode
import javafx.scene.input.KeyEvent
import net.namekdev.theconsole.commands.api.ICommandLineHandler
import net.namekdev.theconsole.commands.api.ICommandLineService
import net.namekdev.theconsole.commands.api.ICommandLineUtils
import net.namekdev.theconsole.state.api.IConsoleContext
import net.namekdev.theconsole.view.api.IConsoleOutputEntry

class CommandLineService implements ICommandLineService, ICommandLineUtils, EventHandler<KeyEvent> {
	val IConsoleContext consoleContext

	val ICommandLineHandler basicHandler
	var ICommandLineHandler currentHandler

	var IConsoleOutputEntry lastAddedEntry
	val CommandHistory history = new CommandHistory
	var String temporaryCommandName

	val SPACE_CHAR = 32 as char


	new(IConsoleContext consoleContext, CommandManager commandManager) {
		this.consoleContext = consoleContext
		consoleContext.input.keyPressHandler = this

		basicHandler = new CommandLineHandler(commandManager)
		resetHandler()
	}

	override setHandler(ICommandLineHandler handler) {
		handler.init(consoleContext, this)

		if (handler != currentHandler && currentHandler != basicHandler && currentHandler != null) {
			currentHandler.dispose()
		}

		currentHandler = handler
	}

	override resetHandler() {
		setHandler(basicHandler)
	}

	override getHandler() {
		return currentHandler
	}

	def void dispose() {
		consoleContext.input.keyPressHandler = null
		currentHandler.dispose()

		if (basicHandler != currentHandler) {
			basicHandler.dispose()
		}
	}

	override setInputEntry(String text) {
		if (text == null) {
			lastAddedEntry = null
			return
		}

		if (lastAddedEntry != null) {
			if (!lastAddedEntry.valid) {
				lastAddedEntry = null
			}
		}

		// don't add the same output second time
		if (lastAddedEntry == null || lastAddedEntry.type != IConsoleOutputEntry.INPUT) {
			lastAddedEntry = consoleContext.output.addTextEntry(text)
			lastAddedEntry.type = IConsoleOutputEntry.INPUT
		}
		else if (lastAddedEntry != null) {
			// modify existing text entry
			lastAddedEntry.setText(text)
		}
	}

	override setInput(String text) {
		setInput(text, -1)
	}

	override setInput(String text, int caretPos) {
		consoleContext.input.setText(text)
		consoleContext.input.setCursorPosition(if (caretPos >= 0) caretPos else text.length())
	}

	override getInput() {
		return consoleContext.input.getText()
	}

	override getInputCursorPosition() {
		return consoleContext.input.cursorPosition
	}

	override countSpacesInInput() {
		var count = 0 as int
		val str = getInput()

		for (var i = 0, val n = str.length(); i < n; i++) {
			if (str.charAt(i) == SPACE_CHAR) {
				count++
			}
		}

		return count
	}


	override handle(KeyEvent evt) {
		switch (evt.code) {
			case KeyCode.TAB: {
				currentHandler.handleCompletion()
				evt.consume()
			}

			case KeyCode.ENTER: {
				val input = getInput()

				if (currentHandler.handleExecution(input, this, consoleContext)) {
					setInput("")
					history.save(input)
					lastAddedEntry = null
					temporaryCommandName = null
					history.resetPointer()
				}
			}

			case KeyCode.ESCAPE: {
				setInput("")
				lastAddedEntry = null

				if (temporaryCommandName == null) {
					history.resetPointer()
				}
				else {
					temporaryCommandName = null
				}
			}

			case KeyCode.BACK_SPACE,
			case KeyCode.DELETE: //DELETE
			{
				if (consoleContext.input.text.length == 0) {
					// forget old entry
					lastAddedEntry = null
				}
			}

			case KeyCode.UP: {
				if (history.hasAny()) {
					val input = getInput()

					if (input.equals(history.getCurrent()))
						history.morePast()
					else {
						temporaryCommandName = input
					}

					setInput(history.getCurrent())
				}
			}

			case KeyCode.DOWN: {
				if (history.hasAny()) {
					if (history.lessPast()) {
						setInput(if (temporaryCommandName != null) temporaryCommandName else "")
					}
					else {
						setInput(history.getCurrent())
					}
				}
			}
		}
	}

}
