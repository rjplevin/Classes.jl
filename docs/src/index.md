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
