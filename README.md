# oopz

oopzie, I accidentally oop'd my Zig

## what

a suite of helper functions for safely working with object-oriented C++ code in
Zig, designed for a very specific situation:

- the interface you are working with is object-oriented
- the types it exposes are `opaque`, and represent a class hierarchy
- you have to extend those types with your own types
- you want comptime type checking

if the parent types are not `opaque`, this library will not work for you.

## why

sometimes, despite all efforts otherwise, you find yourself needing to do weird
shit like pretending like your `Dog` is not a `Vehicle`.

this library was born from [`gdzig`](https://github.com/gdzig/gdzig), a library
for building extensions in [Godot](https://godotengine.org/).

## how

first map the external opaque types:

```zig
pub const Object = opaque {
    pub const Base = void;
}
pub const Animal = opaque {
    pub const Base = Object;
}
pub const Dog = opaque {
    pub const Base = Animal;
};
pub const Vehicle = opaque {
    pub const Base = Object;
};
pub const Car = opaque {
    pub const Base = Vehicle;
};
```

then take an oop all over your Zig type:

```zig
pub const ReliantRobin = struct {
  base: *Car,
}
```

now with the magic of Comptime™, you can safely upcast your `ReliantRobin` to a `Vehicle`:

```zig
std.testing.expect(oopz.isA(Vehicle, ReliantRobin));
std.testing.expect(!oopz.isA(Dog, ReliantRobin));

const a_vehicle: *Vehicle = oopz.upcast(*Vehicle, &a_reliant_robin);
const a_dog: *Dog = oopz.upcast(*Dog, &a_reliant_robin);
// error: what the fuck
```

## functions

```zig
pub fn BaseOf(comptime T: type) type
pub fn isClass(comptime T: type) bool
pub fn isOpaqueClass(comptime T: type) bool
pub fn isStructClass(comptime T: type) bool
pub fn isClassPtr(comptime T: type) bool
pub fn isOpaqueClassPtr(comptime T: type) bool
pub fn isStructClassPtr(comptime T: type) bool
pub fn depthOf(comptime T: type) comptime_int
pub fn ancestorsOf(comptime T: type) [depthOf(T)]type
pub fn selfAndAncestorsOf(comptime T: type) [1 + depthOf(T)]type
pub fn isA(comptime T: type, comptime U: type) bool
pub fn isAny(comptime types: anytype, comptime U: type) bool
pub fn assertIsA(comptime T: type, comptime U: type) void
pub fn assertIsAny(comptime types: anytype, comptime U: type) void
```

## limitations

this is not a complete implementation of object-oriented programming.

- no multiple inheritance
- no polymorphic method dispatch
- no virtual methods or method overriding
- no interfaces or abstract classes
- downcasting is an inherently runtime operation, and is not built-in. you can
  use the helpers provided by `oopz` to implement your own downcasting logic
  with a comptime check to ensure the target is a valid child type.
