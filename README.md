[![Build Status](https://travis-ci.org/rjplevin/Classes.jl.svg?branch=master)](https://travis-ci.org/rjplevin/Classes.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/github/rjplevin/Classes.jl?branch=master&?svg=true)](https://ci.appveyor.com/project/rjplevin/classes-jl/branch/master)
[![codecov](https://codecov.io/gh/rjplevin/Classes.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/rjplevin/Classes.jl)
[![Coverage Status](https://img.shields.io/coveralls/github/rjplevin/Classes.jl/master.svg)](https://coveralls.io/github/rjplevin/Classes.jl?branch=master)

# Classes.jl
A simple, Julian approach to inheritance of structure and methods.

## Motivation
Julia is not an object-oriented language in the traditional sense in that there is no inheritance of structure.
If multiple types need to share structure, you have several options:

1. Write out the common fields manually.
1. Write a macro that emits the common fields. This is better than the manual approach
   since it creates a single point of modification.
1. Use composition instead of inheritance: create a new type that holds the common fields 
   and include an instance of this in each of the structs that needs the common fields.
1. Use an existing package that provides the required features.

All of these have downsides:

* As suggested above, writing out the duplicate fields manually creates maintenance challenges 
  since you no longer have a single  point of modification.  
* Using a macro to emit the common fields solves this problem, but there's still
  no convient way to identify the relatedness of the structs that contain these common fields.
* Composition -- the typically recommended julian approach -- generally involves creating 
  functions to delegate from the outer type to the inner type. This can become tedious if 
  you have multiple levels of nesting. Of course you
  can write forwarding macros to handle this, but this also becomes repetitive.
* Neither of the packages I reviewed -- OOPMacro.jl and ConcreteAbstractions.jl -- combine the
  power and simplicity I was after, and neither has been updated in years.

`Classes.jl` provides one macro, `@class`, which is a simple wrapper around
existing Julia syntax. `Classes.jl` exploits the type Julia system to provide inheritance
of methods while enabling shared structure without duplicative code.

## The @class macro

A "class" is a concrete type with a defined relationship to a hierarchy of automatically
generated abstract types. The `@class` macro saves the field definitions for each class
so that subclasses receive all their parent's fields in addition to those defined locally.
Inner constructors are passed through unchanged.

`Classes.jl` constructs a "shadow" abstract type hierarchy to represent the relationships among 
the defined classes. For each class `Foo`, the abstract type `AbstractFoo` is defined, where `AbstractFoo` 
is a subtype of the abstract type associated with the superclass of `Foo`.

Given these two class definitions (note that `Class` is defined in `Classes.jl`):

```julia
using Classes

@class Foo <: Class begin       # or, equivalently, @class Foo begin ... end
   foo::Int
end

@class mutable Bar <: Foo begin
    bar::Int
end
```

The following julia code is emitted:

```julia
abstract type AbstractFoo <: AbstractClass end

struct Foo{} <: AbstractFoo
    x::Int

    function Foo(x::Int)
        new(x)
    end

    function Foo(self::T, x::Int) where T <: AbstractFoo
        self.x = x
        self
    end
end

abstract type AbstractBar <: AbstractFoo end

mutable struct Bar{} <: AbstractBar
    x::Int
    bar::Int

    function Bar(x::Int, bar::Int)
        new(x, bar)
    end

    function Bar(self::T, x::Int, bar::Int) where T <: AbstractBar
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

```julia
Classes.superclass(::Type{Bar}) = Foo

Classes.issubclass(::Type{Bar}, ::Type{Foo}) = true
# And so on, up the type hierarchy
```

Adding the `mutable` keyword after `@class` results in a mutable struct, but this
feature is not inherited by subclasses; it must be specified (if desired) for each
subclass. `Classes.jl` offers no special handling of mutability: it is the user's 
responsibility to ensure that combinations of mutable and immutable classes and related 
methods make sense.

## Defining methods to operate on a class hierarchy 

To define a function that operates on a class and its subclasses, specify the
associated abstract type rather than the class name in the method signature.

For example, give the class `Bar`, you can write a function that applies to
`Bar` and its subclasses by specifying the type `AbstractBar`:

```julia
my_method(obj::AbstractBar, other, stuff) = do_something(obj, other, args)
```

See the online [documentation](https://github.com/rjplevin/Classes.jl/blob/master/docs/src/index.md) for further details.
