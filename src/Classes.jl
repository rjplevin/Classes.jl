module Classes

using DataStructures
using MacroTools
using MacroTools:combinedef, combinestructdef
using InteractiveUtils: subtypes

export @class, Class, AbstractClass, isclass, classof, superclass, superclasses, issubclass, subclasses, absclass

abstract type AbstractClass end            # supertype of all shadow class types
abstract type Class <: AbstractClass end   # superclass of all concrete classes

include("utilities.jl")

_cache = nothing

# Return info about a class in a named tuple
function _class_info(::Type{T}) where {T <: AbstractClass}
    global _cache
    _cache === nothing && (_cache = Dict())
    haskey(_cache, T) && return _cache[T]

    # @info "_class_info($T)"

    typ = (typeof(T) === UnionAll ? Base.unwrap_unionall(T) : T)

    # note: must extract symbol from type to create required expression
    ivars = (isabstracttype(typ) ? Expr[] : [:($vname::$(typename(vtype))) for (vname, vtype) in zip(fieldnames(typ), typ.types)])
    wheres = typ.parameters

    d = Dict(t.name=>regensym(t.name) for t in wheres)    # create mapping of type params to gen'd symbols
    ivars = [_translate_ivar(d, iv) for iv in ivars]      # translate types to use gensyms
    wheres = [_translate_where(d, w) for w in wheres]

    result = (wheres=wheres, ivars=ivars, super=superclass(typ))
    _cache[T] = result
    return result
end

"""
    superclass(t::Type{Class})

Returns the type of the concrete superclass of the given class, or `nothing`
for `Class`, which is the root of the class hierarchy.
"""
superclass(::Type{Class}) = nothing

"""
    superclasses(::Type{T}) where {T <: AbstractClass}

Returns a vector of superclasses from the superclass of the current class
to `Class`, in order.
"""
superclasses(::Type{Class}) = []

function superclasses(::Type{T}) where {T <: AbstractClass}
    super = superclass(T)
    [super, superclasses(super)...]
end

"""
    isclass(X)

Return `true` if `X` is a concrete subclass of `AbstractClass`, or is `Class`, which is abstract.
"""
isclass(any) = false

# Note that !isabstracttype(T) != isconcretetype(T): parameterized types return false for both
isclass(::Type{T}) where {T <: AbstractClass} = (T === Class || !isabstracttype(T))

"""
    issubclass(t1::DataType, t2::DataType)

Returns `true` if `t1` is a subclass of `t2`, else false.
"""
# identity
issubclass(::Type{T}, ::Type{T}) where {T <: AbstractClass} = true

issubclass(::Type{T1}, ::Type{T2}) where {T1 <: AbstractClass, T2 <: AbstractClass} = T1 in Set(superclasses(T2))

"""
    classof(::Type{T}) where {T <: AbstractClass}

Compute the concrete class associated with abstract class `T`, which must
be a subclass of `AbstractClass`.
"""
function classof(::Type{T}) where {T <: AbstractClass}
    if isclass(T)
        return T
    end

    # Abstract types should have only one concrete subtype
    concrete = filter(isconcretetype, subtypes(T))

    if length(concrete) == 1
        return concrete[1]
    end

    # Should never happen unless user manually creates errant subtypes
    error("Abstract class supertype $T has multiple concrete subtypes: $concrete")
end

"""
    subclasses(::Type{T}) where {T <: AbstractClass}

Compute the vector of subclasses for a given class.
"""
function subclasses(::Type{T}) where {T <: AbstractClass}
    # immediate supertype is "our" entry in the type hierarchy
    super = supertype(T)

    # collect immediate subclasses
    subs = [classof(t) for t in subtypes(super) if isabstracttype(t)]

    # recurse on subclasses
    return [subs; [subclasses(t) for t in subs]...]
end

"""
    absclass(::Type{T}) where {T <: AbstractClass}

Returns the abstract type associated with the concrete class `T`.
"""
function absclass(::Type{T}) where {T <: AbstractClass}
    isclass(T) ? supertype(T) : error("absclass(T) must be called on concrete classes; $T is abstract.")
end


include("@class.jl")

end # module
