# Classes.jl

The key feature of the package is the management of an abstract type hierarchy that
defines the subclass and superclass relationships desired of the the concrete types
representing the classes. The concrete types defined for each class include all the
fields defined in any declared superclass, plus the fields defined within the class
declaration. The abstract type hierarchy allows methods to be defined for a class
that can also be called on its subclasses, whose fields are a superset of those of 
its superclass.

The `Classes.jl` package includes the macro, `@class`, and several 
exported functions, described below.

## The @class macro

The `@class` macro does all the real work for this package. For each class (say, `MyClass`) created 
via `@class`, the following code is emitted:

* An abstract type created by prepending `Abstract` on the given class name (e.g., `AbstractMyClass`), 
  which is a subtype of the abstract type associated
  with a named superclass, if given, or `Classes.AbstractClass` if not specified.

* A concrete type `MyClass <: AbstractMyClass` with the fields of its superclass plus any
  locally defined fields.

* Several methods, including constructors, initializers, and introspection methods.

### The 'mutable' keyword

Class mutability is specified  by including `mutable` before the class name, e.g.,
`@class mutable MyClass ...` Note that mutability is not inherited; it must be stated in
each subclass if mutability is required.

### Functions emitted by the @class macro

The `@class` macro emits 

#### Constructors

* "All fields" constructor

  This constructor takes as arguments all the fields accumulated through superclasses, in
  the order defined, and calls `new()` on the args. This simply duplicates the default
  constructor, which is necessary since we define other "inner" constructors and initializers.

#### Initializers

Initializers are functions that set values on an existing class instance. These come
in several forms:

* "All fields" initializer

  Similar to the "all fields" constructor except that it takes an object that must
  be a class or subclass of the defined class.

* "Local fields" initializer

  Takes an instance of the class (or subclass thereof) and initializes only the fields newly
  defined by the current class. This is provided to support custom initializers that can
  chain from subclasses to superclasses.

* "Superclass copy" initializer

  Provided primarily to support immutable classes (but available to mutable classes as well),
  this initializer takes as arguments all locally-defined fields plus an instance of the 
  immediate superclass of the present class, from which values are copied into a call to
  `new` on the present class.

#### Reflection methods

* `isclass(T)`
   
   Return `true` if `T` is a concrete subclass of `AbstractClass`, or is `Class`, which is abstract.
   Returns `false` otherwise.

* `issubclass(class, superclass)`

   For all superclasses of the newly defined class, a method of `issubclass` is emitted that
   returns `true` for the new class and its superclasses.

* `superclass(class)`

   Returns the superclass of the newly defined class.

* `superclasses(::Type{T}) where {T <: AbstractClass}`

  Returns a Vector of superclasses from the superclass of class `T`
  to `Class`, in order.

* `subclasses(::Type{T}) where {T <: AbstractClass}`

  Returns a Vector of the subclasses for a given class `T`.

* `classof(::Type{T}) where {T <: AbstractClass}`

   Computes the concrete class associated with abstract type `T`, which must
   be a subclass of `AbstractClass`.

* `absclass(::Type{T}) where {T <: AbstractClass}`

  Returns the abstract type associated with the concrete class `T`.

## Defining methods on a class hierarchy

To define a function that operates on a class and its subclasses, specify the
associated abstract type rather than the class name in the method signature. Since 
the subclass contains a superset of the fields in the superclass, this works out fine.
Subclasses can override a superclass method by redefining the method on the
more specific class.

Example:

```julia
@class Foo begin
    i::Int
end

@class Bar <: Foo begin
    f::Float64
end

compute(obj::AbstractFoo) = obj.i * obj.i
```

Since `Bar <: AbstractBar <: AbstractFoo`,  the method also applies to instances of `Bar`.

```julia
julia> foo = Foo(5)
Foo(5)

julia> compute(foo)
25

julia> bar = Bar(4, 3.3)
Bar(4, 3.3)

julia> compute(bar)
16
```

We can redefine `compute` for class `Bar` to override its inherited superclass definition.
Note that we can use the type `AbstractBar`, which allows this method to be "inherited" by
subclasses of `Bar`, or we can use `Bar` directly, in which case the method applies only to
this concrete type.

```julia
julia> compute(obj::AbstractBar) = obj.i * obj.f
compute (generic function with 2 methods)

julia> compute(bar)
13.2
```

Subclasses of `Bar` now inherit this new definition, rather than the one inherited from `Foo`,
since the prior class is more specialized (further down in the shadow abstract type hierarchy).

## Example

```julia
using Classes

@class Foo <: Class begin
   foo::Int

   Foo() = Foo(0)

   # Although Foo is immutable, subclasses might not be,
   # so it's still useful to define this method.
   function Foo(self::AbstractFoo)
        self.foo = 0
    end
end

@class mutable Bar <: Foo begin
    bar::Int

    # Mutable classes can use this pattern
    function Bar(self::Union{Nothing, AbstractBar}=nothing)
        self = (self === nothing ? new() : self)
        superclass(Bar)(self)
        Bar(self, 0)
    end
end
```

Produces the following methods:

```julia
# Custom constructors defined inside the @class above
Foo()
Foo(self::AbstractFoo)

#
# Methods emitted by @class macro for Foo
#

# all-fields constructor
Foo(foo::Int64)

# local-field initializer
Foo(self::T, foo::Int64) where T<:AbstractFoo

# Custom constructor defined inside the @class above
Bar()

# Custom initializer defined inside the @class above
Bar(self::Union{Nothing, AbstractBar})

#
# Methods emitted by @class macro for Bar
#

# all-fields constructor
Bar(foo::Int64, bar::Int64)

# local-fields initializer
Bar(self::T, bar::Int64) where T<:AbstractBar

# all fields initializer
Bar(self::T, foo::Int64, bar::Int64) where T<:AbstractBar 

#  Superclass-copy initializer 
Bar(bar::Int64, s::Foo)
```

## Example from Mimi

The following diagram shows the relationship between the concrete structs and abstract types create by 
the `@class` macro. Solid lines indicate subtype relationships; dotted lines indicate subclass 
relationships, which exist outside the julia type system.

![Mimi component structure](figs/Classes.png)

Each class as a corresponding "shadow" abstract supertype (of the same name surrounded by underscores) which 
is a parent to all abstract supertypes of its subclasses.
