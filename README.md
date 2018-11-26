# Classes.jl
A simple, Julian approach to inheritance of structure and methods.

Julia is not an object-oriented language in the traditional sense that only abstract types can be inherited. Thus,
if multiple types need to share structure, you either:

1. Write out the common fields manually,
2. Write a macro that emits the common fields, or
3. Use someone else's macros that provide such features.


