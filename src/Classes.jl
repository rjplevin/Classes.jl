module Classes

using MacroTools
using InteractiveUtils: subtypes

export @class, @method, classof, superclass, superclasses, issubclass, subclasses, Class, _Class_

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

"""
Compute the concrete class associated with a shadow abstract class, which must
be a subclass of _Class_.
"""
function classof(::Type{T}) where {T <: _Class_}
    if ! isabstracttype(T)
        return T
    end

    # Abstract types should have only one concrete subtype
    concrete = filter(t -> !isabstracttype(t), subtypes(T))

    if length(concrete) == 1
        return concrete[1]
    end

    # Should never happen unless user manually creates errant subtypes
    error("Abstract class supertype $T has multiple concrete subtypes: $concrete")
end

function subclasses(::Type{T}) where {T <: _Class_}
    # immediate supertype is "our" entry in the type hierarchy
    super = supertype(T)
    
    # collect immediate subclasses
    subs = [classof(t) for t in subtypes(super) if isabstracttype(t)]

    # recurse on subclasses
    return [subs; [subclasses(t) for t in subs]...]
end

"""
Return the symbol for the abstract class for `cls`
"""
_absclass(cls::Symbol) = Symbol("_$(cls)_")

function _constructors(class, fields, wheres)
    args = [sym for (sym, arg_type, slurp, default) in map(splitarg, fields)]
    assigns = [:(self.$arg = $arg) for arg in args]

    params = [clause.args[1] for clause in wheres]

    dflt = :(
        function $class{$(params...)}($(fields...)) where {$(wheres...)}
            new{$(params...)}($(args...))
        end
    )

    init = :(
        function $class(self::T, $(fields...)) where {T <: $(_absclass(class)), $(wheres...)}
            $(assigns...)
        end
    )

    return [dflt, init]
end

macro class(elements...)
    # @info "elements: $elements"
    mutable = (elements[1] == :mutable)
    if mutable
        elements = elements[2:end]
    end

    len = length(elements)
    
    if len == 1                       # no fields defined
        name_expr = elements[1]
        definition = quote end
    elseif len == 2
        (name_expr, definition) = elements
    else
        error("Unrecognized form for @class definition: $elements")
    end
   
    # @info "name: $name_expr"
    # @info "def: $definition"

    if ! @capture(definition, begin exprs__ end)
        error("@class $name_expr: badly formatted @class expression: $exprs")
    end

    # allow for optional type params and supertype
    if ! @capture(name_expr, ((cls_{wheres__}  | cls_) <: supercls_) | (cls_{wheres__} | cls_))
        error("Unrecognized class name expression: $name_expr")
    end

    if supercls === nothing
        supercls = :Class
    end

    if wheres == nothing
        wheres = []
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

    abs_class = _absclass(cls)
    abs_super = _absclass(supercls)

    # add default constructors
    append!(ctors, _constructors(cls, all_fields, wheres))

    struct_def = :(
        struct $cls{$(wheres...)} <: $abs_class
            $(all_fields...)
            $(ctors...)
        end
    )

    # toggles definition between mutable and immutable struct
    struct_def.args[1] = mutable

    result = quote
        abstract type $abs_class <: $abs_super end
        $struct_def
        
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
    @method get_foo(obj::MyClass) obj.foo
->
    get_foo(obj::T) where T <: _MyClass_
    
so it works on subclasses, too.
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
    abs_super = _absclass(T)

    # Redefine the function to accept any first arg that's a subclass of abstype
    parts[:whereparams] = (:($type_symbol <: $abs_super), whereparams...)
    args[1] = :($arg1::$type_symbol)
    expr = MacroTools.combinedef(parts)
    return esc(expr)
end

end # module
