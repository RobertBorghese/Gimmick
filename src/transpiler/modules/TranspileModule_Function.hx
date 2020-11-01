package transpiler.modules;

import basic.Ref;

import ast.scope.ScopeMember;
import ast.scope.members.FunctionMember;
import ast.scope.members.FunctionOption.FunctionOptionHelper;

import parsers.expr.Position;

import transpiler.modules.TranspileModule_Expression;
import transpiler.modules.TranspileModule_Type;

class TranspileModule_Function {
	public static function transpile(func: FunctionMember, transpiler: Transpiler) {
		if(func.isInject()) {
			return;
		}
		if(transpiler.context.isCpp()) {
			transpiler.addHeaderContent(transpileFunctionHeader(func, transpiler.context));
		}
		transpiler.addSourceContent(transpileFunctionSourceTopLevel(func, transpiler.context, 0));
	}

	public static function transpileFunctionSourceTopLevel(func: FunctionMember, context: TranspilerContext, tabLevel: Int): String {
		final data = func;
		final type = data.type.get();
		final funcStart = if(context.isCpp()) {
			TranspileModule_Type.transpile(type.returnType);
		} else {
			"function";
		};
		final functionDeclaration = funcStart + " " + data.name + transpileFunctionArguments(func, context);
		var result = functionDeclaration + " {\n";
		var tabs = "";
		for(i in 0...tabLevel) tabs += "\t";
		var prevCond = true;
		var popThisType = false;
		if(func.type.get().thisType == StaticExtension) {
			final args = func.type.get().arguments;
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
		final type = data.type.get();
		final funcStart = if(context.isCpp()) {
			TranspileModule_Type.transpile(type.returnType);
		} else {
			"function";
		};
		var functionDeclaration = funcStart + " " + data.name + transpileFunctionArguments(func, context);
		functionDeclaration = FunctionOptionHelper.decorateFunctionHeader(functionDeclaration, func.options, context.isJs());
		return functionDeclaration + ";";
	}

	public static function transpileFunctionArguments(func: FunctionMember, context: TranspilerContext): String {
		final args = func.type.get().arguments;
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
