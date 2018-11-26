module Classes

using MacroTools

export @class, @method, superclass, superclasses, issubclass, subclasses, Class, _Class_

_class_members = Dict{Symbol, Vector{Expr}}([:Class => []])

abstract type _Class_ end            # supertype of all shadow class types
abstract type Class <: _Class_ end   # superclass of all concrete classes

superclass(t::Type{Class}) = nothing
superclasses(t::Type{Class}) = []
superclasses(t::Type{T} where {T <: _Class_}) = [superclass(t), superclasses(superclass(t))...]

# catch-all
issubclass(t1::DataType, t2::DataType) = false

# identity
issubclass(t1::Type{T}, t2::Type{T}) where {T <: _Class_} = true

function subclasses(t::Type{T}) where {T <: _Class_}
    # immediate supertype is "our" entry in the type hierarchy
    super = supertype(T) 
    
    # collect immediate subclasses
    subs = [classof(t) for t in subtypes(super) if startswith(string(t), "_")]

    # recurse on subclasses
    return [subs; [subclasses(t) for t in subs]...]
end

"""
Compute the concrete class associated with a shadow abstract class, which must
be a subclass of _Class_.
"""
function classof(::Type{T}) where {T <: _Class_}
    name = string(T)

    if (length(name) > 2 && startswith(name, "_") && endswith(name, "_"))
        return eval(Symbol(name[2:end-1]))
    end
    
    # If called on a concrete type, return the type
    return T
end

macro class(name_expr, block)
    if ! @capture(block, begin exprs__ end)
        error("@class $name_expr: badly formatted @class expression: $exprs")
    end

    if ! @capture(name_expr, cls_ <: supercls_)
        cls = name_expr
        supercls = :Class
    end

    # split the expressions into constructors and field definitions
    ctors  = []
    fields = []
    for ex in exprs
        try 
            splitdef(ex)        # raises AssertionError if not a func def
            push!(ctors, ex)
        catch
            push!(fields, ex)
        end
    end

    # append our fields to parents'
    all_fields = [_class_members[supercls]; fields]
    _class_members[cls] = all_fields

    abs_class = Symbol("_$(cls)_")
    abs_super = Symbol("_$(supercls)_")

    result = quote
        abstract type $abs_class <: $abs_super end
        struct $cls <: $abs_class
            $(all_fields...)
            $(ctors...)
        end
        
        Classes.superclass(::Type{$cls}) = $supercls
        Classes.issubclass(::Type{$cls}, ::Type{$supercls}) = true
    end

    # Start traversal up hierarchy with superclass since superclass() for 
    # this class doesn't exist until after this macro is evaluated.
    expr = quote
        for sup in superclasses($supercls)
            eval(:(Classes.issubclass(::Type{$$cls}, ::Type{$sup}) = true))
        end
        nothing
    end

    push!(result.args, expr)
    return esc(result)
end

#=
Converts, e.g., `@method get_foo(obj::MyClass) obj.foo` to
`get_foo(obj::T) where T <: _MyClass_` so it works on all subclasses.
=#

macro method(funcdef)
    parts = splitdef(funcdef)
    name = parts[:name]
    args = parts[:args]
    whereparams = parts[:whereparams]

    if ! @capture(args[1], arg1_::T_)
        error("First argument of method $name must be explicitly typed")
    end

    type_symbol = gensym("$T")
    abs_super = Symbol("_$(T)_")

    # Redefine the function to accept any first arg that's a subclass of abstype
    parts[:whereparams] = (:($type_symbol <: $abs_super), whereparams...)
    args[1] = :($arg1::$type_symbol)
    expr = MacroTools.combinedef(parts)
    return esc(expr)
end

end # module
