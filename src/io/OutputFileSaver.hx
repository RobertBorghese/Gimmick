package io;

import haxe.io.Path;

import sys.FileSystem;
import sys.io.File;

import ast.SourceFile;

import transpiler.Language;
import transpiler.OutputFile;

class OutputFileSaver {
	var files: Array<SourceFile>;
	var outputPaths: Array<String>;

	public function new(outputPaths: Array<String>) {
		this.outputPaths = outputPaths;
		files = [];
	}

	public function addFiles(newFiles: Array<SourceFile>) {
		files = files.concat(newFiles);
	}

	public function transpile(language: Language) {
		for(file in files) {
			transpileFile(file, language);
		}
	}

	function transpileFile(file: SourceFile, language: Language) {
		final outputFile = new OutputFile(file, language);
		saveToPaths(outputFile.output());
	}

	function saveToPaths(content: Map<String,String>) {
		#if (sys || hxnodejs)
		for(path in outputPaths) {
			for(filePath in content.keys()) {
				final c = content[filePath];
				if(c != null) {
					if(c.length == 0 && !FileSystem.exists(filePath)) {
						continue;
					}
					final filePath = Path.join([path, filePath]);
					final dir = Path.directory(filePath);
					if(!FileSystem.exists(dir)) {
						FileSystem.createDirectory(dir);
					}
					File.saveContent(filePath, c);
				}
			}
		}
		#end
	}

	public static function getOutputFolders(argParser: CompilerArgumentParser): Array<String> {
		final outputPaths = argParser.getValuesOr("out", ["."]);
		return outputPaths;
	}
}
