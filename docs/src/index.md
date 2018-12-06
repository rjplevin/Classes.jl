# Classes.jl

## Example from Mimi

The following diagram shows the relationship between the concrete structs and abstract types create by the `@class` macro. Solid lines indicate subtype relationships; dotted lines indicate
subclass relationships, which exist outside the julia type system.

![Mimi component structure](figs/Classes.png)

Each class as a corresponding "shadow" abstract supertype (of the same name surrounded by underscores) which is a parent to all abstract supertypes of its subclasses. The subclasses of, say, `ComponentDef` are all subtypes of `_ComponentDef_`, thus methods defined as

```
@method function foo(obj::ComponentDef)
    ...
end
```

are emitted essentially as the following:

```
function foo(obj::T) where {T <: _ComponentDef_}
    ...
end
```

So the `foo` method can be called on any subclass of `ComponentDef`. The user deals only with the concrete types; the abstract types are created and used only by the `@class` and `@method` macros.

## Functions emitted by the @class macro

The `@class` macro emits several functions, including constructors, initializers, and support methods.

### Constructors

* "All fields" constructor

  This constructor takes as arguments all the fields accumulated through superclasses, in
  the order defined, and calls `new()` on the args. This simply duplicates the default
  constructor, which is necessary since we define other "inner" constructors and initializers.

### Initializers

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

### Support methods

* `issubclass(class, superclass)`

   For all superclasses of the newly defined class, a method of `issubclass` is emitted that
   returns true for the new class and its superclasses.

* `superclass(class)`

   Returns the superclass of the newly defined class.

### Example

```
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
```
# Custom constructors defined inside the @class above
Foo()
Foo(self::_Foo_)

#
# Methods emitted by @class macro for Foo
#

# all-fields constructor
Foo(foo::Int64)

# local-field initializer
Foo(self::T, foo::Int64) where T<:_Foo_ 


# Custom constructor defined inside the @class above
Bar()

# Custom initializer defined inside the @class above
Bar(self::Union{Nothing, _Bar_})

#
# Methods emitted by @class macro for Bar
#

# all-fields constructor
Bar(foo::Int64, bar::Int64)

# local-fields initializer
Bar(self::T, bar::Int64) where T<:_Bar_

# all fields initializer
Bar(self::T, foo::Int64, bar::Int64) where T<:_Bar_  

#  Superclass-copy initializer 
Bar(bar::Int64, s::Foo)
```