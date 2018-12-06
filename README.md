# Classes.jl
A simple, Julian approach to inheritance of structure and methods.

## Motivation
Julia is not an object-oriented language in the traditional sense that only abstract types can be inherited. Thus,
if multiple types need to share structure, you either:

1. Write out the common fields manually.
1. Create a new type that holds the common fields and include an instance of this in
   each of the structs that needs the common fields.
1. Write a macro that emits the common fields.
1. Use someone else's macros that provide such features.

All of these have downsides:

* Writing out the fields manually creates maintenance challenges since you no longer have a single 
  point of modification.  
* Using a macro to emit the common fields solves this problem, but there's still
  no convient way to identify the relatedness of the structs that contain these common fields.
* Creating a new type for common fields generally involves creating functions to delegate from the outer 
  type to the inner type.  This can become tedious if you have multiple levels of nesting. Of course you
  can write forwarding macros to handle this, but this also becomes repetitive.
* None of the packages I reviewed seemed to combine the power and simplicity I was after, and several
  of them haven't been updated in years (e.g., OOPMacro.jl, ConcreteAbstractions.jl).

`Classes.jl` provides two macros, `@class` and `@method` that address this problem. (I believe it does
so in a sufficiently Julian manner as to not offend language purists. ;~)

## The @class macro

A "class" is a concrete type with a defined relationship to a hierarchy of automatically
generated abstract types. The `@class` macro saves the field definitions for each class
so that subclasses receive all their parent's fields in addition to those defined locally.
Inner constructors are passed through unchanged.

`Classes.jl` constructs a "shadow" abstract type hierarchy to represent the relationships among 
the defined classes. For each class `Foo`, the abstract type `_Foo_` is defined, where `_Foo_` 
is a subtype of the abstract type associated with the superclass of `Foo`.

Given these two class definitions (note that `Class` is defined in `Classes.jl`):

```
import Classes

@class Foo <: Class begin       # or, equivalently, @class Foo begin ... end
   foo::Int
end

@class mutable Bar <: Foo begin
    bar::Int
end
```

The following julia code is emitted:

```
abstract type _Foo_ <: _Class_ end

struct Foo{} <: _Foo_
    x::Int

    function Foo(x::Int)
        new(x)
    end

    function Foo(self::T, x::Int) where T <: _Foo_
        self.x = x
        self
    end
end

abstract type _Bar_ <: _Foo_ end

mutable struct Bar{} <: _Bar_
    x::Int
    bar::Int

    function Bar(x::Int, bar::Int)
        new(x, bar)
    end

    function Bar(self::T, x::Int, bar::Int) where T <: _Bar_
        self.x = x
        self.bar = bar
        self
    end
end
```

Note that the second emitted constructor is parameterized such that it can be called 
on the class's subclasses to set fields defined by the class. Of course, this is
callable only on a mutable struct.

In addition, introspection functions are emitted that relate these:

```
Classes.superclass(::Type{Bar}) = Foo

Classes.issubclass(::Type{Bar}, ::Type{Foo}) = true
# And so on, up the type hierarchy
```

Adding the `mutable` keyword after `@class` results in a mutable struct, but this
feature is not inherited by subclasses; it must be specified (if desired) for each
subclass. `Classes.jl` offers no special handling of mutability: it is the user's 
responsibility to ensure that combinations of mutable and immutable classes and related 
methods make sense.

* Keyword parameters

## The @method macro

A "method" is a function whose first argument must be a type defined by `@class`.
The `@method` macro uses the shadow abstract type hierarchy to redefine the given 
function so that it applies to the given class as well as its subclasses.

Subclasses can override a superclass method by redefining the method on the
more specific class.

Continuing our example from above, 

```
@method foo(obj::Foo) = obj.foo
```
emits essentially the following:

```
foo(obj::T) where T <: _Foo_ = obj.foo
```

Since `Bar <: _Bar_ <: _Foo_`,  the method also applies to instances of `Bar`.

```
julia> f = Foo(1)
Foo(1)

julia> b = Bar(10, 11)
Bar(10, 11)

julia> foo(f)
1

julia> foo(b)
10
```

We can redefine `foo` for class `Bar` to override its "inherited" superclass definition:

```
julia> @method foo(obj::Bar) = obj.foo * 2
foo (generic function with 2 methods)

julia> foo(b)
20
```

Subclasses of `Bar` now inherit its definition, rather than the one from `Foo`:

```
julia> @class Baz <: Bar begin
          baz::Int
       end

julia> z = Baz(100, 101, 102)
Baz(100, 101, 102)

julia> dump(z)
Baz
  foo: Int64 100
  bar: Int64 101
  baz: Int64 102
  
julia> foo(z)
200
```