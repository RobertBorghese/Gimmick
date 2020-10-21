package ast.scope.members;

import basic.Ref;

import ast.scope.members.MemberLocation;

import parsers.expr.Position;
using parsers.expr.TypedExpression;
import parsers.expr.InfixOperator.InfixOperators;

import ast.typing.Type;
import ast.scope.ExpressionMember;

class VariableMember {
	public var name(default, null): String;
	public var type(default, null): Type;
	public var isStatic(default, null): Bool;
	public var position(default, null): Position;
	public var expression(default, null): Null<TypedExpression>;
	public var memberLocation(default, null): MemberLocation;

	var ref: Null<Ref<VariableMember>>;

	public function new(name: String, type: Type, isStatic: Bool, position: Position, expression: Null<TypedExpression>, memberLocation: MemberLocation) {
		this.name = name;
		this.type = type;
		this.isStatic = isStatic;
		this.position = position;
		this.expression = expression;
		this.memberLocation = memberLocation;
	}

	public function getRef(): Ref<VariableMember> {
		if(ref == null) {
			ref = new Ref<VariableMember>(this);
		}
		return ref;
	}

	public function getNamespaces(): Null<Array<String>> {
		return switch(memberLocation) {
			case TopLevel(namespaces): namespaces;
			default: null;
		}
	}

	public function shouldSplitAssignment(): Bool {
		return expression != null && !expression.isConst();
	}

	public function cloneWithoutExpression(): VariableMember {
		final newType = type.clone();
		newType.setConst(false);
		return new VariableMember(name, newType, isStatic, position.clone(), null, memberLocation);
	}

	public function constructAssignementExpression(): Null<ExpressionMember> {
		if(expression == null) {
			return null;
		}
		var namespaces = null;
		switch(memberLocation) {
			case TopLevel(n): namespaces = n;
			default: {}
		}
		final lexpr = TypedExpression.Value(Literal.Name(name, namespaces), position, Type.Unknown());
		final assign = TypedExpression.Infix(InfixOperators.Assignment, lexpr, expression, position, type);
		return ExpressionMember.Basic(assign);
	}
}
