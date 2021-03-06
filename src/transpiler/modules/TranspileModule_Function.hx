package transpiler.modules;

import basic.Ref;

import ast.scope.ScopeMember;
import ast.scope.members.FunctionMember;
import ast.scope.members.FunctionOption.FunctionOptionHelper;
import ast.typing.Type;

import parsers.error.Error;
import parsers.error.ErrorType;
import parsers.expr.Position;

import transpiler.modules.TranspileModule_Expression;
import transpiler.modules.TranspileModule_Type;
import transpiler.modules.TranspileModule_OperatorOverload;

class TranspileModule_Function {
	public static function transpile(func: FunctionMember, transpiler: Transpiler) {
		if(!func.shouldTranspile()) {
			return;
		}
		if(transpiler.context.isCpp()) {
			transpiler.addHeaderContent(transpileFunctionHeader(func, transpiler.context));
		}
		transpiler.addSourceContent(transpileFunctionSourceTopLevel(func, transpiler.context, 0));
	}

	public static function transpileFunctionSourceTopLevel(func: FunctionMember, context: TranspilerContext, tabLevel: Int, namespaces: Null<Array<String>> = null): String {
		final data = func;
		final type = data.type.get();
		final funcStart = getStart(data, context);
		final namespacePrefix = if(context.isCpp() && namespaces != null) {
			context.reverseJoinArray(namespaces, "::") + "::";
		} else {
			"";
		}
		
		if(context.isJs() && func.isDestructor()) {
			Error.addErrorFromPos(ErrorType.JsCannotUseDestructor, func.declarePosition);
		}

		var name = getName(data, context);
		if(!context.allowSameNameFunctions() && func.shouldHaveUniqueName()) {
			name += func.uniqueFunctionSuffix();
		}
		final functionDeclaration = funcStart + namespacePrefix + name + transpileFunctionArguments(func, context);
		var result = functionDeclaration + " {\n";
		var tabs = "";
		for(i in 0...tabLevel) tabs += "\t";
		var prevCond = true;
		var popThisType = false;
		if(func.type.get().thisType == StaticExtension) {
			final args = func.type.get().allArguments();
			if(args.length > 0) {
				context.pushThisExpr(Value(Literal.Name(args[0].name, null), Position.BLANK, args[0].type));
				popThisType = true;
			}
		}
		for(e in data.members) {
			if(!e.shouldTranspile(context, prevCond)) { prevCond = false; continue; }
			prevCond = true;
			result += tabs + "\t" + transpileFunctionMember(e, context, tabLevel + 1) + "\n";
		}
		if(popThisType) {
			context.popThisExpr();
		}
		result += tabs + "}";
		return result;
	}

	public static function transpileFunctionHeader(func: FunctionMember, context: TranspilerContext): String {
		final data = func;
		final funcStart = getStart(data, context);
		var functionDeclaration = funcStart + getName(data, context) + transpileFunctionArguments(func, context);
		functionDeclaration = FunctionOptionHelper.decorateFunctionHeader(functionDeclaration, func.options, context.isJs());
		return functionDeclaration + ";";
	}

	public static function hasStart(func: FunctionMember, context: TranspilerContext) {
		if(context.isCpp()) {
			return !func.isConstructor() && !func.isDestructor();
		}
		return true;
	}

	public static function getStart(func: FunctionMember, context: TranspilerContext) {
		if(!hasStart(func, context)) {
			return "";
		}
		return if(context.isCpp()) {
			var returnType = func.type.get().returnType;
			if(returnType.isUnknown()) {
				returnType = Type.Void();
			}
			TranspileModule_Type.transpile(returnType) + " ";
		} else if(context.currentClassName() == null) {
			"function ";
		} else {
			"";
		}
	}

	public static function getName(func: FunctionMember, context: TranspilerContext) {
		var name = func.name;
		final opName = TranspileModule_OperatorOverload.getOperatorFunctionName(func, context);
		if(opName != null) {
			name = opName;
		} else if(context.isCpp()) {
			var clsName = context.currentClassName();
			if(clsName == null) clsName = "";
			if(func.isConstructor()) {
				name = clsName;
			} else if(func.isDestructor()) {
				name = "~" + clsName;
			}
		} else if(context.isJs()) {
			if(func.isConstructor()) {
				name = "constructor";
			} else if(func.isDestructor()) {
				name = "destructor";
			}
		}
		return name;
	}

	public static function transpileFunctionArguments(func: FunctionMember, context: TranspilerContext): String {
		final args = func.type.get().allArguments();
		if(context.isCpp()) {
			return "(" + args.map(a -> TranspileModule_Type.transpile(a.type) + " " + a.name).join(", ") + ")";
		} else {
			return "(" + args.map(a -> a.name).join(", ") + ")";
		}
	}

	public static function transpileFunctionMember(member: ScopeMember, context: TranspilerContext, tabLevel: Int): String {
		switch(member.type) {
			case Variable(variable): {
				return TranspileModule_Variable.transpileVariableSource(variable, context);
			}
			case Function(func): {
				// TODO: function inside function
				//TranspileModule_Function.transpile(func, this);
			}
			case Expression(expr): {
				return TranspileModule_Expression.transpileExprMember(expr, context, tabLevel);
			}
			default: {}
		}
		return "";
	}
}
