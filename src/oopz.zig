/// Returns the base type of T.
///
/// Expects a class type, e.g `MyClass`, not `*MyClass`.
pub fn BaseOf(comptime T: type) type {
    if (comptime !isClass(T)) {
        if (comptime isClassPtr(T)) {
            @compileError("expected an opaque class type, found '" ++ @typeName(T) ++ "'. did you mean '" ++ @typeName(RecursiveChild(T)) ++ "'?");
        }
        @compileError("expected an opaque class type, found '" ++ @typeName(T) ++ "'. did you remember to add the 'base' struct field?");
    }

    return comptime switch (@typeInfo(T)) {
        .@"struct" => RecursiveChild(@FieldType(T, "base")),
        .@"opaque" => T.Base,
        else => unreachable,
    };
}

/// Returns true if the type is a "class".
///
/// A type is a class if:
///
/// - It is a struct with a `base: *Base` field.
/// - It is an opaque type with a `Base: type` decl
///
/// Expects a class type, e.g `MyClass`, not `*MyClass`.
pub fn isClass(comptime T: type) bool {
    return comptime switch (@typeInfo(T)) {
        .@"struct" => isStructClass(T),
        .@"opaque" => isOpaqueClass(T),
        else => false,
    };
}

/// Returns true if a type is both a class, and an opaque type.
///
/// Opaque classes require a `Base: type` declaration.
///
/// Expects a class type, e.g. `MyClass`, not `*MyClass`.
pub fn isOpaqueClass(comptime T: type) bool {
    return comptime switch (@typeInfo(T)) {
        .@"opaque" => @hasDecl(T, "Base") and (T.Base == void or isClass(T.Base)),
        else => false,
    };
}

/// Returns true if a type is both a class, and a struct type.
///
/// Struct classes require a `base: *Base` field.
///
/// Expects a class type, e.g. `MyClass`, not `*MyClass`.
pub fn isStructClass(comptime T: type) bool {
    return comptime switch (@typeInfo(T)) {
        .@"struct" => @hasField(T, "base") and isClassPtr(@FieldType(T, "base")),
        else => false,
    };
}

/// Returns true if the type is pointer to a "class" type; a.k.a. it has a base.
///
/// Expects a pointer type, e.g. `*MyClass`, not `MyClass`.
pub fn isClassPtr(comptime T: type) bool {
    return comptime sw: switch (@typeInfo(T)) {
        .optional => |info| continue :sw @typeInfo(info.child),
        .pointer => |info| isClass(info.child),
        else => false,
    };
}

/// Returns true if a type is a pointer to an opaque class type.
///
/// Expects a pointer type, e.g. `*MyClass`, not `MyClass`.
pub fn isOpaqueClassPtr(comptime T: type) bool {
    return comptime sw: switch (@typeInfo(T)) {
        .optional => |info| continue :sw @typeInfo(info.child),
        .pointer => |info| isOpaqueClass(info.child),
        else => false,
    };
}

/// Returns true if a type is a pointer to a struct class type.
///
/// Expects a pointer type, e.g. `*MyClass`, not `MyClass`.
pub fn isStructClassPtr(comptime T: type) bool {
    return comptime sw: switch (@typeInfo(T)) {
        .optional => |info| continue :sw @typeInfo(info.child),
        .pointer => |info| isStructClass(info.child),
        else => false,
    };
}

/// Returns how many levels of inheritance T has.
///
/// Expects a class type, e.g `MyClass`, not `*MyClass`.
pub fn depthOf(comptime T: type) comptime_int {
    comptime var i = 0;
    comptime var Cur = T;
    inline while (isClass(Cur)) : (i += 1) {
        Cur = BaseOf(Cur);
        if (Cur == void) break;
    }
    return i;
}

/// Returns the type hierarchy of T as an array of types, in ascending order, starting with the parent of T.
///
/// Expects a class type, e.g `MyClass`, not `*MyClass`.
pub fn ancestorsOf(comptime T: type) [depthOf(T)]type {
    if (comptime depthOf(T) == 0) {
        return [0]type{};
    }

    comptime var hierarchy: [depthOf(T)]type = undefined;
    inline for (0..depthOf(T)) |i| {
        hierarchy[i] = BaseOf(if (i == 0) T else hierarchy[i - 1]);
    }
    return hierarchy;
}

/// Returns the type hierarchy of T as an array of types, in ascending order. starting with T.
///
/// Expects a class type, e.g `MyClass`, not `*MyClass`.
pub fn selfAndAncestorsOf(comptime T: type) [1 + depthOf(T)]type {
    return [_]type{T} ++ ancestorsOf(T);
}

/// Is U a child of T
///
/// Expects class types, e.g `MyClass`, not `*MyClass`.
pub fn isA(comptime T: type, comptime U: type) bool {
    if (isClassPtr(T) or isClassPtr(U)) {
        @compileError("isA expects a class type, not a pointer type; found '" ++ @typeName(T) ++ "' and '" ++ @typeName(U) ++ "'");
    }
    if (!isClass(T) or !isClass(U)) {
        return false;
    }
    if (comptime T == U) {
        return true;
    }

    @setEvalBranchQuota(10_000);
    inline for (selfAndAncestorsOf(U)) |Ancestor| {
        if (comptime T == Ancestor) {
            return true;
        }
    }

    return false;
}

/// Is U a child of any of the types in types
///
/// Expects class types, e.g `MyClass`, not `*MyClass`.
pub fn isAny(comptime types: anytype, comptime U: type) bool {
    inline for (0..types.len) |i| {
        if (comptime isA(types[i], U)) {
            return true;
        }
    }
    return false;
}

/// Upcast a value to a parent type in the class hierarchy with compile time guaranteed success.
///
/// Expects pointer types, e.g `*MyClass`, not `MyClass`.
///
/// Supports optional pointers when both arguments are optional pointer types.
pub inline fn upcast(comptime T: type, value: anytype) blk: {
    const U = @TypeOf(value);

    if (!isClassPtr(T)) {
        @compileError("upcast expects a class pointer type as the target type, found '" ++ @typeName(T) ++ "'");
    }
    if (!isClassPtr(U)) {
        @compileError("upcast expects a class pointer type as the source value, found '" ++ @typeName(U) ++ "'");
    }
    if (@typeInfo(T) == .optional and @typeInfo(U) != .optional or @typeInfo(T) != .optional and @typeInfo(U) == .optional) {
        @compileError("upcast expects that if one argument is an optional pointer, the other is an optional pointer. found '" ++ @typeName(T) ++ "' and '" ++ @typeName(U) ++ "'");
    }

    const PtrT = if (@typeInfo(T) == .optional) @typeInfo(T).optional.child else T;
    const PtrU = if (@typeInfo(U) == .optional) @typeInfo(U).optional.child else U;

    if (@typeInfo(PtrU).pointer.is_const and !@typeInfo(PtrT).pointer.is_const) {
        @compileError("upcast expects matching pointer constness, found '" ++ @typeName(T) ++ "' and '" ++ @typeName(U) ++ "'");
    }

    assertIsA(RecursiveChild(T), RecursiveChild(U));

    break :blk T;
} {
    const U = @TypeOf(value);

    if (@typeInfo(U) == .optional and value == null) {
        return null;
    }

    var opaque_ptr: if (@typeInfo(U).pointer.is_const) *const anyopaque else *anyopaque = @ptrCast(value);

    // Walk up the inheritance hierarchy from child to parent
    inline for (selfAndAncestorsOf(RecursiveChild(U))) |CurrentType| {
        // Found our target type - return the properly typed pointer
        if (comptime CurrentType == RecursiveChild(T)) {
            return @ptrCast(@alignCast(opaque_ptr));
        }

        // Move to the next level up in the hierarchy
        opaque_ptr = switch (@typeInfo(CurrentType)) {
            .@"struct" => @ptrCast(@field(@as(if (@typeInfo(U).pointer.is_const) *const CurrentType else *CurrentType, @ptrCast(@alignCast(opaque_ptr))), "base")),
            .@"opaque" => @ptrCast(opaque_ptr),
            else => unreachable,
        };
    }

    unreachable;
}

/// Asserts at compile time that the given type is a subtype of the specified type.
pub fn assertIsA(comptime T: type, comptime U: type) void {
    if (comptime !isA(T, U)) {
        const message = fmt.comptimePrint("expected type '{s}', found '{s}'", .{ @typeName(T), @typeName(U) });
        @compileError(message);
    }
}

/// Asserts at compile time that the given type is a subtype of any of the specified types.
pub fn assertIsAny(comptime types: anytype, comptime U: type) void {
    if (comptime !isAny(types, U)) {
        var names: []const u8 = "";
        for (if (@hasField(types, "len")) types else .{types}, 0..) |t, i| {
            if (i == 0) {
                names = names ++ "'" ++ @typeName(t) ++ "'";
            } else if (i == types.len - 1) {
                names = names ++ ", or '" ++ @typeName(t) ++ "'";
            } else {
                names = names ++ ", '" ++ @typeName(t) ++ "'";
            }
        }
        const message = fmt.comptimePrint("expected type {s}, found '{s}'", .{ names, @typeName(U) });
        @compileError(message);
    }
}

/// Recursively dereferences a type to its base; e.g. `Child(?*?*?*T)` returns `T`.
fn RecursiveChild(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |info| RecursiveChild(info.child),
        .pointer => |info| RecursiveChild(info.child),
        else => T,
    };
}

const Object = opaque {
    const Base = void;
};
const Node = opaque {
    const Base = Object;
};
const Node3D = opaque {
    const Base = Node;
};
const MyNode = struct {
    base: *Node3D,
};
const RefCounted = opaque {
    const Base = Object;
};
const Resource = opaque {
    const Base = RefCounted;
};

test "BaseOf" {
    try testing.expectEqual(Object, BaseOf(Node));
    try testing.expectEqual(Node, BaseOf(Node3D));
    try testing.expectEqual(Node3D, BaseOf(MyNode));

    try testing.expectEqual(Object, BaseOf(RefCounted));
    try testing.expectEqual(RefCounted, BaseOf(Resource));
}

test "depthOf" {
    try testing.expectEqual(0, depthOf(Object));

    try testing.expectEqual(1, depthOf(Node));
    try testing.expectEqual(2, depthOf(Node3D));
    try testing.expectEqual(3, depthOf(MyNode));

    try testing.expectEqual(1, depthOf(RefCounted));
    try testing.expectEqual(2, depthOf(Resource));
}

test "ancestorsOf" {
    comptime try testing.expectEqualSlices(type, &.{}, &ancestorsOf(Object));

    comptime try testing.expectEqualSlices(type, &.{Object}, &ancestorsOf(Node));
    comptime try testing.expectEqualSlices(type, &.{ Node, Object }, &ancestorsOf(Node3D));
    comptime try testing.expectEqualSlices(type, &.{ Node3D, Node, Object }, &ancestorsOf(MyNode));

    comptime try testing.expectEqualSlices(type, &.{Object}, &ancestorsOf(RefCounted));
    comptime try testing.expectEqualSlices(type, &.{ RefCounted, Object }, &ancestorsOf(Resource));
}

test "selfAndAncestorsOf" {
    comptime try testing.expectEqualSlices(type, &.{Object}, &selfAndAncestorsOf(Object));

    comptime try testing.expectEqualSlices(type, &.{ Node, Object }, &selfAndAncestorsOf(Node));
    comptime try testing.expectEqualSlices(type, &.{ Node3D, Node, Object }, &selfAndAncestorsOf(Node3D));
    comptime try testing.expectEqualSlices(type, &.{ MyNode, Node3D, Node, Object }, &selfAndAncestorsOf(MyNode));

    comptime try testing.expectEqualSlices(type, &.{ RefCounted, Object }, &selfAndAncestorsOf(RefCounted));
    comptime try testing.expectEqualSlices(type, &.{ Resource, RefCounted, Object }, &selfAndAncestorsOf(Resource));
}

test "isA: is self" {
    try testing.expect(comptime isA(Object, Object));
    try testing.expect(comptime isA(Node, Node));
    try testing.expect(comptime isA(Node3D, Node3D));
    try testing.expect(comptime isA(MyNode, MyNode));
    try testing.expect(comptime isA(RefCounted, RefCounted));
    try testing.expect(comptime isA(Resource, Resource));
}

test "isA: is parent" {
    try testing.expect(comptime isA(Object, Node));
    try testing.expect(comptime isA(Object, RefCounted));
    try testing.expect(comptime isA(Node, Node3D));
    try testing.expect(comptime isA(Node3D, MyNode));
    try testing.expect(comptime isA(RefCounted, Resource));
}

test "isA: is root" {
    try testing.expect(comptime isA(Object, Node));
    try testing.expect(comptime isA(Object, Node3D));
    try testing.expect(comptime isA(Object, MyNode));
    try testing.expect(comptime isA(Object, RefCounted));
    try testing.expect(comptime isA(Object, Resource));
}

test "isA: is not child" {
    try testing.expect(comptime !isA(Node, Object));
    try testing.expect(comptime !isA(Node3D, Object));
    try testing.expect(comptime !isA(Node3D, Node));
    try testing.expect(comptime !isA(MyNode, Object));
    try testing.expect(comptime !isA(MyNode, Node));
    try testing.expect(comptime !isA(MyNode, Node3D));
}

test "isA: is not something else" {
    try testing.expect(comptime !isA(RefCounted, Node));
    try testing.expect(comptime !isA(RefCounted, Node3D));
    try testing.expect(comptime !isA(RefCounted, MyNode));
    try testing.expect(comptime !isA(Node, RefCounted));
    try testing.expect(comptime !isA(Node, Resource));
    try testing.expect(comptime !isA(Node3D, RefCounted));
    try testing.expect(comptime !isA(Node3D, Resource));
    try testing.expect(comptime !isA(MyNode, RefCounted));
    try testing.expect(comptime !isA(MyNode, Resource));
}

test "isAny" {
    try testing.expect(comptime isAny(.{ Node, RefCounted }, Node));
    try testing.expect(comptime isAny(.{ Node, RefCounted }, RefCounted));
    try testing.expect(comptime isAny(.{ Node, RefCounted }, Node3D));
    try testing.expect(comptime isAny(.{ Node, RefCounted }, Resource));

    try testing.expect(comptime !isAny(.{ Node3D, Node }, Resource));
}

test "upcast" {
    const object: *Object = @ptrFromInt(0xAAAAAAAAAAAAAAAA);
    const node: *Node = @ptrFromInt(0xAAAAAAAAAAAAAAAA);
    const node3D: *Node3D = @ptrFromInt(0xAAAAAAAAAAAAAAAA);

    var my_mut_node: MyNode = .{ .base = node3D };
    const my_const_node: MyNode = .{ .base = node3D };

    const object2: *Object = @ptrFromInt(0xBBBBBBBBBBBBBBBB);
    const ref_counted: *RefCounted = @ptrFromInt(0xBBBBBBBBBBBBBBBB);
    const resource: *Resource = @ptrFromInt(0xBBBBBBBBBBBBBBBB);

    try testing.expectEqual(object, upcast(*Object, object));
    try testing.expectEqual(object, upcast(*Object, node));
    try testing.expectEqual(object, upcast(*Object, node3D));
    try testing.expectEqual(object, upcast(*Object, &my_mut_node));
    try testing.expectEqual(object, upcast(*const Object, &my_mut_node));
    try testing.expectEqual(object, upcast(*const Object, &my_const_node));

    try testing.expectEqual(node, upcast(*Node, node));
    try testing.expectEqual(node, upcast(*Node, node3D));
    try testing.expectEqual(node, upcast(*Node, &my_mut_node));
    try testing.expectEqual(node, upcast(*const Node, &my_mut_node));
    try testing.expectEqual(node, upcast(*const Node, &my_const_node));

    try testing.expectEqual(node3D, upcast(*Node3D, node3D));
    try testing.expectEqual(node3D, upcast(*Node3D, &my_mut_node));
    try testing.expectEqual(node3D, upcast(*const Node3D, &my_mut_node));
    try testing.expectEqual(node3D, upcast(*const Node3D, &my_const_node));

    try testing.expectEqual(&my_mut_node, upcast(*MyNode, &my_mut_node));
    try testing.expectEqual(&my_mut_node, upcast(*const MyNode, &my_mut_node));
    try testing.expectEqual(&my_const_node, upcast(*const MyNode, &my_const_node));

    try testing.expectEqual(object2, upcast(*Object, ref_counted));
    try testing.expectEqual(object2, upcast(*Object, resource));

    try testing.expectEqual(ref_counted, upcast(*RefCounted, ref_counted));
    try testing.expectEqual(ref_counted, upcast(*RefCounted, resource));

    try testing.expectEqual(resource, upcast(*Resource, resource));
}

const std = @import("std");
const fmt = std.fmt;
const testing = std.testing;
const Tuple = std.meta.Tuple;
