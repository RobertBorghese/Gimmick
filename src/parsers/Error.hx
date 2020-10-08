package parsers;

using StringTools;

import basic.Ref;

import parsers.Parser;
import parsers.ErrorType;

import parsers.expr.Position;

class Error {
	public var errorType(default, null): ErrorType;
	public var lineStr(default, null): String;
	public var file(default, null): String;
	public var line(default, null): Int;
	public var start(default, null): Int;
	public var end(default, null): Int;

	var params: Null<Array<String>>;

	static var errors: Array<Error> = [];

	public function new(errorType: ErrorType, lineStr: String, file: String, line: Int, start: Int, end: Int, params: Null<Array<String>>) {
		this.errorType = errorType;
		this.lineStr = lineStr;
		this.file = file;
		this.line = line;
		this.start = start;
		this.end = end;
		this.params = params;
	}

	function errorDescLine(): String {
		return "\"" + file + "\" - Line #" + line + " (" + start + ", " + end + "):";
	}

	public function toString(): String {
		final msg = formatString(errorType.getErrorMessage(), params);
		var result = "";
		result += msg + "\n";
		result += repeatChar("-", msg.length) + "\n";
		result += errorDescLine() + "\n";
		result += lineStr;
		return result;
	}

	public static function addError(errorType: ErrorType, parser: Parser, start: Int, endOffset: Int = 0, params: Null<Array<String>> = null) {
		final lineNumber = parser.getLineNumber();
		final lineStr = findLine(parser.content, lineNumber);
		final end = parser.getIndexFromLine() + endOffset;
		final errorLineString = formatLineString(lineStr, lineNumber, start, end, errorType, params);
		final error = new Error(errorType, errorLineString, parser.getRelativePath(), lineNumber, start, end, params);
		errors.push(error);
	}

	public static function addErrorWithStartEnd(errorType: ErrorType, parser: Parser, start: Int, end: Int, params: Null<Array<String>> = null) {
		final lineNumber = parser.getLineNumber();
		final lineStr = findLine(parser.content, lineNumber);
		final errorLineString = formatLineString(lineStr, lineNumber, start, end, errorType, params);
		final error = new Error(errorType, errorLineString, parser.getRelativePath(), lineNumber, start, end, params);
		errors.push(error);
	}

	public static function addErrorFromPos(errorType: ErrorType, position: Position, params: Null<Array<String>> = null) {
		final lineNumber = position.line;
		final lineStart = new Ref(0);
		final lineStr = findLine(position.file.source, lineNumber, lineStart);
		final start = position.startIndex - lineStart.get() - 1;
		final end = position.endIndex - lineStart.get() - 1;
		final errorLineString = formatLineString(lineStr, lineNumber, start, end, errorType, params);
		final error = new Error(errorType, errorLineString, position.file.pathInfo.relativePath, lineNumber, start, end, params);
		errors.push(error);
	}

	static function findLine(content: String, lineNumber: Int, lineStartIndex: Null<Ref<Int>> = null): String {
		var result = "";
		var saveLine = false;
		var currLine = 1;
		var currIndex = 0;
		var lineStart = 0;
		while(currIndex < content.length) {
			if(content.fastCodeAt(currIndex) == 10) {
				currLine++;
				if(saveLine) {
					if(lineStartIndex != null) lineStartIndex.set(lineStart);
					return result;
				} else if(currLine == lineNumber) {
					saveLine = true;
				}
				lineStart = currIndex;
			} else if(saveLine) {
				result += content.charAt(currIndex);
			}
			currIndex++;
		}
		if(lineStartIndex != null) lineStartIndex.set(lineStart);
		return result;
	}

	static function formatLineString(line: String, lineNumber: Int, start: Int, end: Int, err: ErrorType, params: Null<Array<String>>): String {
		final lineNumberOffset = Std.string(lineNumber).length + 1;

		final tabSize = 4;
		final formattedLine = reformatTabs(line, tabSize, end);
		final difference = formattedLine.length - line.length;
		start += difference;
		end += difference;

		var result = "";
		result += repeatChar(" ", lineNumberOffset) + "|\n";

		result += "" + lineNumber + " | ";
		result += formattedLine.rtrim() + "\n";

		result += repeatChar(" ", lineNumberOffset) + "| ";
		result += repeatChar(" ", start) + repeatChar("^", Std.int(Math.max(1, end - start)));
		result += " " + formatString(err.getErrorLabel(), params) + "\n";

		return result;
	}

	static function reformatTabs(input: String, tabSize: Int, end: Int): String {
		final tabReplacement = repeatChar(" ", tabSize);
		var result = "";
		for(i in 0...input.length) {
			final char = input.charAt(i);
			if(i < end && char == "\t") {
				result += tabReplacement;
			} else {
				result += char;
			}
		}
		return result;
	}

	static function repeatChar(str: String, amount: Int): String {
		if(amount == 0) return "";
		var result = str;
		for(i in 1...amount) result += str;
		return result;
	}

	public static function printAllErrors() {
		haxe.Log.trace(errors.map(e -> e.toString()).join("\n"), null);
	}

	public static function hasErrors(): Bool {
		return errors.length != 0;
	}

	public static function errorCount(): Int {
		return errors.length;
	}

	static function formatString(str: String, params: Null<Array<String>>): String {
		if(params != null) {
			var index = 1;
			var result = str;
			for(p in params) {
				result = result.replace("%" + Std.string(index++), p);
			}
			return result;
		}
		return str;
	}
}