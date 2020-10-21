package ast.scope;

import ast.scope.ScopeMember;
import ast.typing.Type;

import parsers.expr.TypedExpression;

enum ExpressionMember {
	Basic(expr: TypedExpression);
	Pass;
	Break;
	Continue;
	Scope(subExpressions: Array<ScopeMember>);
	IfStatement(expr: TypedExpression, subExpressions: Array<ScopeMember>, checkTrue: Bool);
	IfElseStatement(ifStatement: ExpressionMember, elseExpressions: Array<ScopeMember>);
	IfElseIfChain(ifStatements: Array<ExpressionMember>, elseExpressions: Null<Array<ScopeMember>>);
	Loop(expr: Null<TypedExpression>, subExpressions: Array<ScopeMember>, checkTrue: Bool);
	ReturnStatement(expr: TypedExpression);
}

class ExpressionMemberHelper {
	public static function isReturn(expr: ExpressionMember): Bool {
		switch(expr) {
			case ReturnStatement(_): return true;
			case Scope(exprs): return hasReturn(exprs);
			case IfElseStatement(ifState, elseExpressions): {
				var ifHasReturn = false;
				switch(ifState) {
					case IfStatement(_, exprs, _): {
						if(!hasReturn(exprs)) {
							return false;
						}
					}
					default: {}
				}
				return hasReturn(elseExpressions);
			}
			case IfElseIfChain(ifStatements, elseExpressions): {
				for(ifState in ifStatements) {
					switch(ifState) {
						case IfStatement(_, exprs, _): {
							if(!hasReturn(exprs)) {
								return false;
							}
						}
						default: {}
					}
				}
				return elseExpressions == null ? true : hasReturn(elseExpressions);
			}
			default: {}
		}
		return false;
	}

	public static function hasReturn(exprList: Array<ScopeMember>): Bool {
		for(e in exprList) {
			switch(e.type) {
				case Expression(expr): {
					if(isReturn(expr)) {
						return true;
					}
				}
				default: {}
			}
		}
		return false;
	}

	public static function isPass(expr: ExpressionMember): Bool {
		switch(expr) {
			case Pass: return true;
			default: {}
		}
		return false;
	}
}
