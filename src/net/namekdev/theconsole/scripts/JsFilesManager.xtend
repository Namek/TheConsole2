package net.namekdev.theconsole.scripts

import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.nio.file.FileSystems
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.PathMatcher
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes
import java.util.ArrayList
import java.util.List
import java.util.Map
import java.util.Queue
import java.util.TreeMap
import net.namekdev.theconsole.commands.CommandManager
import net.namekdev.theconsole.commands.internal.ScriptCommand
import net.namekdev.theconsole.modules.ModuleManager
import net.namekdev.theconsole.state.api.IConsoleContextProvider
import net.namekdev.theconsole.utils.PathUtils
import net.namekdev.theconsole.utils.RecursiveWatcher
import net.namekdev.theconsole.utils.RecursiveWatcher.FileChangeEvent
import net.namekdev.theconsole.utils.api.IDatabase

import static java.nio.file.FileVisitResult.*
import static java.nio.file.StandardWatchEventKinds.ENTRY_CREATE
import static java.nio.file.StandardWatchEventKinds.ENTRY_DELETE
import static java.nio.file.StandardWatchEventKinds.ENTRY_MODIFY

class JsFilesManager {
	final String SCRIPT_FILE_EXTENSION = "js"

	IDatabase settingsDatabase
	IDatabase.ISectionAccessor scriptsDatabase
	IConsoleContextProvider consoleContextProvider
	CommandManager commandManager
	ModuleManager moduleManager

	final Path scriptsWatchDir = PathUtils.scriptsDir
	private PathMatcher scriptExtensionMatcher

	Map<String, ScriptCommand> scripts = new TreeMap



	new(IDatabase database, IConsoleContextProvider consoleContextProvider, CommandManager commandManager, ModuleManager moduleManager) {
		this.settingsDatabase = database
		this.scriptsDatabase = settingsDatabase.getScriptsSection()
		this.consoleContextProvider = consoleContextProvider
		this.commandManager = commandManager
		this.moduleManager = moduleManager

		val fs = FileSystems.getDefault()
		scriptExtensionMatcher = fs.getPathMatcher("glob:**/*." + SCRIPT_FILE_EXTENSION)
	}

	def void init() {
		if (!Files.isDirectory(scriptsWatchDir)) {
			val path = scriptsWatchDir.toAbsolutePath().toString()
			defaultContextConsole.log("No scripts folder found, creating a new one: " + path)
			new File(path).mkdirs()
		}

		// TODO if the scripts folder doesn't exist, then create it and copy standard scripts from internals

		analyzeScriptsFolder(scriptsWatchDir)

		try {
			val RecursiveWatcher watcher = new RecursiveWatcher(scriptsWatchDir, 500, scriptsFolderWatcher)
			watcher.start()
		}
		catch (IOException exc) {
			defaultContextConsole.error(exc.toString())
		}
	}

	def private ConsoleProxy getDefaultContextConsole() {
		return consoleContextProvider.contextOfDefaultTab.proxy
	}

	def private createScriptStorage(String name) {
		return scriptsDatabase.getSection(name, true)
	}

	def private void analyzeScriptsFolder(Path folder) {
		val List<Path> modules = new ArrayList
		val List<Path> scripts = new ArrayList

		Files.walkFileTree(folder, new SimpleFileVisitor<Path>() {
			override FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) {
				if (ModuleManager.isModule(dir)) {
					modules.add(dir)

					return SKIP_SUBTREE
				}

				return CONTINUE
			}

			override visitFile(Path file, BasicFileAttributes attr) {
				if (!attr.isRegularFile()) {
					return CONTINUE
				}

				scripts.add(file)

				return CONTINUE
			}

			override FileVisitResult postVisitDirectory(Path dir, IOException exc) {
				return CONTINUE
			}
		})

		// initialize modules first, later single-file scripts

		modules.forEach [modulePath |
			moduleManager.receiveModulePath(modulePath)
		]

		scripts.forEach [scriptPath |
			tryReadScriptFile(scriptPath)
		]
	}

	def private void tryReadScriptFile(Path path) {
		if (!scriptExtensionMatcher.matches(path)) {
			return
		}

		val scriptName = pathToScriptName(path)
		val console = defaultContextConsole

		try {
			var code = new String(Files.readAllBytes(path), StandardCharsets.UTF_8)

			// TODO try to pre-compile script for error-check

			var script = scripts.get(scriptName)

			if (script == null) {
				console.log("Loading script: " + scriptName)
				script = new ScriptCommand(scriptName, code, createScriptStorage(scriptName))
				scripts.put(scriptName, script)
				commandManager.put(scriptName, script)
			}
			else {
				console.log("Reloading script: " + scriptName)
				script.code = code
			}
		}
		catch (IOException exc) {
			console.error(exc.toString())
		}
	}

	def private void removeScriptByPath(Path path) {
		val scriptName = pathToScriptName(path)
		scripts.remove(scriptName)
		commandManager.remove(scriptName)
	}

	def private String pathToScriptName(Path path) {
		var filename = path.getFileName().toString()

		if (filename.toLowerCase().endsWith(SCRIPT_FILE_EXTENSION)) {
			filename = filename.substring(0, filename.length() - SCRIPT_FILE_EXTENSION.length() - 1)
		}

		return filename
	}

	val scriptsFolderWatcher = new RecursiveWatcher.WatchListener {
		override onWatchEvents(Queue<FileChangeEvent> events) {
			for (FileChangeEvent evt : events) {
				val fullPath = evt.parentFolderPath.resolve(evt.relativePath)
				val isModule = moduleManager.doesFileBelongToModule(fullPath)

				if (evt.eventType == ENTRY_CREATE || evt.eventType == ENTRY_MODIFY) {
					if (isModule) {
						moduleManager.receiveModulePath(fullPath.parent)
					}
					else {
						tryReadScriptFile(fullPath)
					}
				}
				else if (evt.eventType == ENTRY_DELETE) {
					if (isModule) {
						moduleManager.receiveModuleDeleted(fullPath.parent)
					}
					else {
						removeScriptByPath(fullPath)
					}
				}
			}
		}
	}
}