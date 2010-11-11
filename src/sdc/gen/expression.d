/**
 * Copyright 2010 Bernard Helyer.
 * Copyright 2010 Jakob Ovrum.
 * This file is part of SDC. SDC is licensed under the GPL.
 * See LICENCE or sdc.d for more details.
 */
module sdc.gen.expression;

import std.conv;
import std.string;

import llvm.c.Core;

import sdc.global;
import sdc.util;
import sdc.location;
import sdc.compilererror;
import sdc.extract.base;
import ast = sdc.ast.all;
import sdc.gen.sdcmodule;
import sdc.gen.type;
import sdc.gen.value;


Value genExpression(ast.Expression expression, Module mod)
{
    auto v = genAssignExpression(expression.assignExpression, mod);
    if (expression.expression !is null) {
        return genExpression(expression.expression, mod);
    }
    return v;
}

Value genAssignExpression(ast.AssignExpression expression, Module mod)
{
    auto lhs = genConditionalExpression(expression.conditionalExpression, mod);
    if (expression.assignType == ast.AssignType.None) {
        return lhs;
    }
    auto rhs = genAssignExpression(expression.assignExpression, mod);
    rhs = implicitCast(rhs.location, rhs, lhs.type);
    switch (expression.assignType) with (ast.AssignType) {
    case None:
        assert(false);
    case Normal:
        lhs.set(expression.location, rhs);
        break;
    case AddAssign:
        lhs.set(expression.location, lhs.add(expression.location, rhs));
        break;
    case SubAssign:
        lhs.set(expression.location, lhs.sub(expression.location, rhs));
        break;
    case MulAssign:
        lhs.set(expression.location, lhs.mul(expression.location, rhs));
        break;
    case DivAssign:
        lhs.set(expression.location, lhs.div(expression.location, rhs));
        break;
    case ModAssign:
        throw new CompilerPanic(expression.location, "modulo assign is unimplemented.");
    case AndAssign:
        throw new CompilerPanic(expression.location, "and assign is unimplemented.");
    case OrAssign:
        throw new CompilerPanic(expression.location, "or assign is unimplemented.");
    case XorAssign:
        throw new CompilerPanic(expression.location, "xor assign is unimplemented.");
    case CatAssign:
        throw new CompilerPanic(expression.location, "cat assign is unimplemented.");
    case ShiftLeftAssign:
        throw new CompilerPanic(expression.location, "shift left assign is unimplemented.");
    case SignedShiftRightAssign:
        throw new CompilerPanic(expression.location, "signed shift assign is unimplemented.");
    case UnsignedShiftRightAssign:
        throw new CompilerPanic(expression.location, "unsigned shift assign is unimplemented.");
    case PowAssign:
        throw new CompilerPanic(expression.location, "pow assign is unimplemented.");
    default:
        throw new CompilerPanic(expression.location, "unimplemented assign expression type.");
    }
    return rhs;
}

Value genConditionalExpression(ast.ConditionalExpression expression, Module mod)
{
    auto a = genOrOrExpression(expression.orOrExpression, mod);
    if (expression.expression !is null) {
        auto e = genExpression(expression.expression, mod.dup);
        auto v = e.type.getValue(mod, expression.location);
        
        auto condTrueBB  = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.get(), "condTrue");
        auto condFalseBB = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.get(), "condFalse");
        auto condEndBB   = LLVMAppendBasicBlockInContext(mod.context, mod.currentFunction.get(), "condEnd");
        LLVMBuildCondBr(mod.builder, a.performCast(expression.location, new BoolType(mod)).get(), condTrueBB, condFalseBB);
        LLVMPositionBuilderAtEnd(mod.builder, condTrueBB);
        v.set(expression.location, genExpression(expression.expression, mod));
        LLVMBuildBr(mod.builder, condEndBB);
        LLVMPositionBuilderAtEnd(mod.builder, condFalseBB);
        v.set(expression.location, genConditionalExpression(expression.conditionalExpression, mod));
        LLVMBuildBr(mod.builder, condEndBB);
        LLVMPositionBuilderAtEnd(mod.builder, condEndBB);
        
        a = v;
    }
    return a;
}

Value genOrOrExpression(ast.OrOrExpression expression, Module mod)
{
    Value val;
    if (expression.orOrExpression !is null) {
        auto lhs = genOrOrExpression(expression.orOrExpression, mod);
        val = genAndAndExpression(expression.andAndExpression, mod);
        val.or(lhs);
    } else {
        val = genAndAndExpression(expression.andAndExpression, mod);
    }
    return val;
}

Value genAndAndExpression(ast.AndAndExpression expression, Module mod)
{
    return genOrExpression(expression.orExpression, mod);
}

Value genOrExpression(ast.OrExpression expression, Module mod)
{
    return genXorExpression(expression.xorExpression, mod);
}

Value genXorExpression(ast.XorExpression expression, Module mod)
{
    return genAndExpression(expression.andExpression, mod);
}

Value genAndExpression(ast.AndExpression expression, Module mod)
{
    return genCmpExpression(expression.cmpExpression, mod);
}

Value genCmpExpression(ast.CmpExpression expression, Module mod)
{
    auto lhs = genShiftExpression(expression.lhShiftExpression, mod);
    switch (expression.comparison) {
    case ast.Comparison.None:
        break;
    case ast.Comparison.Equality:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.eq(expression.location, rhs);
        break;
    case ast.Comparison.NotEquality:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.neq(expression.location, rhs);
        break;
    case ast.Comparison.Greater:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.gt(expression.location, rhs);
        break;
    case ast.Comparison.LessEqual:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.lte(expression.location, rhs);
        break;
    case ast.Comparison.Less:
        auto rhs = genShiftExpression(expression.rhShiftExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &rhs);
        lhs = lhs.lt(expression.location, rhs);
        break;
    default:
        throw new CompilerPanic(expression.location, "unhandled comparison expression.");
    }
    return lhs;
}

Value genShiftExpression(ast.ShiftExpression expression, Module mod)
{
    return genAddExpression(expression.addExpression, mod);
}

Value genAddExpression(ast.AddExpression expression, Module mod)
{
    Value val;
    if (expression.addExpression !is null) {
        auto lhs = genAddExpression(expression.addExpression, mod);
        val = genMulExpression(expression.mulExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &val);
        
        final switch (expression.addOperation) {
        case ast.AddOperation.Add:
            val = lhs.add(expression.location, val);
            break;
        case ast.AddOperation.Subtract:
            val = lhs.sub(expression.location, val);
            break;
        case ast.AddOperation.Concat:
            throw new CompilerPanic(expression.location, "unimplemented add operation.");
        }
    } else {
        val = genMulExpression(expression.mulExpression, mod);
    }
    
    return val;
}

Value genMulExpression(ast.MulExpression expression, Module mod)
{
    Value val;
    if (expression.mulExpression !is null) {
        auto lhs = genMulExpression(expression.mulExpression, mod);
        val = genPowExpression(expression.powExpression, mod);
        binaryOperatorImplicitCast(expression.location, &lhs, &val);
        
        final switch (expression.mulOperation) {
        case ast.MulOperation.Mul:
            val = lhs.mul(expression.location, val);
            break;
        case ast.MulOperation.Div:
            val = lhs.div(expression.location, val);
            break;
        case ast.MulOperation.Mod:
            throw new CompilerPanic(expression.location, "unimplemented mul operation.");
            assert(false);
        }
    } else {
        val = genPowExpression(expression.powExpression, mod);
    }
    return val;
}

Value genPowExpression(ast.PowExpression expression, Module mod)
{
    return genUnaryExpression(expression.unaryExpression, mod);
}

Value genUnaryExpression(ast.UnaryExpression expression, Module mod)
{
    Value val;
    final switch (expression.unaryPrefix) {
    case ast.UnaryPrefix.PrefixDec:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val.set(expression.location, val.dec(expression.location));
        break;
    case ast.UnaryPrefix.PrefixInc:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val.set(expression.location, val.inc(expression.location));
        break;
    case ast.UnaryPrefix.Cast:
        val = genUnaryExpression(expression.castExpression.unaryExpression, mod);
        val = val.performCast(expression.location, astTypeToBackendType(expression.castExpression.type, mod, OnFailure.DieWithError));
        break;
    case ast.UnaryPrefix.UnaryMinus:
        val = genUnaryExpression(expression.unaryExpression, mod);
        auto zero = new IntValue(mod, expression.location, 0);
        binaryOperatorImplicitCast(expression.location, &zero, &val);
        val = zero.sub(expression.location, val);
        break;
    case ast.UnaryPrefix.UnaryPlus:
        val = genUnaryExpression(expression.unaryExpression, mod);
        break;
    case ast.UnaryPrefix.AddressOf:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val = val.addressOf();
        break;
    case ast.UnaryPrefix.Dereference:
        val = genUnaryExpression(expression.unaryExpression, mod);
        val = val.dereference(expression.location);
        break;
    case ast.UnaryPrefix.LogicalNot:
    case ast.UnaryPrefix.BitwiseNot:
        throw new CompilerPanic(expression.location, "unimplemented unary expression.");
    case ast.UnaryPrefix.None:
        val = genPostfixExpression(expression.postfixExpression, mod);
        break;
    }
    return val;
}

Value genPostfixExpression(ast.PostfixExpression expression, Module mod, Value suppressPrimary = null)
{
    Value lhs;
    if (suppressPrimary is null) {
        lhs = genPrimaryExpression(expression.primaryExpression, mod);
    } else {
        lhs = suppressPrimary;
    }
    
    final switch (expression.type) {
    case ast.PostfixType.None:
        break;
    case ast.PostfixType.PostfixInc:
        auto val = lhs;
        auto tmp = lhs.type.getValue(mod, lhs.location);
        tmp.set(expression.location, lhs);
        lhs = tmp;
        val.set(expression.location, val.inc(expression.location));
        break;
    case ast.PostfixType.PostfixDec:
        auto val = lhs;
        auto tmp = lhs.type.getValue(mod, lhs.location);
        tmp.set(expression.location, lhs);
        lhs = tmp;
        val.set(expression.location, val.dec(expression.location));
        break;
    case ast.PostfixType.Parens:
        if (lhs.type.dtype == DType.Function) {
            auto asFunction = cast(FunctionType) lhs.type;
            assert(asFunction);
            Value[] args;
            Location[] argLocations;
            auto argList = cast(ast.ArgumentList) expression.firstNode;
            assert(argList);
            foreach (expr; argList.expressions) {
                auto oldAggregate = mod.callingAggregate;
                mod.callingAggregate = null;
                args ~= genAssignExpression(expr, mod);
                argLocations ~= expr.location;
                mod.callingAggregate = oldAggregate;
            }
            if (mod.callingAggregate !is null) {
                auto p = new PointerValue(mod, expression.location, mod.callingAggregate.type);
                p.set(expression.location, mod.callingAggregate.addressOf());
                args ~= p;
            }
            lhs = lhs.call(argList.location, argLocations, args);
        } else {
            throw new CompilerError(expression.location, "can only call functions.");
        }
        break;
    case ast.PostfixType.Index:
        Value[] args;
        foreach (expr; (cast(ast.ArgumentList) expression.firstNode).expressions) {
            args ~= genAssignExpression(expr, mod);
        }
        if (args.length == 0 || args.length > 1) {
            throw new CompilerPanic(expression.location, "slice argument lists must contain only one argument.");
        }
        lhs = lhs.index(lhs.location, args[0]);
        break;
    case ast.PostfixType.Dot:
        auto qname = cast(ast.QualifiedName) expression.firstNode;
        mod.base = lhs;
        foreach (identifier; qname.identifiers) {
            if (mod.base.type.dtype == DType.Struct) {
                mod.callingAggregate = mod.base;
            }
            mod.base = genIdentifier(identifier, mod);
        }
        lhs = mod.base;
        mod.base = null;
        lhs = genPostfixExpression(cast(ast.PostfixExpression) expression.secondNode, mod, lhs);
        mod.callingAggregate = null;
        break;
    case ast.PostfixType.Slice:
        throw new CompilerPanic(expression.location, "unimplemented postfix expression type.");
        assert(false);
    }
    return lhs;
}

Value genPrimaryExpression(ast.PrimaryExpression expression, Module mod)
{
    switch (expression.type) {
    case ast.PrimaryType.IntegerLiteral:
        return new IntValue(mod, expression.location, extractIntegerLiteral(cast(ast.IntegerLiteral) expression.node));
    case ast.PrimaryType.FloatLiteral:
        return new DoubleValue(mod, expression.location, extractFloatLiteral(cast(ast.FloatLiteral) expression.node));
    case ast.PrimaryType.True:
        return new BoolValue(mod, expression.location, true);
    case ast.PrimaryType.False:
        return new BoolValue(mod, expression.location, false);
    case ast.PrimaryType.CharacterLiteral: 
        return new CharValue(mod, expression.location, cast(char)extractCharacterLiteral(cast(ast.CharacterLiteral) expression.node));
    case ast.PrimaryType.StringLiteral:
        return new StringValue(mod, expression.location, extractStringLiteral(cast(ast.StringLiteral) expression.node));
    case ast.PrimaryType.Identifier:
        return genIdentifier(cast(ast.Identifier) expression.node, mod);
    case ast.PrimaryType.ParenExpression:
        return genExpression(cast(ast.Expression) expression.node, mod);
    case ast.PrimaryType.This:
        auto i = new ast.Identifier();
        i.location = expression.location;
        i.value = "this";
        return genIdentifier(i, mod);
    case ast.PrimaryType.Null:
        return new NullPointerValue(mod, expression.location);
    case ast.PrimaryType.BasicTypeDotIdentifier:
        auto v = primitiveTypeToBackendType(cast(ast.PrimitiveType) expression.node, mod).getValue(mod, expression.location);
        return v.getMember(expression.location, extractIdentifier(cast(ast.Identifier) expression.secondNode));
    default:
    
        throw new CompilerPanic(expression.location, "unhandled primary expression type.");
    }
}

Value genIdentifier(ast.Identifier identifier, Module mod)
{
    auto name = extractIdentifier(identifier);
    void failure() 
    { 
        throw new CompilerError(identifier.location, format("unknown identifier '%s'.", name));
    }
    
    
    Value implicitBase;
    if (mod.base !is null) {
        return mod.base.getMember(identifier.location, name);
    } else {
        auto s = mod.search("this");
        if (s !is null) {
            if (s.storeType != StoreType.Value) {
                throw new CompilerPanic(identifier.location, "this reference not a value.");
            }
            implicitBase = s.value;
        }
    }
    auto store = mod.search(name);
    if (store is null) {
        if (implicitBase !is null) {
            store = new Store(implicitBase.getMember(identifier.location, name));
        }
        if (store is null) {
            failure();
        }
    }
    
    if (store.storeType == StoreType.Value) {
        return store.value();
    } else if (store.storeType == StoreType.Scope) {
        return new ScopeValue(mod, identifier.location, store.getScope());
    } else if (store.storeType == StoreType.Type) {
        return store.type().getValue(mod, identifier.location);
    } else {
        assert(false);
    }
}
