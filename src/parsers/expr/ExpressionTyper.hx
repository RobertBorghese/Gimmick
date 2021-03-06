package parsers.expr;

import ast.scope.Scope;
import ast.scope.ScopeMember;
import ast.scope.ScopeParameterSearchResult;

import ast.typing.Type;

import parsers.error.Error;
import parsers.error.ErrorType;
import parsers.expr.Expression;
import parsers.expr.Literal;
import parsers.expr.Operator;
import parsers.expr.PrefixOperator;
import parsers.expr.SuffixOperator;
import parsers.expr.InfixOperator;
import parsers.expr.CallOperator;

using parsers.expr.Expression.ExpressionHelper;
using parsers.expr.TypedExpression;

// ================================================
// * ExpressionTyperValueContext
// ================================================

class ExpressionTyperValueContext {
	public var result(default, null): Null<Type> = null;
	public var literal(default, null): Literal;
	public var pos(default, null): Position;
	public var incrementCall(default, null): Bool;
	public var replacement(default, null): Null<Literal> = null;
	public var varName(default, null): Null<String> = null;

	public function new(literal: Literal, pos: Position, context: Null<ExpressionTypingContext>) {
		this.literal = literal;
		this.pos = pos;
		incrementCall = context != null && context.incrementCall;
	}

	public function setResult(result: Null<Type>) {
		this.result = result;
	}

	public function setReplacement(replacement: Null<Literal>) {
		this.replacement = replacement;
	}

	public function setVarName(varName: String) {
		this.varName = varName;
	}

	public function replacementOr(other: Literal): Literal {
		return replacement != null ? replacement : other;
	}

	public function getVarName(): String {
		return varName != null ? varName : "";
	}
}

// ================================================
// * ExpressionTypingContext
// ================================================

class ExpressionTypingContext {
	public var incrementCall(default, null): Bool;
	public var isStaticExtension(default, null): Bool;
	public var prependedArgs(default, null): Null<Array<TypedExpression>>;
	public var arguments(default, null): Null<Array<TypedExpression>>;
	public var handlingTemplateInput(default, null): Null<Array<Type>>;

	public function new(incrementCall: Bool) {
		this.incrementCall = incrementCall;
		isStaticExtension = false;
		prependedArgs = null;
		arguments = null;
		handlingTemplateInput = null;
	}

	public function setIsStaticExtension() {
		isStaticExtension = true;
	}

	public function setPrependedArguments(prependedArgs: Array<TypedExpression>) {
		this.prependedArgs = prependedArgs;
	}

	public function setCallParameters(params: Array<TypedExpression>) {
		arguments = params;
	}

	public function setHandlingTemplateInput(typeArgs: Null<Array<Type>>) {
		handlingTemplateInput = typeArgs;
	}
}

// ================================================
// * ExpressionTyper
// ================================================

class ExpressionTyper {
	var parser: Parser;
	var mode: TypingMode;
	var isInterpret: Bool;
	var thisType: Null<Type>;
	var convertAssignmentToArgument: Bool;
	var exprStack: Array<Expression>;

	public function new(parser: Parser, mode: TypingMode = Normal, isInterpret: Bool = false, thisType: Null<Type> = null) {
		this.parser = parser;
		this.mode = mode;
		this.isInterpret = isInterpret;
		this.thisType = thisType;
		convertAssignmentToArgument = false;
		exprStack = [];
	}

	public function isAssignment(): Bool {
		if(exprStack.length >= 2) {
			final test = exprStack[exprStack.length - 2];
			switch(test) {
				case Infix(op, _, _, _): {
					if(op.op == "=") return true;
					else if(op.op != ".") return false;
				}
				default: return false;
			}
		}
		if(exprStack.length >= 3) {
			final test = exprStack[exprStack.length - 3];
			switch(test) {
				case Infix(op, _, _, _): {
					if(op.op == "=") return true;
					else return false;
				}
				default: return false;
			}
		}
		return false;
	}

	public function getInternalTypeStacked(expression: Expression, accessor: Null<TypedExpression> = null, context: Null<ExpressionTypingContext> = null): Null<TypedExpression> {
		exprStack.push(expression);
		final result = getInternalType(expression, accessor, context);
		exprStack.pop();
		return result;
	}

	public function getInternalType(expression: Expression, accessor: Null<TypedExpression> = null, context: Null<ExpressionTypingContext> = null): Null<TypedExpression> {
		final isPrelim = mode != Normal;
		final isUntyped = mode == Typeless;
		switch(expression) {
			case Prefix(op, expr, pos): {
				final typedExpr = getInternalTypeStacked(expr);
				if(typedExpr != null) {
					final result = op.findReturnType(typedExpr.getType());
					if(result != null) {
						parser.onTypeUsed(result);
						return Prefix(op, typedExpr, pos, result);
					} else if(!isPrelim) {
						Error.addErrorFromPos(ErrorType.InvalidPrefixOperator, pos, [typedExpr.getType().toString()]);
					}
				}
				return null;
			}
			case Suffix(op, expr, pos): {
				final typedExpr = getInternalTypeStacked(expr);
				if(typedExpr != null) {
					final type = typedExpr.getType();
					final result = op.findReturnType(type);
					if(result != null) {
						parser.onTypeUsed(result);
						return Suffix(op, typedExpr, pos, result);
					} else if(!isPrelim) {
						Error.addErrorFromPos(ErrorType.InvalidSuffixOperator, pos, [type.toString()]);
					}
				}
				return null;
			}
			case Infix(op, lexpr, rexpr, pos): {
				final accessContext = new ExpressionTypingContext(false);
				if(op.isAccessor() && context != null && context.arguments != null) {
					accessContext.setCallParameters(context.arguments);
				}

				final lContext = if(op.isGenericInput() && context != null) {
					final rexprTyped = getInternalTypeStacked(rexpr, null, accessContext);
					final rtype = rexprTyped != null ? rexprTyped.getType() : null;
					context.setHandlingTemplateInput(rtype != null ? rtype.toTypeArgs() : null);
					context;
				} else {
					final otherContext = new ExpressionTypingContext(false);
					otherContext.setHandlingTemplateInput(null);
					otherContext;
				}
				var lexprTyped = getInternalTypeStacked(lexpr, op.isGenericInput() ? accessor : null, lContext);
				if(op.isGenericInput() && context != null) {
					context.setHandlingTemplateInput(null);
				}
				if(lexprTyped != null) {

					if(op.op == ".") {
						final typeSelf = lexprTyped.getType().isTypeSelf();
						if(typeSelf != null) {
							if(rexpr.isAlloc()) {
								//final allocTypeSelf = Type.TypeSelf(typeSelf, true);
								final newExpr = parsers.expr.Expression.Value(Literal.TypeName(typeSelf), expression.getFullPosition());
								var isCall = true;
								if(context == null) {
									context = new ExpressionTypingContext(true);
									context.setCallParameters([]);
									isCall = false;
								}
								final newExprTyped = getInternalTypeStacked(newExpr, null, context);
								return newExprTyped.convertToAlloc(isCall);
							}
						}
					}

					final rexprTyped = getInternalTypeStacked(rexpr, op.isAccessor() ? lexprTyped : null, accessContext);
					if(rexprTyped != null) {
						if(op.op == "=") {
							if(convertAssignmentToArgument) {
								convertAssignmentToArgument = false;
								switch(lexprTyped) {
									case Call(op, expr, params, pos, t): {
										params.push(rexprTyped);
										return Call(op, expr, params, pos, t);
									}
									default: {}
								}
							} else if(lexprTyped.getType().isUnknown()) {
								final newExpr = lexprTyped.discoverVariableType(rexprTyped.getType());
								if(newExpr != null) {
									lexprTyped = newExpr;
								}
							}
						}
						final rType = rexprTyped.getType();
						final lType = op.isAccessor() ? null : lexprTyped.getType();
						if(lType != null) {
							final templateResult = handleTemplateInput(op, lType, rType, pos);
							if(templateResult != null) {
								return templateResult;
							}
						}
						final result = lType == null ? rType : op.findReturnType(lType, rType, pos, parser.scope);
						if(result != null) {
							parser.onTypeUsed(result);
							if(!isInterpret && accessContext != null && accessContext.isStaticExtension) {
								if(context != null) context.setPrependedArguments([lexprTyped]);
								return rexprTyped;
							}
							return Infix(op, lexprTyped, rexprTyped, pos, result);
						} else if(!isPrelim) {
							final lTypeErr = lType == null ? lexprTyped.getType().toString() : lType.toString();
							Error.addErrorFromPos(ErrorType.InvalidInfixOperator, pos, [lTypeErr, rType.toString()]);
						}
					}
				}
				
				return null;
			}
			case Call(op, expr, params, pos): {
				final typedParamExprs: Array<TypedExpression> = [];
				for(p in params) {
					final r = getInternalTypeStacked(p);
					if(r != null) {
						typedParamExprs.push(r);
					}
				}

				final isCall = op == CallOperators.Call;
				final context = new ExpressionTypingContext(isCall);
				if(isCall) context.setCallParameters(typedParamExprs);
				final typedExpr = getInternalTypeStacked(expr, null, context);
				final exprPos = [ExpressionHelper.getFullPosition(expr), pos];
				final otherPos = params.map(p -> ExpressionHelper.getFullPosition(p));
				if(!isPrelim) {
					Error.completePromiseMulti("funcWrongParam", exprPos.concat(otherPos));
				} else {
					Error.clearErrorPromise("funcWrongParam");
				}
				if(typedExpr != null) {
					final typedParams: Array<TypedExpression> = [];
					if(context.prependedArgs != null) {
						for(p in context.prependedArgs) {
							typedParams.push(p);
						}
					}
					for(expr in typedParamExprs) {
						typedParams.push(expr);
					}

					final type = typedExpr.getType();
					final result = op.findReturnType(type, typedParams.map(p -> p.getType()));
					if(result != null) {
						parser.onTypeUsed(result);
						return Call(op, typedExpr, typedParams, pos, result);
					} else if(!isPrelim) {
						Error.addErrorFromPos(ErrorType.InvalidCallOperator, pos, [type.toString()]);
					}
				}
				return null;
			}
			case Value(literal, pos): {
				var result = isUntyped ? Type.Any() : Type.fromLiteral(literal, parser.scope, thisType);
				if(result != null) {
					final valueContext = new ExpressionTyperValueContext(literal, pos, context);
					valueContext.setResult(result);
					switch(result.type) {
						case UnknownNamed(name, typeParams): {
							if(typeParams == null && context != null) {
								typeParams = context.handlingTemplateInput;
							}
							valueContext.setVarName(name);
							parser.scope.push();
							final typedExpr = if(accessor == null) {
								typeUnknownWithoutAccessor(name, typeParams, context, valueContext);
							} else {
								typeUnknownWithAccessor(name, typeParams, accessor, context, valueContext);
							}
							parser.scope.pop();
							if(typedExpr != null) {
								return typedExpr;
							}
						}
						case TypeSelf(type, isAlloc): {
							if(!isPrelim && context != null && context.arguments != null) {
								switch(type.type) {
									case Class(cls, _): {
										if(!isPrelim && !cls.get().hasConstructors()) {
											Error.addErrorFromPos(ErrorType.ClassHasNoConstructors, pos, [type.toString()]);
										}
										final options = cls.get().findConstructorWithParameters(context.arguments.map(p -> p.getType()));
										final member = retrieveMemberFromOptions(options, pos);
										if(member != null) {
											member.onMemberUsed(parser);
											valueContext.setResult(Type.TypeSelf(type));//member.getType());
											switch(member.type) {
												case ScopeMemberType.Function(funcMember): {
													valueContext.setReplacement(Literal.TypeName(type));
													if(valueContext.incrementCall) {
														funcMember.get().incrementCallCount();
													}
												}
												default: {}
											}
										}
									}
									default: {}
								}
							}
						}
						default: {}
					}

					result = valueContext.result;
					if(result != null) {
						if(!isPrelim && result.templateRequired() && (context == null || context.handlingTemplateInput == null)) {
							Error.addErrorFromPos(if(result.isClassType() != null) {
								ErrorType.ClassRequiresTypeArguments;
							} else {
								ErrorType.FunctionRequiresTypeArguments;
							}, pos);
						}
						parser.onTypeUsed(result);
						return Value(valueContext.replacementOr(literal), pos, result);
					} else if(!isPrelim) {
						if(accessor == null) {
							Error.addErrorFromPos(ErrorType.UnknownVariable, pos, [valueContext.getVarName()]);
						} else {
							Error.addErrorFromPos(ErrorType.UnknownMember, pos, [valueContext.getVarName(), accessor.getType().toString()]);
						}
					}
				} else if(!isPrelim) {
					switch(literal) {
						case Literal.This: {
							Error.addErrorFromPos(ErrorType.InvalidThisOrSelf, pos);
						}
						default: {
							Error.addErrorFromPos(ErrorType.InvalidValue, pos);
						}
					}
				}
			}
		}
		return null;
	}

	public function typeUnknownWithoutAccessor(name: String, typeArgs: Null<Array<Type>>, context: Null<ExpressionTypingContext>, valueContext: ExpressionTyperValueContext): Null<TypedExpression> {
		final member = if(context != null && context.arguments != null) {
			final options = parser.scope.findMemberWithParameters(name, typeArgs, context.arguments);
			retrieveMemberFromOptions(options, valueContext.pos);
		} else {
			parser.scope.findMember(name);
		}
		if(member != null) {
			member.onMemberUsed(parser);
			valueContext.setResult(member.getType());
			switch(member.type) {
				case ScopeMemberType.Variable(varMember): {
					valueContext.setReplacement(Variable(varMember.get()));
				}
				case ScopeMemberType.Function(funcMember): {
					if(valueContext.result == null || valueContext.result.isTypeSelf() == null) {
						valueContext.setReplacement(Function(funcMember.get()));
					}
					if(valueContext.incrementCall) {
						funcMember.get().incrementCallCount();
					}
				}
				case ScopeMemberType.GetSet(getsetMember): {
					valueContext.setReplacement(GetSet(getsetMember.get()));
				}
				case ScopeMemberType.Class(clsMember): {
					valueContext.setReplacement(TypeName(Type.Class(clsMember.get().type, null)));
				}
				default: {}
			}
		} else {
			valueContext.setResult(null);
		}
		return null;
	}

	public function typeUnknownWithAccessor(name: String, typeArgs: Null<Array<Type>>, accessor: TypedExpression, context: Null<ExpressionTypingContext>, valueContext: ExpressionTyperValueContext): Null<TypedExpression> {
		final inputType = accessor.getType().resolveTemplateType(parser.scope);
		inputType.revealTemplateArgsToScope(parser.scope);
		final member = if(context != null && context.arguments != null) {
			final options = parser.scope.findModifyFunctionWithParameters(inputType, name, context.arguments);
			retrieveMemberFromOptions(options, valueContext.pos);
		} else {
			parser.scope.findModifyFunction(inputType, name);
		}
		if(member != null) {
			member.onMemberUsed(parser);
			valueContext.setResult(member.getType());
			var isGetSet = 0;
			switch(member.type) {
				case ScopeMemberType.Function(funcMember): {
					valueContext.setReplacement(Function(funcMember.get()));
					if(valueContext.incrementCall) {
						funcMember.get().incrementCallCount();
					}
				}
				case ScopeMemberType.GetSet(getsetMember): {
					isGetSet = 1;
					if(!isInterpret) {
						if(isAssignment()) {
							final setFunc = getsetMember.get().set;
							if(setFunc != null) {
								valueContext.setReplacement(Function(setFunc));
								isGetSet = 2;
							}
						} else {
							final getFunc = getsetMember.get().get;
							if(getFunc != null) {
								valueContext.setReplacement(Function(getFunc));
								isGetSet = 3;
							}
						}
					} else {
						valueContext.setReplacement(GetSet(getsetMember.get()));
					}
				}
				default: {}
			}

			if(!isInterpret && valueContext.replacement != null && context != null) {
				context.setIsStaticExtension();

				if(isGetSet != 0 && valueContext.result != null) {
					if(isGetSet == 2) convertAssignmentToArgument = true;
					parser.onTypeUsed(valueContext.result);
					final internalResult: TypedExpression = Value(valueContext.replacementOr(valueContext.literal), valueContext.pos, valueContext.result);
					return Call(CallOperators.Call, internalResult, [accessor], valueContext.pos, valueContext.result);
				}
			}
		} else {
			final accessed = if(context != null && context.arguments != null) {
				final options = inputType.findAllAccessorMembersWithParameters(name, typeArgs, context.arguments);
				final mem = retrieveMemberFromOptions(options, valueContext.pos);
				if(mem != null) {
					mem.getType();
				} else {
					null;
				}
			} else {
				inputType.findAccessorMemberType(name);
			}
			valueContext.setResult(accessed);
		}
		return null;
	}

	public function retrieveMemberFromOptions(result: ScopeParameterSearchResult, pos: Position): Null<ScopeMember> {
		final options = result.foundMembers;
		return if(options != null) {
			switch(options.length) {
				case 0: null;
				case 1: options[0];
				default: {
					var extractName = function(opt: ScopeMember) {
						final mem = opt.extractFunctionMember();
						if(mem != null) {
							return mem.toString();
						}
						return "";
					};
					if(options.length == 2) {
						Error.addErrorFromPos(ErrorType.AmbiguousFunctionCall, pos, options.map(extractName));
					} else if(options.length == 3) {
						Error.addErrorFromPos(ErrorType.AmbiguousFunctionCall3, pos, options.map(extractName));
					} else {
						Error.addErrorFromPos(ErrorType.AmbiguousFunctionCallMulti, pos, options.slice(0, 2).map(extractName).concat([Std.string(options.length - 2)]));
					}
					options[0];
				}
			}
		} else {
			null;
		}
	}

	public function handleTemplateInput(op: InfixOperator, ltype: Type, rtype: Type, position: Position): Null<TypedExpression> {
		if(op.op == "!") {
			var resultType: Null<Type> = null;
			var leftType: Null<Type> = null;
			var rightType: Null<Type> = null;
			switch([ltype.type, switch(rtype.type) {
				case Tuple(types): TypeSelf(rtype, false);
				default: rtype.type;
			}]) {
				case [TypeSelf(lt, _), TypeSelf(rt, _)]: {
					leftType = lt;
					rightType = rt;
				}
				case [Function(_, _), TypeSelf(rt, _)] | [External(_, _), TypeSelf(rt, _)]: {
					leftType = ltype;
					rightType = rt;
				}
				default: {}
			}
			if(leftType != null && rightType != null) {
				final typeList = switch(rightType.type) {
					case Tuple(types): types;
					default: [rightType];
				}
				final newType = leftType.applyTemplateArgs(typeList);
				resultType = if(newType != null) {
					switch(newType.type) {
						case Class(_, _): Type.TypeSelf(newType);
						default: newType;
					}
				} else {
					final positions: Array<Position> = [position];
					for(t in typeList) {
						positions.push(t.position == null ? Position.BLANK : t.position);
					}
					final isPrelim = mode != Normal;
					if(!isPrelim) {
						Error.completePromiseMulti("matchTemplateArgs", positions);
					} else {
						Error.clearErrorPromise("matchTemplateArgs");
					}
					ltype;
				}
			}
			if(resultType != null) {
				return Value(switch(resultType.type) {
					case TypeSelf(t, _): Literal.TypeName(t);
					case Function(funcType, args): {
						var mem = funcType.get().member;
						if(mem != null) {
							if(args != null) {
								mem = mem.applyTypeArguments(args);
							}
							Literal.Function(mem);
						} else {
							null;
						}
					}
					default: null;
				}, 

				#if js
				// Using this because Rest args appear broken on JS target.
				// Should remove after future Haxe update fixes.
				position.mergeArray([ltype.position, rtype.position])
				#else
				position.merge(ltype.position, rtype.position)
				#end

				, resultType.applyTypeArguments());
			}
		}
		return null;
	}
}
