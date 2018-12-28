# Classes.jl

The key feature of the package is the management of an abstract type hierarchy that
defines the subclass and superclass relationships desired of the the concrete types
representing the classes. The concrete types defined for each class include all the
fields defined in any declared superclass, plus the fields defined within the class
declaration. The abstract type hierarchy allows methods defined for a class to be
called on its subclasses, whose fields are a superset of those of its superclass.

The `Classes.jl` package comprises two macros (`@class` and `@method`) and several 
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

## The @method macro

As defined in this package, a "class method" is simply a function whose first argument is
a type defined by `@class`. The `@method` macro uses the shadow abstract type hierarchy to 
redefine the given function so that it applies to the given class as well as its subclasses.

Thus the following `@method` invocation:

```
@method my_method(obj::Bar, other, stuff) = do_something(obj, other, stuff)
```

emits the following code:

```
my_method(obj::AbstractBar, other, stuff) = do_something(obj, other, args)
```

The only change is that the type of first argument is changed to the abstract supertype
associated with the concrete type `Bar`, allowing subclasses of `Bar` -- whose
abstract supertype would by a subtype of `AbstractBar` -- to use the method as well. Since 
the subclass contains a superset of the fields in the superclass, this works out fine.

Subclasses can override a superclass method by redefining the method on the
more specific class.

Say we define the following method on class `Foo`:

```julia
@method get_foo(obj::Foo) = obj.foo
```

This is equivalent to writing:

```julia
get_foo(obj::AbstractFoo) = obj.foo
```

Since `Bar <: AbstractBar <: AbstractFoo`,  the method also applies to instances of `Bar`.

```julia
julia> f = Foo(1)
Foo(1)

julia> b = Bar(10, 11)
Bar(10, 11)

julia> get_foo(f)
1

julia> get_foo(b)
10
```

We can redefine `get_foo` for class `Bar` to override its inherited superclass definition:

```julia
julia> @method get_foo(obj::Bar) = obj.foo * 2
get_foo (generic function with 2 methods)

julia> get_foo(b)
20
```

Subclasses of `Bar` now inherit this new definition, rather than the one inherited from `Foo`,
since the prior class is more specialized (further down in the shadow abstract type hierarchy).

```julia
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
  
julia> get_foo(z)
200
```

The user deals primarily with the concrete types; the abstract types are created and used mainly by 
the `@class` and `@method` macros. However, methods can be defined directly using classes' abstract 
types, allowing the use of classes and inheritance in arguments besides the first one, which is the 
only one handled by this macro.

## Example

```julia
using Classes

@class Foo <: Class begin
   foo::Int

   Foo() = Foo(0)

   # Although Foo is immutable, subclasses might not be,
   # so it's still useful to define this method.
   function Foo(self::absclass(Foo))
        self.foo = 0
    end
end

@class mutable Bar <: Foo begin
    bar::Int

    # Mutable classes can use this pattern
    function Bar(self::Union{Nothing, absclass(Bar)}=nothing)
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
is a parent to all abstract supertypes of its subclasses. The subclasses of, say, `ComponentDef` are all 
subtypes of `AbstractComponentDef`, thus methods defined as:

```julia
@method function foo(obj::ComponentDef)
    ...
end
```

are emitted as:

```julia
function foo(obj::T) where {T <: AbstractComponentDef}
    ...
end
```

This allows the `foo` method to be called on any subclass of `ComponentDef`.
