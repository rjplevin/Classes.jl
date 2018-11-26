# Classes.jl
A simple, Julian approach to inheritance of structure and methods.

Julia is not an object-oriented language in the traditional sense that only abstract types can be inherited. Thus,
if multiple types need to share structure, you either:

1. Write out the common fields manually.
1. Create a new type that holds the common fields and include an instance of this in
   each of the structs that needs the common fields.
1. Write a macro that emits the common fields.
1. Use someone else's macros that provide such features.

All of these have downsides:

* Writing out the fields manually creates maintenance challenges since you no longer have a single 
  point of modification.  Using a macro to emit the common fields solves this problem, but there's still
  no way to identify the relatedness of the structs that contain these common fields.
* Creating a new type for common fields generally involves creating functions to delegate from the outer 
  type to the inner type.
  This can become annoying if you have multiple levels of nesting. Of course you can write forwarding macros
  to handle this, but this also becomes repetitive and annoying.
* None of the packages I reviewed seemed to combine the power and simplicity I was after.

`Classes.jl` provides two short macros, `@class` and `@method` that (I hope) solve this problem in a
sufficiently Julian manner to not offend language purists.

## The @class macro

* A "class" is a concrete type. The `@class` macro saves the field definitions for each class
  so that subclasses receive all their parent's fields in addition to those defined locally.

* `Classes.jl` constructs a "shadow" type hierarchy to represent the relationships among the
  defined classes. For each class `Foo`, the abstract type `_Foo_` is defined, where `_Foo_` 
  is a subtype of the abstract type associated with the superclass of `Foo`.

Given these two class definitions (note that `Class` is defined in `Classes.jl`):

 ```
@class Foo <: Class begin
   foo::Int
end

@class Bar <: Foo begin
    bar::Int
end
```

The following julia code is emitted:

```
abstract type _Foo_ <: _Class_ end

struct Foo <: _Foo_
    foo::Int
end

abstract type _Bar_ <: _Foo_ end

struct Bar <: _Bar_
    foo::Int
    bar::Int
end
```

In addition, functions are emitted that relate these:

```
Classes.superclass(::Type{Bar}) = Foo

Classes.issubclass(::Type{Bar}, ::Type{Foo}) = true
# And so on, up the type hierarchy
```

## The @method macro

* A "method" is a function whose first argument must be a type defined by `@class`.
* The `@method` macro uses the shadow type hierarchy to redefine the given function
  so that it applies to the given class and all of its subclasses.
* Subclasses can override a superclass method by redefining the method on the
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

julia> @method foo(obj::Bar) = obj.foo * 2
foo (generic function with 2 methods)

julia> foo(b)
20

julia> @class Baz <: Bar begin
          baz::Int
       end

julia> z = Baz(100, 101, 102)
Baz(100, 101, 102)

julia> foo(z)
200
```